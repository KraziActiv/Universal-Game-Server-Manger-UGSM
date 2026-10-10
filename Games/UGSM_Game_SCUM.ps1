# SCUM Game
# Pre Template compitable.

$script:UGSMGameSCUMEditorSchemaCache = $null

function Test-UGSMGameSCUMVerboseLogging {
    [CmdletBinding()]
    param()

    if (Get-Variable -Name 'UGSM_EnableVerboseSCUMLogging' -Scope Script -ErrorAction SilentlyContinue) {
        try { return [bool]$script:UGSM_EnableVerboseSCUMLogging } catch { }
    }

    $envValue = [string]$env:UGSM_VERBOSE_SCUM
    return ($envValue -in @('1', 'true', 'yes', 'on'))
}


function ConvertTo-UGSMGameSCUMSafeLogText {
    [CmdletBinding()]
    param([AllowNull()][object]$Value)

    if ($null -eq $Value) { return '' }

    $text = [string]$Value
    if ([string]::IsNullOrEmpty($text)) { return $text }

    try {
        if ($global:UGSM_Settings) {
            $pairs = @(
                @($global:UGSM_Settings.ProfileRoot, '%UGSM_PROFILES%'),
                @($global:UGSM_Settings.ProfilesRoot, '%UGSM_PROFILES%'),
                @($global:UGSM_Settings.SteamRoot, '%UGSM_STEAM%'),
                @($global:UGSM_Settings.SteamCmdRoot, '%UGSM_STEAM%'),
                @($global:UGSM_Settings.InstallRoot, '%UGSM_INSTALL%'),
                @($global:UGSM_Settings.ServerRoot, '%UGSM_SERVER_ROOT%')
            )

            foreach ($pair in $pairs) {
                $raw = [string]$pair[0]
                $label = [string]$pair[1]
                if (-not [string]::IsNullOrWhiteSpace($raw)) {
                    $escaped = [regex]::Escape($raw.TrimEnd('\\','/'))
                    $text = [regex]::Replace($text, $escaped, $label, [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
                }
            }
        }
    }
    catch { }

    try {
        $local = [Environment]::GetFolderPath('LocalApplicationData')
        if (-not [string]::IsNullOrWhiteSpace($local)) {
            $text = [regex]::Replace($text, [regex]::Escape($local), '%LOCALAPPDATA%', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
        }

        $profile = [Environment]::GetFolderPath('UserProfile')
        if (-not [string]::IsNullOrWhiteSpace($profile)) {
            $text = [regex]::Replace($text, [regex]::Escape($profile), '%USERPROFILE%', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
        }

        $text = [regex]::Replace($text, '(?i)C:\\Users\\[^\\;:"''<>\r\n]+', '%USERPROFILE%')
        $text = [regex]::Replace($text, '(?i)(https://discord(?:app)?\.com/api/webhooks/)[^\s;"''<>]+', '$1<redacted>')
        $text = [regex]::Replace($text, '(?i)(password\s*[=:]\s*)[^;\r\n]+', '$1<redacted>')
        $text = [regex]::Replace($text, '(?i)(token\s*[=:]\s*)[^;\r\n]+', '$1<redacted>')
        $text = [regex]::Replace($text, '(?i)(gslt\s*[=:]\s*)[^;\r\n]+', '$1<redacted>')
        $text = [regex]::Replace($text, '(?i)(api[_ -]?key\s*[=:]\s*)[^;\r\n]+', '$1<redacted>')
        $text = [regex]::Replace($text, '(?i)(secret\s*[=:]\s*)[^;\r\n]+', '$1<redacted>')
    }
    catch { }

    return $text
}

function Write-UGSMGameSCUMLog {
    [CmdletBinding()]
    param(
        [ValidateSet('TRACE', 'DEBUG', 'INFO', 'WARN', 'ERROR', 'FATAL')]
        [string]$Level = 'INFO',

        [Parameter(Mandatory)]
        [string]$Message,

        [System.Exception]$Exception,

        [switch]$VerboseOnly
    )

    if ($VerboseOnly.IsPresent -and -not (Test-UGSMGameSCUMVerboseLogging)) { return }

    $safeMessage = ConvertTo-UGSMGameSCUMSafeLogText -Value $Message

    if (Get-Command -Name Write-UGSMLog -ErrorAction SilentlyContinue) {
        if ($Exception) {
            Write-UGSMLog -Level $Level -Category 'SCUM' -Message $safeMessage -Exception $Exception
        }
        else {
            Write-UGSMLog -Level $Level -Category 'SCUM' -Message $safeMessage
        }
        return
    }

    if ($Exception) {
        Write-Host (('[{0}] [SCUM] {1}: {2}' -f $Level, $safeMessage, (ConvertTo-UGSMGameSCUMSafeLogText -Value $Exception.Message)))
    }
    else {
        Write-Host (('[{0}] [SCUM] {1}' -f $Level, $safeMessage))
    }
}

function Write-UGSMGameSCUMPathLog {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Message
    )

    Write-UGSMGameSCUMLog -Level 'DEBUG' -Message $Message -VerboseOnly
}


function Ensure-UGSMGameSCUMInstanceDiscordShape {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$Instance
    )

    if (-not $Instance) { return $Instance }

    if (-not $Instance.PSObject.Properties['Discord'] -or $null -eq $Instance.Discord) {
        Add-Member -InputObject $Instance -MemberType NoteProperty -Name 'Discord' -Value ([pscustomobject]@{}) -Force
    }

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

function Get-UGSMGameSCUMSupportedFeatures {
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
        GracefulStop  = $false

        Mods          = $false
        Workshop      = $false
        ModTabMode    = 'None'

        ModStateStorage           = 'InstanceJson'
        InstanceModsProperty      = 'Mods'
        InstanceModStatesProperty = 'ModStates'

        Discord       = $true
        AdvancedFiles = $true
        UserLists     = $true

        IniFiles        = $true
        JsonFiles       = $true
        XmlFiles        = $false
        CfgFiles        = $false
        PropertiesFiles = $false
        YamlFiles       = $false
        TomlFiles       = $false
        LuaFiles        = $false
        TextFiles       = $true
        PSSQLite        = $true

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
            OpenManifest     = $true
            RefreshSummary   = $true
        }
    }
}

function Get-UGSMGameSCUMModsDefinition {
    [CmdletBinding()]
    param()

    $features = Get-UGSMGameSCUMSupportedFeatures

    if (Get-Command -Name New-UGSMDefaultModsDefinition -ErrorAction SilentlyContinue) {
        $mods = New-UGSMDefaultModsDefinition -GameId 'SCUM' -DisplayName 'Mods' -Supported ([bool]$features.Mods)
    }
    else {
        $mods = [pscustomobject]@{
            Supported = [bool]$features.Mods
            DisplayName = 'Mods'
            Version = 2
            ModStateStorage = 'InstanceJson'
            InstanceModsProperty = 'Mods'
            InstanceModStatesProperty = 'ModStates'
            ModTabMode = 'None'
            Capabilities = [pscustomobject]@{ SteamWorkshop = $false; ArchiveImport = $false; FolderImport = $false; FrameworkInstall = $false; PluginManager = $false; MapList = $false; ConfigMerge = $false; LoadOrder = $false; UrlDownload = $false; KeyCopy = $false; ServerSideCopy = $false; RuntimeSync = $false; BuildIndexCache = $false; OpenManifest = $true; RefreshSummary = $true }
            Archive = [pscustomobject]@{ AllowedExtensions = @(); InstallFolderRelative = $null; RequireSafetyNotice = $false }
            Workshop = [pscustomobject]@{ IdField = 'WorkshopItemIds'; SupportsCollections = $false; ConfigStrategy = 'Unsupported'; AppId = '513710'; WorkshopAppId = '513710'; LoginMode = 'Anonymous' }
            Framework = [pscustomobject]@{ Id = ''; Label = ''; OfficialSourceOnly = $true; RequiresConfirmation = $false }
            Paths = [pscustomobject]@{ ModsFolderRelative = $null; ManifestFileName = $null }
            StoragePolicy = [pscustomobject]@{ Mode = 'InstanceJson'; KeepWorkshopModsShared = $true; CopyFullModsToProfile = $false; CopyOnlyRequiredFilesToProfile = $true; RuntimeMode = 'None'; SummaryFileName = $null }
            UI = [pscustomobject]@{ InlineWorkshopInput = $false; ShowActiveLoadOrder = $false; ShowSafetyNotice = $false; ShowProfileLightNotice = $false }
            Safety = [pscustomobject]@{ ShowThirdPartyNotice = $false; RequireConfirmation = $false; NoticeKind = 'None' }
            Hooks = [pscustomobject]@{ Refresh = ''; Save = ''; Install = ''; Remove = ''; Validate = ''; BuildCustomTab = ''; AfterModsChanged = ''; AfterWorkshopDownload = '' }
            GameId = 'SCUM'
        }
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

    if ($mods.PSObject.Properties['Supported']) { $mods.Supported = [bool]$features.Mods }
    else { Add-Member -InputObject $mods -MemberType NoteProperty -Name Supported -Value ([bool]$features.Mods) -Force }

    if ($mods.PSObject.Properties['ModTabMode']) { $mods.ModTabMode = 'None' }
    else { Add-Member -InputObject $mods -MemberType NoteProperty -Name ModTabMode -Value 'None' -Force }

    if ($mods.PSObject.Properties['Capabilities'] -and $mods.Capabilities) {
        foreach ($name in @('SteamWorkshop','ArchiveImport','FolderImport','FrameworkInstall','PluginManager','MapList','ConfigMerge','LoadOrder','UrlDownload','KeyCopy','ServerSideCopy','RuntimeSync','BuildIndexCache')) {
            if ($mods.Capabilities.PSObject.Properties[$name]) { $mods.Capabilities.$name = $false }
        }
        foreach ($name in @('OpenManifest','RefreshSummary')) {
            if ($mods.Capabilities.PSObject.Properties[$name]) { $mods.Capabilities.$name = $true }
        }
    }

    return $mods
}


function Get-UGSMGameSCUMMetadata {
    [CmdletBinding()]
    param()

    $serverExeRelativePath = Join-Path 'SCUM/Binaries/Win64' 'SCUMServer.exe'
    $features = Get-UGSMGameSCUMSupportedFeatures
    $modsDefinition = Get-UGSMGameSCUMModsDefinition

    return [pscustomobject]@{
        Id                       = 'SCUM'
        Name                     = 'SCUM'
        Category                 = 'Survival'
        Description              = 'Dedicated server module for SCUM with install management, profile support, and SCUM.db elevated user editing.'
        IsCustom                 = $false
        SupportTier              = 'Full'
        SortOrder                = 10
        IsVisible                = [bool]$features.IsVisible

        SupportedTabs            = @('Home', 'Games', 'Instances', 'Analytics', 'Tasks', 'Files', 'About', 'Settings')
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
        SteamAppId               = 3792580
        SteamStoreAppId          = 513710
        ServerExecutable         = 'SCUMServer.exe'
        ServerExecutableRelative = $serverExeRelativePath
        UsesSharedBinaries       = $true
        InstanceType             = 'DedicatedServer'

        ConfigRootRelative       = 'SCUM/Saved/Config/WindowsServer'
        SaveRootRelative         = 'SCUM/Saved/SaveFiles'
        LogRootRelative          = 'SCUM/Saved/Logs'

        RequiredFiles            = @(
            $serverExeRelativePath
            'SCUM/Content'
        )

        InstallMarkers           = @(
            $serverExeRelativePath
        )

        PortSchema               = @(
            @{ Name = 'GamePort'; Protocol = 'UDP'; PreferredStart = 7777 }
            @{ Name = 'QueryPort'; Protocol = 'UDP'; PreferredStart = 7779 }
            @{ Name = 'RconPort'; Protocol = 'TCP'; PreferredStart = 7781 }
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
            RequiresPSSQLiteForElevatedUsers = $true
            ElevatedUsersDatabaseRelative    = 'SCUM\Saved\SaveFiles\SCUM.db'
            Notes                            = @(
                'Elevated user management requires the PSSQLite PowerShell module.',
                'Players usually need to have joined the server at least once before they can appear in SCUM.db workflows.',
                'SCUM mods are not enabled in UGSM for this pass.'
            )
        }
    }
}

function Get-UGSMGameSCUMInstallDefinition {
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
            throw 'SCUM install definition failed: InstallPath could not be resolved.'
        }

        $InstallPath = Join-Path $steamRoot 'servers\SCUM'
    }

    $meta = Get-UGSMGameSCUMMetadata

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
        LogRootPath          = Join-Path $InstallPath 'SCUM\Saved\Logs'
    }
}

function Get-UGSMGameSCUMAppDataRoot {
    [CmdletBinding()]
    param()

    if (Get-Command -Name Get-UGSMAppDataRoot -ErrorAction SilentlyContinue) {
        return [string](Get-UGSMAppDataRoot)
    }

    return (Join-Path $env:LOCALAPPDATA 'UGSM')
}

function Get-UGSMGameSCUMProfileBaseRoot {
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
        $probe = Get-UGSMDefaultInstanceProfilePath -GameId 'SCUM' -Name '_probe_'
        if (-not [string]::IsNullOrWhiteSpace([string]$probe)) {
            return (Split-Path -Parent (Split-Path -Parent $probe))
        }
    }

    return (Join-Path (Get-UGSMGameSCUMAppDataRoot) 'Profiles')
}

function Get-UGSMGameSCUMTemplateRoot {
    [CmdletBinding()]
    param()

    return (Join-Path (Get-UGSMGameSCUMAppDataRoot) 'Templates\SCUM')
}

function Get-UGSMGameSCUMProfileRoot {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ProfileName
    )

    return (Join-Path (Join-Path (Get-UGSMGameSCUMProfileBaseRoot) 'SCUM') $ProfileName)
}


function Get-UGSMGameSCUMRuntimeRoot {
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
            $profileRoot = Get-UGSMGameSCUMProfileRoot -ProfileName $candidate
        }
    }

    if ([string]::IsNullOrWhiteSpace([string]$profileRoot)) {
        throw 'SCUM runtime root could not be resolved for the selected instance.'
    }

    return $profileRoot
}

function Remove-UGSMGameSCUMPath {
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

function New-UGSMGameSCUMDirectoryJunction {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$LinkPath,

        [Parameter(Mandatory)]
        [string]$TargetPath
    )

    if (-not (Test-Path -LiteralPath $TargetPath -PathType Container)) {
        throw "SCUM junction target was not found: $TargetPath"
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

        Remove-UGSMGameSCUMPath -Path $LinkPath
    }

    try {
        New-Item -ItemType Junction -Path $LinkPath -Target $TargetPath -Force -ErrorAction Stop | Out-Null
    }
    catch {
        $null = & cmd.exe /c ('mklink /J "{0}" "{1}"' -f $LinkPath, $TargetPath)
        if ($LASTEXITCODE -ne 0 -and -not (Test-Path -LiteralPath $LinkPath -PathType Container)) {
            throw "SCUM junction creation failed for '$LinkPath' -> '$TargetPath'."
        }
    }
}

function Copy-UGSMGameSCUMFilesToRuntime {
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

    Copy-UGSMGameSCUMDirectoryContent -Source $Source -Destination $Destination -ClearDestination:$ClearDestination
}

function Get-UGSMGameSCUMRuntimeDefinition {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Instance,

        [Parameter(Mandatory)]
        [object]$InstallDefinition
    )

    # SCUM does not currently expose a clean profile argument like DayZ -profiles.
    # To keep profiles isolated without duplicating the full server install, UGSM launches
    # through a lightweight per-profile runtime tree made of junctions to shared binaries.
    # The real per-server data remains only under:
    #   <ProfilePath>\SCUM\Saved\...
    $runtimeRoot = Get-UGSMGameSCUMRuntimeRoot -Instance $Instance
    $runtimeInstallRoot = $runtimeRoot
    $runtimeScumRoot = Join-Path $runtimeRoot 'SCUM'
    $runtimeSavedRoot = Join-Path $runtimeScumRoot 'Saved'

    return [pscustomobject]@{
        RuntimeRoot           = $runtimeRoot
        RuntimeInstallRoot    = $runtimeInstallRoot
        RuntimeScumRoot       = $runtimeScumRoot
        RuntimeSavedRoot      = $runtimeSavedRoot
        RuntimeConfigRootPath = Join-Path $runtimeSavedRoot 'Config\WindowsServer'
        RuntimeSaveRootPath   = Join-Path $runtimeSavedRoot 'SaveFiles'
        RuntimeLogRootPath    = Join-Path $runtimeSavedRoot 'Logs'
        RuntimeServerExePath  = Join-Path $runtimeScumRoot 'Binaries\Win64\SCUMServer.exe'
        SharedInstallPath     = [string]$InstallDefinition.InstallPath
        SharedScumRoot        = Join-Path ([string]$InstallDefinition.InstallPath) 'SCUM'
    }
}

function Resolve-UGSMGameSCUMDatabasePath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Instance,

        [switch]$PreferRuntime
    )

    $paths = Get-UGSMGameSCUMProfilePaths -Instance $Instance

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

