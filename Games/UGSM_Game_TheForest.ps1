# UGSM Game TheForest
# UGSM game module for The Forest.
#
# Purpose
# -------
# This file is the architecture baseline for creating new UGSM game modules.
# It keeps the shared runtime-only profile model, schema-driven editor layout,
# generic file helpers, and the handler contract used by the game modules.
#
# Use this file as the starting point for new games:
# 1. Copy to UGSM_Game_<GameName>.ps1
# 2. Replace TheForest with the real game token
# 3. Update metadata, install definition, runtime layout, schema, and any
#    game-specific workflows
# 4. Remove optional blocks that are marked as game-specific
#
# Design rules
# ------------
# - Visible in the game catalog when IsVisible is true
# - Runtime-only working paths
# - No profile sync / no copy-back workflow
# - Generic reusable helpers first
# - Schema includes sample tabs and subtabs for multi-file games
# - Game-specific logic stays in the game module and must be labeled clearly
# - Default lifecycle for Steam games: Install, Update, Verify, Remove binaries only
# - Remove the sample reference tab once a real game module is built

function Test-UGSMGameTheForestVerboseLogging {
    [CmdletBinding()]
    param()

    if ((Get-Variable -Name 'UGSM_EnableVerboseGameTheForestLogging' -Scope Script -ErrorAction SilentlyContinue) -and [bool]$script:UGSM_EnableVerboseGameTheForestLogging) { return $true }
    if (-not [string]::IsNullOrWhiteSpace($env:UGSM_VERBOSE_GAME_TheForest)) { return $true }
    return $false
}

function ConvertTo-UGSMGameTheForestSafeLogText {
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
        # the TheForest itself does not add portability-scan false positives.
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

function Write-UGSMGameTheForestLog {
    [CmdletBinding()]
    param(
        [ValidateSet('TRACE','DEBUG','INFO','WARN','ERROR')]
        [string]$Level = 'DEBUG',

        [Parameter(Mandatory)]
        [string]$Message,

        [System.Exception]$Exception
    )

    if (($Level -in @('TRACE','DEBUG')) -and -not (Test-UGSMGameTheForestVerboseLogging)) { return }

    $safeMessage = ConvertTo-UGSMGameTheForestSafeLogText -Value $Message

    if ($Exception) {
        $exceptionType = $Exception.GetType().Name
        $exceptionMessage = ConvertTo-UGSMGameTheForestSafeLogText -Value $Exception.Message
        $safeMessage = "$safeMessage Exception=$exceptionType`: $exceptionMessage"
    }

    if (Get-Command -Name Write-UGSMLog -ErrorAction SilentlyContinue) {
        Write-UGSMLog -Level $Level -Category 'Game:TheForest' -Message $safeMessage
    }
}

function Write-UGSMGameTheForestPathLog {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Message
    )

    # Compatibility wrapper for older TheForest notes. New modules should use Write-UGSMGameTheForestLog.
    Write-UGSMGameTheForestLog -Level 'DEBUG' -Message $Message
}

function Ensure-UGSMGameTheForestInstanceDiscordShape {
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


function Get-UGSMGameTheForestSupportedFeatures {
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
        Rcon          = $false
        GracefulStop  = $false

        # The Forest has no native dedicated-server Workshop/mod flow in UGSM.
        # ModAPI/third-party loaders are intentionally informational only for now.
        Mods          = $false
        Workshop      = $false
        ModTabMode    = 'None'

        ModStateStorage           = 'InstanceJson'
        InstanceModsProperty      = 'Mods'
        InstanceModStatesProperty = 'ModStates'

        Discord       = $true
        AdvancedFiles = $true
        UserLists     = $false

        IniFiles        = $false
        JsonFiles       = $false
        XmlFiles        = $false
        CfgFiles        = $true
        PropertiesFiles = $false
        YamlFiles       = $false
        TomlFiles       = $false
        LuaFiles        = $false
        TextFiles       = $false
        PSSQLite        = $false

        ModCapabilities = [pscustomobject]@{
            SteamWorkshop    = $false
            LoadOrder        = $false
            ArchiveImport    = $false
            FolderImport     = $false
            FrameworkInstall = $false
            PluginManager    = $false
            KeyCopy          = $false
            ServerSideCopy   = $false
            RuntimeSync      = $false
            BuildIndexCache  = $false
            MapList          = $false
            ConfigMerge      = $false
            UrlDownload      = $false
            OpenManifest     = $false
            RefreshSummary   = $false
        }
    }
}

function Get-UGSMGameTheForestModsDefinition {
    [CmdletBinding()]
    param()

    $features = Get-UGSMGameTheForestSupportedFeatures

    if (Get-Command -Name New-UGSMDefaultModsDefinition -ErrorAction SilentlyContinue) {
        $mods = New-UGSMDefaultModsDefinition -GameId 'TheForest' -DisplayName 'Mods' -Supported ([bool]$features.Mods)
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
            GameId = 'TheForest'
        }
    }


    # TheForest Workshop App ID placeholder. Copied games must replace 000000 with
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

function Get-UGSMGameTheForestMetadata {
    [CmdletBinding()]
    param()

    $serverExeRelativePath = 'TheForestDedicatedServer.exe'
    $features = Get-UGSMGameTheForestSupportedFeatures
    $modsDefinition = Get-UGSMGameTheForestModsDefinition

    return [pscustomobject]@{
        Id                       = 'TheForest'
        Name                     = 'The Forest'
        Category                 = 'Survival'
        Description              = 'The Forest dedicated server.'
        IsCustom                 = $false
        SupportTier              = 'Full'
        SortOrder                = 170
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
        SteamAppId               = '556450'
        SteamStoreAppId          = '242760'
        ServerExecutable         = 'TheForestDedicatedServer.exe'
        ServerExecutableRelative = $serverExeRelativePath
        UsesSharedBinaries       = $true
        InstanceType             = 'DedicatedServer'

        ConfigRootRelative       = ''
        SaveRootRelative         = ''
        LogRootRelative          = ''

        RequiredFiles            = @('TheForestDedicatedServer.exe')
        InstallMarkers           = @('TheForestDedicatedServer.exe')

        PortSchema               = @(
            @{ Name = 'SteamPort'; Protocol = 'UDP'; PreferredStart = 8766 }
            @{ Name = 'GamePort'; Protocol = 'UDP'; PreferredStart = 27015 }
            @{ Name = 'QueryPort'; Protocol = 'UDP'; PreferredStart = 27016 }
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
                'The Forest does not use the shared UGSM workshop-mod flow in this module pass.',
                'Server data is stored per profile; binaries remain shared in the Steam install folder.'
            )
        }
    }
}

function Get-UGSMGameTheForestInstallDefinition {
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
            throw 'TheForest install definition failed: InstallPath could not be resolved.'
        }

        $InstallPath = Join-Path $steamRoot 'servers\TheForest'
    }

    $meta = Get-UGSMGameTheForestMetadata

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
        LogRootPath          = Join-Path $InstallPath 'Logs'
    }
}

function Get-UGSMGameTheForestAppDataRoot {
    [CmdletBinding()]
    param()

    if (Get-Command -Name Get-UGSMAppDataRoot -ErrorAction SilentlyContinue) {
        return [string](Get-UGSMAppDataRoot)
    }

    return (Join-Path $env:LOCALAPPDATA 'UGSM')
}

function Get-UGSMGameTheForestProfileBaseRoot {
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
        $probe = Get-UGSMDefaultInstanceProfilePath -GameId 'TheForest' -Name '_probe_'
        if (-not [string]::IsNullOrWhiteSpace([string]$probe)) {
            return (Split-Path -Parent (Split-Path -Parent $probe))
        }
    }

    return (Join-Path (Get-UGSMGameTheForestAppDataRoot) 'Profiles')
}

function Get-UGSMGameTheForestTheForestRoot {
    [CmdletBinding()]
    param()

    return (Join-Path (Get-UGSMGameTheForestAppDataRoot) 'TheForests\TheForest')
}

function Get-UGSMGameTheForestProfileRoot {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ProfileName
    )

    return (Join-Path (Join-Path (Get-UGSMGameTheForestProfileBaseRoot) 'TheForest') $ProfileName)
}


function Get-UGSMGameTheForestRuntimeRoot {
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
            $profileRoot = Get-UGSMGameTheForestProfileRoot -ProfileName $candidate
        }
    }

    if ([string]::IsNullOrWhiteSpace([string]$profileRoot)) {
        throw 'TheForest runtime root could not be resolved for the selected instance.'
    }

    return $profileRoot
}