function Ensure-UGSMGameSCUMRuntimeLayout {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Instance,

        [Parameter(Mandatory)]
        [object]$InstallDefinition
    )

    $runtime = Get-UGSMGameSCUMRuntimeDefinition -Instance $Instance -InstallDefinition $InstallDefinition
    $sharedInstallRoot = [string]$InstallDefinition.InstallPath
    $sharedScumRoot = Join-Path $sharedInstallRoot 'SCUM'

    $instanceId = [string]$(if ($Instance -and $Instance.PSObject.Properties['Id']) { $Instance.Id } else { $Instance.Name })
    $profileName = [string]$(if ($Instance -and $Instance.PSObject.Properties['Name']) { $Instance.Name } else { $instanceId })

    $profilePath = $null
    if ($Instance -and $Instance.PSObject.Properties.Name -contains 'ProfilePath' -and -not [string]::IsNullOrWhiteSpace([string]$Instance.ProfilePath)) {
        $profilePath = [string]$Instance.ProfilePath
    }
    elseif (-not [string]::IsNullOrWhiteSpace($profileName)) {
        $profilePath = Get-UGSMGameSCUMProfileRoot -ProfileName $profileName
    }

    if ([string]::IsNullOrWhiteSpace($profilePath)) {
        throw 'SCUM runtime layout failed: Profile path could not be resolved.'
    }

    if (-not (Test-Path -LiteralPath $sharedInstallRoot -PathType Container)) {
        throw "SCUM runtime layout failed: Shared install root was not found: $sharedInstallRoot"
    }

    if (-not (Test-Path -LiteralPath $sharedScumRoot -PathType Container)) {
        throw "SCUM runtime layout failed: Shared SCUM root was not found: $sharedScumRoot"
    }

    # Keep only the SCUM profile data as real files. Everything else that SCUM needs to
    # resolve beside the EXE is a junction back to the one shared SteamCMD install.
    foreach ($path in @($runtime.RuntimeRoot, $runtime.RuntimeScumRoot, $runtime.RuntimeSavedRoot, $runtime.RuntimeConfigRootPath, $runtime.RuntimeSaveRootPath, $runtime.RuntimeLogRootPath)) {
        if (-not (Test-Path -LiteralPath $path -PathType Container)) {
            New-Item -ItemType Directory -Path $path -Force | Out-Null
        }
    }

    # Root-level folders beside SCUM, such as Engine, are linked into the profile root.
    foreach ($child in @(Get-ChildItem -LiteralPath $sharedInstallRoot -Force -ErrorAction SilentlyContinue)) {
        if ($child.Name -ieq 'SCUM') {
            continue
        }

        $targetPath = Join-Path $runtime.RuntimeInstallRoot $child.Name
        if ($child.PSIsContainer) {
            New-UGSMGameSCUMDirectoryJunction -LinkPath $targetPath -TargetPath $child.FullName
        }
        else {
            # Do not copy shared install root files into each profile. SCUM profiles should
            # only contain per-server Saved data plus junctions back to the shared install.
            # Remove legacy copies that older UGSM builds may have placed here.
            if (Test-Path -LiteralPath $targetPath -PathType Leaf) {
                try {
                    Remove-Item -LiteralPath $targetPath -Force -ErrorAction Stop
                    Write-UGSMGameSCUMLog -Level 'DEBUG' -Message ("Removed legacy copied SCUM root file from profile runtime. InstanceId={0}; File={1}" -f $instanceId, $targetPath)
                }
                catch {
                    Write-UGSMGameSCUMLog -Level 'WARN' -Message ("Could not remove legacy copied SCUM root file from profile runtime. InstanceId={0}; File={1}" -f $instanceId, $targetPath) -Exception $_.Exception
                }
            }
        }
    }

    # SCUM folders are linked except Saved. Saved stays real and per-profile.
    foreach ($child in @(Get-ChildItem -LiteralPath $sharedScumRoot -Force -ErrorAction SilentlyContinue)) {
        if ($child.Name -ieq 'Saved') {
            continue
        }

        $targetPath = Join-Path $runtime.RuntimeScumRoot $child.Name
        if ($child.PSIsContainer) {
            New-UGSMGameSCUMDirectoryJunction -LinkPath $targetPath -TargetPath $child.FullName
        }
        else {
            Copy-Item -LiteralPath $child.FullName -Destination $targetPath -Force -ErrorAction SilentlyContinue
        }
    }

    $profileConfigRoot = Join-Path $profilePath 'SCUM\Saved\Config\WindowsServer'
    $profileSaveRoot = Join-Path $profilePath 'SCUM\Saved\SaveFiles'
    $profileServerSettings = Join-Path $profileConfigRoot 'ServerSettings.ini'

    if (-not (Test-Path -LiteralPath $profileServerSettings -PathType Leaf)) {
        Write-UGSMGameSCUMLog -Level 'WARN' -Message ("SCUM profile config was missing before runtime layout. Reinitializing profile. InstanceId={0}; ProfilePath={1}; ExpectedConfig={2}" -f $instanceId, $profilePath, $profileServerSettings)
        try {
            Initialize-UGSMGameSCUMProfile -Instance $Instance -InstallPath ([string]$InstallDefinition.InstallPath) -Force | Out-Null
        }
        catch {
            Write-UGSMGameSCUMLog -Level 'ERROR' -Message ("SCUM profile reinitialization failed before runtime layout. InstanceId={0}" -f $instanceId) -Exception $_.Exception
            throw
        }
    }

    if (-not (Test-Path -LiteralPath $profileConfigRoot -PathType Container)) {
        New-Item -ItemType Directory -Path $profileConfigRoot -Force | Out-Null
    }
    if (-not (Test-Path -LiteralPath $profileSaveRoot -PathType Container)) {
        New-Item -ItemType Directory -Path $profileSaveRoot -Force | Out-Null
    }

    $runtimeServerSettings = Join-Path ([string]$runtime.RuntimeConfigRootPath) 'ServerSettings.ini'
    if (-not (Test-Path -LiteralPath $runtimeServerSettings -PathType Leaf)) {
        throw "SCUM runtime layout failed: ServerSettings.ini was not found in the profile config path: $runtimeServerSettings"
    }

    $serverExe = [string]$runtime.RuntimeServerExePath
    if (-not (Test-Path -LiteralPath $serverExe -PathType Leaf)) {
        throw "SCUM runtime layout failed: SCUMServer.exe was not available through the profile runtime junctions: $serverExe"
    }

    Write-UGSMGameSCUMLog -Level 'DEBUG' -Message ("SCUM lightweight runtime layout ready. InstanceId={0}; ProfileRoot={1}; RuntimeExe={2}; ConfigRoot={3}" -f $instanceId, $runtime.RuntimeRoot, $serverExe, $runtime.RuntimeConfigRootPath)

    return $runtime
}

function Initialize-UGSMGameSCUMRuntimeData {
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
        Copy-UGSMGameSCUMFilesToRuntime -Source $ProfileConfigRoot -Destination $RuntimeConfigRoot
    }

    if ((Get-ChildItem -LiteralPath $RuntimeSaveRoot -Force -ErrorAction SilentlyContinue | Measure-Object).Count -eq 0) {
        Copy-UGSMGameSCUMFilesToRuntime -Source $ProfileSaveRoot -Destination $RuntimeSaveRoot
    }
}

function Copy-UGSMGameSCUMDirectoryContent {
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

    try {
        $sourceFull = [System.IO.Path]::GetFullPath($Source)
        $destinationFull = [System.IO.Path]::GetFullPath($Destination)
        if ($sourceFull.Equals($destinationFull, [System.StringComparison]::OrdinalIgnoreCase)) {
            return
        }
    }
    catch {}

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

function Get-UGSMGameSCUMRunningBootstrapProcesses {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ServerExecutablePath,

        [Parameter(Mandatory)]
        [datetime]$StartedAfter
    )

    $matches = @()
    try {
        $matches = @(Get-CimInstance Win32_Process -Filter "Name = 'SCUMServer.exe'" -ErrorAction Stop)
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

function Start-UGSMGameSCUMBootstrapProcess {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ServerExecutablePath,

        [Parameter(Mandatory)]
        [string]$WorkingDirectory,

        [int]$BootstrapSeconds = 15
    )

    if (-not (Test-Path -LiteralPath $ServerExecutablePath -PathType Leaf)) {
        throw "SCUM server executable was not found: $ServerExecutablePath"
    }

    $bootstrapTime = [Math]::Max(10, $BootstrapSeconds)
    $launchStartedAt = Get-Date
    $preferredPid = 0

    $proc = Start-Process `
        -FilePath $ServerExecutablePath `
        -ArgumentList @('-log', '-MaxPlayers=1', '-nobattleye') `
        -WorkingDirectory $WorkingDirectory `
        -PassThru

    try {
        if ($proc -and $proc.PSObject.Properties['Id']) {
            $preferredPid = [int]$proc.Id
        }
    }
    catch {
        $preferredPid = 0
    }

    Start-Sleep -Seconds $bootstrapTime

    $stopResults = @()

    if ($preferredPid -gt 0) {
        $targetPid = [int]$preferredPid

        try {
            & taskkill.exe /PID $targetPid /T /F | Out-Null
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

    $remaining = @(Get-Process -Name 'SCUMServer' -ErrorAction SilentlyContinue)

    if ($remaining.Count -gt 0) {
        & taskkill.exe /IM SCUMServer.exe /T /F | Out-Null
        $fallbackExit = $LASTEXITCODE

        Start-Sleep -Seconds 2

        $remaining = @(Get-Process -Name 'SCUMServer' -ErrorAction SilentlyContinue)
        foreach ($p in $remaining) {
            try {
                if ($p -and $p.PSObject.Properties['Id']) {
                    Stop-Process -Id ([int]$p.Id) -Force -ErrorAction Stop
                }
            }
            catch {
            }
        }
    }

    Start-Sleep -Seconds 2

    $remainingFinal = @(Get-Process -Name 'SCUMServer' -ErrorAction SilentlyContinue)
    $remainingPids = @()
    foreach ($p in $remainingFinal) {
        try {
            if ($p -and $p.PSObject.Properties['Id']) {
                $remainingPids += [int]$p.Id
            }
        }
        catch {
        }
    }

    return [pscustomobject]@{
        PreferredPid  = $preferredPid
        StartedAt     = $launchStartedAt
        BootstrapTime = $bootstrapTime
        StopResults   = $stopResults
        Exited        = ($remainingFinal.Count -eq 0)
        RemainingPids = @($remainingPids)
    }
}



function Initialize-UGSMGameSCUMTemplateDefaultFiles {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$TemplateConfigRoot
    )

    if ([string]::IsNullOrWhiteSpace($TemplateConfigRoot)) {
        throw 'SCUM default template creation failed: TemplateConfigRoot is blank.'
    }

    if (-not (Test-Path -LiteralPath $TemplateConfigRoot -PathType Container)) {
        New-Item -ItemType Directory -Path $TemplateConfigRoot -Force | Out-Null
    }

    $serverSettingsPath = Join-Path $TemplateConfigRoot 'ServerSettings.ini'

    function Add-SCUMTemplateFieldsFromTab {
        param([AllowNull()][object]$Tab)

        if (-not $Tab) { return }

        if ($Tab.PSObject.Properties['Fields']) {
            foreach ($field in @($Tab.Fields)) {
                if (-not $field) { continue }

                $fieldType = [string]$field.Type
                if ($fieldType -notin @('Text','Password','MultilineText','Number','Boolean')) { continue }

                $section = [string]$field.Section
                $key = [string]$field.Key
                if ([string]::IsNullOrWhiteSpace($section) -or [string]::IsNullOrWhiteSpace($key)) { continue }

                $value = ''
                if ($field.ContainsKey('DefaultValue')) {
                    $value = [string]$field.DefaultValue
                }

                Set-UGSMGameSCUMIniValue -Path $serverSettingsPath -Section $section -Key $key -Value $value
            }
        }

        if ($Tab.PSObject.Properties['SubTabs']) {
            foreach ($subTab in @($Tab.SubTabs)) {
                Add-SCUMTemplateFieldsFromTab -Tab $subTab
            }
        }
    }

    $schema = Get-UGSMGameSCUMEditorSchema
    foreach ($tab in @($schema.Tabs)) {
        Add-SCUMTemplateFieldsFromTab -Tab $tab
    }

    foreach ($listFile in @('AdminUsers.ini','ExclusiveUsers.ini','WhitelistedUsers.ini','BannedUsers.ini','SilencedUsers.ini')) {
        $path = Join-Path $TemplateConfigRoot $listFile
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
            Set-Content -LiteralPath $path -Value '' -Encoding UTF8
        }
    }

    foreach ($jsonFile in @('RaidTimes.json','EconomyOverride.json')) {
        $path = Join-Path $TemplateConfigRoot $jsonFile
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
            Set-Content -LiteralPath $path -Value "{}" -Encoding UTF8
        }
    }

    return [pscustomobject]@{
        Success            = $true
        TemplateConfigRoot = $TemplateConfigRoot
        ServerSettingsPath = $serverSettingsPath
        GeneratedFiles     = @(
            Get-ChildItem -LiteralPath $TemplateConfigRoot -File -Force -ErrorAction SilentlyContinue |
            Select-Object -ExpandProperty Name
        )
    }
}

function Ensure-UGSMGameSCUMTemplate {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$InstallPath,

        [switch]$ForceRefresh,

        [int]$BootstrapSeconds = 15
    )

    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    Write-UGSMGameSCUMLog -Level 'INFO' -Message ("Template ensure requested. InstallPath={0}; Force={1}" -f $InstallPath, [bool]$ForceRefresh.IsPresent)

    $definition = Get-UGSMGameSCUMInstallDefinition -InstallPath $InstallPath
    $validation = Test-UGSMGameSCUMInstall -InstallPath $InstallPath
    if (-not $validation.IsValid) {
        throw "SCUM install is not valid at '$InstallPath'."
    }

    $templateRoot = Get-UGSMGameSCUMTemplateRoot
    $templateConfigRoot = Join-Path $templateRoot 'Config\WindowsServer'
    $templateSaveRoot = Join-Path $templateRoot 'SaveFiles'

    New-Item -ItemType Directory -Path $templateRoot -Force | Out-Null
    New-Item -ItemType Directory -Path $templateConfigRoot -Force | Out-Null
    New-Item -ItemType Directory -Path $templateSaveRoot -Force | Out-Null

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
    $bootstrapError = ''
    if ($needsBootstrap) {
        try {
            $bootstrapResult = Start-UGSMGameSCUMBootstrapProcess -ServerExecutablePath $definition.ServerExecutablePath -WorkingDirectory $InstallPath -BootstrapSeconds $BootstrapSeconds
            if ($bootstrapResult -and $bootstrapResult.PSObject.Properties['Exited'] -and -not [bool]$bootstrapResult.Exited) {
                $bootstrapError = ('SCUM bootstrap server did not shut down cleanly. Remaining PIDs: {0}' -f (($bootstrapResult.RemainingPids -join ', ')))
            }
        }
        catch {
            $bootstrapError = $_.Exception.Message
        }

        if (-not [string]::IsNullOrWhiteSpace($bootstrapError)) {
            Write-UGSMGameSCUMLog -Level 'WARN' -Message ("SCUM bootstrap could not fully complete. Falling back to built-in template defaults. Error={0}" -f $bootstrapError)
        }
    }

    $copiedFromGenerated = $false
    $generatedConfigFiles = @()

    if (Test-Path -LiteralPath $sourceConfigRoot -PathType Container) {
        $generatedConfigFiles = @(Get-ChildItem -LiteralPath $sourceConfigRoot -File -Force -ErrorAction SilentlyContinue)
        if ($generatedConfigFiles.Count -gt 0) {
            Copy-UGSMGameSCUMDirectoryContent -Source $sourceConfigRoot -Destination $templateConfigRoot -ClearDestination -IncludeExtensions @('.ini', '.json', '.xml', '.cfg')
            $copiedFromGenerated = $true
        }
    }

    if (-not $copiedFromGenerated) {
        $defaultResult = Initialize-UGSMGameSCUMTemplateDefaultFiles -TemplateConfigRoot $templateConfigRoot
        $generatedConfigFiles = @(Get-ChildItem -LiteralPath $templateConfigRoot -File -Force -ErrorAction SilentlyContinue)
    }

    if ($generatedConfigFiles.Count -eq 0) {
        throw "SCUM template creation failed: no generated or built-in template files were created in: $templateConfigRoot"
    }

    $sw.Stop()
    Write-UGSMGameSCUMLog -Level 'INFO' -Message ("Template ensure completed. InstallPath={0}; BootstrapPerformed={1}; GeneratedConfigFiles={2}; Source={3}; DurationMs={4}" -f $InstallPath, [bool]$needsBootstrap, $generatedConfigFiles.Count, $(if ($copiedFromGenerated) { 'GameGenerated' } else { 'BuiltInDefaults' }), $sw.ElapsedMilliseconds)

    return [pscustomobject]@{
        GameId               = 'SCUM'
        InstallPath          = $InstallPath
        TemplateRoot         = $templateRoot
        TemplateConfigRoot   = $templateConfigRoot
        TemplateSaveRoot     = $templateSaveRoot
        SourceConfigRoot     = $sourceConfigRoot
        SourceSaveRoot       = $sourceSaveRoot
        BootstrapPerformed   = $needsBootstrap
        BootstrapResult      = $bootstrapResult
        BootstrapError       = $bootstrapError
        GeneratedConfigFiles = @($generatedConfigFiles.Name)
        UsedBuiltInDefaults  = (-not $copiedFromGenerated)
    }
}


function Initialize-UGSMGameSCUMProfile {
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
        throw 'ProfileName could not be resolved for SCUM profile initialization.'
    }

    if ([string]::IsNullOrWhiteSpace($effectiveInstallPath)) {
        throw 'InstallPath is required to initialize a SCUM profile.'
    }

    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    Write-UGSMGameSCUMLog -Level 'INFO' -Message ("Profile initialization requested. InstanceId={0}; ProfileName={1}; Force={2}" -f $instanceId, $effectiveProfileName, [bool]$Force.IsPresent)

    $templateRoot = Get-UGSMGameSCUMTemplateRoot
    $templateConfigRoot = Join-Path $templateRoot 'Config\WindowsServer'
    $hasTemplateConfig = (Test-Path -LiteralPath $templateConfigRoot -PathType Container) -and @(
        Get-ChildItem -LiteralPath $templateConfigRoot -File -Force -ErrorAction SilentlyContinue
    ).Count -gt 0

    if (-not $hasTemplateConfig) {
        try {
            [void](Ensure-UGSMGameSCUMTemplate -InstallPath $effectiveInstallPath -BootstrapSeconds $BootstrapSeconds)
        }
        catch {
            Write-UGSMGameSCUMLog -Level 'WARN' -Message ("SCUM profile initialization could not build a generated template; using built-in defaults if possible. Error={0}" -f $_.Exception.Message)
            [void](Initialize-UGSMGameSCUMTemplateDefaultFiles -TemplateConfigRoot $templateConfigRoot)
        }
    }

    if (-not (Test-Path -LiteralPath $templateConfigRoot -PathType Container)) {
        throw 'SCUM template does not exist yet. Install or repair SCUM first so the template can be built.'
    }

    $profileRoot = Get-UGSMGameSCUMProfileRoot -ProfileName $effectiveProfileName
    if ((Test-Path -LiteralPath $profileRoot -PathType Container) -and $Force) {
        Get-ChildItem -LiteralPath $profileRoot -Force -ErrorAction SilentlyContinue |
        Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
    }

    New-Item -ItemType Directory -Path $profileRoot -Force | Out-Null

    $runtimeRoot = $profileRoot
    $runtimeInstallRoot = $runtimeRoot
    $runtimeScumRoot = Join-Path $runtimeInstallRoot 'SCUM'
    $runtimeSavedRoot = Join-Path $runtimeScumRoot 'Saved'
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

    Copy-UGSMGameSCUMDirectoryContent -Source $templateConfigRoot -Destination $runtimeConfigRoot -ClearDestination

    $serverSettingsPath = Join-Path $runtimeConfigRoot 'ServerSettings.ini'
    if (Test-Path -LiteralPath $serverSettingsPath -PathType Leaf) {
        try {
            $content = Get-Content -LiteralPath $serverSettingsPath -Raw

            if ($content -match '(?im)^\s*scum\.ServerName\s*=') {
                $content = [Regex]::Replace($content, '(?im)^\s*scum\.ServerName\s*=.*$', ('scum.ServerName={0}' -f $effectiveProfileName))
            }

            if ($content -match '(?im)^\s*scum\.ServerDescription\s*=') {
                $content = [Regex]::Replace($content, '(?im)^\s*scum\.ServerDescription\s*=.*$', ('scum.ServerDescription=UGSM SCUM Profile - {0}' -f $effectiveProfileName))
            }

            Set-Content -LiteralPath $serverSettingsPath -Value $content -Encoding UTF8
        }
        catch {
        }
    }

    $sw.Stop()
    Write-UGSMGameSCUMLog -Level 'INFO' -Message ("Profile initialization completed. InstanceId={0}; ProfileName={1}; DurationMs={2}; ConfigRoot={3}" -f $instanceId, $effectiveProfileName, $sw.ElapsedMilliseconds, $runtimeConfigRoot)

    return [pscustomobject]@{
        GameId             = 'SCUM'
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

function Test-UGSMGameSCUMInstall {
    [CmdletBinding()]
    param(
        [string]$InstallPath
    )

    $definition = Get-UGSMGameSCUMInstallDefinition -InstallPath $InstallPath
    if (-not $definition -or [string]::IsNullOrWhiteSpace([string]$definition.InstallPath)) {
        throw 'SCUM validation failed: InstallPath could not be resolved.'
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
        GameId                 = 'SCUM'
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

function Start-UGSMGameSCUMInstance {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Instance
    )

    if (-not $Instance) {
        throw 'SCUM start failed: Instance was null.'
    }

    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    $instanceId = [string]$(if ($Instance.PSObject.Properties['Id']) { $Instance.Id } else { $Instance.Name })
    Write-UGSMGameSCUMLog -Level 'INFO' -Message ("Start requested. InstanceId={0}; InstallPath={1}" -f $instanceId, [string]$Instance.InstallPath)

    $validation = Test-UGSMGameSCUMInstall -InstallPath $Instance.InstallPath
    if (-not $validation -or -not $validation.IsInstalled -or -not $validation.ServerExecutableExists) {
        throw 'SCUM start failed: SCUM is not installed or the server executable is missing.'
    }

    $installDef = Get-UGSMGameSCUMInstallDefinition -InstallPath $Instance.InstallPath -Instance $Instance
    if (-not $installDef) {
        throw 'SCUM start failed: Install definition could not be resolved.'
    }

    $profilePath = $null
    if ($Instance.PSObject.Properties.Name -contains 'ProfilePath' -and -not [string]::IsNullOrWhiteSpace([string]$Instance.ProfilePath)) {
        $profilePath = [string]$Instance.ProfilePath
    }
    else {
        $profilePath = Get-UGSMGameSCUMProfileRoot -ProfileName ([string]$Instance.Name)
    }

    if ([string]::IsNullOrWhiteSpace($profilePath) -or -not (Test-Path -LiteralPath $profilePath -PathType Container)) {
        throw "SCUM start failed: Profile path was not found: $profilePath"
    }

    $runtime = Ensure-UGSMGameSCUMRuntimeLayout -Instance $Instance -InstallDefinition $installDef

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
        throw "SCUM start failed: Runtime ServerSettings.ini was not found: $serverSettingsPath"
    }

    $serverExe = [string]$runtime.RuntimeServerExePath
    $workingDirectory = Split-Path -Parent $serverExe
    if (-not (Test-Path -LiteralPath $serverExe -PathType Leaf)) {
        throw "SCUM start failed: Runtime server executable was not found: $serverExe"
    }

    $gamePort = 0
    $queryPort = 0
    $rconPort = 0

    if ($Instance.PSObject.Properties['Ports'] -and $Instance.Ports) {
        [void][int]::TryParse([string]$Instance.Ports.GamePort, [ref]$gamePort)
        [void][int]::TryParse([string]$Instance.Ports.QueryPort, [ref]$queryPort)
        [void][int]::TryParse([string]$Instance.Ports.RconPort, [ref]$rconPort)
    }
    if ($gamePort -le 0 -and $Instance.PSObject.Properties['GamePort']) { [void][int]::TryParse([string]$Instance.GamePort, [ref]$gamePort) }
    if ($queryPort -le 0 -and $Instance.PSObject.Properties['QueryPort']) { [void][int]::TryParse([string]$Instance.QueryPort, [ref]$queryPort) }
    if ($rconPort -le 0 -and $Instance.PSObject.Properties['RconPort']) { [void][int]::TryParse([string]$Instance.RconPort, [ref]$rconPort) }

    if ($gamePort -le 0) { $gamePort = 7777 }
    if ($queryPort -le 0) { $queryPort = $gamePort + 2 }
    if ($rconPort -le 0) { $rconPort = $queryPort + 2 }

    try {
        if (-not ($Instance.PSObject.Properties['Ports']) -or -not $Instance.Ports) {
            $Instance | Add-Member -NotePropertyName 'Ports' -NotePropertyValue ([pscustomobject]@{}) -Force
        }
        foreach ($pair in @(
                @{ Name = 'GamePort'; Value = $gamePort },
                @{ Name = 'QueryPort'; Value = $queryPort },
                @{ Name = 'RconPort'; Value = $rconPort }
            )) {
            if ($Instance.Ports.PSObject.Properties[$pair.Name]) { $Instance.Ports.PSObject.Properties[$pair.Name].Value = [int]$pair.Value }
            else { $Instance.Ports | Add-Member -NotePropertyName $pair.Name -NotePropertyValue ([int]$pair.Value) -Force }

            if ($Instance.PSObject.Properties[$pair.Name]) { $Instance.PSObject.Properties[$pair.Name].Value = [int]$pair.Value }
            else { $Instance | Add-Member -NotePropertyName $pair.Name -NotePropertyValue ([int]$pair.Value) -Force }
        }
    }
    catch { }

    $maxPlayersRaw = $null
    try {
        $iniData = Read-UGSMGameSCUMIniFile -Path $serverSettingsPath
        $maxPlayersRaw = Get-UGSMGameSCUMIniValue -IniData $iniData -Section 'General' -Key 'scum.MaxPlayers' -DefaultValue $null
    }
    catch { $maxPlayersRaw = $null }

    $maxPlayers = 0
    [void][int]::TryParse([string]$maxPlayersRaw, [ref]$maxPlayers)
    if ($maxPlayers -le 0 -and $Instance.PSObject.Properties['MaxPlayers']) { [void][int]::TryParse([string]$Instance.MaxPlayers, [ref]$maxPlayers) }

    $arguments = New-Object System.Collections.Generic.List[string]
    [void]$arguments.Add('-log')
    [void]$arguments.Add(('-port={0}' -f [int]$gamePort))
    [void]$arguments.Add(('-QueryPort={0}' -f [int]$queryPort))
    if ($maxPlayers -gt 0) { [void]$arguments.Add(('-MaxPlayers={0}' -f [int]$maxPlayers)) }
    if ($rconPort -gt 0) { [void]$arguments.Add(('-RCONPort={0}' -f [int]$rconPort)) }
    [void]$arguments.Add('-nobattleye')

    Write-UGSMGameSCUMLog -Level 'INFO' -Message ("Launching process. InstanceId={0}; Exe={1}; WorkingDirectory={2}; Args={3}" -f $instanceId, $serverExe, $workingDirectory, (($arguments.ToArray()) -join ' '))

    $proc = Start-Process `
        -FilePath $serverExe `
        -ArgumentList ($arguments.ToArray()) `
        -WorkingDirectory $workingDirectory `
        -PassThru

    if (-not $proc -or -not $proc.Id) {
        throw 'SCUM start failed: Start-Process did not return a valid process.'
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
            GameId            = 'SCUM'
            ProfilePath       = $profilePath
            RuntimeRoot       = [string]$runtime.RuntimeRoot
            RuntimeConfigRoot = [string]$runtime.RuntimeConfigRootPath
            RuntimeSaveRoot   = [string]$runtime.RuntimeSaveRootPath
            RuntimeLogRoot    = [string]$runtime.RuntimeLogRootPath
            Pid               = $gamePid
            GamePort          = $gamePort
            QueryPort         = $queryPort
            RconPort          = $rconPort
            StartedAtUtc      = [DateTime]::UtcNow.ToString('o')
        }
        $runtimeData | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $runtimeMarker -Encoding UTF8
    }
    catch {}

    try { $Instance = Update-UGSMGameSCUMInstanceNormalizedDiscordInfo -Instance $Instance -Persist:$true } catch {}

    $sw.Stop()
    Write-UGSMGameSCUMLog -Level 'INFO' -Message ("Start completed. InstanceId={0}; Pid={1}; DurationMs={2}" -f $instanceId, $gamePid, $sw.ElapsedMilliseconds)

    return [pscustomobject]@{
        Instance = $Instance
        Pid      = $gamePid
        Status   = 'Running'
        Runtime  = $runtime
    }
}

function Stop-UGSMGameSCUMInstance {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Instance
    )

    if (-not $Instance) {
        throw 'SCUM stop failed: Instance was null.'
    }

    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    $instanceId = [string]$(if ($Instance.PSObject.Properties['Id']) { $Instance.Id } else { $Instance.Name })
    Write-UGSMGameSCUMLog -Level 'INFO' -Message ("Stop requested. InstanceId={0}; Pid={1}" -f $instanceId, [string]$Instance.Pid)

    $installDef = Get-UGSMGameSCUMInstallDefinition -InstallPath $Instance.InstallPath -Instance $Instance
    if (-not $installDef) {
        throw 'SCUM stop failed: Install definition could not be resolved.'
    }

    $runtime = Get-UGSMGameSCUMRuntimeDefinition -Instance $Instance -InstallDefinition $installDef

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
            & taskkill.exe /PID $targetProcessId /T /F | Out-Null
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
        throw ("SCUM stop failed: Process {0} is still running." -f $targetProcessId)
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

    foreach ($propName in @('CurrentPlayers','PlayerCount','OnlinePlayers','PlayersOnline')) {
        [void](Set-UGSMGameSCUMObjectProperty -Object $Instance -Name $propName -Value 0)
    }
    [void](Set-UGSMGameSCUMObjectProperty -Object $Instance -Name 'PlayerCountSource' -Value 'SCUM_LOG_GLOBAL_STATS')
    [void](Set-UGSMGameSCUMObjectProperty -Object $Instance -Name 'PlayerCountStatus' -Value 'Stopped')
    [void](Set-UGSMGameSCUMObjectProperty -Object $Instance -Name 'PlayerCountLastError' -Value '')
    [void](Set-UGSMGameSCUMObjectProperty -Object $Instance -Name 'PlayerCountUpdatedUtc' -Value ([DateTime]::UtcNow.ToString('o')))
    try { [void](Save-UGSMGameSCUMInstanceDefinition -Instance $Instance) } catch { }

    $sw.Stop()
    Write-UGSMGameSCUMLog -Level 'INFO' -Message ("Stop completed. InstanceId={0}; Pid={1}; DurationMs={2}" -f $instanceId, [string]$targetProcessId, $sw.ElapsedMilliseconds)

    return [pscustomobject]@{
        Instance = $Instance
        Status   = 'Stopped'
        Runtime  = $runtime
    }
}


function Set-UGSMGameSCUMObjectProperty {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$Object,
        [Parameter(Mandatory)][string]$Name,
        [AllowNull()]$Value
    )

    if ($Object.PSObject.Properties[$Name]) {
        $Object.$Name = $Value
    }
    else {
        $Object | Add-Member -NotePropertyName $Name -NotePropertyValue $Value -Force
    }

    return $Object
}

function Get-UGSMGameSCUMObjectPropertyValue {
    [CmdletBinding()]
    param(
        [AllowNull()][object]$Object,
        [string[]]$Names = @(),
        [AllowNull()]$DefaultValue = $null
    )

    if (-not $Object) { return $DefaultValue }

    foreach ($name in @($Names)) {
        if ([string]::IsNullOrWhiteSpace([string]$name)) { continue }

        if ($Object -is [hashtable]) {
            if ($Object.ContainsKey($name) -and $null -ne $Object[$name] -and -not [string]::IsNullOrWhiteSpace([string]$Object[$name])) { return $Object[$name] }
            continue
        }

        if ($Object.PSObject.Properties[$name] -and $null -ne $Object.$name -and -not [string]::IsNullOrWhiteSpace([string]$Object.$name)) {
            return $Object.$name
        }
    }

    return $DefaultValue
}

function Get-UGSMGameSCUMRuntimeLogFiles {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$Instance,
        [AllowNull()]$Paths
    )

    $logRoots = New-Object System.Collections.Generic.List[string]

    if ($Paths) {
        foreach ($propName in @('RuntimeLogRoot','ProfileLogRoot','LogRoot')) {
            if ($Paths.PSObject.Properties[$propName] -and -not [string]::IsNullOrWhiteSpace([string]$Paths.$propName)) {
                [void]$logRoots.Add([string]$Paths.$propName)
            }
        }
    }

    try {
        $runtimeRoot = Get-UGSMGameSCUMRuntimeRoot -Instance $Instance
        if (-not [string]::IsNullOrWhiteSpace([string]$runtimeRoot)) {
            [void]$logRoots.Add((Join-Path $runtimeRoot 'SCUM\Saved\Logs'))
        }
    }
    catch { }

    $files = New-Object System.Collections.Generic.List[object]
    foreach ($root in @($logRoots.ToArray() | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) } | Select-Object -Unique)) {
        try {
            if (Test-Path -LiteralPath $root -PathType Container) {
                foreach ($file in @(Get-ChildItem -LiteralPath $root -Filter '*.log' -File -ErrorAction SilentlyContinue | Sort-Object LastWriteTimeUtc -Descending)) {
                    [void]$files.Add($file)
                }
            }
        }
        catch { }
    }

    return @($files.ToArray() | Sort-Object LastWriteTimeUtc -Descending)
}