function Remove-UGSMGameTheForestPath {
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

function New-UGSMGameTheForestDirectoryJunction {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$LinkPath,

        [Parameter(Mandatory)]
        [string]$TargetPath
    )

    if (-not (Test-Path -LiteralPath $TargetPath -PathType Container)) {
        throw "TheForest junction target was not found: $TargetPath"
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

        Remove-UGSMGameTheForestPath -Path $LinkPath
    }

    try {
        New-Item -ItemType Junction -Path $LinkPath -Target $TargetPath -Force -ErrorAction Stop | Out-Null
    }
    catch {
        $null = & cmd.exe /c ('mklink /J "{0}" "{1}"' -f $LinkPath, $TargetPath)
        if ($LASTEXITCODE -ne 0 -and -not (Test-Path -LiteralPath $LinkPath -PathType Container)) {
            throw "TheForest junction creation failed for '$LinkPath' -> '$TargetPath'."
        }
    }
}

function Copy-UGSMGameTheForestFilesToRuntime {
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

    Copy-UGSMGameTheForestDirectoryContent -Source $Source -Destination $Destination -ClearDestination:$ClearDestination
}

function Get-UGSMGameTheForestRuntimeDefinition {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Instance,

        [Parameter(Mandatory)]
        [object]$InstallDefinition
    )

    $runtimeRoot = Get-UGSMGameTheForestRuntimeRoot -Instance $Instance
    $configRoot = $runtimeRoot
    $saveRoot = Join-Path $runtimeRoot 'Saves'
    $logRoot = Join-Path $runtimeRoot 'Logs'

    return [pscustomobject]@{
        RuntimeRoot           = $runtimeRoot
        RuntimeInstallRoot    = [string]$InstallDefinition.InstallPath
        RuntimeGameRoot       = [string]$InstallDefinition.InstallPath
        RuntimeSavedRoot      = $runtimeRoot
        RuntimeConfigRootPath = $configRoot
        RuntimeSaveRootPath   = $saveRoot
        RuntimeLogRootPath    = $logRoot
        RuntimeServerExePath  = Join-Path ([string]$InstallDefinition.InstallPath) 'TheForestDedicatedServer.exe'
        SharedInstallPath     = [string]$InstallDefinition.InstallPath
        SharedGameRoot        = [string]$InstallDefinition.InstallPath
    }
}

function Resolve-UGSMGameTheForestDatabasePath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Instance,

        [switch]$PreferRuntime
    )

    $paths = Get-UGSMGameTheForestProfilePaths -Instance $Instance

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

function Ensure-UGSMGameTheForestRuntimeLayout {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Instance,

        [Parameter(Mandatory)]
        [object]$InstallDefinition
    )

    $runtime = Get-UGSMGameTheForestRuntimeDefinition -Instance $Instance -InstallDefinition $InstallDefinition

    foreach ($path in @($runtime.RuntimeRoot, $runtime.RuntimeConfigRootPath, $runtime.RuntimeSaveRootPath, $runtime.RuntimeLogRootPath)) {
        if (-not (Test-Path -LiteralPath $path -PathType Container)) {
            New-Item -ItemType Directory -Path $path -Force | Out-Null
        }
    }

    $serverCfgPath = Join-Path $runtime.RuntimeConfigRootPath 'Server.cfg'
    $instanceName = if ($Instance -and $Instance.PSObject.Properties.Name -contains 'Name') { [string]$Instance.Name } else { 'UGSM The Forest Server' }
    Ensure-UGSMGameTheForestDefaultServerCfg -Path $serverCfgPath -ServerName $instanceName

    return $runtime
}

function Initialize-UGSMGameTheForestRuntimeData {
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
        Copy-UGSMGameTheForestFilesToRuntime -Source $ProfileConfigRoot -Destination $RuntimeConfigRoot
    }

    if ((Get-ChildItem -LiteralPath $RuntimeSaveRoot -Force -ErrorAction SilentlyContinue | Measure-Object).Count -eq 0) {
        Copy-UGSMGameTheForestFilesToRuntime -Source $ProfileSaveRoot -Destination $RuntimeSaveRoot
    }
}

function Copy-UGSMGameTheForestDirectoryContent {
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

function Get-UGSMGameTheForestRunningBootstrapProcesses {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ServerExecutablePath,

        [Parameter(Mandatory)]
        [datetime]$StartedAfter
    )

    $matches = @()
    try {
        $matches = @(Get-CimInstance Win32_Process -Filter "Name = 'TheForestServer.exe'" -ErrorAction Stop)
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

function Start-UGSMGameTheForestBootstrapProcess {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ServerExecutablePath,

        [Parameter(Mandatory)]
        [string]$WorkingDirectory,

        [int]$BootstrapSeconds = 15
    )

    if (-not (Test-Path -LiteralPath $ServerExecutablePath -PathType Leaf)) {
        throw "TheForest server executable was not found: $ServerExecutablePath"
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

    $remaining = @(Get-Process -Name 'TheForestServer' -ErrorAction SilentlyContinue)

    if ($remaining.Count -gt 0) {

        & taskkill.exe /IM TheForestServer.exe /T /F
        $fallbackExit = $LASTEXITCODE

        Start-Sleep -Seconds 2

        $remaining = @(Get-Process -Name 'TheForestServer' -ErrorAction SilentlyContinue)
        foreach ($p in $remaining) {
            try {
                Stop-Process -Id $p.Id -Force -ErrorAction Stop
            }
            catch {
            }
        }
    }

    Start-Sleep -Seconds 2

    $remainingFinal = @(Get-Process -Name 'TheForestServer' -ErrorAction SilentlyContinue)

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

function Ensure-UGSMGameTheForestTheForest {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$InstallPath,

        [switch]$ForceRefresh,

        [int]$BootstrapSeconds = 15
    )

    $definition = Get-UGSMGameTheForestInstallDefinition -InstallPath $InstallPath
    $validation = Test-UGSMGameTheForestInstall -InstallPath $InstallPath
    if (-not $validation.IsValid) {
        throw "TheForest install is not valid at '$InstallPath'."
    }

    return [pscustomobject]@{
        GameId                       = 'TheForest'
        InstallPath                  = [string]$definition.InstallPath
        ServerExecutablePath         = [string]$definition.ServerExecutablePath
        TheForestRoot                = [string]$definition.InstallPath
        TheForestConfigRoot          = [string]$definition.InstallPath
        TheForestSaveRoot            = ''
        SourceConfigRoot             = [string]$definition.InstallPath
        SourceSaveRoot               = ''
        BootstrapPerformed           = $false
        BootstrapResult              = $null
        GeneratedConfigFiles         = @()
    }
}

function Ensure-UGSMGameTheForestDefaultServerCfg {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Path,
        [string]$ServerName = 'UGSM The Forest Server'
    )

    Ensure-UGSMGameTheForestParentDirectory -Path $Path
    if (Test-Path -LiteralPath $Path -PathType Leaf) { return }

    $safeName = if ([string]::IsNullOrWhiteSpace($ServerName)) { 'UGSM The Forest Server' } else { [string]$ServerName }
    $content = @(
        '// Dedicated Server Settings.',
        '// Managed by UGSM. Password/token values are not logged by UGSM.',
        'serverIP ',
        'serverSteamPort 8766',
        'serverGamePort 27015',
        'serverQueryPort 27016',
        ('serverName ' + $safeName),
        'serverPlayers 8',
        'serverPassword ',
        'serverPasswordAdmin ',
        'serverSteamAccount ',
        'enableVAC on',
        'serverAutoSaveInterval 15',
        'difficulty Normal',
        'initType Continue',
        'slot 1',
        'showLogs off',
        'serverContact ',
        'veganMode off',
        'vegetarianMode off',
        'resetHolesMode off',
        'treeRegrowMode off',
        'allowBuildingDestruction on',
        'allowEnemiesCreativeMode off',
        'allowCheats off',
        'saveFolderPath ',
        'targetFpsIdle 5',
        'targetFpsActive 60'
    )
    Set-Content -LiteralPath $Path -Value $content -Encoding UTF8
}

function Initialize-UGSMGameTheForestProfile {
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
    }

    if ([string]::IsNullOrWhiteSpace($effectiveProfileName)) { throw 'ProfileName could not be resolved for The Forest profile initialization.' }
    if ([string]::IsNullOrWhiteSpace($effectiveInstallPath)) { throw 'InstallPath is required to initialize a The Forest profile.' }

    $definition = Get-UGSMGameTheForestInstallDefinition -InstallPath $effectiveInstallPath
    if (-not (Test-Path -LiteralPath ([string]$definition.ServerExecutablePath) -PathType Leaf)) {
        throw 'The Forest profile initialization failed: server executable was not found.'
    }

    $profileRoot = Get-UGSMGameTheForestProfileRoot -ProfileName $effectiveProfileName
    if ((Test-Path -LiteralPath $profileRoot -PathType Container) -and $Force) {
        Get-ChildItem -LiteralPath $profileRoot -Force -ErrorAction SilentlyContinue | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
    }

    $saveRoot = Join-Path $profileRoot 'Saves'
    $logsRoot = Join-Path $profileRoot 'Logs'
    New-Item -ItemType Directory -Path $profileRoot -Force | Out-Null
    New-Item -ItemType Directory -Path $saveRoot -Force | Out-Null
    New-Item -ItemType Directory -Path $logsRoot -Force | Out-Null

    $serverCfgPath = Join-Path $profileRoot 'Server.cfg'
    Ensure-UGSMGameTheForestDefaultServerCfg -Path $serverCfgPath -ServerName $effectiveProfileName

    return [pscustomobject]@{
        GameId      = 'TheForest'
        InstanceId  = $instanceId
        ProfileName = $effectiveProfileName
        InstallPath = $effectiveInstallPath
        ProfileRoot = $profileRoot
        ConfigRoot  = $profileRoot
        SaveRoot    = $saveRoot
        LogsRoot    = $logsRoot
        Initialized = $true
        CopiedFiles = @('Server.cfg')
    }
}