function Get-UGSMGameSCUMCurrentPlayerCountFromLog {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$Instance,
        [AllowNull()]$Paths,
        [int]$TailLines = 600
    )

    if (-not $Paths) {
        try { $Paths = Get-UGSMGameSCUMProfilePaths -Instance $Instance } catch { $Paths = $null }
    }

    $logFiles = @(Get-UGSMGameSCUMRuntimeLogFiles -Instance $Instance -Paths $Paths)
    if ($logFiles.Count -lt 1) {
        return [pscustomobject]@{
            Success         = $false
            Source          = 'SCUM_LOG_GLOBAL_STATS'
            Status          = 'LogUnavailable'
            LastError       = 'No SCUM runtime log file was found.'
            LastLogFileName = ''
            UpdatedUtc      = [DateTime]::UtcNow.ToString('o')
        }
    }

    foreach ($logFile in $logFiles) {
        try {
            $lines = @(Get-Content -LiteralPath ([string]$logFile.FullName) -Tail $TailLines -ErrorAction Stop)
            for ($i = $lines.Count - 1; $i -ge 0; $i--) {
                $line = [string]$lines[$i]
                if ($line -notmatch 'LogSCUM:\s+Global\s+Stats') { continue }

                $playerCountText = $null
                if ($line -match '\bP:\s*(\d+)\s*\(') {
                    $playerCountText = [string]$matches[1]
                }
                elseif ($line -match '\bP:\s*(\d+)\b') {
                    $playerCountText = [string]$matches[1]
                }

                $currentPlayers = 0
                if ($null -ne $playerCountText -and [int]::TryParse($playerCountText, [ref]$currentPlayers)) {
                    return [pscustomobject]@{
                        Success         = $true
                        Source          = 'SCUM_LOG_GLOBAL_STATS'
                        Status          = 'OK'
                        CurrentPlayers  = [int]$currentPlayers
                        PlayerCount     = [int]$currentPlayers
                        MaxPlayers      = 0
                        LastError       = ''
                        LastLogFileName = [string]$logFile.Name
                        UpdatedUtc      = [DateTime]::UtcNow.ToString('o')
                    }
                }
            }
        }
        catch {
            return [pscustomobject]@{
                Success         = $false
                Source          = 'SCUM_LOG_GLOBAL_STATS'
                Status          = 'ReadFailed'
                LastError       = [string]$_.Exception.Message
                LastLogFileName = [string]$logFile.Name
                UpdatedUtc      = [DateTime]::UtcNow.ToString('o')
            }
        }
    }

    return [pscustomobject]@{
        Success         = $false
        Source          = 'SCUM_LOG_GLOBAL_STATS'
        Status          = 'NoGlobalStatsLine'
        LastError       = 'No LogSCUM: Global Stats line was found in recent log output.'
        LastLogFileName = [string]$logFiles[0].Name
        UpdatedUtc      = [DateTime]::UtcNow.ToString('o')
    }
}

function Get-UGSMGameSCUMCurrentPlayerCount {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$Instance,
        [AllowNull()]$Paths
    )

    # SCUM did not return reliable local Valve/A2S replies in testing. The server
    # already writes the live player count in:
    #   <ProfilePath>\SCUM\Saved\Logs\*.log
    #   LogSCUM: Global Stats ... | C: 1 (1), P: 1 (1), ...
    # Use that log value for Discord/dashboard and avoid the UDP probe delay.
    if (-not $Paths) { try { $Paths = Get-UGSMGameSCUMProfilePaths -Instance $Instance } catch { $Paths = $null } }

    $info = Get-UGSMGameSCUMCurrentPlayerCountFromLog -Instance $Instance -Paths $Paths
    if ($info -and $info.Success) {
        Write-UGSMGameSCUMLog -Level 'DEBUG' -Message ('SCUM player count resolved from log. InstanceId={0}; Players={1}; Log={2}' -f [string]$Instance.Id, [int]$info.CurrentPlayers, [string]$info.LastLogFileName)
        return $info
    }

    $status = if ($info -and $info.PSObject.Properties['Status']) { [string]$info.Status } else { 'Unknown' }
    $errorText = if ($info -and $info.PSObject.Properties['LastError']) { [string]$info.LastError } else { 'SCUM runtime log player count could not be resolved.' }
    Write-UGSMGameSCUMLog -Level 'DEBUG' -Message ('SCUM player count not resolved from log. InstanceId={0}; Status={1}; Error={2}' -f [string]$Instance.Id, $status, $errorText)
    return $info
}

function Update-UGSMGameSCUMInstanceNormalizedDiscordInfo {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$Instance,
        [switch]$IncludePlayerCount,
        [switch]$Persist
    )

    $updatedInstance = Ensure-UGSMGameSCUMInstanceDiscordShape -Instance $Instance
    $paths = $null
    try { $paths = Get-UGSMGameSCUMProfilePaths -Instance $updatedInstance } catch { $paths = $null }

    $serverName = $null
    $maxPlayers = $null

    if ($paths -and $paths.PSObject.Properties['ServerSettingsPath'] -and (Test-Path -LiteralPath ([string]$paths.ServerSettingsPath) -PathType Leaf)) {
        try {
            $iniData = Read-UGSMGameSCUMIniFile -Path ([string]$paths.ServerSettingsPath)
            $serverName = Get-UGSMGameSCUMIniValue -IniData $iniData -Section 'General' -Key 'scum.ServerName' -DefaultValue $null
            $maxPlayers = Get-UGSMGameSCUMIniValue -IniData $iniData -Section 'General' -Key 'scum.MaxPlayers' -DefaultValue $null
        }
        catch { }
    }

    if (-not [string]::IsNullOrWhiteSpace([string]$serverName)) {
        $cleanName = ([string]$serverName).Trim()
        foreach ($prop in @('ServerName','PublicServerName','DisplayName')) {
            [void](Set-UGSMGameSCUMObjectProperty -Object $updatedInstance -Name $prop -Value $cleanName)
        }
    }

    $maxPlayersInt = 0
    if ([int]::TryParse([string]$maxPlayers, [ref]$maxPlayersInt) -and $maxPlayersInt -gt 0) {
        foreach ($prop in @('MaxPlayers','ServerMaxPlayers')) {
            [void](Set-UGSMGameSCUMObjectProperty -Object $updatedInstance -Name $prop -Value $maxPlayersInt)
        }
    }

    foreach ($portName in @('GamePort','QueryPort','RconPort')) {
        $normalizedPort = Get-UGSMGameSCUMObjectPropertyValue -Object $updatedInstance -Names @($portName) -DefaultValue $null
        if ($updatedInstance.PSObject.Properties['Ports'] -and $updatedInstance.Ports) {
            $normalizedPort = Get-UGSMGameSCUMObjectPropertyValue -Object $updatedInstance.Ports -Names @($portName) -DefaultValue $normalizedPort
        }
        $normalizedPortInt = 0
        if ([int]::TryParse([string]$normalizedPort, [ref]$normalizedPortInt) -and $normalizedPortInt -gt 0) {
            [void](Set-UGSMGameSCUMObjectProperty -Object $updatedInstance -Name $portName -Value $normalizedPortInt)
        }
    }

    if ($IncludePlayerCount.IsPresent) {
        $statusText = [string](Get-UGSMGameSCUMObjectPropertyValue -Object $updatedInstance -Names @('Status') -DefaultValue '')
        $isRunning = $statusText.Trim().ToLowerInvariant() -in @('running','online','started')

        if (-not $isRunning) {
            foreach ($prop in @('CurrentPlayers','PlayerCount','OnlinePlayers','PlayersOnline')) {
                [void](Set-UGSMGameSCUMObjectProperty -Object $updatedInstance -Name $prop -Value 0)
            }
            [void](Set-UGSMGameSCUMObjectProperty -Object $updatedInstance -Name 'PlayerCountSource' -Value 'SCUM_LOG_GLOBAL_STATS')
            [void](Set-UGSMGameSCUMObjectProperty -Object $updatedInstance -Name 'PlayerCountStatus' -Value 'Stopped')
            [void](Set-UGSMGameSCUMObjectProperty -Object $updatedInstance -Name 'PlayerCountLastError' -Value '')
            [void](Set-UGSMGameSCUMObjectProperty -Object $updatedInstance -Name 'PlayerCountUpdatedUtc' -Value ([DateTime]::UtcNow.ToString('o')))
        }
        else {
            $playerInfo = Get-UGSMGameSCUMCurrentPlayerCount -Instance $updatedInstance -Paths $paths
            if ($playerInfo -and $playerInfo.Success) {
                foreach ($prop in @('CurrentPlayers','PlayerCount','OnlinePlayers','PlayersOnline')) {
                    [void](Set-UGSMGameSCUMObjectProperty -Object $updatedInstance -Name $prop -Value ([int]$playerInfo.CurrentPlayers))
                }
                [void](Set-UGSMGameSCUMObjectProperty -Object $updatedInstance -Name 'PlayerCountSource' -Value ([string]$playerInfo.Source))
                [void](Set-UGSMGameSCUMObjectProperty -Object $updatedInstance -Name 'PlayerCountStatus' -Value 'OK')
                [void](Set-UGSMGameSCUMObjectProperty -Object $updatedInstance -Name 'PlayerCountLastError' -Value '')
                [void](Set-UGSMGameSCUMObjectProperty -Object $updatedInstance -Name 'PlayerCountUpdatedUtc' -Value ([DateTime]::UtcNow.ToString('o')))
                if ($playerInfo.PSObject.Properties['LastLogFileName']) {
                    [void](Set-UGSMGameSCUMObjectProperty -Object $updatedInstance -Name 'PlayerCountLastLogFileName' -Value ([string]$playerInfo.LastLogFileName))
                }
            }
            elseif ($playerInfo) {
                [void](Set-UGSMGameSCUMObjectProperty -Object $updatedInstance -Name 'PlayerCountSource' -Value ([string]$playerInfo.Source))
                [void](Set-UGSMGameSCUMObjectProperty -Object $updatedInstance -Name 'PlayerCountStatus' -Value ([string]$playerInfo.Status))
                [void](Set-UGSMGameSCUMObjectProperty -Object $updatedInstance -Name 'PlayerCountLastError' -Value ([string]$playerInfo.LastError))
                [void](Set-UGSMGameSCUMObjectProperty -Object $updatedInstance -Name 'PlayerCountUpdatedUtc' -Value ([DateTime]::UtcNow.ToString('o')))
                if ($playerInfo.PSObject.Properties['LastLogFileName']) {
                    [void](Set-UGSMGameSCUMObjectProperty -Object $updatedInstance -Name 'PlayerCountLastLogFileName' -Value ([string]$playerInfo.LastLogFileName))
                }
            }
        }
    }

    if ($Persist.IsPresent) {
        try { [void](Save-UGSMGameSCUMInstanceDefinition -Instance $updatedInstance) } catch { Write-UGSMGameSCUMLog -Level 'WARN' -Message ('Failed to persist SCUM normalized Discord info. InstanceId={0}; Error={1}' -f [string]$updatedInstance.Id, [string]$_.Exception.Message) }
    }

    return $updatedInstance
}

function Update-UGSMGameSCUMDiscordRuntimeInfo {
    [CmdletBinding()]
    param([Parameter(Mandatory)][object]$Instance)

    return (Update-UGSMGameSCUMInstanceNormalizedDiscordInfo -Instance $Instance -IncludePlayerCount -Persist)
}

function Register-UGSMGameSCUMModule {
    [CmdletBinding()]
    param()

    $metadata = Get-UGSMGameSCUMMetadata

    return [pscustomobject]@{
        Id       = [string]$metadata.Id
        Metadata = $metadata
        Handlers = [pscustomobject]@{
            GetMetadata       = 'Get-UGSMGameSCUMMetadata'
            TestInstall       = 'Test-UGSMGameSCUMInstall'
            TestInstance      = 'Test-UGSMGameSCUMInstance'
            EnsureTemplate    = 'Ensure-UGSMGameSCUMTemplate'
            InitializeProfile = 'Initialize-UGSMGameSCUMProfile'
            Start             = 'Start-UGSMGameSCUMInstance'
            Stop              = 'Stop-UGSMGameSCUMInstance'

            BuildEditor       = 'New-UGSMGameSCUMInstanceEditor'
            SaveEditor        = 'Save-UGSMGameSCUMInstanceEditor'
        }
    }
}


function Get-UGSMGameSCUMBackupTargets {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$Instance,
        [ValidateSet('Settings','Mods','All')]
        [string]$Scope = 'Settings'
    )

    $targets = New-Object System.Collections.Generic.List[object]

    if ($Scope -in @('Settings','All')) {
        $paths = Get-UGSMGameSCUMProfilePaths -Instance $Instance
        $settingsTargets = @(
            @{ Path = $paths.ServerSettingsPath;          Relative = 'SCUM\Saved\Config\WindowsServer\ServerSettings.ini';   Label = 'SCUM server settings INI' },
            @{ Path = $paths.AdminUsersPath;              Relative = 'SCUM\Saved\Config\WindowsServer\AdminUsers.ini';       Label = 'SCUM admin users list' },
            @{ Path = $paths.ExclusiveUsersPath;          Relative = 'SCUM\Saved\Config\WindowsServer\ExclusiveUsers.ini';   Label = 'SCUM exclusive users list' },
            @{ Path = $paths.WhitelistedUsersPath;        Relative = 'SCUM\Saved\Config\WindowsServer\WhitelistedUsers.ini'; Label = 'SCUM whitelist users list' },
            @{ Path = $paths.BannedUsersPath;             Relative = 'SCUM\Saved\Config\WindowsServer\BannedUsers.ini';      Label = 'SCUM banned users list' },
            @{ Path = $paths.SilencedUsersPath;           Relative = 'SCUM\Saved\Config\WindowsServer\SilencedUsers.ini';    Label = 'SCUM silenced users list' },
            @{ Path = $paths.EconomyOverridePath;         Relative = 'SCUM\Saved\Config\WindowsServer\EconomyOverride.json'; Label = 'SCUM economy override JSON' },
            @{ Path = $paths.NotificationsPath;           Relative = 'SCUM\Saved\Config\WindowsServer\Notifications.json';   Label = 'SCUM notifications JSON' },
            @{ Path = $paths.RaidTimesPath;               Relative = 'SCUM\Saved\Config\WindowsServer\RaidTimes.json';       Label = 'SCUM raid times JSON' }
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

    return @($targets.ToArray())
}

function Invoke-UGSMGameSCUMManagedBackup {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$Instance,
        [ValidateSet('Settings','Mods','All')]
        [string]$Scope = 'Settings',
        [string]$Reason = 'SCUM managed file change'
    )

    if (-not (Get-Command -Name Invoke-UGSMManagedFileBackup -ErrorAction SilentlyContinue)) { return $null }

    try {
        $targets = @(Get-UGSMGameSCUMBackupTargets -Instance $Instance -Scope $Scope)
        return Invoke-UGSMManagedFileBackup -GameId 'SCUM' -Instance $Instance -Targets $targets -Reason $Reason -KeepLatest 3
    }
    catch {
        Write-UGSMGameSCUMLog -Level 'WARN' -Message ('SCUM managed backup failed. Scope=' + $Scope + '; Reason=' + $Reason) -Exception $_.Exception
        return $null
    }
}

function Get-UGSMGameSCUMProfilePaths {
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
        $profileRoot = Get-UGSMGameSCUMProfileRoot -ProfileName ([string]$Instance.Name)
    }
    elseif (Get-Command -Name Get-UGSMDefaultInstanceProfilePath -ErrorAction SilentlyContinue) {
        $profileRoot = Get-UGSMDefaultInstanceProfilePath -GameId 'SCUM' -Name ([string]$Instance.Name)
    }

    if ([string]::IsNullOrWhiteSpace([string]$profileRoot)) {
        throw 'SCUM profile paths could not be resolved for the selected instance.'
    }

    $runtimeRoot = Get-UGSMGameSCUMRuntimeRoot -Instance $Instance
    $runtimeConfigRoot = Join-Path $runtimeRoot 'SCUM\Saved\Config\WindowsServer'
    $runtimeSaveRoot = Join-Path $runtimeRoot 'SCUM\Saved\SaveFiles'
    $runtimeLogRoot = Join-Path $runtimeRoot 'SCUM\Saved\Logs'

    $runtimeMarkerPath = Join-Path $runtimeSaveRoot 'UGSM.Runtime.json'
    $runtimeDatabasePath = Join-Path $runtimeSaveRoot 'SCUM.db'

    [pscustomobject]@{
        ProfileRoot                 = $profileRoot

        ProfileConfigRoot           = $runtimeConfigRoot
        ProfileSaveRoot             = $runtimeSaveRoot
        ProfileLogRoot              = $runtimeLogRoot

        RuntimeRoot                 = $runtimeRoot
        RuntimeConfigRoot           = $runtimeConfigRoot
        RuntimeSaveRoot             = $runtimeSaveRoot
        RuntimeLogRoot              = $runtimeLogRoot
        RuntimeMarkerPath           = $runtimeMarkerPath
        IsRuntimeActive             = (Test-Path -LiteralPath $runtimeMarkerPath -PathType Leaf)

        ConfigRoot                  = $runtimeConfigRoot
        SaveRoot                    = $runtimeSaveRoot
        LogRoot                     = $runtimeLogRoot

        ServerSettingsPath          = Join-Path $runtimeConfigRoot 'ServerSettings.ini'
        AdminUsersPath              = Join-Path $runtimeConfigRoot 'AdminUsers.ini'
        ExclusiveUsersPath          = Join-Path $runtimeConfigRoot 'ExclusiveUsers.ini'
        WhitelistedUsersPath        = Join-Path $runtimeConfigRoot 'WhitelistedUsers.ini'
        BannedUsersPath             = Join-Path $runtimeConfigRoot 'BannedUsers.ini'
        SilencedUsersPath           = Join-Path $runtimeConfigRoot 'SilencedUsers.ini'
        EconomyOverridePath         = Join-Path $runtimeConfigRoot 'EconomyOverride.json'
        NotificationsPath           = Join-Path $runtimeConfigRoot 'Notifications.json'
        RaidTimesPath               = Join-Path $runtimeConfigRoot 'RaidTimes.json'

        RuntimeServerSettingsPath   = Join-Path $runtimeConfigRoot 'ServerSettings.ini'
        RuntimeAdminUsersPath       = Join-Path $runtimeConfigRoot 'AdminUsers.ini'
        RuntimeExclusiveUsersPath   = Join-Path $runtimeConfigRoot 'ExclusiveUsers.ini'
        RuntimeWhitelistedUsersPath = Join-Path $runtimeConfigRoot 'WhitelistedUsers.ini'
        RuntimeBannedUsersPath      = Join-Path $runtimeConfigRoot 'BannedUsers.ini'
        RuntimeSilencedUsersPath    = Join-Path $runtimeConfigRoot 'SilencedUsers.ini'
        RuntimeEconomyOverridePath  = Join-Path $runtimeConfigRoot 'EconomyOverride.json'
        RuntimeNotificationsPath    = Join-Path $runtimeConfigRoot 'Notifications.json'
        RuntimeRaidTimesPath        = Join-Path $runtimeConfigRoot 'RaidTimes.json'

        ProfileDatabasePath         = $null
        RuntimeDatabasePath         = $runtimeDatabasePath
        DatabasePath                = $runtimeDatabasePath
    }
}

function Read-UGSMGameSCUMIniFile {
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

function Get-UGSMGameSCUMIniValue {
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

function Set-UGSMGameSCUMIniValue {
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

function Read-UGSMGameSCUMStringListFile {
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

function Write-UGSMGameSCUMStringListFile {
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

function Test-UGSMGameSCUMPSSQLiteInstalled {
    [CmdletBinding()]
    param()

    return ($null -ne (Get-Module -ListAvailable -Name PSSQLite | Select-Object -First 1))
}

function Install-UGSMGameSCUMPSSQLite {
    [CmdletBinding()]
    param()

    Install-Module -Name PSSQLite -Scope CurrentUser -Force -Confirm:$false -ErrorAction Stop
    return (Test-UGSMGameSCUMPSSQLiteInstalled)
}

function Get-UGSMGameSCUMElevatedUsers {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$DatabasePath
    )

    if (-not (Test-UGSMGameSCUMPSSQLiteInstalled)) {
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

function Save-UGSMGameSCUMElevatedUsers {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$DatabasePath,
        [string[]]$UserIds
    )

    if (-not (Test-UGSMGameSCUMPSSQLiteInstalled)) {
        throw 'PSSQLite is not installed.'
    }

    if (-not (Test-Path -LiteralPath $DatabasePath -PathType Leaf)) {
        throw 'SCUM.db was not found.'
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


function Resolve-UGSMGameSCUMEditorFieldPath {
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


function Save-UGSMGameSCUMInstanceDefinition {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$Instance
    )

    $commandCandidates = @(
        'Save-UGSMInstance',
        'Save-UGSMInstanceDefinition',
        'Set-UGSMInstance',
        'Update-UGSMInstance'
    )

    foreach ($commandName in $commandCandidates) {
        $cmd = Get-Command -Name $commandName -ErrorAction SilentlyContinue
        if (-not $cmd) { continue }

        try {
            & $cmd.Name -Instance $Instance
            return $Instance
        }
        catch {
            try {
                & $cmd.Name $Instance
                return $Instance
            }
            catch {
                # Try the next known save function name.
            }
        }
    }

    throw 'SCUM instance save failed: no compatible UGSM instance save service was found.'
}

function ConvertTo-UGSMGameSCUMEditorFieldValue {
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
        'InstanceText' {
            return [string]$Control.Text
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

function Save-UGSMGameSCUMInstanceEditor {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$Instance,
        [Parameter(Mandatory)][hashtable]$EditorState
    )

    $discordInput = [ordered]@{}
    $hasDiscordChanges = $false

    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    $instanceId = [string]$(if ($Instance -and $Instance.PSObject.Properties['Id']) { $Instance.Id } else { '' })
    Write-UGSMGameSCUMLog -Level 'INFO' -Message ("Save editor requested. InstanceId={0}" -f $instanceId)

    $updatedInstance = Ensure-UGSMGameSCUMInstanceDiscordShape -Instance $Instance
    $paths = Get-UGSMGameSCUMProfilePaths -Instance $updatedInstance

    foreach ($dirPath in @($paths.ConfigRoot, $paths.SaveRoot, $paths.LogRoot)) {
        if (-not [string]::IsNullOrWhiteSpace([string]$dirPath) -and -not (Test-Path -LiteralPath $dirPath -PathType Container)) {
            New-Item -ItemType Directory -Path $dirPath -Force | Out-Null
        }
    }

    Invoke-UGSMGameSCUMManagedBackup -Instance $updatedInstance -Scope 'Settings' -Reason 'Before SCUM settings save' | Out-Null

    $saveSummary = [ordered]@{
        IniKeysWritten       = 0
        StringListsWritten   = 0
        RuntimeCopiesUpdated = 0
        InstanceSettingsSaved = 0
    }

    $instanceMetadataChanged = $false

    function Set-SCUMInstanceProperty {
        param(
            [Parameter(Mandatory)][object]$TargetInstance,
            [Parameter(Mandatory)][string]$Name,
            [AllowNull()][object]$Value
        )

        $currentValue = $null
        $hasProperty = $false
        if ($TargetInstance.PSObject.Properties[$Name]) {
            $hasProperty = $true
            $currentValue = $TargetInstance.$Name
        }

        if (([string]$currentValue) -ne ([string]$Value)) {
            if ($hasProperty) {
                $TargetInstance.$Name = $Value
            }
            else {
                Add-Member -InputObject $TargetInstance -MemberType NoteProperty -Name $Name -Value $Value -Force
            }

            Set-Variable -Name instanceMetadataChanged -Value $true -Scope 1
        }
    }

    foreach ($entry in $EditorState.GetEnumerator()) {
        $item = $entry.Value
        if (-not $item) { continue }

        $field = $item.Field
        $control = $item.Control
        if (-not $field -or -not $control) { continue }

        switch ([string]$field.Type) {
            'StringList' {
                $targetPath = Resolve-UGSMGameSCUMEditorFieldPath -Field $field -Paths $paths -TargetSet Runtime
                if ([string]::IsNullOrWhiteSpace([string]$targetPath)) {
                    $targetPath = Resolve-UGSMGameSCUMEditorFieldPath -Field $field -Paths $paths
                }

                if ([string]::IsNullOrWhiteSpace([string]$targetPath)) {
                    throw ("SCUM save failed: no runtime path could be resolved for string list field '{0}'." -f [string]$field.Id)
                }

                $values = @($control.Lines | ForEach-Object { [string]$_ })
                Write-UGSMGameSCUMStringListFile -Path $targetPath -Values $values
                $saveSummary.StringListsWritten++
                $saveSummary.RuntimeCopiesUpdated++
            }

            'Boolean' {
                $value = ConvertTo-UGSMGameSCUMEditorFieldValue -Field $field -Control $control
                Set-UGSMGameSCUMIniValue -Path $paths.ServerSettingsPath -Section ([string]$field.Section) -Key ([string]$field.Key) -Value $value
                $saveSummary.IniKeysWritten++
                $saveSummary.RuntimeCopiesUpdated++
            }

            'Number' {
                $value = ConvertTo-UGSMGameSCUMEditorFieldValue -Field $field -Control $control
                Set-UGSMGameSCUMIniValue -Path $paths.ServerSettingsPath -Section ([string]$field.Section) -Key ([string]$field.Key) -Value $value
                $saveSummary.IniKeysWritten++
                $saveSummary.RuntimeCopiesUpdated++
            }

            'MultilineText' {
                $value = ConvertTo-UGSMGameSCUMEditorFieldValue -Field $field -Control $control
                Set-UGSMGameSCUMIniValue -Path $paths.ServerSettingsPath -Section ([string]$field.Section) -Key ([string]$field.Key) -Value $value
                $saveSummary.IniKeysWritten++
                $saveSummary.RuntimeCopiesUpdated++
            }

            'Password' {
                $value = ConvertTo-UGSMGameSCUMEditorFieldValue -Field $field -Control $control
                Set-UGSMGameSCUMIniValue -Path $paths.ServerSettingsPath -Section ([string]$field.Section) -Key ([string]$field.Key) -Value $value
                $saveSummary.IniKeysWritten++
                $saveSummary.RuntimeCopiesUpdated++
            }

            'Text' {
                $value = ConvertTo-UGSMGameSCUMEditorFieldValue -Field $field -Control $control
                Set-UGSMGameSCUMIniValue -Path $paths.ServerSettingsPath -Section ([string]$field.Section) -Key ([string]$field.Key) -Value $value
                $saveSummary.IniKeysWritten++
                $saveSummary.RuntimeCopiesUpdated++
            }

            'InstanceText' {
                $value = [string](ConvertTo-UGSMGameSCUMEditorFieldValue -Field $field -Control $control)
                if ([string]$field.Model -eq 'Discord') {
                    $discordInput[[string]$field.Property] = $value
                    $hasDiscordChanges = $true
                }
            }

            'InstanceBoolean' {
                $value = [bool](ConvertTo-UGSMGameSCUMEditorFieldValue -Field $field -Control $control)
                if ([string]$field.Model -eq 'Discord') {
                    $discordInput[[string]$field.Property] = $value
                    $hasDiscordChanges = $true
                }
            }
        }
    }

    try {
        $resolvedServerName = Get-UGSMGameSCUMIniValue -IniData (Read-UGSMGameSCUMIniFile -Path $paths.ServerSettingsPath) -Section 'General' -Key 'scum.ServerName' -DefaultValue ''
        if (-not [string]::IsNullOrWhiteSpace([string]$resolvedServerName)) {
            Set-SCUMInstanceProperty -TargetInstance $updatedInstance -Name 'ServerName' -Value ([string]$resolvedServerName)
            Set-SCUMInstanceProperty -TargetInstance $updatedInstance -Name 'PublicServerName' -Value ([string]$resolvedServerName)
            Set-SCUMInstanceProperty -TargetInstance $updatedInstance -Name 'DisplayName' -Value ([string]$resolvedServerName)
        }

        $resolvedMaxPlayers = Get-UGSMGameSCUMIniValue -IniData (Read-UGSMGameSCUMIniFile -Path $paths.ServerSettingsPath) -Section 'General' -Key 'scum.MaxPlayers' -DefaultValue ''
        if (-not [string]::IsNullOrWhiteSpace([string]$resolvedMaxPlayers)) {
            Set-SCUMInstanceProperty -TargetInstance $updatedInstance -Name 'MaxPlayers' -Value ([string]$resolvedMaxPlayers)
            Set-SCUMInstanceProperty -TargetInstance $updatedInstance -Name 'ServerMaxPlayers' -Value ([string]$resolvedMaxPlayers)
        }
    }
    catch {
        Write-UGSMGameSCUMLog -Level 'WARN' -Message ("SCUM save could not mirror name/max players to instance metadata. Error={0}" -f $_.Exception.Message)
    }

    if ($hasDiscordChanges) {
        $persistScript = {
            param($PersistedInstance)
            [void](Save-UGSMGameSCUMInstanceDefinition -Instance $PersistedInstance)
        }

        $discordResult = Save-UGSMInstanceDiscordSettingsModel -Instance $updatedInstance -InputObject ([pscustomobject]$discordInput) -PersistInstance $persistScript
        if ($discordResult -and $discordResult.PSObject.Properties['Instance']) {
            $updatedInstance = $discordResult.Instance
            $saveSummary.InstanceSettingsSaved++
            $instanceMetadataChanged = $false
        }
    }

    if ($instanceMetadataChanged) {
        [void](Save-UGSMGameSCUMInstanceDefinition -Instance $updatedInstance)
        $saveSummary.InstanceSettingsSaved++
    }

    $sw.Stop()
    Write-UGSMGameSCUMLog -Level 'INFO' -Message ("Save editor completed. InstanceId={0}; DurationMs={1}; IniKeys={2}; StringLists={3}" -f $instanceId, $sw.ElapsedMilliseconds, $saveSummary.IniKeysWritten, $saveSummary.StringListsWritten)

    return [pscustomobject]@{
        Success = $true
        Message = ("Saved SCUM runtime settings. INI keys: {0}. User lists: {1}." -f $saveSummary.IniKeysWritten, $saveSummary.StringListsWritten)
        Summary = [pscustomobject]$saveSummary
        Instance = $updatedInstance
    }
}

function New-UGSMGameSCUMInstanceEditor {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$Instance,
        [Parameter(Mandatory)][hashtable]$Theme,
        [Parameter(Mandatory)][System.Windows.Forms.Panel]$HostPanel,
        [AllowNull()][System.Windows.Forms.Label]$StatusLabel
    )

    $swEditor = [System.Diagnostics.Stopwatch]::StartNew()
    $instanceId = [string]$(if ($Instance -and $Instance.PSObject.Properties['Id']) { $Instance.Id } else { $Instance.Name })
    Write-UGSMGameSCUMLog -Level 'INFO' -Message ("Editor creation started. InstanceId={0}" -f $instanceId)

    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing

    $Instance = Ensure-UGSMGameSCUMInstanceDiscordShape -Instance $Instance
    $paths = Get-UGSMGameSCUMProfilePaths -Instance $Instance
    $schema = Get-UGSMGameSCUMEditorSchema
    $iniData = Read-UGSMGameSCUMIniFile -Path $paths.ServerSettingsPath
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

    function Get-SCUMSafeIniValue {
        param([hashtable]$Field)
        try {
            return [string](Get-UGSMGameSCUMIniValue -IniData $iniData -Section $Field.Section -Key $Field.Key -DefaultValue $Field.DefaultValue)
        }
        catch {
            if ($StatusLabel) { $StatusLabel.Text = 'SCUM field load failed for ' + [string]$Field.Id + ': ' + $_.Exception.Message }
            return [string]$(if ($Field.ContainsKey('DefaultValue')) { $Field.DefaultValue } else { '' })
        }
    }

    function Get-SCUMSafeInstanceValue {
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
            if ($StatusLabel) { $StatusLabel.Text = 'SCUM instance field load failed for ' + [string]$Field.Id + ': ' + $_.Exception.Message }
        }

        if ($Field.ContainsKey('DefaultValue')) {
            return $Field.DefaultValue
        }

        return $null
    }

    function New-SCUMTextBox {
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

    function New-SCUMStretchTextBox {
        param(
            [switch]$Multiline,
            [int]$Height = 24,
            [switch]$MaskSecret
        )

        $tb = New-SCUMTextBox -Width $layout.ControlWidth -Multiline:$Multiline -Height $Height -MaskSecret:$MaskSecret
        $tb.Width = $layout.ControlWidth
        $tb.Anchor = 'Left,Right,Top'
        return $tb
    }

    function New-SCUMNarrowHost {
        $panel = New-Object System.Windows.Forms.Panel
        $panel.Dock = 'Top'
        $panel.Height = 26
        $panel.Margin = New-Object System.Windows.Forms.Padding(0)
        $panel.Padding = New-Object System.Windows.Forms.Padding(0)
        return $panel
    }

    function New-SCUMElevatedUsersControl {
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

        $status = New-UGSMLabel -Text 'Checks for PSSQLite and edits SCUM.db in the selected profile.' -X 0 -Y 0 -Width 420 -Height 28 -FontSize 8.5 -Color $Theme.Muted
        $status.AutoSize = $false
        [void]$wrapper.Controls.Add($status, 0, 0)
        $wrapper.SetColumnSpan($status, 2)

        $list = New-Object System.Windows.Forms.ListBox
        $list.Dock = 'Fill'
        $list.Height = 170
        $list.Margin = New-Object System.Windows.Forms.Padding(0, 0, 12, 0)
        $list.BackColor = $global:UGSM_ColorArtBackground
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

        $btnInstallSql = New-UGSMButton -Text 'Install PSSQLite' -Width 150 -Height 28 -BackColor $global:UGSM_ColorSpecial
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

        $btnRemoveDb = New-UGSMButton -Text 'Remove Selected' -Width 150 -Height 28 -BackColor $global:UGSM_ColorDangerSurface
        $btnRemoveDb.Dock = 'Top'
        [void]$wrapper.Controls.Add($btnRemoveDb, 1, 5)

        $btnSaveDb = New-UGSMButton -Text 'Save DB' -Width 150 -Height 28 -BackColor $Theme.Accent
        $btnSaveDb.Dock = 'Top'
        [void]$wrapper.Controls.Add($btnSaveDb, 1, 6)

        $loadDbState = {
            $list.Items.Clear()
            $moduleInstalled = Test-UGSMGameSCUMPSSQLiteInstalled
            $btnInstallSql.Visible = -not $moduleInstalled
            if (-not $moduleInstalled) {
                [void]$list.Items.Add('PSSQLite is not installed.')
                [void]$list.Items.Add('Install it to edit elevated users in SCUM.db.')
                return
            }

            $dbPath = Resolve-UGSMGameSCUMDatabasePath -Instance $Instance -PreferRuntime
            if ([string]::IsNullOrWhiteSpace([string]$dbPath)) {
                [void]$list.Items.Add('SCUM.db path could not be resolved for this profile.')
                return
            }

            if (-not (Test-Path -LiteralPath $dbPath -PathType Leaf)) {
                [void]$list.Items.Add('SCUM.db was not found yet for this instance.')
                [void]$list.Items.Add($dbPath)
                return
            }

            try {
                $ids = @(Get-UGSMGameSCUMElevatedUsers -DatabasePath $dbPath)
                if ($ids.Count -eq 0) {
                    [void]$list.Items.Add('No elevated users were found.')
                }
                else {
                    foreach ($id in $ids) { [void]$list.Items.Add($id) }
                }
            }
            catch {
                [void]$list.Items.Add('Error reading SCUM.db: ' + $_.Exception.Message)
            }
        }.GetNewClosure()

        $btnInstallSql.Add_Click({
                try {
                    Install-UGSMGameSCUMPSSQLite | Out-Null
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
                    $dbPath = Resolve-UGSMGameSCUMDatabasePath -Instance $Instance -PreferRuntime
                    if ([string]::IsNullOrWhiteSpace([string]$dbPath)) { throw 'SCUM.db path could not be resolved for this instance.' }
                    Save-UGSMGameSCUMElevatedUsers -DatabasePath $dbPath -UserIds $userIds
                    if ($StatusLabel) { $StatusLabel.Text = 'Saved elevated users to SCUM.db: ' + $dbPath }
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

    function Add-SCUMFieldRow {
        param(
            [Parameter(Mandatory)][System.Windows.Forms.FlowLayoutPanel]$Parent,
            [Parameter(Mandatory)][hashtable]$Field,
            [Parameter(Mandatory)][object]$Instance,
            [AllowNull()][System.Windows.Forms.Label]$StatusLabel
        )

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
                    $fieldHost = New-SCUMNarrowHost
                    $control = New-Object System.Windows.Forms.CheckBox
                    $control.AutoSize = $true
                    $control.Anchor = 'Left'
                    $control.Margin = New-Object System.Windows.Forms.Padding(0)
                    $control.BackColor = [System.Drawing.Color]::Transparent
                    $control.ForeColor = New-UGSMColor $Theme.Text
                    $control.Checked = ([string](Get-SCUMSafeIniValue -Field $Field) -match '^(?i:true|1|yes)$')
                    [void]$fieldHost.Controls.Add($control)
                    [void]$row.Controls.Add($fieldHost, 1, 0)
                    $controlMap[$Field.Id] = @{ Field = $Field; Control = $control }
                }
                'InstanceBoolean' {
                    $fieldHost = New-SCUMNarrowHost
                    $control = New-Object System.Windows.Forms.CheckBox
                    $control.AutoSize = $true
                    $control.Anchor = 'Left'
                    $control.Margin = New-Object System.Windows.Forms.Padding(0)
                    $control.BackColor = [System.Drawing.Color]::Transparent
                    $control.ForeColor = New-UGSMColor $Theme.Text
                    $instanceValue = Get-SCUMSafeInstanceValue -Field $Field
                    $control.Checked = [bool]$instanceValue
                    [void]$fieldHost.Controls.Add($control)
                    [void]$row.Controls.Add($fieldHost, 1, 0)
                    $controlMap[$Field.Id] = @{ Field = $Field; Control = $control }
                }
                'Number' {
                    $numberHost = New-SCUMNarrowHost
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
                    $rawValue = Get-SCUMSafeIniValue -Field $Field
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
                'Password' {
                    $control = New-SCUMStretchTextBox -MaskSecret
                    $control.Text = [string](Get-SCUMSafeIniValue -Field $Field)
                    [void]$row.Controls.Add($control, 1, 0)
                    $controlMap[$Field.Id] = @{ Field = $Field; Control = $control }
                }
                'MultilineText' {
                    $control = New-SCUMStretchTextBox -Multiline -Height $layout.MultilineHeight
                    $control.Text = [string](Get-SCUMSafeIniValue -Field $Field)
                    [void]$row.Controls.Add($control, 1, 0)
                    $controlMap[$Field.Id] = @{ Field = $Field; Control = $control }
                }
                'InstanceText' {
                    $isSecretField = $false
                    if ($Field.ContainsKey('Secret')) { $isSecretField = [bool]$Field.Secret }
                    $control = New-SCUMStretchTextBox -MaskSecret:$isSecretField
                    $control.Text = [string](Get-SCUMSafeInstanceValue -Field $Field)
                    [void]$row.Controls.Add($control, 1, 0)
                    $controlMap[$Field.Id] = @{ Field = $Field; Control = $control }
                }
                'StringList' {
                    $control = New-SCUMTextBox -Width $layout.WideControlWidth -Multiline -Height $layout.StringListHeight
                    $resolvedListPath = Resolve-UGSMGameSCUMEditorFieldPath -Field $Field -Paths $paths
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
                    $buttonHost = New-SCUMNarrowHost
                    $control = New-UGSMButton -Text ([string]$Field.ButtonText) -X 0 -Y 0 -Width 220 -Height 30 -BackColor $global:UGSM_ColorNeutral
                    $action = $Field.Action
                    $control.Add_Click({
                            try { & $action $Instance $paths $StatusLabel }
                            catch { if ($StatusLabel) { $StatusLabel.Text = 'SCUM action failed: ' + $_.Exception.Message } }
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

                    New-SCUMElevatedUsersControl -Instance $Instance -Parent $elevatedHost -StatusLabel $StatusLabel | Out-Null
                    [void]$row.Controls.Add($elevatedHost, 1, 0)
                }
                default {
                    $control = New-SCUMStretchTextBox
                    $control.Text = [string](Get-SCUMSafeIniValue -Field $Field)
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
            $errorLabel = New-UGSMLabel -Text ('SCUM field row failed: ' + $_.Exception.Message) -X 0 -Y 0 -Width 700 -Height 18 -FontSize 8.5 -Color $global:UGSM_ColorErrorTextSoft
            $errorLabel.Margin = New-Object System.Windows.Forms.Padding(0, 4, 0, 0)
            [void]$row.Controls.Add($errorLabel, 1, 0)
        }

        [void]$Parent.Controls.Add($row)
    }

    function New-SCUMEditorContent {
        param(
            [Parameter(Mandatory)][System.Windows.Forms.Control]$Parent,
            [string]$Description,
            [object[]]$Fields
        )

        $scroll = New-Object System.Windows.Forms.Panel
        $scroll.Dock = 'Fill'
        $scroll.AutoScroll = $true
        $scroll.BackColor = $global:UGSM_ColorPageBackground
        [void]$Parent.Controls.Add($scroll)

        $content = New-Object System.Windows.Forms.FlowLayoutPanel
        $content.Dock = 'Top'
        $content.AutoSize = $true
        $content.AutoSizeMode = 'GrowAndShrink'
        $content.FlowDirection = 'TopDown'
        $content.WrapContents = $false
        $content.Margin = New-Object System.Windows.Forms.Padding(0)
        $content.Padding = New-Object System.Windows.Forms.Padding($layout.ContentPadding, 10, $layout.ContentPadding, 10)
        $content.BackColor = $global:UGSM_ColorPageBackground
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
            Add-SCUMFieldRow -Parent $content -Field $field -Instance $Instance -StatusLabel $StatusLabel
        }

        & $refreshScrollLayout
    }

    $HostPanel.SuspendLayout()
    try {
        $HostPanel.Controls.Clear()
        $HostPanel.BackColor = $global:UGSM_ColorSurfaceDeep

        $root = New-Object System.Windows.Forms.TableLayoutPanel
        $root.Dock = 'Fill'
        $root.Margin = New-Object System.Windows.Forms.Padding(0)
        $root.Padding = New-Object System.Windows.Forms.Padding(0)
        $root.BackColor = $global:UGSM_ColorSurfaceDeep
        $root.ColumnCount = 1
        $root.RowCount = 3
        [void]$root.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent, 100)))
        [void]$root.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Absolute, $layout.HeaderHeight)))
        [void]$root.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Absolute, $layout.ToolbarHeight)))
        [void]$root.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Percent, 100)))
        [void]$HostPanel.Controls.Add($root)

        $header = New-Object System.Windows.Forms.Panel
        $header.Dock = 'Fill'
        $header.BackColor = $global:UGSM_ColorHeaderBackground
        [void]$root.Controls.Add($header, 0, 0)

        $title = New-UGSMLabel -Text ('SCUM Profile Editor - ' + [string]$Instance.Name) -X 12 -Y 10 -Width 420 -Height 18 -FontSize 10 -Style Bold -Color $Theme.Text
        $pathLabel = New-UGSMLabel -Text ([string]$paths.ProfileRoot) -X 12 -Y 28 -Width 760 -Height 16 -FontSize 8 -Color $Theme.Muted
        [void]$header.Controls.Add($title)
        [void]$header.Controls.Add($pathLabel)

        $toolbar = New-Object System.Windows.Forms.Panel
        $toolbar.Dock = 'Fill'
        $toolbar.BackColor = $global:UGSM_ColorHeaderBackground
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

        $btnReload = New-UGSMButton -Text 'Reload' -X 0 -Y 0 -Width 84 -Height 28 -BackColor $global:UGSM_ColorNeutral
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
            $tabPage.Text = [string]$tabDef.Title
            $tabPage.BackColor = $global:UGSM_ColorPageBackground
            [void]$tabs.TabPages.Add($tabPage)

            if ($tabDef.PSObject.Properties.Name -contains 'SubTabs' -and @($tabDef.SubTabs).Count -gt 0) {
                $subTabs = New-Object System.Windows.Forms.TabControl
                $subTabs.Dock = 'Fill'
                $subTabs.SuspendLayout()
                [void]$tabPage.Controls.Add($subTabs)

                foreach ($subDef in @($tabDef.SubTabs)) {
                    $subPage = New-Object System.Windows.Forms.TabPage
                    $subPage.SuspendLayout()
                    $subPage.Text = [string]$subDef.Title
                    $subPage.BackColor = $global:UGSM_ColorPageBackground
                    [void]$subTabs.TabPages.Add($subPage)
                    New-SCUMEditorContent -Parent $subPage -Description ([string]$(if ($subDef.PSObject.Properties.Name -contains 'Description') { $subDef.Description } else { '' })) -Fields @($subDef.Fields)
                    $subPage.ResumeLayout($false)
                }

                $subTabs.ResumeLayout($false)
            }
            else {
                New-SCUMEditorContent -Parent $tabPage -Description ([string]$(if ($tabDef.PSObject.Properties.Name -contains 'Description') { $tabDef.Description } else { '' })) -Fields @($tabDef.Fields)
            }

            $tabPage.ResumeLayout($false)
        }

        $tabs.ResumeLayout($true)

        $btnSave.Add_Click({
                try {
                    Write-UGSMGameSCUMLog -Level 'INFO' -Message ("Save clicked from editor. InstanceId={0}" -f $instanceId)
                    $result = Save-UGSMGameSCUMInstanceEditor -Instance $Instance -EditorState $controlMap
                    if ($result -and ($result.PSObject.Properties.Name -contains 'Instance') -and $result.Instance) {
                        $Instance = $result.Instance
                    }
                    if ($StatusLabel) {
                        $StatusLabel.Text = [string]$(if ($result -and $result.PSObject.Properties.Name -contains 'Message') { $result.Message } else { 'Saved SCUM profile settings.' })
                    }
                }
                catch {
                    if ($StatusLabel) { $StatusLabel.Text = 'SCUM save failed: ' + $_.Exception.Message }
                }
            }.GetNewClosure())

        $btnReload.Add_Click({
                try {
                    Write-UGSMGameSCUMLog -Level 'INFO' -Message ("Reload clicked from editor. InstanceId={0}" -f $instanceId)
                    New-UGSMGameSCUMInstanceEditor -Instance $Instance -Theme $Theme -HostPanel $HostPanel -StatusLabel $StatusLabel | Out-Null
                    if ($StatusLabel) { $StatusLabel.Text = 'SCUM profile editor reloaded.' }
                }
                catch {
                    if ($StatusLabel) { $StatusLabel.Text = 'SCUM reload failed: ' + $_.Exception.Message }
                }
            }.GetNewClosure())

        $root.Tag = [pscustomobject]@{
            Instance   = $Instance
            Paths      = $paths
            ControlMap = $controlMap
            Schema     = $schema
            Status     = $StatusLabel
        }

        if ($StatusLabel) { $StatusLabel.Text = 'SCUM profile editor loaded.' }
        $swEditor.Stop()
        $level = if ($swEditor.ElapsedMilliseconds -ge 2000) { 'WARN' } else { 'INFO' }
        Write-UGSMGameSCUMLog -Level $level -Message ("Editor creation finished. InstanceId={0}; DurationMs={1}; Tabs={2}" -f $instanceId, $swEditor.ElapsedMilliseconds, @($schema.Tabs).Count)
        return $root
    }
    finally {
        $HostPanel.ResumeLayout()
    }
}