function Test-UGSMGameTheForestInstall {
    [CmdletBinding()]
    param(
        [string]$InstallPath
    )

    $definition = Get-UGSMGameTheForestInstallDefinition -InstallPath $InstallPath
    if (-not $definition -or [string]::IsNullOrWhiteSpace([string]$definition.InstallPath)) {
        throw 'TheForest validation failed: InstallPath could not be resolved.'
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
        GameId                       = 'TheForest'
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

function Start-UGSMGameTheForestInstance {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Instance
    )

    if (-not $Instance) { throw 'The Forest start failed: Instance was null.' }

    $validation = Test-UGSMGameTheForestInstall -InstallPath $Instance.InstallPath
    if (-not $validation -or -not $validation.IsInstalled -or -not $validation.ServerExecutableExists) {
        throw 'The Forest start failed: The Forest is not installed or the server executable is missing.'
    }

    $installDef = Get-UGSMGameTheForestInstallDefinition -InstallPath $Instance.InstallPath -Instance $Instance
    $profilePath = if ($Instance.PSObject.Properties.Name -contains 'ProfilePath' -and -not [string]::IsNullOrWhiteSpace([string]$Instance.ProfilePath)) { [string]$Instance.ProfilePath } else { Get-UGSMGameTheForestProfileRoot -ProfileName ([string]$Instance.Name) }

    if ([string]::IsNullOrWhiteSpace($profilePath)) { throw 'The Forest start failed: Profile path could not be resolved.' }

    $runtime = Ensure-UGSMGameTheForestRuntimeLayout -Instance $Instance -InstallDefinition $installDef
    $serverExe = [string]$runtime.RuntimeServerExePath
    $serverCfg = Join-Path ([string]$runtime.RuntimeConfigRootPath) 'Server.cfg'
    $saveRoot = [string]$runtime.RuntimeSaveRootPath
    $logRoot = [string]$runtime.RuntimeLogRootPath

    foreach ($path in @($profilePath, $saveRoot, $logRoot)) {
        if (-not (Test-Path -LiteralPath $path -PathType Container)) { New-Item -ItemType Directory -Path $path -Force | Out-Null }
    }
    Ensure-UGSMGameTheForestDefaultServerCfg -Path $serverCfg -ServerName ([string]$Instance.Name)

    $steamPort = if ($Instance.PSObject.Properties['Ports'] -and $Instance.Ports -and $Instance.Ports.PSObject.Properties['SteamPort']) { [int]$Instance.Ports.SteamPort } else { 8766 }
    $gamePort  = if ($Instance.PSObject.Properties['Ports'] -and $Instance.Ports -and $Instance.Ports.PSObject.Properties['GamePort'])  { [int]$Instance.Ports.GamePort }  else { 27015 }
    $queryPort = if ($Instance.PSObject.Properties['Ports'] -and $Instance.Ports -and $Instance.Ports.PSObject.Properties['QueryPort']) { [int]$Instance.Ports.QueryPort } else { $gamePort }

    Set-UGSMGameTheForestCfgValue -Path $serverCfg -Key 'serverSteamPort' -Value ([string]$steamPort)
    Set-UGSMGameTheForestCfgValue -Path $serverCfg -Key 'serverGamePort' -Value ([string]$gamePort)
    Set-UGSMGameTheForestCfgValue -Path $serverCfg -Key 'serverQueryPort' -Value ([string]$queryPort)
    Set-UGSMGameTheForestCfgValue -Path $serverCfg -Key 'saveFolderPath' -Value $saveRoot

    if (-not (Test-Path -LiteralPath $serverExe -PathType Leaf)) { throw 'The Forest start failed: Runtime server executable was not found.' }

    $cfgValues = Read-UGSMGameTheForestCfgFile -Path $serverCfg
    $showLogsValue = ''
    if ($cfgValues -and $cfgValues.Contains('showLogs')) { $showLogsValue = [string]$cfgValues['showLogs'] }
    $showServerWindow = ($showLogsValue -match '^(?i:on|true|1|yes)$')

    $arguments = @(
        '-dedicated',
        '-nosteamclient',
        '-configfilepath', ('"' + $serverCfg + '"'),
        '-savefolderpath', ('"' + $saveRoot + '"')
    )

    if (-not $showServerWindow) {
        $arguments = @('-batchmode', '-nographics') + $arguments
    }

    $proc = Start-Process -FilePath $serverExe -ArgumentList $arguments -WorkingDirectory (Split-Path -Parent $serverExe) -PassThru
    if (-not $proc -or -not $proc.Id) { throw 'The Forest start failed: Start-Process did not return a valid process.' }

    $gamePid = [int]$proc.Id
    if ($Instance.PSObject.Properties.Name -contains 'Pid') { $Instance.Pid = $gamePid }
    if ($Instance.PSObject.Properties.Name -contains 'Status') { $Instance.Status = 'Running' }
    if ($Instance.PSObject.Properties.Name -contains 'ProfilePath' -and [string]::IsNullOrWhiteSpace([string]$Instance.ProfilePath)) { $Instance.ProfilePath = $profilePath }

    try {
        $runtimeMarker = Join-Path $runtime.RuntimeSaveRootPath 'UGSM.Runtime.json'
        $runtimeData = [pscustomobject]@{
            InstanceId        = [string]$Instance.Id
            GameId            = 'TheForest'
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

    return [pscustomObject]@{ Instance = $Instance; Pid = $gamePid; Status = 'Running'; Runtime = $runtime }
}

function Stop-UGSMGameTheForestInstance {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Instance
    )

    if (-not $Instance) {
        throw 'TheForest stop failed: Instance was null.'
    }

    $installDef = Get-UGSMGameTheForestInstallDefinition -InstallPath $Instance.InstallPath -Instance $Instance
    if (-not $installDef) {
        throw 'TheForest stop failed: Install definition could not be resolved.'
    }

    $runtime = Get-UGSMGameTheForestRuntimeDefinition -Instance $Instance -InstallDefinition $installDef

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
        throw ("TheForest stop failed: Process {0} is still running." -f $targetProcessId)
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

function Register-UGSMGameTheForestModule {
    [CmdletBinding()]
    param()

    $metadata = Get-UGSMGameTheForestMetadata

    return [pscustomobject]@{
        Id       = [string]$metadata.Id
        Metadata = $metadata
        Handlers = [pscustomobject]@{
            GetMetadata       = 'Get-UGSMGameTheForestMetadata'
            TestInstall       = 'Test-UGSMGameTheForestInstall'
            TestInstance      = 'Test-UGSMGameTheForestInstance'
            EnsureTheForest    = 'Ensure-UGSMGameTheForestTheForest'
            InitializeProfile = 'Initialize-UGSMGameTheForestProfile'
            Start             = 'Start-UGSMGameTheForestInstance'
            Stop              = 'Stop-UGSMGameTheForestInstance'

            BuildEditor       = 'New-UGSMGameTheForestInstanceEditor'
            SaveEditor        = 'Save-UGSMGameTheForestInstanceEditor'
        }
    }
}


function Get-UGSMGameTheForestBackupTargets {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$Instance,
        [ValidateSet('Settings','Mods','All')]
        [string]$Scope = 'Settings'
    )

    $targets = New-Object System.Collections.Generic.List[object]

    if ($Scope -in @('Settings','All')) {
        $paths = Get-UGSMGameTheForestProfilePaths -Instance $Instance
        [void]$targets.Add([pscustomobject]@{
            SourcePath   = [string]$paths.ServerCfgPath
            RelativePath = 'Server.cfg'
            Label        = 'The Forest server.cfg'
        })
    }

    return @($targets.ToArray())
}

function Invoke-UGSMGameTheForestManagedBackup {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$Instance,
        [ValidateSet('Settings','Mods','All')]
        [string]$Scope = 'Settings',
        [string]$Reason = 'TheForest managed file change'
    )

    if (-not (Get-Command -Name Invoke-UGSMManagedFileBackup -ErrorAction SilentlyContinue)) { return $null }

    try {
        $targets = @(Get-UGSMGameTheForestBackupTargets -Instance $Instance -Scope $Scope)
        return Invoke-UGSMManagedFileBackup -GameId 'TheForest' -Instance $Instance -Targets $targets -Reason $Reason -KeepLatest 3
    }
    catch {
        Write-UGSMGameTheForestLog -Level 'WARN' -Message ('TheForest managed backup failed. Scope=' + $Scope + '; Reason=' + $Reason) -Exception $_.Exception
        return $null
    }
}

function Get-UGSMGameTheForestProfilePaths {
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
        $profileRoot = Get-UGSMGameTheForestProfileRoot -ProfileName ([string]$Instance.Name)
    }

    if ([string]::IsNullOrWhiteSpace([string]$profileRoot)) {
        throw 'The Forest profile paths could not be resolved for the selected instance.'
    }

    $configRoot = $profileRoot
    $saveRoot = Join-Path $profileRoot 'Saves'
    $logRoot = Join-Path $profileRoot 'Logs'
    $serverCfg = Join-Path $configRoot 'Server.cfg'
    $runtimeMarkerPath = Join-Path $saveRoot 'UGSM.Runtime.json'

    [pscustomobject]@{
        ProfileRoot                 = $profileRoot
        ProfileConfigRoot           = $configRoot
        ProfileSaveRoot             = $saveRoot
        ProfileLogRoot              = $logRoot
        RuntimeRoot                 = $profileRoot
        RuntimeConfigRoot           = $configRoot
        RuntimeSaveRoot             = $saveRoot
        RuntimeLogRoot              = $logRoot
        RuntimeMarkerPath           = $runtimeMarkerPath
        IsRuntimeActive             = (Test-Path -LiteralPath $runtimeMarkerPath -PathType Leaf)
        ConfigRoot                  = $configRoot
        SaveRoot                    = $saveRoot
        LogRoot                     = $logRoot
        PrimaryCfgPath              = $serverCfg
        ServerCfgPath               = $serverCfg
        RuntimePrimaryCfgPath       = $serverCfg
        RuntimeServerCfgPath        = $serverCfg
        PrimaryIniPath              = $null
        PrimaryJsonPath             = $null
        PrimaryXmlPath              = $null
        ServerSettingsPath          = $serverCfg
        GameplayJsonPath            = $null
        GameplayXmlPath             = $null
        AdminUsersPath              = $null
        ExclusiveUsersPath          = $null
        WhitelistedUsersPath        = $null
        BannedUsersPath             = $null
        SilencedUsersPath           = $null
        RuntimeServerSettingsPath   = $serverCfg
        RuntimeGameplayJsonPath     = $null
        RuntimeGameplayXmlPath      = $null
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

function Read-UGSMGameTheForestIniFile {
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

function Get-UGSMGameTheForestIniValue {
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

function Set-UGSMGameTheForestIniValue {
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

function Read-UGSMGameTheForestStringListFile {
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

function Write-UGSMGameTheForestStringListFile {
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


function Ensure-UGSMGameTheForestParentDirectory {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Path
    )

    $parent = Split-Path -Parent $Path
    if (-not [string]::IsNullOrWhiteSpace($parent) -and -not (Test-Path -LiteralPath $parent -PathType Container)) {
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
    }
}

function Read-UGSMGameTheForestJsonFile {
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

function Write-UGSMGameTheForestJsonFile {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Path,
        [AllowNull()]$Value
    )

    Ensure-UGSMGameTheForestParentDirectory -Path $Path
    $json = $null
    if ($null -eq $Value) {
        $json = "{}"
    }
    else {
        $json = ($Value | ConvertTo-Json -Depth 100)
    }

    Set-Content -LiteralPath $Path -Value $json -Encoding UTF8
}

function Read-UGSMGameTheForestXmlFile {
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

function Write-UGSMGameTheForestXmlFile {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][xml]$Xml
    )

    Ensure-UGSMGameTheForestParentDirectory -Path $Path
    $Xml.Save($Path)
}

function Read-UGSMGameTheForestCfgFile {
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

function Set-UGSMGameTheForestCfgValue {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Key,
        [AllowNull()][string]$Value
    )

    Ensure-UGSMGameTheForestParentDirectory -Path $Path

    $lines = [System.Collections.Generic.List[string]]::new()
    if (Test-Path -LiteralPath $Path -PathType Leaf) {
        foreach ($existingLine in @(Get-Content -LiteralPath $Path -ErrorAction SilentlyContinue)) {
            [void]$lines.Add([string]$existingLine)
        }
    }

    $keyRegex = '^\s*' + [regex]::Escape($Key) + '\s*[= ]'
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($lines[$i] -match $keyRegex) {
            $lines[$i] = ('{0} {1}' -f $Key, $Value)
            Set-Content -LiteralPath $Path -Value $lines -Encoding UTF8
            return
        }
    }

    [void]$lines.Add(('{0} {1}' -f $Key, $Value))
    Set-Content -LiteralPath $Path -Value $lines -Encoding UTF8
}

# GAME-SPECIFIC OPTIONAL BLOCK
# Remove this whole PSSQLite section unless the target game really stores editable server/admin data in SQLite.
function Test-UGSMGameTheForestPSSQLiteInstalled {
    [CmdletBinding()]
    param()

    return ($null -ne (Get-Module -ListAvailable -Name PSSQLite | Select-Object -First 1))
}

function Install-UGSMGameTheForestPSSQLite {
    [CmdletBinding()]
    param()

    Install-Module -Name PSSQLite -Scope CurrentUser -Force -Confirm:$false -ErrorAction Stop
    return (Test-UGSMGameTheForestPSSQLiteInstalled)
}

function Get-UGSMGameTheForestElevatedUsers {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$DatabasePath
    )

    if (-not (Test-UGSMGameTheForestPSSQLiteInstalled)) {
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

function Save-UGSMGameTheForestElevatedUsers {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$DatabasePath,
        [string[]]$UserIds
    )

    if (-not (Test-UGSMGameTheForestPSSQLiteInstalled)) {
        throw 'PSSQLite is not installed.'
    }

    if (-not (Test-Path -LiteralPath $DatabasePath -PathType Leaf)) {
        throw 'TheForest.db was not found.'
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


function Resolve-UGSMGameTheForestEditorFieldPath {
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

function ConvertTo-UGSMGameTheForestEditorFieldValue {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][hashtable]$Field,
        [Parameter(Mandatory)]$Control
    )

    switch ([string]$Field.Type) {
        'Choice' {
            if ($Control.PSObject.Properties.Name -contains 'SelectedItem' -and $Control.SelectedItem) { return [string]$Control.SelectedItem }
            return [string]$Control.Text
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


function Get-UGSMGameTheForestInstanceDefinitionPath {
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

function Save-UGSMGameTheForestInstanceDefinition {
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

    $definitionPath = Get-UGSMGameTheForestInstanceDefinitionPath -Instance $Instance
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

function Save-UGSMGameTheForestInstanceEditor {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$Instance,
        [Parameter(Mandatory)][hashtable]$EditorState
    )

    $paths = Get-UGSMGameTheForestProfilePaths -Instance $Instance
    $updatedInstance = Ensure-UGSMGameTheForestInstanceDiscordShape -Instance $Instance
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

    Invoke-UGSMGameTheForestManagedBackup -Instance $updatedInstance -Scope 'Settings' -Reason 'Before TheForest settings save' | Out-Null

    foreach ($entry in $EditorState.GetEnumerator()) {
        $item = $entry.Value
        if (-not $item) { continue }

        $field = $item.Field
        $control = $item.Control
        if (-not $field -or -not $control) { continue }

        switch ([string]$field.Type) {
            'StringList' {
                $targetPath = Resolve-UGSMGameTheForestEditorFieldPath -Field $field -Paths $paths -TargetSet Runtime
                if ([string]::IsNullOrWhiteSpace([string]$targetPath)) {
                    $targetPath = Resolve-UGSMGameTheForestEditorFieldPath -Field $field -Paths $paths
                }

                if ([string]::IsNullOrWhiteSpace([string]$targetPath)) {
                    throw ("TheForest save failed: no runtime path could be resolved for string list field '{0}'." -f [string]$field.Id)
                }

                $values = @($control.Lines | ForEach-Object { [string]$_ })
                Write-UGSMGameTheForestStringListFile -Path $targetPath -Values $values
                $saveSummary.StringListsWritten++
                $saveSummary.RuntimeCopiesUpdated++
            }

            'Boolean' {
                $value = ConvertTo-UGSMGameTheForestEditorFieldValue -Field $field -Control $control
                if ([string]$field.File -ieq 'Server.cfg') {
                    $cfgValue = if ([string]$field.Type -eq 'Boolean') { if ($control.Checked) { 'on' } else { 'off' } } else { $value }
                    Set-UGSMGameTheForestCfgValue -Path $paths.ServerCfgPath -Key ([string]$field.Key) -Value $cfgValue
                }
                else {
                    Set-UGSMGameTheForestIniValue -Path $paths.ServerSettingsPath -Section ([string]$field.Section) -Key ([string]$field.Key) -Value $value
                }
                $saveSummary.IniKeysWritten++
                $saveSummary.RuntimeCopiesUpdated++
            }

            'Number' {
                $value = ConvertTo-UGSMGameTheForestEditorFieldValue -Field $field -Control $control
                if ([string]$field.File -ieq 'Server.cfg') {
                    $cfgValue = if ([string]$field.Type -eq 'Boolean') { if ($control.Checked) { 'on' } else { 'off' } } else { $value }
                    Set-UGSMGameTheForestCfgValue -Path $paths.ServerCfgPath -Key ([string]$field.Key) -Value $cfgValue
                }
                else {
                    Set-UGSMGameTheForestIniValue -Path $paths.ServerSettingsPath -Section ([string]$field.Section) -Key ([string]$field.Key) -Value $value
                }
                $saveSummary.IniKeysWritten++
                $saveSummary.RuntimeCopiesUpdated++
            }

            'MultilineText' {
                $value = ConvertTo-UGSMGameTheForestEditorFieldValue -Field $field -Control $control
                if ([string]$field.File -ieq 'Server.cfg') {
                    $cfgValue = if ([string]$field.Type -eq 'Boolean') { if ($control.Checked) { 'on' } else { 'off' } } else { $value }
                    Set-UGSMGameTheForestCfgValue -Path $paths.ServerCfgPath -Key ([string]$field.Key) -Value $cfgValue
                }
                else {
                    Set-UGSMGameTheForestIniValue -Path $paths.ServerSettingsPath -Section ([string]$field.Section) -Key ([string]$field.Key) -Value $value
                }
                $saveSummary.IniKeysWritten++
                $saveSummary.RuntimeCopiesUpdated++
            }

            'Choice' {
                $value = ConvertTo-UGSMGameTheForestEditorFieldValue -Field $field -Control $control
                if ([string]$field.File -ieq 'Server.cfg') {
                    Set-UGSMGameTheForestCfgValue -Path $paths.ServerCfgPath -Key ([string]$field.Key) -Value $value
                }
                else {
                    Set-UGSMGameTheForestIniValue -Path $paths.ServerSettingsPath -Section ([string]$field.Section) -Key ([string]$field.Key) -Value $value
                }
                $saveSummary.IniKeysWritten++
                $saveSummary.RuntimeCopiesUpdated++
            }

            'Password' {
                $value = ConvertTo-UGSMGameTheForestEditorFieldValue -Field $field -Control $control
                if ([string]$field.File -ieq 'Server.cfg') {
                    Set-UGSMGameTheForestCfgValue -Path $paths.ServerCfgPath -Key ([string]$field.Key) -Value $value
                }
                else {
                    Set-UGSMGameTheForestIniValue -Path $paths.ServerSettingsPath -Section ([string]$field.Section) -Key ([string]$field.Key) -Value $value
                }
                $saveSummary.IniKeysWritten++
                $saveSummary.RuntimeCopiesUpdated++
            }

            'Text' {
                $value = ConvertTo-UGSMGameTheForestEditorFieldValue -Field $field -Control $control
                if ([string]$field.File -ieq 'Server.cfg') {
                    $cfgValue = if ([string]$field.Type -eq 'Boolean') { if ($control.Checked) { 'on' } else { 'off' } } else { $value }
                    Set-UGSMGameTheForestCfgValue -Path $paths.ServerCfgPath -Key ([string]$field.Key) -Value $cfgValue
                }
                else {
                    Set-UGSMGameTheForestIniValue -Path $paths.ServerSettingsPath -Section ([string]$field.Section) -Key ([string]$field.Key) -Value $value
                }
                $saveSummary.IniKeysWritten++
                $saveSummary.RuntimeCopiesUpdated++
            }

            'InstanceText' {
                $value = [string](ConvertTo-UGSMGameTheForestEditorFieldValue -Field $field -Control $control)
                if ([string]$field.Model -eq 'Discord') {
                    $discordInput[[string]$field.Property] = $value
                    $hasDiscordChanges = $true
                }
            }

            'InstanceBoolean' {
                $value = [bool]$control.Checked
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
            [void](Save-UGSMGameTheForestInstanceDefinition -Instance $PersistedInstance)
        }

        $discordResult = Save-UGSMInstanceDiscordSettingsModel -Instance $updatedInstance -InputObject ([pscustomobject]$discordInput) -PersistInstance $persistScript
        if ($discordResult -and $discordResult.PSObject.Properties['Instance']) {
            $updatedInstance = $discordResult.Instance
            $saveSummary.InstanceSettingsSaved++
        }
    }

    return [pscustomobject]@{
        Success = $true
        Message = ("Saved TheForest settings. INI keys: {0}. User lists: {1}. Instance settings: {2}." -f $saveSummary.IniKeysWritten, $saveSummary.StringListsWritten, $saveSummary.InstanceSettingsSaved)
        Summary = [pscustomobject]$saveSummary
        Instance = $updatedInstance
    }
}

function New-UGSMGameTheForestInstanceEditor {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$Instance,
        [Parameter(Mandatory)][hashtable]$Theme,
        [Parameter(Mandatory)][System.Windows.Forms.Panel]$HostPanel,
        [AllowNull()][System.Windows.Forms.Label]$StatusLabel
    )

    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing

    $Instance = Ensure-UGSMGameTheForestInstanceDiscordShape -Instance $Instance
    $paths = Get-UGSMGameTheForestProfilePaths -Instance $Instance
    $schema = Get-UGSMGameTheForestEditorSchema
    $iniData = Read-UGSMGameTheForestIniFile -Path $paths.ServerSettingsPath
    $cfgData = Read-UGSMGameTheForestCfgFile -Path $paths.ServerCfgPath
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

    function Get-TheForestSafeIniValue {
        param([hashtable]$Field)
        try {
            if ([string]$Field.File -ieq 'Server.cfg') {
                $key = [string]$Field.Key
                if ($cfgData -and $cfgData.Contains($key)) { return [string]$cfgData[$key] }
                return [string]$(if ($Field.ContainsKey('DefaultValue')) { $Field.DefaultValue } else { '' })
            }
            return [string](Get-UGSMGameTheForestIniValue -IniData $iniData -Section $Field.Section -Key $Field.Key -DefaultValue $Field.DefaultValue)
        }
        catch {
            if ($StatusLabel) { $StatusLabel.Text = 'The Forest field load failed for ' + [string]$Field.Id + ': ' + $_.Exception.Message }
            return [string]$(if ($Field.ContainsKey('DefaultValue')) { $Field.DefaultValue } else { '' })
        }
    }

    function Get-TheForestSafeInstanceValue {
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
            if ($StatusLabel) { $StatusLabel.Text = 'TheForest instance field load failed for ' + [string]$Field.Id + ': ' + $_.Exception.Message }
        }

        if ($Field.ContainsKey('DefaultValue')) {
            return $Field.DefaultValue
        }

        return $null
    }

    function New-TheForestTextBox {
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

    function New-TheForestStretchTextBox {
        param(
            [switch]$Multiline,
            [int]$Height = 24,
            [switch]$MaskSecret
        )

        $tb = New-TheForestTextBox -Width $layout.ControlWidth -Multiline:$Multiline -Height $Height -MaskSecret:$MaskSecret
        $tb.Width = $layout.ControlWidth
        $tb.Anchor = 'Left,Right,Top'
        return $tb
    }

    function New-TheForestNarrowHost {
        $panel = New-Object System.Windows.Forms.Panel
        $panel.Dock = 'Top'
        $panel.Height = 26
        $panel.Margin = New-Object System.Windows.Forms.Padding(0)
        $panel.Padding = New-Object System.Windows.Forms.Padding(0)
        return $panel
    }

    function New-TheForestElevatedUsersControl {
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

        $status = New-UGSMLabel -Text 'Checks for PSSQLite and edits TheForest.db in the selected profile.' -X 0 -Y 0 -Width 420 -Height 28 -FontSize 8.5 -Color $Theme.Muted
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
            $moduleInstalled = Test-UGSMGameTheForestPSSQLiteInstalled
            $btnInstallSql.Visible = -not $moduleInstalled
            if (-not $moduleInstalled) {
                [void]$list.Items.Add('PSSQLite is not installed.')
                [void]$list.Items.Add('Install it to edit elevated users in TheForest.db.')
                return
            }

            $dbPath = Resolve-UGSMGameTheForestDatabasePath -Instance $Instance -PreferRuntime
            if ([string]::IsNullOrWhiteSpace([string]$dbPath)) {
                [void]$list.Items.Add('TheForest.db path could not be resolved for this profile.')
                return
            }

            if (-not (Test-Path -LiteralPath $dbPath -PathType Leaf)) {
                [void]$list.Items.Add('TheForest.db was not found yet for this instance.')
                [void]$list.Items.Add($dbPath)
                return
            }

            try {
                $ids = @(Get-UGSMGameTheForestElevatedUsers -DatabasePath $dbPath)
                if ($ids.Count -eq 0) {
                    [void]$list.Items.Add('No elevated users were found.')
                }
                else {
                    foreach ($id in $ids) { [void]$list.Items.Add($id) }
                }
            }
            catch {
                [void]$list.Items.Add('Error reading TheForest.db: ' + $_.Exception.Message)
            }
        }.GetNewClosure()

        $btnInstallSql.Add_Click({
                try {
                    Install-UGSMGameTheForestPSSQLite | Out-Null
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
                    $dbPath = Resolve-UGSMGameTheForestDatabasePath -Instance $Instance -PreferRuntime
                    if ([string]::IsNullOrWhiteSpace([string]$dbPath)) { throw 'TheForest.db path could not be resolved for this instance.' }
                    Save-UGSMGameTheForestElevatedUsers -DatabasePath $dbPath -UserIds $userIds
                    if ($StatusLabel) { $StatusLabel.Text = 'Saved elevated users to TheForest.db: ' + $dbPath }
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

    function Add-TheForestFieldRow {
        param(
            [Parameter(Mandatory)][System.Windows.Forms.FlowLayoutPanel]$Parent,
            [Parameter(Mandatory)][object]$Field,
            [Parameter(Mandatory)][object]$Instance,
            [AllowNull()][System.Windows.Forms.Label]$StatusLabel
        )

        # Shared helpers may return hashtable fields, ordered dictionaries, or PSCustomObject fields.
        # Normalize here so the TheForest editor can render any supported schema shape.
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
            if ($null -eq $modsDefinition) { $modsDefinition = Get-UGSMGameTheForestModsDefinition }

            if (Get-Command -Name New-UGSMSharedSteamWorkshopModsEditor -CommandType Function -ErrorAction SilentlyContinue) {
                [void](New-UGSMSharedSteamWorkshopModsEditor -Parent $modsHost -Instance $Instance -ModsDefinition $modsDefinition -Theme $Theme -StatusLabel $StatusLabel)
            }
            else {
                $missing = New-UGSMLabel -Text 'Shared mods helper is not loaded. Load UGSM_Game_Helper.ps1 to preview the TheForest Mods tab.' -X 0 -Y 0 -Width 900 -Height 24 -FontSize 9 -Color $Theme.Muted
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
                    $fieldHost = New-TheForestNarrowHost
                    $control = New-Object System.Windows.Forms.CheckBox
                    $control.AutoSize = $true
                    $control.Anchor = 'Left'
                    $control.Margin = New-Object System.Windows.Forms.Padding(0)
                    $control.BackColor = [System.Drawing.Color]::Transparent
                    $control.ForeColor = New-UGSMColor $Theme.Text
                    $control.Checked = ([string](Get-TheForestSafeIniValue -Field $Field) -match '^(?i:true|1|yes|on)$')
                    [void]$fieldHost.Controls.Add($control)
                    [void]$row.Controls.Add($fieldHost, 1, 0)
                    $controlMap[$Field.Id] = @{ Field = $Field; Control = $control }
                }
                'InstanceBoolean' {
                    $fieldHost = New-TheForestNarrowHost
                    $control = New-Object System.Windows.Forms.CheckBox
                    $control.AutoSize = $true
                    $control.Anchor = 'Left'
                    $control.Margin = New-Object System.Windows.Forms.Padding(0)
                    $control.BackColor = [System.Drawing.Color]::Transparent
                    $control.ForeColor = New-UGSMColor $Theme.Text
                    $instanceValue = Get-TheForestSafeInstanceValue -Field $Field
                    $control.Checked = [bool]$instanceValue
                    [void]$fieldHost.Controls.Add($control)
                    [void]$row.Controls.Add($fieldHost, 1, 0)
                    $controlMap[$Field.Id] = @{ Field = $Field; Control = $control }
                }
                'Choice' {
                    $choiceHost = New-TheForestNarrowHost
                    $control = New-Object System.Windows.Forms.ComboBox
                    $control.DropDownStyle = 'DropDownList'
                    $control.Width = [Math]::Max($layout.NarrowControlWidth, 160)
                    $control.Margin = New-Object System.Windows.Forms.Padding(0)
                    foreach ($option in @($Field.Options)) { [void]$control.Items.Add([string]$option) }
                    $currentValue = [string](Get-TheForestSafeIniValue -Field $Field)
                    if ([string]::IsNullOrWhiteSpace($currentValue) -and $Field.ContainsKey('DefaultValue')) { $currentValue = [string]$Field.DefaultValue }
                    $selectedIndex = -1
                    for ($ci = 0; $ci -lt $control.Items.Count; $ci++) {
                        if ([string]$control.Items[$ci] -ieq $currentValue) { $selectedIndex = $ci; break }
                    }
                    if ($selectedIndex -ge 0) { $control.SelectedIndex = $selectedIndex }
                    elseif ($control.Items.Count -gt 0) { $control.SelectedIndex = 0 }
                    [void]$choiceHost.Controls.Add($control)
                    [void]$row.Controls.Add($choiceHost, 1, 0)
                    $controlMap[$Field.Id] = @{ Field = $Field; Control = $control }
                }
                'Number' {
                    $numberHost = New-TheForestNarrowHost
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
                    $rawValue = Get-TheForestSafeIniValue -Field $Field
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
                    $control = New-TheForestStretchTextBox -Multiline -Height $layout.MultilineHeight
                    $control.Text = [string](Get-TheForestSafeIniValue -Field $Field)
                    [void]$row.Controls.Add($control, 1, 0)
                    $controlMap[$Field.Id] = @{ Field = $Field; Control = $control }
                }
                'Password' {
                    $control = New-TheForestStretchTextBox -MaskSecret
                    $control.Text = [string](Get-TheForestSafeIniValue -Field $Field)
                    [void]$row.Controls.Add($control, 1, 0)
                    $controlMap[$Field.Id] = @{ Field = $Field; Control = $control }
                }
                'InstanceText' {
                    $isSecretField = $false
                    if ($Field.ContainsKey('Secret')) { $isSecretField = [bool]$Field.Secret }
                    $control = New-TheForestStretchTextBox -MaskSecret:$isSecretField
                    $control.Text = [string](Get-TheForestSafeInstanceValue -Field $Field)
                    [void]$row.Controls.Add($control, 1, 0)
                    $controlMap[$Field.Id] = @{ Field = $Field; Control = $control }
                }
                'Text' {
                    $isSecretField = $false
                    if ($Field.ContainsKey('Secret')) { $isSecretField = [bool]$Field.Secret }
                    $control = New-TheForestStretchTextBox -MaskSecret:$isSecretField
                    $control.Text = [string](Get-TheForestSafeIniValue -Field $Field)
                    [void]$row.Controls.Add($control, 1, 0)
                    $controlMap[$Field.Id] = @{ Field = $Field; Control = $control }
                }
                'StringList' {
                    $control = New-TheForestTextBox -Width $layout.WideControlWidth -Multiline -Height $layout.StringListHeight
                    $resolvedListPath = Resolve-UGSMGameTheForestEditorFieldPath -Field $Field -Paths $paths
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
                    $buttonHost = New-TheForestNarrowHost
                    $control = New-UGSMButton -Text ([string]$Field.ButtonText) -X 0 -Y 0 -Width 220 -Height 30 -BackColor '#253341'
                    $action = $Field.Action
                    $control.Add_Click({
                            try { & $action $Instance $paths $StatusLabel }
                            catch { if ($StatusLabel) { $StatusLabel.Text = 'TheForest action failed: ' + $_.Exception.Message } }
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

                    New-TheForestElevatedUsersControl -Instance $Instance -Parent $elevatedHost -StatusLabel $StatusLabel | Out-Null
                    [void]$row.Controls.Add($elevatedHost, 1, 0)
                }
                default {
                    $control = New-TheForestStretchTextBox
                    $control.Text = [string](Get-TheForestSafeIniValue -Field $Field)
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
            $errorLabel = New-UGSMLabel -Text ('TheForest field row failed: ' + $_.Exception.Message) -X 0 -Y 0 -Width 700 -Height 18 -FontSize 8.5 -Color '#FF7B72'
            $errorLabel.Margin = New-Object System.Windows.Forms.Padding(0, 4, 0, 0)
            [void]$row.Controls.Add($errorLabel, 1, 0)
        }

        [void]$Parent.Controls.Add($row)
    }

    function New-TheForestEditorContent {
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
            Add-TheForestFieldRow -Parent $content -Field $field -Instance $Instance -StatusLabel $StatusLabel
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

        $title = New-UGSMLabel -Text ('TheForest Profile Editor - ' + [string]$Instance.Name) -X 12 -Y 10 -Width 420 -Height 18 -FontSize 10 -Style Bold -Color $Theme.Text
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
                $modsTabFeatures = Get-UGSMGameTheForestSupportedFeatures
                if ([bool]$modsTabFeatures.Mods) {
                    try {
                        $modsDefinition = Get-UGSMGameTheForestModsDefinition
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
                        $err = New-UGSMLabel -Text ('TheForest shared Mods tab failed: ' + $_.Exception.Message) -X 12 -Y 12 -Width 1000 -Height 24 -FontSize 9 -Color '#FF7B72'
                        [void]$tabPage.Controls.Add($err)
                        if ($StatusLabel) { $StatusLabel.Text = 'TheForest shared Mods tab failed: ' + $_.Exception.Message }
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
                    New-TheForestEditorContent -Parent $subPage -Description ([string]$(if ($subDef.PSObject.Properties.Name -contains 'Description') { $subDef.Description } else { '' })) -Fields @($subDef.Fields)
                }
            }
            else {
                New-TheForestEditorContent -Parent $tabPage -Description ([string]$(if ($tabDef.PSObject.Properties.Name -contains 'Description') { $tabDef.Description } else { '' })) -Fields @($tabDef.Fields)
            }
        }

        $btnSave.Add_Click({
                try {
                    $result = Save-UGSMGameTheForestInstanceEditor -Instance $Instance -EditorState $controlMap
                    if ($StatusLabel) {
                        $StatusLabel.Text = [string]$(if ($result -and $result.PSObject.Properties.Name -contains 'Message') { $result.Message } else { 'Saved TheForest profile settings.' })
                    }
                }
                catch {
                    if ($StatusLabel) { $StatusLabel.Text = 'TheForest save failed: ' + $_.Exception.Message }
                }
            }.GetNewClosure())

        $btnReload.Add_Click({
                try {
                    New-UGSMGameTheForestInstanceEditor -Instance $Instance -Theme $Theme -HostPanel $HostPanel -StatusLabel $StatusLabel | Out-Null
                    if ($StatusLabel) { $StatusLabel.Text = 'TheForest profile editor reloaded.' }
                }
                catch {
                    if ($StatusLabel) { $StatusLabel.Text = 'TheForest reload failed: ' + $_.Exception.Message }
                }
            }.GetNewClosure())

        $root.Tag = [pscustomobject]@{
            Instance   = $Instance
            Paths      = $paths
            ControlMap = $controlMap
            Schema     = $schema
            Status     = $StatusLabel
        }

        if ($StatusLabel) { $StatusLabel.Text = 'TheForest profile editor loaded.' }
        return $root
    }
    finally {
        $HostPanel.ResumeLayout()
    }
}

function Invoke-UGSMGameTheForestOpenPath {
    [CmdletBinding()]
    param(
        [AllowEmptyString()][AllowNull()][string]$Path,
        [switch]$EnsureFile,
        [switch]$EnsureFolder,
        [AllowNull()][System.Windows.Forms.Label]$StatusLabel,
        [string]$OpenedMessage = 'Opened path.'
    )

    if ([string]::IsNullOrWhiteSpace([string]$Path)) {
        throw 'TheForest open failed: target path was blank.'
    }

    if ($EnsureFolder) {
        if (-not (Test-Path -LiteralPath $Path -PathType Container)) {
            throw ("TheForest open failed: folder does not exist: {0}" -f $Path)
        }

        Start-Process -FilePath 'explorer.exe' -ArgumentList @($Path) -ErrorAction Stop | Out-Null
        if ($StatusLabel) { $StatusLabel.Text = $OpenedMessage }
        return
    }

    if ($EnsureFile) {
        $parent = Split-Path -Parent $Path
        if ([string]::IsNullOrWhiteSpace([string]$parent)) {
            throw 'TheForest open failed: file parent path could not be resolved.'
        }

        if (-not (Test-Path -LiteralPath $parent -PathType Container)) {
            throw ("TheForest open failed: folder does not exist: {0}" -f $parent)
        }

        if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
            throw ("TheForest open failed: file does not exist: {0}" -f $Path)
        }

        Start-Process -FilePath 'notepad.exe' -ArgumentList @($Path) -ErrorAction Stop | Out-Null
        if ($StatusLabel) { $StatusLabel.Text = $OpenedMessage }
        return
    }

    Start-Process -FilePath 'explorer.exe' -ArgumentList @($Path) -ErrorAction Stop | Out-Null
    if ($StatusLabel) { $StatusLabel.Text = $OpenedMessage }
}

function Resolve-UGSMGameTheForestEditorPath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$Instance,
        [AllowNull()]$Paths,
        [Parameter(Mandatory)][string]$Target
    )

    if (-not $Instance) {
        throw 'TheForest action failed: selected instance was null.'
    }

    if (-not $Paths) {
        $Paths = Get-UGSMGameTheForestProfilePaths -Instance $Instance
    }

    if (-not $Paths) {
        throw ("TheForest action failed: could not resolve paths for '{0}'." -f $Target)
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
        throw ("TheForest action failed: could not resolve path for '{0}'." -f $Target)
    }

    return [string]$candidate
}

function Invoke-UGSMGameTheForestEditorAction {
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

    $resolvedPath = Resolve-UGSMGameTheForestEditorPath -Instance $Instance -Paths $Paths -Target $Target

    Invoke-UGSMGameTheForestOpenPath `
        -Path $resolvedPath `
        -EnsureFile:$EnsureFile `
        -EnsureFolder:$EnsureFolder `
        -StatusLabel $StatusLabel `
        -OpenedMessage $OpenedMessage
}


<#Adjust Schema to be game specific. these values were taken from Ark Survival Evolved. #>




function Get-UGSMGameTheForestEditorSchema {
    [CmdletBinding()]
    param()

    $actions = [ordered]@{
        OpenPrimaryCfg = { param($Instance, $Paths, $StatusLabel) Invoke-UGSMGameTheForestEditorAction -Instance $Instance -Paths $Paths -Target 'PrimaryCfg' -EnsureFile -StatusLabel $StatusLabel -OpenedMessage 'Opened Server.cfg.' }
    }

    return [pscustomobject]@{
        Version = 2
        Tabs = @(
            [pscustomobject]@{
                Title       = 'Server'
                Description = 'The Forest dedicated server settings stored in Server.cfg.'
                Fields      = @(
                    @{ Id = 'ServerName'; Type = 'Text'; File = 'Server.cfg'; Key = 'serverName'; Label = 'Server Name'; DefaultValue = 'UGSM The Forest Server'; Hint = 'Name shown in the server browser.' }
                    @{ Id = 'ServerIp'; Type = 'Text'; File = 'Server.cfg'; Key = 'serverIP'; Label = 'Server IP'; DefaultValue = ''; Hint = 'Optional local/server IP. Leave blank unless the server requires a specific bind address.' }
                    @{ Id = 'ServerPlayers'; Type = 'Number'; File = 'Server.cfg'; Key = 'serverPlayers'; Label = 'Max Players'; DefaultValue = 8; Min = 1; Max = 32; Decimals = 0; Hint = 'Maximum player count.' }
                    @{ Id = 'ServerPassword'; Type = 'Text'; File = 'Server.cfg'; Key = 'serverPassword'; Label = 'Server Password'; DefaultValue = ''; Secret = $true; Hint = 'Optional join password. UGSM masks this in the UI and safe logs.' }
                    @{ Id = 'ServerPasswordAdmin'; Type = 'Text'; File = 'Server.cfg'; Key = 'serverPasswordAdmin'; Label = 'Admin Password'; DefaultValue = ''; Secret = $true; Hint = 'Optional admin password. UGSM masks this in the UI and safe logs.' }
                    @{ Id = 'ServerSteamAccount'; Type = 'Text'; File = 'Server.cfg'; Key = 'serverSteamAccount'; Label = 'Steam Server Login Token'; DefaultValue = ''; Secret = $true; Hint = 'Optional game server login token. Do not share this token.' }
                    @{ Id = 'ServerContact'; Type = 'Text'; File = 'Server.cfg'; Key = 'serverContact'; Label = 'Contact Email'; DefaultValue = ''; Hint = 'Optional public contact value used by the server.' }
                )
            }
            [pscustomobject]@{
                Title       = 'Network / Ports'
                Description = 'Ports used by The Forest dedicated server.'
                Fields      = @(
                    @{ Id = 'ServerSteamPort'; Type = 'Number'; File = 'Server.cfg'; Key = 'serverSteamPort'; Label = 'Steam Port'; DefaultValue = 8766; Min = 1; Max = 65535; Decimals = 0; Hint = 'Steam communication port.' }
                    @{ Id = 'ServerGamePort'; Type = 'Number'; File = 'Server.cfg'; Key = 'serverGamePort'; Label = 'Game Port'; DefaultValue = 27015; Min = 1; Max = 65535; Decimals = 0; Hint = 'Game communication port.' }
                    @{ Id = 'ServerQueryPort'; Type = 'Number'; File = 'Server.cfg'; Key = 'serverQueryPort'; Label = 'Query Port'; DefaultValue = 27016; Min = 1; Max = 65535; Decimals = 0; Hint = 'Server query port.' }
                )
            }
            [pscustomobject]@{
                Title       = 'Gameplay'
                Description = 'Common gameplay settings from Server.cfg.'
                Fields      = @(
                    @{ Id = 'Difficulty'; Type = 'Choice'; File = 'Server.cfg'; Key = 'difficulty'; Label = 'Difficulty'; DefaultValue = 'Normal'; Options = @('Peaceful','Normal','Hard'); Hint = 'Game difficulty.' }
                    @{ Id = 'InitType'; Type = 'Choice'; File = 'Server.cfg'; Key = 'initType'; Label = 'Init Type'; DefaultValue = 'Continue'; Options = @('New','Continue'); Hint = 'Start a new save or continue the selected slot.' }
                    @{ Id = 'Slot'; Type = 'Number'; File = 'Server.cfg'; Key = 'slot'; Label = 'Save Slot'; DefaultValue = 1; Min = 1; Max = 5; Decimals = 0; Hint = 'Save slot 1 through 5.' }
                    @{ Id = 'ServerAutoSaveInterval'; Type = 'Number'; File = 'Server.cfg'; Key = 'serverAutoSaveInterval'; Label = 'Auto Save Interval'; DefaultValue = 15; Min = 1; Max = 1440; Decimals = 0; Hint = 'Auto-save interval in minutes.' }
                    @{ Id = 'EnableVac'; Type = 'Boolean'; File = 'Server.cfg'; Key = 'enableVAC'; Label = 'Enable VAC'; DefaultValue = $true; Hint = 'Enable Valve Anti-Cheat.' }
                    @{ Id = 'ShowLogs'; Type = 'Boolean'; File = 'Server.cfg'; Key = 'showLogs'; Label = 'Show Logs'; DefaultValue = $false; Hint = 'Show server log window/output if supported.' }
                    @{ Id = 'VeganMode'; Type = 'Boolean'; File = 'Server.cfg'; Key = 'veganMode'; Label = 'Vegan Mode'; DefaultValue = $false; Hint = 'No enemies.' }
                    @{ Id = 'VegetarianMode'; Type = 'Boolean'; File = 'Server.cfg'; Key = 'vegetarianMode'; Label = 'Vegetarian Mode'; DefaultValue = $false; Hint = 'No enemies during daytime.' }
                    @{ Id = 'ResetHolesMode'; Type = 'Boolean'; File = 'Server.cfg'; Key = 'resetHolesMode'; Label = 'Reset Holes Mode'; DefaultValue = $false; Hint = 'Reset structure holes when loading.' }
                    @{ Id = 'TreeRegrowMode'; Type = 'Boolean'; File = 'Server.cfg'; Key = 'treeRegrowMode'; Label = 'Tree Regrow Mode'; DefaultValue = $false; Hint = 'Regrow cut trees when sleeping.' }
                    @{ Id = 'AllowBuildingDestruction'; Type = 'Boolean'; File = 'Server.cfg'; Key = 'allowBuildingDestruction'; Label = 'Allow Building Destruction'; DefaultValue = $true; Hint = 'Allow buildings to be destroyed.' }
                    @{ Id = 'AllowEnemiesCreativeMode'; Type = 'Boolean'; File = 'Server.cfg'; Key = 'allowEnemiesCreativeMode'; Label = 'Allow Enemies In Creative'; DefaultValue = $false; Hint = 'Allow enemies in creative games.' }
                    @{ Id = 'AllowCheats'; Type = 'Boolean'; File = 'Server.cfg'; Key = 'allowCheats'; Label = 'Allow Client Console'; DefaultValue = $false; Hint = 'Allow clients to use the built-in console.' }
                )
            }
            [pscustomobject]@{
                Title       = 'Performance / Advanced'
                Description = 'Performance settings and manual file access.'
                Fields      = @(
                    @{ Id = 'TargetFpsIdle'; Type = 'Number'; File = 'Server.cfg'; Key = 'targetFpsIdle'; Label = 'Target FPS Idle'; DefaultValue = 5; Min = 1; Max = 240; Decimals = 0; Hint = 'Target FPS when no clients are connected.' }
                    @{ Id = 'TargetFpsActive'; Type = 'Number'; File = 'Server.cfg'; Key = 'targetFpsActive'; Label = 'Target FPS Active'; DefaultValue = 60; Min = 1; Max = 240; Decimals = 0; Hint = 'Target FPS while clients are connected.' }
                    @{ Id = 'OpenPrimaryCfg'; Type = 'ActionButton'; Label = 'Server.cfg'; ButtonText = 'Open Server.cfg'; Action = $actions.OpenPrimaryCfg; Hint = 'Open the managed Server.cfg file for this instance.' }
                )
            }
            [pscustomobject]@{
                Title       = 'Mods'
                Description = 'The Forest does not include native dedicated-server mod support through UGSM. Some players use third-party tools such as ModAPI, but that workflow is outside UGSM managed mods. UGSM does not install, manage, validate, or support third-party mod loaders for this game. Third-party mods or loaders may affect stability, security, saves, compatibility, and gameplay. Use them at your own risk. UGSM is not responsible for server issues, data loss, broken saves, crashes, malware, or other problems caused by third-party tools or mod files.'
                Fields      = @()
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
                            $result = Test-UGSMDiscordWebhook -WebhookUrl $discordModel.EffectiveWebhookUrl -Label ('The Forest ' + [string]$Instance.Name)
                            if ($result -and $result.PSObject.Properties['Success'] -and [bool]$result.Success) {
                                $target = if ($discordModel.UsesGlobalWebhook) { 'global webhook' } else { 'server webhook' }
                                if ($StatusLabel) { $StatusLabel.Text = 'Discord test sent successfully using the ' + $target + '.' }
                            }
                            else {
                                $errorText = if ($result -and $result.PSObject.Properties['Error']) { [string]$result.Error } else { 'Unknown Discord webhook error.' }
                                if ($StatusLabel) { $StatusLabel.Text = 'Discord test failed: ' + $errorText }
                            }
                        }
                        catch { if ($StatusLabel) { $StatusLabel.Text = 'Discord test failed: ' + $_.Exception.Message } }
                    } }
                )
            }
        )
    }
}