function Invoke-UGSMGameSCUMOpenPath {
    [CmdletBinding()]
    param(
        [AllowEmptyString()][AllowNull()][string]$Path,
        [switch]$EnsureFile,
        [switch]$EnsureFolder,
        [AllowNull()][System.Windows.Forms.Label]$StatusLabel,
        [string]$OpenedMessage = 'Opened path.'
    )

    if ([string]::IsNullOrWhiteSpace([string]$Path)) {
        throw 'SCUM open failed: target path was blank.'
    }

    if ($EnsureFolder) {
        if (-not (Test-Path -LiteralPath $Path -PathType Container)) {
            throw ("SCUM open failed: folder does not exist: {0}" -f $Path)
        }

        Start-Process -FilePath 'explorer.exe' -ArgumentList @($Path) -ErrorAction Stop | Out-Null
        if ($StatusLabel) { $StatusLabel.Text = $OpenedMessage }
        return
    }

    if ($EnsureFile) {
        $parent = Split-Path -Parent $Path
        if ([string]::IsNullOrWhiteSpace([string]$parent)) {
            throw 'SCUM open failed: file parent path could not be resolved.'
        }

        if (-not (Test-Path -LiteralPath $parent -PathType Container)) {
            throw ("SCUM open failed: folder does not exist: {0}" -f $parent)
        }

        if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
            throw ("SCUM open failed: file does not exist: {0}" -f $Path)
        }

        Start-Process -FilePath 'notepad.exe' -ArgumentList @($Path) -ErrorAction Stop | Out-Null
        if ($StatusLabel) { $StatusLabel.Text = $OpenedMessage }
        return
    }

    Start-Process -FilePath 'explorer.exe' -ArgumentList @($Path) -ErrorAction Stop | Out-Null
    if ($StatusLabel) { $StatusLabel.Text = $OpenedMessage }
}

function Resolve-UGSMGameSCUMEditorPath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$Instance,
        [AllowNull()]$Paths,
        [Parameter(Mandatory)][string]$Target
    )

    if (-not $Instance) {
        throw 'SCUM action failed: selected instance was null.'
    }

    if (-not $Paths) {
        $Paths = Get-UGSMGameSCUMProfilePaths -Instance $Instance
    }

    if (-not $Paths) {
        throw ("SCUM action failed: could not resolve paths for '{0}'." -f $Target)
    }

    $candidate = switch ($Target) {
        'ServerSettings' { [string]$Paths.ServerSettingsPath }
        'AdminUsers' { [string]$Paths.AdminUsersPath }
        'ExclusiveUsers' { [string]$Paths.ExclusiveUsersPath }
        'WhitelistedUsers' { [string]$Paths.WhitelistedUsersPath }
        'RaidTimes' { [string]$Paths.RaidTimesPath }
        'EconomyOverride' { [string]$Paths.EconomyOverridePath }
        'ProfileFolder' { [string]$Paths.ProfileRoot }
        default { $null }
    }

    if ([string]::IsNullOrWhiteSpace([string]$candidate)) {
        throw ("SCUM action failed: could not resolve path for '{0}'." -f $Target)
    }

    return [string]$candidate
}

function Invoke-UGSMGameSCUMEditorAction {
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

    $resolvedPath = Resolve-UGSMGameSCUMEditorPath -Instance $Instance -Paths $Paths -Target $Target

    Invoke-UGSMGameSCUMOpenPath `
        -Path $resolvedPath `
        -EnsureFile:$EnsureFile `
        -EnsureFolder:$EnsureFolder `
        -StatusLabel $StatusLabel `
        -OpenedMessage $OpenedMessage
}

function Get-UGSMGameSCUMEditorSchema {
    [CmdletBinding()]
    param()

    if ($script:UGSMGameSCUMEditorSchemaCache) {
        return $script:UGSMGameSCUMEditorSchemaCache
    }

    $actions = @{
        OpenServerSettings   = { param($Instance, $Paths, $StatusLabel) Invoke-UGSMGameSCUMEditorAction -Instance $Instance -Paths $Paths -Target 'ServerSettings'   -EnsureFile   -StatusLabel $StatusLabel -OpenedMessage 'Opened ServerSettings.ini.' }
        OpenAdminUsers       = { param($Instance, $Paths, $StatusLabel) Invoke-UGSMGameSCUMEditorAction -Instance $Instance -Paths $Paths -Target 'AdminUsers'       -EnsureFile   -StatusLabel $StatusLabel -OpenedMessage 'Opened AdminUsers.ini.' }
        OpenExclusiveUsers   = { param($Instance, $Paths, $StatusLabel) Invoke-UGSMGameSCUMEditorAction -Instance $Instance -Paths $Paths -Target 'ExclusiveUsers'   -EnsureFile   -StatusLabel $StatusLabel -OpenedMessage 'Opened ExclusiveUsers.ini.' }
        OpenWhitelistedUsers = { param($Instance, $Paths, $StatusLabel) Invoke-UGSMGameSCUMEditorAction -Instance $Instance -Paths $Paths -Target 'WhitelistedUsers' -EnsureFile   -StatusLabel $StatusLabel -OpenedMessage 'Opened WhitelistedUsers.ini.' }
        OpenRaidTimes        = { param($Instance, $Paths, $StatusLabel) Invoke-UGSMGameSCUMEditorAction -Instance $Instance -Paths $Paths -Target 'RaidTimes'        -EnsureFile   -StatusLabel $StatusLabel -OpenedMessage 'Opened RaidTimes.json.' }
        OpenEconomy          = { param($Instance, $Paths, $StatusLabel) Invoke-UGSMGameSCUMEditorAction -Instance $Instance -Paths $Paths -Target 'EconomyOverride'  -EnsureFile   -StatusLabel $StatusLabel -OpenedMessage 'Opened EconomyOverride.json.' }
        OpenProfileFolder    = { param($Instance, $Paths, $StatusLabel) Invoke-UGSMGameSCUMEditorAction -Instance $Instance -Paths $Paths -Target 'ProfileFolder'    -EnsureFolder -StatusLabel $StatusLabel -OpenedMessage 'Opened the SCUM profile folder.' }
    }

    $samplePaths = [pscustomobject]@{
        AdminUsersPath       = 'AdminUsers.ini'
        ExclusiveUsersPath   = 'ExclusiveUsers.ini'
        WhitelistedUsersPath = 'WhitelistedUsers.ini'
        BannedUsersPath      = 'BannedUsers.ini'
        SilencedUsersPath    = 'SilencedUsers.ini'
    }

    $schema = [pscustomobject]@{
        Tabs = @(
            [pscustomobject]@{
                Title  = 'General'
                Fields = @(
                    @{ Id = 'ServerName'; Type = 'Text'; Section = 'General'; Key = 'scum.ServerName'; Label = 'Server Name'; DefaultValue = 'SCUM Server'; Hint = 'The public server name shown in the browser.' }
                    @{ Id = 'ServerDescription'; Type = 'MultilineText'; Section = 'General'; Key = 'scum.ServerDescription'; Label = 'Server Description'; DefaultValue = ''; Hint = 'Short summary shown to players before they join.' }
                    @{ Id = 'ServerPassword'; Type = 'Password'; Section = 'General'; Key = 'scum.ServerPassword'; Label = 'Server Password'; DefaultValue = ''; Secret = $true; Hint = 'Leave blank to keep the server open. Masked on screen.' }
                    @{ Id = 'MaxPlayers'; Type = 'Number'; Section = 'General'; Key = 'scum.MaxPlayers'; Label = 'Max Players'; DefaultValue = '64'; Min = 1; Max = 128; Decimals = 0; Hint = 'Maximum simultaneous players allowed on the server.' }
                    @{ Id = 'WelcomeMessage'; Type = 'MultilineText'; Section = 'General'; Key = 'scum.WelcomeMessage'; Label = 'Welcome Message'; DefaultValue = ''; Hint = 'Shown when a player joins the server.' }
                    @{ Id = 'Motd'; Type = 'MultilineText'; Section = 'General'; Key = 'scum.MessageOfTheDay'; Label = 'Message of the Day'; DefaultValue = ''; Hint = 'Recurring message broadcast to connected players.' }
                    @{ Id = 'MotdCooldown'; Type = 'Number'; Section = 'General'; Key = 'scum.MessageOfTheDayCooldown'; Label = 'MOTD Cooldown'; DefaultValue = '10.000000'; Min = 0; Max = 1440; Decimals = 3; Increment = '0.500'; Hint = 'Minutes between Message of the Day repeats.' }
                    @{ Id = 'Playstyle'; Type = 'Text'; Section = 'General'; Key = 'scum.ServerPlaystyle'; Label = 'Playstyle'; DefaultValue = 'PVE'; Hint = 'Examples include PVE or PVP. This is metadata shown to players.' }
                    @{ Id = 'RconPort'; Type = 'Number'; Section = 'General'; Key = 'scum.RCONPort'; Label = 'RCON Port'; DefaultValue = '7778'; Min = 1; Max = 65535; Decimals = 0; Hint = 'Reserved for future RCON integration. This key may be absent in older files.' }
                    @{ Id = 'RconPassword'; Type = 'Password'; Section = 'General'; Key = 'scum.RCONPassword'; Label = 'RCON Password'; DefaultValue = ''; Secret = $true; Hint = 'Reserved for future RCON integration. Masked on screen.' }
                    @{ Id = 'MinTick'; Type = 'Number'; Section = 'General'; Key = 'scum.MinServerTickRate'; Label = 'Min Tick Rate'; DefaultValue = '5'; Min = 1; Max = 128; Decimals = 0; Hint = 'Lower bound for server simulation tick rate.' }
                    @{ Id = 'MaxTick'; Type = 'Number'; Section = 'General'; Key = 'scum.MaxServerTickRate'; Label = 'Max Tick Rate'; DefaultValue = '30'; Min = 1; Max = 128; Decimals = 0; Hint = 'Upper bound for server simulation tick rate.' }
                    @{ Id = 'MaxPingEnabled'; Type = 'Boolean'; Section = 'General'; Key = 'scum.MaxPingCheckEnabled'; Label = 'Enable Max Ping Check'; DefaultValue = 'True'; Hint = 'Kicks or blocks players over the ping limit.' }
                    @{ Id = 'MaxPing'; Type = 'Number'; Section = 'General'; Key = 'scum.MaxPing'; Label = 'Max Ping'; DefaultValue = '200.000000'; Min = 0; Max = 9999; Decimals = 3; Increment = '5'; Hint = 'The maximum allowed ping when ping checks are enabled.' }
                )
            }
            [pscustomobject]@{
                Title   = 'Server Settings'
                SubTabs = @(
                    [pscustomobject]@{ Title = 'Players'; Description = 'Player-facing quality-of-life, chat, camera, and progression settings.'; Fields = @(
                            @{ Id = 'AllowFirstPerson'; Type = 'Boolean'; Section = 'General'; Key = 'scum.AllowFirstPerson'; Label = 'Allow First Person'; DefaultValue = 'True'; Hint = 'Allows first-person camera.' }
                            @{ Id = 'AllowThirdPerson'; Type = 'Boolean'; Section = 'General'; Key = 'scum.AllowThirdPerson'; Label = 'Allow Third Person'; DefaultValue = 'True'; Hint = 'Allows third-person camera.' }
                            @{ Id = 'AllowCrosshair'; Type = 'Boolean'; Section = 'General'; Key = 'scum.AllowCrosshair'; Label = 'Allow Crosshair'; DefaultValue = 'True'; Hint = 'Shows the crosshair to players.' }
                            @{ Id = 'AllowMapScreen'; Type = 'Boolean'; Section = 'General'; Key = 'scum.AllowMapScreen'; Label = 'Allow Map Screen'; DefaultValue = 'True'; Hint = 'Lets players open the in-game map.' }
                            @{ Id = 'AllowVoting'; Type = 'Boolean'; Section = 'General'; Key = 'scum.AllowVoting'; Label = 'Allow Voting'; DefaultValue = 'True'; Hint = 'Enables kick/ban or other player voting systems.' }
                            @{ Id = 'AllowEvents'; Type = 'Boolean'; Section = 'General'; Key = 'scum.AllowEvents'; Label = 'Allow Events'; DefaultValue = 'True'; Hint = 'Enables official event systems on the server.' }
                            @{ Id = 'AllowGlobalChat'; Type = 'Boolean'; Section = 'General'; Key = 'scum.AllowGlobalChat'; Label = 'Allow Global Chat'; DefaultValue = 'True'; Hint = 'Controls server-wide text chat.' }
                            @{ Id = 'AllowLocalChat'; Type = 'Boolean'; Section = 'General'; Key = 'scum.AllowLocalChat'; Label = 'Allow Local Chat'; DefaultValue = 'True'; Hint = 'Controls local proximity chat.' }
                            @{ Id = 'AllowSquadChat'; Type = 'Boolean'; Section = 'General'; Key = 'scum.AllowSquadChat'; Label = 'Allow Squad Chat'; DefaultValue = 'True'; Hint = 'Controls squad chat channels.' }
                            @{ Id = 'HideKillNotification'; Type = 'Boolean'; Section = 'General'; Key = 'scum.HideKillNotification'; Label = 'Hide Kill Notifications'; DefaultValue = 'True'; Hint = 'Suppresses kill feed notifications.' }
                            @{ Id = 'FameGainMultiplier'; Type = 'Number'; Section = 'General'; Key = 'scum.FameGainMultiplier'; Label = 'Fame Gain Multiplier'; DefaultValue = '1.000000'; Min = 0; Max = 100; Decimals = 3; Increment = '0.100'; Hint = 'Scales fame earned from gameplay.' }
                            @{ Id = 'NewPlayerProtection'; Type = 'Boolean'; Section = 'Features'; Key = 'scum.EnableNewPlayerProtection'; Label = 'Enable New Player Protection'; DefaultValue = 'True'; Hint = 'Gives fresh players temporary safety.' }
                            @{ Id = 'NewPlayerProtectionDuration'; Type = 'Number'; Section = 'Features'; Key = 'scum.NewPlayerProtectionDuration'; Label = 'New Player Protection Duration'; DefaultValue = '120.000000'; Min = 0; Max = 10000; Decimals = 3; Increment = '5'; Hint = 'How long the new player protection lasts.' }
                        ) 
                    }
                    [pscustomobject]@{ Title = 'Puppets & NPCs'; Description = 'Controls for puppets, sentries, dropships, and armed NPCs.'; Fields = @(
                            @{ Id = 'MaxAllowedPuppets'; Type = 'Number'; Section = 'World'; Key = 'scum.MaxAllowedPuppets'; Label = 'Max Allowed Puppets'; DefaultValue = '-1'; Min = -1; Max = 10000; Decimals = 0; Hint = 'Global puppet cap. -1 lets the game decide.' }
                            @{ Id = 'DisableSentrySpawning'; Type = 'Boolean'; Section = 'World'; Key = 'scum.DisableSentrySpawning'; Label = 'Disable Sentry Spawning'; DefaultValue = 'False'; Hint = 'Turns bunker and POI sentries off.' }
                            @{ Id = 'EnableSentryRespawning'; Type = 'Boolean'; Section = 'World'; Key = 'scum.EnableSentryRespawning'; Label = 'Enable Sentry Respawning'; DefaultValue = 'True'; Hint = 'Allows destroyed sentries to return.' }
                            @{ Id = 'PuppetsCanOpenDoors'; Type = 'Boolean'; Section = 'World'; Key = 'scum.PuppetsCanOpenDoors'; Label = 'Puppets Can Open Doors'; DefaultValue = 'True'; Hint = 'Makes puppets more dangerous indoors.' }
                            @{ Id = 'PuppetHealthMultiplier'; Type = 'Number'; Section = 'World'; Key = 'scum.PuppetHealthMultiplier'; Label = 'Puppet Health Multiplier'; DefaultValue = '1.000000'; Min = 0; Max = 100; Decimals = 3; Increment = '0.100'; Hint = 'Scales puppet health.' }
                            @{ Id = 'PuppetRunningSpeedMultiplier'; Type = 'Number'; Section = 'World'; Key = 'scum.PuppetRunningSpeedMultiplier'; Label = 'Puppet Running Speed'; DefaultValue = '1.000000'; Min = 0; Max = 20; Decimals = 3; Increment = '0.100'; Hint = 'Scales puppet movement speed.' }
                            @{ Id = 'SentryHealthMultiplier'; Type = 'Number'; Section = 'World'; Key = 'scum.SentryHealthMultiplier'; Label = 'Sentry Health Multiplier'; DefaultValue = '1.000000'; Min = 0; Max = 100; Decimals = 3; Increment = '0.100'; Hint = 'Scales sentry health.' }
                            @{ Id = 'ArmedNPCDifficultyLevel'; Type = 'Number'; Section = 'World'; Key = 'scum.ArmedNPCDifficultyLevel'; Label = 'Armed NPC Difficulty'; DefaultValue = '2'; Min = 0; Max = 10; Decimals = 0; Hint = 'General difficulty tier for armed NPCs.' }
                            @{ Id = 'ArmedNPCHealthMultiplier'; Type = 'Number'; Section = 'World'; Key = 'scum.ArmedNPCHealthMultiplier'; Label = 'Armed NPC Health'; DefaultValue = '1.000000'; Min = 0; Max = 100; Decimals = 3; Increment = '0.100'; Hint = 'Scales armed NPC health.' }
                            @{ Id = 'ArmedNPCDamageMultiplier'; Type = 'Number'; Section = 'World'; Key = 'scum.ArmedNPCDamageMultiplier'; Label = 'Armed NPC Damage'; DefaultValue = '1.000000'; Min = 0; Max = 100; Decimals = 3; Increment = '0.100'; Hint = 'Scales armed NPC weapon damage.' }
                        ) 
                    }
                    [pscustomobject]@{ Title = 'Animals'; Description = 'Wildlife population, hunt, and animal durability controls.'; Fields = @(
                            @{ Id = 'MaxAllowedAnimals'; Type = 'Number'; Section = 'World'; Key = 'scum.MaxAllowedAnimals'; Label = 'Max Allowed Animals'; DefaultValue = '-1'; Min = -1; Max = 10000; Decimals = 0; Hint = 'Global wildlife cap. -1 uses the game default.' }
                            @{ Id = 'AnimalSpawnWeight'; Type = 'Number'; Section = 'World'; Key = 'scum.AnimalWorldEncounterSpawnWeightMultiplier'; Label = 'Animal Encounter Spawn Weight'; DefaultValue = '1.000000'; Min = 0; Max = 100; Decimals = 3; Increment = '0.100'; Hint = 'Scales wildlife encounter frequency.' }
                            @{ Id = 'MaxAllowedHunts'; Type = 'Number'; Section = 'World'; Key = 'scum.MaxAllowedHunts'; Label = 'Max Allowed Hunts'; DefaultValue = '20'; Min = 0; Max = 500; Decimals = 0; Hint = 'Maximum concurrent hunt events.' }
                            @{ Id = 'BearHealth'; Type = 'Number'; Section = 'World'; Key = 'scum.BearMaxHealthMultiplier'; Label = 'Bear Health Multiplier'; DefaultValue = '1.000000'; Min = 0; Max = 100; Decimals = 3; Increment = '0.100'; Hint = 'Scales bear durability.' }
                            @{ Id = 'BoarHealth'; Type = 'Number'; Section = 'World'; Key = 'scum.BoarMaxHealthMultiplier'; Label = 'Boar Health Multiplier'; DefaultValue = '1.000000'; Min = 0; Max = 100; Decimals = 3; Increment = '0.100'; Hint = 'Scales boar durability.' }
                            @{ Id = 'DeerHealth'; Type = 'Number'; Section = 'World'; Key = 'scum.DeerMaxHealthMultiplier'; Label = 'Deer Health Multiplier'; DefaultValue = '1.000000'; Min = 0; Max = 100; Decimals = 3; Increment = '0.100'; Hint = 'Scales deer durability.' }
                            @{ Id = 'WolfHealth'; Type = 'Number'; Section = 'World'; Key = 'scum.WolfMaxHealthMultiplier'; Label = 'Wolf Health Multiplier'; DefaultValue = '1.000000'; Min = 0; Max = 100; Decimals = 3; Increment = '0.100'; Hint = 'Scales wolf durability.' }
                        ) 
                    }
                    [pscustomobject]@{ Title = 'Environment'; Description = 'Time, weather, map shape, and ambient world behavior.'; Fields = @(
                            @{ Id = 'StartTimeOfDay'; Type = 'Text'; Section = 'World'; Key = 'scum.StartTimeOfDay'; Label = 'Start Time of Day'; DefaultValue = '08:00:00'; Hint = 'In-game time when the server starts or restarts.' }
                            @{ Id = 'TimeOfDaySpeed'; Type = 'Number'; Section = 'World'; Key = 'scum.TimeOfDaySpeed'; Label = 'Time of Day Speed'; DefaultValue = '3.840000'; Min = 0; Max = 100; Decimals = 3; Increment = '0.100'; Hint = 'How quickly the day/night cycle advances.' }
                            @{ Id = 'NighttimeDarkness'; Type = 'Number'; Section = 'World'; Key = 'scum.NighttimeDarkness'; Label = 'Nighttime Darkness'; DefaultValue = '0.000000'; Min = 0; Max = 1; Decimals = 3; Increment = '0.050'; Hint = 'Makes nights brighter or darker.' }
                            @{ Id = 'SunriseTime'; Type = 'Text'; Section = 'World'; Key = 'scum.SunriseTime'; Label = 'Sunrise Time'; DefaultValue = '06:00:00'; Hint = 'World sunrise time.' }
                            @{ Id = 'SunsetTime'; Type = 'Text'; Section = 'World'; Key = 'scum.SunsetTime'; Label = 'Sunset Time'; DefaultValue = '21:00:00'; Hint = 'World sunset time.' }
                            @{ Id = 'EnableFog'; Type = 'Boolean'; Section = 'World'; Key = 'scum.EnableFog'; Label = 'Enable Fog'; DefaultValue = 'True'; Hint = 'Enables normal fog behavior.' }
                            @{ Id = 'MaxAllowedBirds'; Type = 'Number'; Section = 'World'; Key = 'scum.MaxAllowedBirds'; Label = 'Max Allowed Birds'; DefaultValue = '15'; Min = 0; Max = 1000; Decimals = 0; Hint = 'Ambient bird cap.' }
                            @{ Id = 'EnableLockedLootContainers'; Type = 'Boolean'; Section = 'World'; Key = 'scum.EnableLockedLootContainers'; Label = 'Enable Locked Loot Containers'; DefaultValue = 'True'; Hint = 'Allows bunker lockers and other locked containers.' }
                            @{ Id = 'CustomMapEnabled'; Type = 'Boolean'; Section = 'World'; Key = 'scum.CustomMapEnabled'; Label = 'Enable Custom Map Bounds'; DefaultValue = 'False'; Hint = 'Turns on a custom playable map rectangle.' }
                        ) 
                    }
                    [pscustomobject]@{ Title = 'Respawn'; Description = 'Respawn permissions, costs, cooldowns, and penalties.'; Fields = @(
                            @{ Id = 'AllowSectorRespawn'; Type = 'Boolean'; Section = 'Respawn'; Key = 'scum.AllowSectorRespawn'; Label = 'Allow Sector Respawn'; DefaultValue = 'True'; Hint = 'Allows sector respawns.' }
                            @{ Id = 'AllowShelterRespawn'; Type = 'Boolean'; Section = 'Respawn'; Key = 'scum.AllowShelterRespawn'; Label = 'Allow Shelter Respawn'; DefaultValue = 'True'; Hint = 'Allows shelter respawns.' }
                            @{ Id = 'AllowSquadmateRespawn'; Type = 'Boolean'; Section = 'Respawn'; Key = 'scum.AllowSquadmateRespawn'; Label = 'Allow Squadmate Respawn'; DefaultValue = 'True'; Hint = 'Allows respawning on squadmates.' }
                            @{ Id = 'RandomRespawnPrice'; Type = 'Text'; Section = 'Respawn'; Key = 'scum.RandomRespawnPrice'; Label = 'Random Respawn Price'; DefaultValue = '250'; Hint = 'Price for random respawns.' }
                            @{ Id = 'SectorRespawnPrice'; Type = 'Text'; Section = 'Respawn'; Key = 'scum.SectorRespawnPrice'; Label = 'Sector Respawn Price'; DefaultValue = '1000'; Hint = 'Price for sector respawns.' }
                            @{ Id = 'ShelterRespawnPrice'; Type = 'Text'; Section = 'Respawn'; Key = 'scum.ShelterRespawnPrice'; Label = 'Shelter Respawn Price'; DefaultValue = '1g'; Hint = 'Price for respawning on shelters.' }
                            @{ Id = 'RandomRespawnCooldown'; Type = 'Number'; Section = 'Respawn'; Key = 'scum.RandomRespawnCooldown'; Label = 'Random Respawn Cooldown'; DefaultValue = '0.000000'; Min = 0; Max = 100000; Decimals = 3; Increment = '5'; Hint = 'Cooldown before random respawn is available again.' }
                            @{ Id = 'SectorRespawnCooldown'; Type = 'Number'; Section = 'Respawn'; Key = 'scum.SectorRespawnCooldown'; Label = 'Sector Respawn Cooldown'; DefaultValue = '240.000000'; Min = 0; Max = 100000; Decimals = 3; Increment = '5'; Hint = 'Cooldown before sector respawn is available again.' }
                            @{ Id = 'PermadeathThreshold'; Type = 'Number'; Section = 'Respawn'; Key = 'scum.PermadeathThreshold'; Label = 'Permadeath Threshold'; DefaultValue = '-2500'; Min = -100000; Max = 100000; Decimals = 0; Hint = 'Threshold used by permadeath rules.' }
                        ) 
                    }
                    [pscustomobject]@{ Title = 'Vehicles'; Description = 'Vehicle population and wear/tear multipliers.'; Fields = @(
                            @{ Id = 'FuelDrain'; Type = 'Number'; Section = 'Vehicles'; Key = 'scum.FuelDrainFromEngineMultiplier'; Label = 'Fuel Drain Multiplier'; DefaultValue = '1.000000'; Min = 0; Max = 100; Decimals = 3; Increment = '0.100'; Hint = 'Scales engine fuel usage.' }
                            @{ Id = 'BatteryDrainEngine'; Type = 'Number'; Section = 'Vehicles'; Key = 'scum.BatteryDrainFromEngineMultiplier'; Label = 'Battery Drain From Engine'; DefaultValue = '1.000000'; Min = 0; Max = 100; Decimals = 3; Increment = '0.100'; Hint = 'Scales battery drain while vehicles run.' }
                            @{ Id = 'BatteryDrainDevices'; Type = 'Number'; Section = 'Vehicles'; Key = 'scum.BatteryDrainFromDevicesMultiplier'; Label = 'Battery Drain From Devices'; DefaultValue = '1.000000'; Min = 0; Max = 100; Decimals = 3; Increment = '0.100'; Hint = 'Scales battery drain from attached devices.' }
                            @{ Id = 'BatteryChargeAlternator'; Type = 'Number'; Section = 'Vehicles'; Key = 'scum.BatteryChargeWithAlternatorMultiplier'; Label = 'Alternator Charge Multiplier'; DefaultValue = '1.000000'; Min = 0; Max = 100; Decimals = 3; Increment = '0.100'; Hint = 'Scales alternator charging speed.' }
                            @{ Id = 'VehicleInactivity'; Type = 'Text'; Section = 'Vehicles'; Key = 'scum.MaximumTimeOfVehicleInactivity'; Label = 'Maximum Vehicle Inactivity'; DefaultValue = '240:00:00'; Hint = 'How long inactive vehicles may stay before cleanup.' }
                            @{ Id = 'VehicleForbiddenZones'; Type = 'Text'; Section = 'Vehicles'; Key = 'scum.MaximumTimeForVehiclesInForbiddenZones'; Label = 'Vehicle Time In Forbidden Zones'; DefaultValue = '02:00:00'; Hint = 'How long vehicles can remain in restricted areas.' }
                            @{ Id = 'LogVehicleDestroyed'; Type = 'Boolean'; Section = 'Vehicles'; Key = 'scum.LogVehicleDestroyed'; Label = 'Log Destroyed Vehicles'; DefaultValue = 'True'; Hint = 'Writes vehicle destruction events to logs.' }
                        ) 
                    }
                    [pscustomobject]@{ Title = 'Damage'; Description = 'Damage scaling for players, sentries, puppets, and item decay.'; Fields = @(
                            @{ Id = 'HumanToHumanDamage'; Type = 'Number'; Section = 'Damage'; Key = 'scum.HumanToHumanDamageMultiplier'; Label = 'Human To Human Damage'; DefaultValue = '1.000000'; Min = 0; Max = 100; Decimals = 3; Increment = '0.100'; Hint = 'Scales direct player-vs-player damage.' }
                            @{ Id = 'HumanMeleeDamage'; Type = 'Number'; Section = 'Damage'; Key = 'scum.HumanToHumanArmedMeleeDamageMultiplier'; Label = 'Armed Melee Damage'; DefaultValue = '1.000000'; Min = 0; Max = 100; Decimals = 3; Increment = '0.100'; Hint = 'Scales melee weapon damage between players.' }
                            @{ Id = 'SentryDamage'; Type = 'Number'; Section = 'Damage'; Key = 'scum.SentryDamageMultiplier'; Label = 'Sentry Damage'; DefaultValue = '1.000000'; Min = 0; Max = 100; Decimals = 3; Increment = '0.100'; Hint = 'Scales sentry weapon damage.' }
                            @{ Id = 'ZombieDamage'; Type = 'Number'; Section = 'Damage'; Key = 'scum.ZombieDamageMultiplier'; Label = 'Puppet Damage'; DefaultValue = '1.000000'; Min = 0; Max = 100; Decimals = 3; Increment = '0.100'; Hint = 'Scales puppet damage dealt to players.' }
                            @{ Id = 'ItemDecay'; Type = 'Number'; Section = 'Damage'; Key = 'scum.ItemDecayDamageMultiplier'; Label = 'Item Decay Damage'; DefaultValue = '1.000000'; Min = 0; Max = 100; Decimals = 3; Increment = '0.100'; Hint = 'Scales general item wear and decay.' }
                            @{ Id = 'FoodDecay'; Type = 'Number'; Section = 'Damage'; Key = 'scum.FoodDecayDamageMultiplier'; Label = 'Food Decay Damage'; DefaultValue = '1.000000'; Min = 0; Max = 100; Decimals = 3; Increment = '0.100'; Hint = 'Scales food spoilage and decay.' }
                        ) 
                    }
                    [pscustomobject]@{ Title = 'Base Building'; Description = 'Flag, element, and raid protection settings.'; Fields = @(
                            @{ Id = 'FlagOvertakeDuration'; Type = 'Text'; Section = 'Features'; Key = 'scum.FlagOvertakeDuration'; Label = 'Flag Overtake Duration'; DefaultValue = '24:00:00'; Hint = 'Time required to overtake a flag.' }
                            @{ Id = 'MaximumElementsPerFlag'; Type = 'Number'; Section = 'Features'; Key = 'scum.MaximumAmountOfElementsPerFlag'; Label = 'Max Elements Per Flag'; DefaultValue = '100'; Min = 0; Max = 100000; Decimals = 0; Hint = 'Base building element limit per flag.' }
                            @{ Id = 'ExtraElementsPerMember'; Type = 'Number'; Section = 'Features'; Key = 'scum.ExtraElementsPerFlagForAdditionalSquadMember'; Label = 'Extra Elements Per Squad Member'; DefaultValue = '25'; Min = 0; Max = 100000; Decimals = 0; Hint = 'Additional base pieces per extra squadmate.' }
                            @{ Id = 'AllowMultipleFlags'; Type = 'Boolean'; Section = 'Features'; Key = 'scum.AllowMultipleFlagsPerPlayer'; Label = 'Allow Multiple Flags Per Player'; DefaultValue = 'False'; Hint = 'Lets a single player own more than one flag.' }
                            @{ Id = 'AllowFlagOnElements'; Type = 'Boolean'; Section = 'Features'; Key = 'scum.AllowFlagPlacementOnBBElements'; Label = 'Allow Flag Placement On BB Elements'; DefaultValue = 'False'; Hint = 'Lets flags be placed on base-building elements.' }
                            @{ Id = 'RaidProtectionType'; Type = 'Number'; Section = 'Features'; Key = 'scum.RaidProtectionType'; Label = 'Raid Protection Type'; DefaultValue = '0'; Min = 0; Max = 10; Decimals = 0; Hint = 'Core raid protection mode selector.' }
                            @{ Id = 'RaidProtectionLog'; Type = 'Boolean'; Section = 'Features'; Key = 'scum.RaidProtectionEnableLog'; Label = 'Enable Raid Protection Logging'; DefaultValue = 'False'; Hint = 'Writes raid protection activity to logs.' }
                            @{ Id = 'RaidTimesMessage'; Type = 'Boolean'; Section = 'Features'; Key = 'scum.RaidProtectionGlobalShouldShowRaidTimesMessage'; Label = 'Show Raid Times Message'; DefaultValue = 'True'; Hint = 'Displays configured raid times to players.' }
                        ) 
                    }
                    [pscustomobject]@{ Title = 'Progression'; Description = 'Skills, squads, quests, and player progression pacing.'; Fields = @(
                            @{ Id = 'SquadInt1'; Type = 'Number'; Section = 'Features'; Key = 'scum.SquadMemberCountAtIntLevel1'; Label = 'Squad Size At INT 1'; DefaultValue = '2'; Min = 1; Max = 100; Decimals = 0; Hint = 'Maximum squad size unlocked at INT level 1.' }
                            @{ Id = 'SquadInt5'; Type = 'Number'; Section = 'Features'; Key = 'scum.SquadMemberCountAtIntLevel5'; Label = 'Squad Size At INT 5'; DefaultValue = '10'; Min = 1; Max = 100; Decimals = 0; Hint = 'Maximum squad size unlocked at INT level 5.' }
                            @{ Id = 'ArcherySkill'; Type = 'Number'; Section = 'Features'; Key = 'scum.ArcherySkillMultiplier'; Label = 'Archery Skill Multiplier'; DefaultValue = '1.000000'; Min = 0; Max = 100; Decimals = 3; Increment = '0.100'; Hint = 'Scales archery progression speed.' }
                            @{ Id = 'AwarenessSkill'; Type = 'Number'; Section = 'Features'; Key = 'scum.AwarenessSkillMultiplier'; Label = 'Awareness Skill Multiplier'; DefaultValue = '1.000000'; Min = 0; Max = 100; Decimals = 3; Increment = '0.100'; Hint = 'Scales awareness progression speed.' }
                            @{ Id = 'MedicalSkill'; Type = 'Number'; Section = 'Features'; Key = 'scum.MedicalSkillMultiplier'; Label = 'Medical Skill Multiplier'; DefaultValue = '1.000000'; Min = 0; Max = 100; Decimals = 3; Increment = '0.100'; Hint = 'Scales medical progression speed.' }
                            @{ Id = 'QuestsEnabled'; Type = 'Boolean'; Section = 'Features'; Key = 'scum.QuestsEnabled'; Label = 'Quests Enabled'; DefaultValue = 'True'; Hint = 'Turns trader and board quests on or off.' }
                            @{ Id = 'QuestCycle'; Type = 'Text'; Section = 'Features'; Key = 'scum.QuestsGlobalCycleDuration'; Label = 'Quest Global Cycle Duration'; DefaultValue = '23:59:59'; Hint = 'How frequently the quest pool rotates.' }
                            @{ Id = 'MaxQuestsPerCycle'; Type = 'Number'; Section = 'Features'; Key = 'scum.MaxQuestsPerCyclePerTrader'; Label = 'Max Quests Per Cycle Per Trader'; DefaultValue = '3'; Min = 0; Max = 100; Decimals = 0; Hint = 'How many quests a trader can offer per cycle.' }
                        ) 
                    }
                )
            }
            [pscustomobject]@{
                Title  = 'Users'
                Fields = @(
                    @{ Id = 'AdminUsers'; Type = 'StringList'; Label = 'Admin Users'; Path = $samplePaths.AdminUsersPath; Hint = 'One Steam64 ID per line. Standard in-file admin list.' }
                    @{ Id = 'ExclusiveUsers'; Type = 'StringList'; Label = 'Exclusive Users'; Path = $samplePaths.ExclusiveUsersPath; Hint = 'Players allowed on a restricted server.' }
                    @{ Id = 'WhitelistedUsers'; Type = 'StringList'; Label = 'Whitelisted Users'; Path = $samplePaths.WhitelistedUsersPath; Hint = 'Players explicitly approved to join.' }
                    @{ Id = 'BannedUsers'; Type = 'StringList'; Label = 'Banned Users'; Path = $samplePaths.BannedUsersPath; Hint = 'Players blocked from joining.' }
                    @{ Id = 'SilencedUsers'; Type = 'StringList'; Label = 'Silenced Users'; Path = $samplePaths.SilencedUsersPath; Hint = 'Players muted from chat.' }
                )
            }
            [pscustomobject]@{
                Title  = 'Admin'
                Fields = @(
                    @{ Id = 'ElevatedUsers'; Type = 'ElevatedUsers'; Label = 'Elevated Users (Database)'; Hint = 'Edits the elevated_users table in SCUM.db. Players usually need to have joined at least once.' }
                )
            }
            [pscustomobject]@{
                Title  = 'Advanced'
                Fields = @(
                    @{ Id = 'OpenServerSettings'; Type = 'ActionButton'; Label = 'ServerSettings.ini'; ButtonText = 'Open ServerSettings.ini'; Action = $actions.OpenServerSettings; Hint = 'Opens the main SCUM server settings file for manual editing.' }
                    @{ Id = 'OpenAdminUsers'; Type = 'ActionButton'; Label = 'AdminUsers.ini'; ButtonText = 'Open AdminUsers.ini'; Action = $actions.OpenAdminUsers; Hint = 'Opens the in-file admin list.' }
                    @{ Id = 'OpenExclusiveUsers'; Type = 'ActionButton'; Label = 'ExclusiveUsers.ini'; ButtonText = 'Open ExclusiveUsers.ini'; Action = $actions.OpenExclusiveUsers; Hint = 'Opens the exclusive users file.' }
                    @{ Id = 'OpenWhitelistedUsers'; Type = 'ActionButton'; Label = 'WhitelistedUsers.ini'; ButtonText = 'Open WhitelistedUsers.ini'; Action = $actions.OpenWhitelistedUsers; Hint = 'Opens the whitelist file.' }
                    @{ Id = 'OpenRaidTimes'; Type = 'ActionButton'; Label = 'RaidTimes.json'; ButtonText = 'Open RaidTimes.json'; Action = $actions.OpenRaidTimes; Hint = 'Opens raid time windows for manual editing.' }
                    @{ Id = 'OpenEconomy'; Type = 'ActionButton'; Label = 'EconomyOverride.json'; ButtonText = 'Open EconomyOverride.json'; Action = $actions.OpenEconomy; Hint = 'Opens trader and economy overrides.' }
                    @{ Id = 'OpenProfileFolder'; Type = 'ActionButton'; Label = 'Profile Folder'; ButtonText = 'Open Profile Folder'; Action = $actions.OpenProfileFolder; Hint = 'Opens the selected SCUM profile folder in Explorer.' }
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
                                    if ($StatusLabel) { $StatusLabel.Text = 'Discord test skipped: no webhook is configured for this server and no global webhook is available.' }
                                    return
                                }

                                $result = Test-UGSMDiscordWebhook -WebhookUrl $discordModel.EffectiveWebhookUrl -Label ("SCUM " + [string]$Instance.Name)

                                if ($result -and $result.PSObject.Properties['Success'] -and [bool]$result.Success) {
                                    $target = if ($discordModel.UsesGlobalWebhook) { 'global webhook' } else { 'server webhook' }
                                    if ($StatusLabel) { $StatusLabel.Text = 'Discord test sent successfully using the ' + $target + '.' }
                                }
                                else {
                                    $errorText = ''
                                    if ($result -and $result.PSObject.Properties['Error']) {
                                        $errorText = [string]$result.Error
                                    }
                                    if ([string]::IsNullOrWhiteSpace($errorText)) {
                                        $errorText = 'Unknown Discord webhook error.'
                                    }
                                    if ($StatusLabel) { $StatusLabel.Text = 'Discord test failed: ' + $errorText }
                                }
                            }
                            catch {
                                if ($StatusLabel) { $StatusLabel.Text = 'Discord test failed: ' + $_.Exception.Message }
                            }
                        }
                    }
                )
            }
        )
    }

    $script:UGSMGameSCUMEditorSchemaCache = $schema
    return $schema
}
