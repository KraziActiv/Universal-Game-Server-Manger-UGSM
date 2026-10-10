#Ark Survival Evolved


function Write-UGSMGameArkSELog {
    [CmdletBinding()]
    param(
        [ValidateSet('TRACE','DEBUG','INFO','WARN','ERROR','FATAL')]
        [string]$Level = 'INFO',
        [Parameter(Mandatory)][string]$Message,
        [System.Exception]$Exception,
        [switch]$VerboseOnly
    )

    $verboseEnabled = $false
    try {
        if (Get-Variable -Name 'UGSM_EnableVerboseArkSELogging' -Scope Script -ErrorAction SilentlyContinue) {
            $verboseEnabled = [bool]$script:UGSM_EnableVerboseArkSELogging
        }
        if (-not $verboseEnabled -and $env:UGSM_VERBOSE_ARKSE -eq '1') {
            $verboseEnabled = $true
        }
    }
    catch { $verboseEnabled = $false }

    if ($VerboseOnly -and -not $verboseEnabled) { return }

    if (Get-Command -Name Write-UGSMLog -ErrorAction SilentlyContinue) {
        if ($Exception) {
            Write-UGSMLog -Level $Level -Category 'ArkSE' -Message $Message -Exception $Exception
        }
        else {
            Write-UGSMLog -Level $Level -Category 'ArkSE' -Message $Message
        }
        return
    }

    $line = '[{0}] [ArkSE] {1}' -f $Level, $Message
    if ($Exception) { $line += ' Exception: ' + $Exception.Message }
    Write-Host $line
}

function Get-UGSMGameArkSEInstanceLabel {
    [CmdletBinding()]
    param([object]$Instance)

    if (-not $Instance) { return '' }
    foreach ($propName in @('Id','InstanceId','Name','ServerName')) {
        try {
            if ($Instance.PSObject.Properties.Name -contains $propName) {
                $value = [string]$Instance.$propName
                if (-not [string]::IsNullOrWhiteSpace($value)) { return $value }
            }
        }
        catch {}
    }
    return ''
}


function Get-UGSMGameArkSEMetadata {
    [CmdletBinding()]
    param()

    $serverExeRelativePath = 'ShooterGame\Binaries\Win64\ShooterGameServer.exe'

    return [pscustomobject]@{
        Id                       = 'ArkSE'
        Name                     = 'Ark Survival Evolved'
        Category                 = 'Survival'
        Description              = 'Dedicated server module for ARK: Survival Evolved.'
        IsCustom                 = $false
        SupportTier              = 'Full'
        SortOrder                = 200
        IsVisible                = $true

        SupportedTabs            = @('Home', 'Games', 'Instances', 'Analytics', 'Tasks', 'About', 'Settings')
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
        SteamAppId               = '376030'
        SteamStoreAppId          = '346110'
        ServerExecutable         = 'ShooterGameServer.exe'
        ServerExecutableRelative = $serverExeRelativePath
        UsesSharedBinaries       = $true
        InstanceType             = 'DedicatedServer'

        ConfigRootRelative       = 'ShooterGame\Saved\Config\WindowsServer'
        SaveRootRelative         = 'ShooterGame\Saved\SavedArks'
        LogRootRelative          = 'ShooterGame\Saved\Logs'

        RequiredFiles            = @(
            'ShooterGame\Binaries\Win64\ShooterGameServer.exe'
            'ShooterGame'
        )

        InstallMarkers           = @(
            'ShooterGame\Binaries\Win64\ShooterGameServer.exe'
            'ShooterGame\Saved\Config'
        )

        PortSchema               = @(
            @{ Name = 'GamePort'; Protocol = 'UDP'; PreferredStart = 7777 }
            @{ Name = 'PeerPort'; Protocol = 'UDP'; PreferredStart = 7778 }
            @{ Name = 'QueryPort'; Protocol = 'UDP'; PreferredStart = 27015 }
            @{ Name = 'RconPort'; Protocol = 'TCP'; PreferredStart = 27020 }
        )

        GameTraits               = [pscustomobject]@{
            UsesIniFiles          = $true
            UsesJsonFiles         = $false
            UsesXmlFiles          = $false
            UsesSqlite            = $false
            UsesProfileSync       = $false
            UsesPluginFramework   = $false
            UsesZipMods           = $false
            UsesFolderCopyMods    = $false
            UsesFileMergeWorkflow = $false
            UsesMissionFiles      = $false
            UsesWorkshopItems     = $true
        }

        SpecialRequirements      = [pscustomobject]@{
            Notes = @(
                'Uses shared binaries so multiple ARK servers can run with different maps and settings.'
            )
        }
    }
}

function Get-UGSMGameArkSEInstallDefinition {
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
            throw 'ArkSE install definition failed: InstallPath could not be resolved.'
        }

        $commonCandidate = Join-Path $steamRoot 'steamapps\common\ArkSE'
        $serverCandidate = Join-Path $steamRoot 'servers\ArkSE'

        if (Test-Path -LiteralPath $commonCandidate -PathType Container) {
            $InstallPath = $commonCandidate
        }
        else {
            $InstallPath = $serverCandidate
        }
    }

    $meta = Get-UGSMGameArkSEMetadata

    return [pscustomobject]@{
        GameId               = $meta.Id
        GameName             = $meta.Name
        SteamAppId           = $meta.SteamAppId
        InstallPath          = [string]$InstallPath
        ServerExecutablePath = Join-Path $InstallPath $meta.ServerExecutableRelative
        RequiredFiles        = @($meta.RequiredFiles)
        InstallMarkers       = @($meta.InstallMarkers)
        ConfigRootPath       = Join-Path $InstallPath $meta.ConfigRootRelative
        SaveRootPath         = Join-Path $InstallPath $meta.SaveRootRelative
        LogRootPath          = Join-Path $InstallPath $meta.LogRootRelative
        MainConfigPath       = Join-Path $InstallPath 'ShooterGame\Saved\Config\WindowsServer\GameUserSettings.ini'
        SecondaryConfigPath  = Join-Path $InstallPath 'ShooterGame\Saved\Config\WindowsServer\Game.ini'
    }
}


function Get-UGSMGameArkSEAppDataRoot {
    [CmdletBinding()]
    param()

    if (Get-Command -Name Get-UGSMAppDataRoot -ErrorAction SilentlyContinue) {
        return [string](Get-UGSMAppDataRoot)
    }

    return (Join-Path $env:LOCALAPPDATA 'UGSM')
}

function Get-UGSMGameArkSEProfileBaseRoot {
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
        $probe = Get-UGSMDefaultInstanceProfilePath -GameId 'ArkSE' -Name '_probe_'
        if (-not [string]::IsNullOrWhiteSpace([string]$probe)) {
            return (Split-Path -Parent (Split-Path -Parent $probe))
        }
    }

    return (Join-Path ( Get-UGSMGameArkSEAppDataRoot) 'Profiles')
}

function Get-UGSMGameArkSEArkSERoot {
    [CmdletBinding()]
    param()

    return (Join-Path (Get-UGSMGameArkSEAppDataRoot) 'Templates\ArkSE')
}


function New-UGSMGameArkSEDefaultConfigFiles {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ConfigRoot,

        [string]$SessionName = 'ArkSE Server'
    )

    New-Item -ItemType Directory -Path $ConfigRoot -Force | Out-Null

    $gameUserSettingsPath = Join-Path $ConfigRoot 'GameUserSettings.ini'
    $gameIniPath = Join-Path $ConfigRoot 'Game.ini'

    $gameUserSettingsContent = @"
[ServerSettings]
SessionName=$SessionName
ServerPassword=
ServerAdminPassword=
RCONEnabled=True
RCONPort=27020
QueryPort=27015
Port=7777
PeerPort=7778
AltSaveDirectoryName=

[/Script/ShooterGame.ShooterGameUserSettings]
MasterAudioVolume=1.000000
MusicAudioVolume=1.000000
SFXAudioVolume=1.000000
VoiceAudioVolume=1.000000
CameraShakeScale=1.000000
bFirstPersonRiding=False
bThirdPersonPlayer=False
bShowStatusNotificationMessages=True
TrueSkyQuality=0.270000
FOVMultiplier=1.000000
GroundClutterDensity=1.000000
bFilmGrain=False
bMotionBlur=True
bUseDFAO=True
bUseSSAO=True
bShowChatBox=True
bCameraViewBob=True
bInvertLookY=False
bFloatingNames=True
bChatBubbles=True
bHideServerInfo=False
bJoinNotifications=False
bCraftablesShowAllItems=False
bLocalInventoryItemsShowAllItems=False
bLocalInventoryCraftingShowAllItems=False
bRemoteInventoryItemsShowAllItems=False
bRemoteInventoryCraftingShowAllItems=False
bRemoteInventoryShowEngrams=False
LookLeftRightSensitivity=1.000000
LookUpDownSensitivity=1.000000
GraphicsQuality=1
ActiveLingeringWorldTiles=10
ClientNetQuality=3
LastServerSearchType=0
LastPVESearchType=0
ServerSort=0
VersionMetaTag=

[SessionSettings]
SessionName=$SessionName
"@

    $gameIniContent = @"
[/Script/ShooterGame.ShooterGameMode]
"@

    Set-Content -LiteralPath $gameUserSettingsPath -Value $gameUserSettingsContent -Encoding UTF8
    Set-Content -LiteralPath $gameIniPath -Value $gameIniContent -Encoding UTF8

    return [pscustomobject]@{
        ConfigRoot           = $ConfigRoot
        GameUserSettingsPath = $gameUserSettingsPath
        GameIniPath          = $gameIniPath
    }
}


function Get-UGSMGameArkSEProfileRoot {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ProfileName
    )

    return (Join-Path (Join-Path ( Get-UGSMGameArkSEProfileBaseRoot) 'ArkSE') $ProfileName)
}


function Get-UGSMGameArkSERuntimeRoot {
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
            $profileRoot = Get-UGSMGameArkSEProfileRoot -ProfileName $candidate
        }
    }

    if ([string]::IsNullOrWhiteSpace([string]$profileRoot)) {
        throw 'ArkSE runtime root could not be resolved for the selected instance.'
    }

    return $profileRoot
}

function Remove-UGSMGameArkSEPath {
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

function New-UGSMArkSEDirectoryJunction {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$LinkPath,

        [Parameter(Mandatory)]
        [string]$TargetPath
    )

    if (-not (Test-Path -LiteralPath $TargetPath -PathType Container)) {
        throw "ArkSE junction target was not found: $TargetPath"
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

        Remove-UGSMGameArkSEPath -Path $LinkPath
    }

    try {
        New-Item -ItemType Junction -Path $LinkPath -Target $TargetPath -Force -ErrorAction Stop | Out-Null
    }
    catch {
        $null = & cmd.exe /c ('mklink /J "{0}" "{1}"' -f $LinkPath, $TargetPath)
        if ($LASTEXITCODE -ne 0 -and -not (Test-Path -LiteralPath $LinkPath -PathType Container)) {
            throw "ArkSE junction creation failed for '$LinkPath' -> '$TargetPath'."
        }
    }
}

function Copy-UGSMGameArkSEFilesToRuntime {
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

    Copy-UGSMGameArkSEDirectoryContent -Source $Source -Destination $Destination -ClearDestination:$ClearDestination
}

function Get-UGSMGameArkSERuntimeDefinition {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Instance,

        [Parameter(Mandatory)]
        [object]$InstallDefinition
    )

    $runtimeRoot = Get-UGSMGameArkSERuntimeRoot -Instance $Instance
    $runtimeInstallRoot = $runtimeRoot
    $runtimeGameRoot = Join-Path $runtimeRoot 'ShooterGame'
    $runtimeSavedRoot = Join-Path $runtimeGameRoot 'Saved'

    return [pscustomobject]@{
        RuntimeRoot                = $runtimeRoot
        RuntimeInstallRoot         = $runtimeInstallRoot
        RuntimeGameRoot            = $runtimeGameRoot
        RuntimeSavedRoot           = $runtimeSavedRoot
        RuntimeConfigRootPath      = Join-Path $runtimeSavedRoot 'Config\WindowsServer'
        RuntimeSaveRootPath        = Join-Path $runtimeSavedRoot 'SavedArks'
        RuntimeLogRootPath         = Join-Path $runtimeSavedRoot 'Logs'
        RuntimeServerExePath       = Join-Path $runtimeRoot 'ShooterGame\Binaries\Win64\ShooterGameServer.exe'
        SharedInstallPath          = [string]$InstallDefinition.InstallPath
        SharedGameRoot             = Join-Path ([string]$InstallDefinition.InstallPath) 'ShooterGame'
        SharedConfigRootPath       = [string]$InstallDefinition.ConfigRootPath
        SharedSaveRootPath         = [string]$InstallDefinition.SaveRootPath
        SharedLogRootPath          = [string]$InstallDefinition.LogRootPath
        RuntimePrimaryConfigPath   = Join-Path $runtimeSavedRoot 'Config\WindowsServer\GameUserSettings.ini'
        RuntimeSecondaryConfigPath = Join-Path $runtimeSavedRoot 'Config\WindowsServer\Game.ini'
    }
}


function Resolve-UGSMArkSEDatabasePath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Instance,

        [switch]$PreferRuntime
    )

    $paths = Get-UGSMGameArkSEProfilePaths -Instance $Instance

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

function Ensure-UGSMArkSERuntimeLayout {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Instance,

        [Parameter(Mandatory)]
        [object]$InstallDefinition
    )

    $runtime = Get-UGSMGameArkSERuntimeDefinition -Instance $Instance -InstallDefinition $InstallDefinition
    $sharedInstallRoot = [string]$InstallDefinition.InstallPath
    $sharedGameRoot = Join-Path $sharedInstallRoot 'ShooterGame'

    foreach ($path in @($runtime.RuntimeRoot, $runtime.RuntimeInstallRoot, $runtime.RuntimeGameRoot, $runtime.RuntimeSavedRoot, $runtime.RuntimeConfigRootPath, $runtime.RuntimeSaveRootPath, $runtime.RuntimeLogRootPath)) {
        if (-not (Test-Path -LiteralPath $path -PathType Container)) {
            New-Item -ItemType Directory -Path $path -Force | Out-Null
        }
    }

    if (Test-Path -LiteralPath $sharedInstallRoot -PathType Container) {
        foreach ($child in @(Get-ChildItem -LiteralPath $sharedInstallRoot -Force -ErrorAction SilentlyContinue)) {
            $targetPath = Join-Path $runtime.RuntimeInstallRoot $child.Name

            if ($child.PSIsContainer -and $child.Name -ieq 'ShooterGame') {
                continue
            }

            if ($child.PSIsContainer) {
                New-UGSMArkSEDirectoryJunction -LinkPath $targetPath -TargetPath $child.FullName
            }
            else {
                Copy-Item -LiteralPath $child.FullName -Destination $targetPath -Force -ErrorAction SilentlyContinue
            }
        }
    }

    if (-not (Test-Path -LiteralPath $sharedGameRoot -PathType Container)) {
        throw "ArkSE runtime layout failed: Shared ShooterGame root was not found: $sharedGameRoot"
    }

    foreach ($child in @(Get-ChildItem -LiteralPath $sharedGameRoot -Force -ErrorAction SilentlyContinue)) {
        $targetPath = Join-Path $runtime.RuntimeGameRoot $child.Name

        if ($child.PSIsContainer -and $child.Name -ieq 'Saved') {
            continue
        }

        if ($child.PSIsContainer) {
            New-UGSMArkSEDirectoryJunction -LinkPath $targetPath -TargetPath $child.FullName
        }
        else {
            Copy-Item -LiteralPath $child.FullName -Destination $targetPath -Force -ErrorAction SilentlyContinue
        }
    }

    $sharedUprojectPath = Join-Path $sharedGameRoot 'ShooterGame.uproject'
    $runtimeUprojectPath = Join-Path $runtime.RuntimeGameRoot 'ShooterGame.uproject'
    if (Test-Path -LiteralPath $sharedUprojectPath -PathType Leaf) {
        Copy-Item -LiteralPath $sharedUprojectPath -Destination $runtimeUprojectPath -Force -ErrorAction SilentlyContinue
    }

    $paths = Get-UGSMGameArkSEProfilePaths -Instance $Instance

    $profileConfigRoot = [string]$paths.ProfileConfigRoot
    $runtimeConfigRoot = [string]$runtime.RuntimeConfigRootPath
    $profileSaveRoot = [string]$paths.ProfileSaveRoot
    $runtimeSaveRoot = [string]$runtime.RuntimeSaveRootPath

    foreach ($pathToEnsure in @($profileConfigRoot, $runtimeConfigRoot, $profileSaveRoot, $runtimeSaveRoot, [string]$runtime.RuntimeLogRootPath)) {
        if (-not [string]::IsNullOrWhiteSpace($pathToEnsure) -and -not (Test-Path -LiteralPath $pathToEnsure -PathType Container)) {
            New-Item -ItemType Directory -Path $pathToEnsure -Force | Out-Null
        }
    }

    $profileGameUserSettingsPath = Join-Path $profileConfigRoot 'GameUserSettings.ini'
    $profileGameIniPath = Join-Path $profileConfigRoot 'Game.ini'

    if (-not (Test-Path -LiteralPath $profileGameUserSettingsPath -PathType Leaf) -or -not (Test-Path -LiteralPath $profileGameIniPath -PathType Leaf)) {
        Write-UGSMGameArkSELog -Level 'WARN' -Message ("Profile config missing before runtime layout. Rebuilding default config. InstanceId={0}; ConfigRoot={1}" -f (Get-UGSMGameArkSEInstanceLabel -Instance $Instance), $profileConfigRoot)
        $null = New-UGSMGameArkSEDefaultConfigFiles -ConfigRoot $profileConfigRoot -SessionName ([string]$Instance.Name)
    }

    $sameConfigRoot = $false
    try {
        $sameConfigRoot = ([System.IO.Path]::GetFullPath($profileConfigRoot).TrimEnd('\\') -ieq [System.IO.Path]::GetFullPath($runtimeConfigRoot).TrimEnd('\\'))
    }
    catch {
        $sameConfigRoot = ($profileConfigRoot -ieq $runtimeConfigRoot)
    }

    if (-not $sameConfigRoot -and (Test-Path -LiteralPath $profileConfigRoot -PathType Container)) {
        Copy-UGSMGameArkSEFilesToRuntime -Source $profileConfigRoot -Destination $runtimeConfigRoot -ClearDestination
    }
    elseif ($sameConfigRoot) {
        Write-UGSMGameArkSELog -Level 'DEBUG' -Message ("Skipped profile-to-runtime config copy because paths are the same. InstanceId={0}; ConfigRoot={1}" -f (Get-UGSMGameArkSEInstanceLabel -Instance $Instance), $profileConfigRoot) -VerboseOnly
    }

    $sameSaveRoot = $false
    try {
        $sameSaveRoot = ([System.IO.Path]::GetFullPath($profileSaveRoot).TrimEnd('\\') -ieq [System.IO.Path]::GetFullPath($runtimeSaveRoot).TrimEnd('\\'))
    }
    catch {
        $sameSaveRoot = ($profileSaveRoot -ieq $runtimeSaveRoot)
    }

    if (-not $sameSaveRoot -and (Test-Path -LiteralPath $profileSaveRoot -PathType Container)) {
        Copy-UGSMGameArkSEFilesToRuntime -Source $profileSaveRoot -Destination $runtimeSaveRoot
    }
    elseif ($sameSaveRoot) {
        Write-UGSMGameArkSELog -Level 'DEBUG' -Message ("Skipped profile-to-runtime save copy because paths are the same. InstanceId={0}; SaveRoot={1}" -f (Get-UGSMGameArkSEInstanceLabel -Instance $Instance), $profileSaveRoot) -VerboseOnly
    }

    if (-not (Test-Path -LiteralPath $runtime.RuntimeLogRootPath -PathType Container)) {
        New-Item -ItemType Directory -Path $runtime.RuntimeLogRootPath -Force | Out-Null
    }

    Write-UGSMGameArkSELog -Level 'INFO' -Message ("ArkSE runtime layout ready. InstanceId={0}; RuntimeRoot={1}; RuntimeExe={2}" -f (Get-UGSMGameArkSEInstanceLabel -Instance $Instance), [string]$runtime.RuntimeRoot, [string]$runtime.RuntimeServerExePath)

    return $runtime
}


function Initialize-UGSMArkSERuntimeData {
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
        Copy-UGSMGameArkSEFilesToRuntime -Source $ProfileConfigRoot -Destination $RuntimeConfigRoot
    }

    if ((Get-ChildItem -LiteralPath $RuntimeSaveRoot -Force -ErrorAction SilentlyContinue | Measure-Object).Count -eq 0) {
        Copy-UGSMGameArkSEFilesToRuntime -Source $ProfileSaveRoot -Destination $RuntimeSaveRoot
    }
}

function Copy-UGSMGameArkSEDirectoryContent {
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

function Get-UGSMGameArkSERunningBootstrapProcesses {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ServerExecutablePath,

        [Parameter(Mandatory)]
        [datetime]$StartedAfter
    )

    $matches = @()
    try {
        $matches = @(Get-CimInstance Win32_Process -Filter "Name = 'ShooterGameServer.exe'" -ErrorAction Stop)
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

function Start-UGSMArkSEBootstrapProcess {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ServerExecutablePath,

        [Parameter(Mandatory)]
        [string]$WorkingDirectory,

        [int]$BootstrapSeconds = 15
    )

    if (-not (Test-Path -LiteralPath $ServerExecutablePath -PathType Leaf)) {
        throw "ArkSE server executable was not found: $ServerExecutablePath"
    }

    $bootstrapTime = [Math]::Max(10, $BootstrapSeconds)
    $launchStartedAt = Get-Date

    $proc = Start-Process `
        -FilePath $ServerExecutablePath `
        -ArgumentList @('TheIsland?listen', '-log', '-NoBattlEye', '-server', '-servergamelog') `
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

    $remaining = @(Get-Process -Name 'ShooterGameServer' -ErrorAction SilentlyContinue)

    if ($remaining.Count -gt 0) {
        & taskkill.exe /IM ShooterGameServer.exe /T /F
        Start-Sleep -Seconds 2

        $remaining = @(Get-Process -Name 'ShooterGameServer' -ErrorAction SilentlyContinue)
        foreach ($p in $remaining) {
            try {
                Stop-Process -Id $p.Id -Force -ErrorAction Stop
            }
            catch {
            }
        }
    }

    Start-Sleep -Seconds 2

    $remainingFinal = @(Get-Process -Name 'ShooterGameServer' -ErrorAction SilentlyContinue)

    return [pscustomobject]@{
        PreferredPid  = [int]$proc.Id
        StartedAt     = $launchStartedAt
        BootstrapTime = $bootstrapTime
        StopResults   = $stopResults
        Exited        = ($remainingFinal.Count -eq 0)
        RemainingPids = @($remainingFinal.Id)
    }
}


function Ensure-UGSMGameArkSEArkSE {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$InstallPath,

        [switch]$ForceRefresh,

        [int]$BootstrapSeconds = 15
    )

    $arkEnsureStopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    Write-UGSMGameArkSELog -Level 'INFO' -Message ("Template ensure requested. InstallPath={0}; ForceRefresh={1}; BootstrapSeconds={2}" -f $InstallPath, [bool]$ForceRefresh, $BootstrapSeconds)

    $definition = Get-UGSMGameArkSEInstallDefinition -InstallPath $InstallPath
    $validation = Test-UGSMGameArkSEInstall -InstallPath $InstallPath
    if (-not $validation.IsValid) {
        throw "ArkSE install is not valid at '$InstallPath'."
    }

    $templateRoot = Get-UGSMGameArkSEArkSERoot
    $templateConfigRoot = Join-Path $templateRoot 'Config\WindowsServer'
    $templateSaveRoot = Join-Path $templateRoot 'SavedArks'

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
        $bootstrapWorkingDirectory = Split-Path -Path $definition.ServerExecutablePath -Parent
        $bootstrapResult = Start-UGSMArkSEBootstrapProcess -ServerExecutablePath $definition.ServerExecutablePath -WorkingDirectory $bootstrapWorkingDirectory -BootstrapSeconds $BootstrapSeconds
    }

    if (Test-Path -LiteralPath $sourceConfigRoot -PathType Container) {
        $generatedConfigFiles = @(Get-ChildItem -LiteralPath $sourceConfigRoot -File -Force -ErrorAction SilentlyContinue)
        if ($generatedConfigFiles.Count -gt 0) {
            Copy-UGSMGameArkSEDirectoryContent -Source $sourceConfigRoot -Destination $templateConfigRoot -ClearDestination -IncludeExtensions @('.ini', '.json', '.xml', '.cfg')
        }
        else {
            New-Item -ItemType Directory -Path $templateConfigRoot -Force | Out-Null
            $generatedConfigFiles = @()
        }
    }
    else {
        New-Item -ItemType Directory -Path $templateConfigRoot -Force | Out-Null
        $generatedConfigFiles = @()
    }

    if ($generatedConfigFiles.Count -eq 0) {
        $null = New-UGSMGameArkSEDefaultConfigFiles -ConfigRoot $templateConfigRoot -SessionName 'ArkSE Template'
        $generatedConfigFiles = @(Get-ChildItem -LiteralPath $templateConfigRoot -File -Force -ErrorAction SilentlyContinue)
    }

    New-Item -ItemType Directory -Path $templateSaveRoot -Force | Out-Null

    $ensureResult = [pscustomobject]@{
        GameId               = 'ArkSE'
        InstallPath          = $InstallPath
        ArkSERoot            = $templateRoot
        ArkSEConfigRoot      = $templateConfigRoot
        ArkSESaveRoot        = $templateSaveRoot
        SourceConfigRoot     = $sourceConfigRoot
        SourceSaveRoot       = $sourceSaveRoot
        BootstrapPerformed   = $needsBootstrap
        BootstrapWorkingDir  = if ($needsBootstrap) { $bootstrapWorkingDirectory } else { $null }
        BootstrapResult      = $bootstrapResult
        GeneratedConfigFiles = @($generatedConfigFiles.Name)
    }

    $arkEnsureStopwatch.Stop()
    Write-UGSMGameArkSELog -Level 'INFO' -Message ("Template ensure completed. InstallPath={0}; BootstrapPerformed={1}; ConfigFiles={2}; DurationMs={3}" -f $InstallPath, [bool]$needsBootstrap, @($generatedConfigFiles).Count, $arkEnsureStopwatch.ElapsedMilliseconds)

    return $ensureResult
}


function Initialize-UGSMGameArkSEProfile {
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
        throw 'ProfileName could not be resolved for ArkSE profile initialization.'
    }

    if ([string]::IsNullOrWhiteSpace($effectiveInstallPath)) {
        throw 'InstallPath is required to initialize a ArkSE profile.'
    }

    $arkInitStopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    Write-UGSMGameArkSELog -Level 'INFO' -Message ("Profile initialization requested. InstanceId={0}; ProfileName={1}; InstallPath={2}; Force={3}" -f $instanceId, $effectiveProfileName, $effectiveInstallPath, [bool]$Force)

    $templateRoot = Get-UGSMGameArkSEArkSERoot
    $templateConfigRoot = Join-Path $templateRoot 'Config\WindowsServer'
    $templateSaveRoot = Join-Path $templateRoot 'SavedArks'

    if (-not (Test-Path -LiteralPath $templateConfigRoot -PathType Container)) {
        try {
            $null = Ensure-UGSMGameArkSEArkSE -InstallPath $effectiveInstallPath -BootstrapSeconds $BootstrapSeconds
        }
        catch {
        }
    }

    $definition = Get-UGSMGameArkSEInstallDefinition -InstallPath $effectiveInstallPath
    $profileRoot = Get-UGSMGameArkSEProfileRoot -ProfileName $effectiveProfileName
    if ((Test-Path -LiteralPath $profileRoot -PathType Container) -and $Force) {
        Get-ChildItem -LiteralPath $profileRoot -Force -ErrorAction SilentlyContinue |
        Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
    }

    $profileGameRoot = Join-Path $profileRoot 'ShooterGame'
    $profileSavedRoot = Join-Path $profileGameRoot 'Saved'
    $profileConfigRoot = Join-Path $profileSavedRoot 'Config\WindowsServer'
    $profileSaveRoot = Join-Path $profileSavedRoot 'SavedArks'
    $profileLogsRoot = Join-Path $profileSavedRoot 'Logs'

    $runtimeRoot = $profileRoot
    $runtimeInstallRoot = $profileRoot
    $runtimeGameRoot = $profileGameRoot
    $runtimeSavedRoot = $profileSavedRoot
    $runtimeConfigRoot = $profileConfigRoot
    $runtimeSaveRoot = $profileSaveRoot
    $runtimeLogsRoot = $profileLogsRoot

    foreach ($path in @($profileRoot, $profileGameRoot, $profileSavedRoot, $profileConfigRoot, $profileSaveRoot, $profileLogsRoot)) {
        if (-not (Test-Path -LiteralPath $path -PathType Container)) {
            New-Item -ItemType Directory -Path $path -Force | Out-Null
        }
    }

    $seedConfigRoot = $null
    if (Test-Path -LiteralPath $templateConfigRoot -PathType Container) {
        $seedConfigRoot = $templateConfigRoot
    }
    elseif (Test-Path -LiteralPath $definition.ConfigRootPath -PathType Container) {
        $seedConfigRoot = [string]$definition.ConfigRootPath
    }

    $seedSaveRoot = $null
    if (Test-Path -LiteralPath $templateSaveRoot -PathType Container) {
        $seedSaveRoot = $templateSaveRoot
    }
    elseif (Test-Path -LiteralPath $definition.SaveRootPath -PathType Container) {
        $seedSaveRoot = [string]$definition.SaveRootPath
    }

    $seedConfigHasFiles = $false
    if (-not [string]::IsNullOrWhiteSpace([string]$seedConfigRoot) -and (Test-Path -LiteralPath $seedConfigRoot -PathType Container)) {
        $seedConfigHasFiles = @(
            Get-ChildItem -LiteralPath $seedConfigRoot -File -Force -ErrorAction SilentlyContinue
        ).Count -gt 0
    }

    if ($seedConfigHasFiles) {
        Copy-UGSMGameArkSEDirectoryContent -Source $seedConfigRoot -Destination $profileConfigRoot -ClearDestination
    }
    else {
        $null = New-UGSMGameArkSEDefaultConfigFiles -ConfigRoot $profileConfigRoot -SessionName $effectiveProfileName
    }

    if (-not [string]::IsNullOrWhiteSpace([string]$seedSaveRoot) -and (Test-Path -LiteralPath $seedSaveRoot -PathType Container)) {
        Copy-UGSMGameArkSEFilesToRuntime -Source $seedSaveRoot -Destination $profileSaveRoot
    }

    $gameUserSettingsPath = Join-Path $profileConfigRoot 'GameUserSettings.ini'
    if (Test-Path -LiteralPath $gameUserSettingsPath -PathType Leaf) {
        try {
            $content = Get-Content -LiteralPath $gameUserSettingsPath -Raw -ErrorAction SilentlyContinue
            if ($content -match '(?im)^\s*SessionName\s*=') {
                $content = [Regex]::Replace($content, '(?im)^\s*SessionName\s*=.*$', ('SessionName={0}' -f $effectiveProfileName))
            }
            elseif (-not [string]::IsNullOrWhiteSpace($content)) {
                $content = $content.TrimEnd() + [Environment]::NewLine + 'SessionName=' + $effectiveProfileName + [Environment]::NewLine
            }
            else {
                $content = 'SessionName=' + $effectiveProfileName + [Environment]::NewLine
            }

            Set-Content -LiteralPath $gameUserSettingsPath -Value $content -Encoding UTF8
        }
        catch {
        }
    }

    try { Sync-UGSMGameArkSEAssignedPortsToConfig -Instance $Instance -Paths (Get-UGSMGameArkSEProfilePaths -Instance $Instance) } catch { }

    $initResult = [pscustomobject]@{
        GameId            = 'ArkSE'
        InstanceId        = $instanceId
        ProfileName       = $effectiveProfileName
        InstallPath       = $effectiveInstallPath
        ProfileRoot       = $profileRoot
        ConfigRoot        = $profileConfigRoot
        SaveRoot          = $profileSaveRoot
        LogsRoot          = $profileLogsRoot
        RuntimeRoot       = $runtimeRoot
        RuntimeConfigRoot = $runtimeConfigRoot
        RuntimeSaveRoot   = $runtimeSaveRoot
        RuntimeLogsRoot   = $runtimeLogsRoot
        ArkSERoot         = $templateRoot
        ArkSEConfigRoot   = $templateConfigRoot
        Initialized       = $true
        CopiedFiles       = @(
            Get-ChildItem -LiteralPath $profileConfigRoot -File -Recurse -Force -ErrorAction SilentlyContinue |
            ForEach-Object { $_.FullName.Substring($profileRoot.Length).TrimStart('') }
        )
    }

    $arkInitStopwatch.Stop()
    Write-UGSMGameArkSELog -Level 'INFO' -Message ("Profile initialization completed. InstanceId={0}; ProfileName={1}; ProfileRoot={2}; ConfigFiles={3}; DurationMs={4}" -f $instanceId, $effectiveProfileName, $profileRoot, @($initResult.CopiedFiles).Count, $arkInitStopwatch.ElapsedMilliseconds)

    return $initResult
}





function Get-UGSMGameArkSEAssignedPorts {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$Instance
    )

    $instanceId = Get-UGSMGameArkSEInstanceLabel -Instance $Instance
    $ports = [ordered]@{}

    function Add-ArkSEPortValue {
        param([string]$Name, [AllowNull()]$Value)
        if ([string]::IsNullOrWhiteSpace($Name) -or $null -eq $Value) { return }
        $text = [string]$Value
        if ([string]::IsNullOrWhiteSpace($text)) { return }
        $number = 0
        if ([int]::TryParse($text, [ref]$number) -and $number -gt 0) {
            $ports[$Name] = $number
        }
    }

    try {
        if ($Instance -and $Instance.PSObject.Properties.Name -contains 'Ports' -and $Instance.Ports) {
            $instancePorts = $Instance.Ports
            foreach ($name in @('GamePort','PeerPort','QueryPort','RconPort','RCONPort')) {
                $value = $null
                if ($instancePorts -is [System.Collections.IDictionary] -and $instancePorts.Contains($name)) {
                    $value = $instancePorts[$name]
                }
                elseif ($instancePorts.PSObject.Properties.Name -contains $name) {
                    $value = $instancePorts.$name
                }
                if ($name -eq 'RCONPort') { Add-ArkSEPortValue -Name 'RconPort' -Value $value }
                else { Add-ArkSEPortValue -Name $name -Value $value }
            }
        }
    }
    catch { }

    if (-not [string]::IsNullOrWhiteSpace($instanceId) -and (Get-Command -Name Get-UGSMPortRegistry -ErrorAction SilentlyContinue)) {
        try {
            $registry = Get-UGSMPortRegistry -CreateIfMissing
            foreach ($assignment in @($registry.Assignments)) {
                if (-not $assignment) { continue }
                $aInstanceId = if ($assignment.PSObject.Properties.Name -contains 'InstanceId') { [string]$assignment.InstanceId } else { '' }
                $aGameId = if ($assignment.PSObject.Properties.Name -contains 'GameId') { [string]$assignment.GameId } else { '' }
                if ($aInstanceId -ne $instanceId -or $aGameId -ne 'ArkSE') { continue }

                $assignmentPorts = $assignment.Ports
                foreach ($name in @('GamePort','PeerPort','QueryPort','RconPort','RCONPort')) {
                    $value = $null
                    if ($assignmentPorts -is [System.Collections.IDictionary] -and $assignmentPorts.Contains($name)) {
                        $value = $assignmentPorts[$name]
                    }
                    elseif ($assignmentPorts -and $assignmentPorts.PSObject.Properties.Name -contains $name) {
                        $value = $assignmentPorts.$name
                    }
                    if ($name -eq 'RCONPort') { Add-ArkSEPortValue -Name 'RconPort' -Value $value }
                    else { Add-ArkSEPortValue -Name $name -Value $value }
                }
                break
            }
        }
        catch {
            Write-UGSMGameArkSELog -Level 'WARN' -Message ("Failed to read ArkSE assigned ports from port registry. InstanceId={0}" -f $instanceId) -Exception $_.Exception
        }
    }

    return [pscustomobject]$ports
}

function Get-UGSMGameArkSEAssignedPortValue {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$Instance,
        [Parameter(Mandatory)][string]$FieldId
    )

    $assigned = Get-UGSMGameArkSEAssignedPorts -Instance $Instance
    if (-not $assigned) { return $null }

    $portName = switch -Regex ($FieldId) {
        '^(Port|GamePort)$' { 'GamePort'; break }
        '^PeerPort$' { 'PeerPort'; break }
        '^QueryPort$' { 'QueryPort'; break }
        '^RCONPort$' { 'RconPort'; break }
        '^RconPort$' { 'RconPort'; break }
        default { '' }
    }

    if ([string]::IsNullOrWhiteSpace($portName)) { return $null }
    if ($assigned.PSObject.Properties.Name -contains $portName) { return $assigned.$portName }
    return $null
}

function Sync-UGSMGameArkSEAssignedPortsToConfig {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$Instance,
        [AllowNull()]$Paths
    )

    $instanceId = Get-UGSMGameArkSEInstanceLabel -Instance $Instance
    if (-not $Paths) { $Paths = Get-UGSMGameArkSEProfilePaths -Instance $Instance }
    $iniPath = [string]$Paths.GameUserSettingsPath
    if ([string]::IsNullOrWhiteSpace($iniPath)) { return }

    $assigned = Get-UGSMGameArkSEAssignedPorts -Instance $Instance
    if (-not $assigned) { return }

    $written = 0
    if ($assigned.PSObject.Properties.Name -contains 'GamePort') {
        Set-UGSMArkSEIniValue -Path $iniPath -Section 'ServerSettings' -Key 'Port' -Value ([string]$assigned.GamePort)
        Set-UGSMArkSEIniValue -Path $iniPath -Section 'SessionSettings' -Key 'Port' -Value ([string]$assigned.GamePort)
        $written++
    }
    if ($assigned.PSObject.Properties.Name -contains 'PeerPort') {
        Set-UGSMArkSEIniValue -Path $iniPath -Section 'ServerSettings' -Key 'PeerPort' -Value ([string]$assigned.PeerPort)
        Set-UGSMArkSEIniValue -Path $iniPath -Section 'SessionSettings' -Key 'PeerPort' -Value ([string]$assigned.PeerPort)
        $written++
    }
    if ($assigned.PSObject.Properties.Name -contains 'QueryPort') {
        Set-UGSMArkSEIniValue -Path $iniPath -Section 'ServerSettings' -Key 'QueryPort' -Value ([string]$assigned.QueryPort)
        Set-UGSMArkSEIniValue -Path $iniPath -Section 'SessionSettings' -Key 'QueryPort' -Value ([string]$assigned.QueryPort)
        $written++
    }
    if ($assigned.PSObject.Properties.Name -contains 'RconPort') {
        Set-UGSMArkSEIniValue -Path $iniPath -Section 'ServerSettings' -Key 'RCONPort' -Value ([string]$assigned.RconPort)
        $written++
    }

    if ($written -gt 0) {
        Write-UGSMGameArkSELog -Level 'DEBUG' -Message ("Synced assigned ArkSE ports into GameUserSettings.ini. InstanceId={0}; Written={1}; GamePort={2}; PeerPort={3}; QueryPort={4}; RconPort={5}" -f $instanceId, $written, [string]$assigned.GamePort, [string]$assigned.PeerPort, [string]$assigned.QueryPort, [string]$assigned.RconPort) -VerboseOnly
    }
}

function Convert-UGSMGameArkSEModIdList {
    [CmdletBinding()]
    param([AllowNull()][object]$InputObject)

    $ids = New-Object System.Collections.Generic.List[string]
    foreach ($raw in @($InputObject)) {
        if ($null -eq $raw) { continue }
        $text = [string]$raw
        if ([string]::IsNullOrWhiteSpace($text)) { continue }
        foreach ($part in ($text -split '[,;\s]+')) {
            $id = [string]$part
            if ([string]::IsNullOrWhiteSpace($id)) { continue }
            $match = [regex]::Match($id, '(?<!\d)(\d{5,})(?!\d)')
            if ($match.Success) { $id = $match.Groups[1].Value }
            if ($id -match '^\d+$' -and -not $ids.Contains($id)) { [void]$ids.Add($id) }
        }
    }
    return [string[]]$ids.ToArray()
}

function Get-UGSMGameArkSEProfileModManifestPath {
    [CmdletBinding()]
    param([Parameter(Mandatory)][object]$Instance)
    $paths = Get-UGSMGameArkSEProfilePaths -Instance $Instance
    return (Join-Path $paths.ProfileRoot 'UGSM_ManagedMods.json')
}

function Save-UGSMGameArkSEManagedMods {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$Instance,
        [AllowNull()][AllowEmptyCollection()][string[]]$ModIds = @()
    )

    $manifestPath = Get-UGSMGameArkSEProfileModManifestPath -Instance $Instance
    $parent = Split-Path -Parent $manifestPath
    if (-not (Test-Path -LiteralPath $parent -PathType Container)) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
    $items = @()
    foreach ($id in @(Convert-UGSMGameArkSEModIdList -InputObject $ModIds)) {
        $items += [pscustomobject]@{
            WorkshopId  = [string]$id
            Enabled     = $true
            LastSyncedUtc = [DateTime]::UtcNow.ToString('o')
        }
    }
    $items | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $manifestPath -Encoding UTF8
    Write-UGSMGameArkSELog -Level 'INFO' -Message ("Managed mod manifest saved. InstanceId={0}; ModCount={1}" -f (Get-UGSMGameArkSEInstanceLabel -Instance $Instance), @($items).Count)
    return $items
}


function Get-UGSMGameArkSEManagedModIds {
    [CmdletBinding()]
    param([Parameter(Mandatory)][object]$Instance)

    $ids = New-Object System.Collections.Generic.List[string]
    try {
        $manifestPath = Get-UGSMGameArkSEProfileModManifestPath -Instance $Instance
        if (Test-Path -LiteralPath $manifestPath -PathType Leaf) {
            $raw = Get-Content -LiteralPath $manifestPath -Raw -ErrorAction Stop
            if (-not [string]::IsNullOrWhiteSpace($raw)) {
                $items = @($raw | ConvertFrom-Json -ErrorAction Stop)
                foreach ($item in $items) {
                    $idText = ''
                    if ($item -and $item.PSObject.Properties['WorkshopId']) { $idText = [string]$item.WorkshopId }
                    elseif ($item -and $item.PSObject.Properties['Id']) { $idText = [string]$item.Id }
                    foreach ($id in @(Convert-UGSMGameArkSEModIdList -InputObject $idText)) {
                        if (-not $ids.Contains($id)) { [void]$ids.Add($id) }
                    }
                }
            }
        }
    } catch {
        Write-UGSMGameArkSELog -Level 'WARN' -Message ("Failed to read ARKSE managed mod manifest. InstanceId={0}" -f (Get-UGSMGameArkSEInstanceLabel -Instance $Instance)) -Exception $_.Exception
    }

    return [string[]]$ids.ToArray()
}

function Set-UGSMGameArkSEActiveModIds {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$Instance,
        [AllowNull()][AllowEmptyCollection()][string[]]$ModIds = @()
    )

    $ids = @(Convert-UGSMGameArkSEModIdList -InputObject $ModIds)
    $value = ($ids -join ',')
    $paths = Get-UGSMGameArkSEProfilePaths -Instance $Instance
    $targets = New-Object System.Collections.Generic.List[string]
    foreach ($candidate in @($paths.GameUserSettingsPath, $paths.RuntimeGameUserSettingsPath)) {
        $text = [string]$candidate
        if ([string]::IsNullOrWhiteSpace($text)) { continue }
        if (-not $targets.Contains($text)) { [void]$targets.Add($text) }
    }

    foreach ($iniPath in $targets) {
        try {
            $parent = Split-Path -Parent $iniPath
            if (-not (Test-Path -LiteralPath $parent -PathType Container)) {
                New-Item -ItemType Directory -Path $parent -Force | Out-Null
            }
            Set-UGSMArkSEIniValue -Path $iniPath -Section 'ServerSettings' -Key 'ActiveMods' -Value $value
            Set-UGSMArkSEIniValue -Path $iniPath -Section 'ServerSettings' -Key 'GameModIds' -Value $value
        } catch {
            Write-UGSMGameArkSELog -Level 'WARN' -Message ("Failed to persist ARKSE active mod IDs. InstanceId={0}; Path={1}" -f (Get-UGSMGameArkSEInstanceLabel -Instance $Instance), $iniPath) -Exception $_.Exception
        }
    }

    Write-UGSMGameArkSELog -Level 'DEBUG' -Message ("ARKSE active mod IDs persisted. InstanceId={0}; ModCount={1}; Mods={2}" -f (Get-UGSMGameArkSEInstanceLabel -Instance $Instance), $ids.Count, ($ids -join ','))
    return [string[]]$ids
}

function Get-UGSMGameArkSEActiveModIds {
    [CmdletBinding()]
    param([Parameter(Mandatory)][object]$Instance)

    $paths = Get-UGSMGameArkSEProfilePaths -Instance $Instance
    $candidateValues = New-Object System.Collections.Generic.List[string]

    foreach ($propName in @('ActiveMods','GameModIds','Mods','WorkshopMods')) {
        try {
            if ($Instance.PSObject.Properties[$propName] -and -not [string]::IsNullOrWhiteSpace([string]$Instance.$propName)) {
                [void]$candidateValues.Add([string]$Instance.$propName)
            }
        } catch {}
    }

    foreach ($iniPath in @($paths.GameUserSettingsPath, $paths.RuntimeGameUserSettingsPath)) {
        if ([string]::IsNullOrWhiteSpace([string]$iniPath) -or -not (Test-Path -LiteralPath $iniPath -PathType Leaf)) { continue }
        foreach ($section in @('ServerSettings','SessionSettings')) {
            foreach ($key in @('ActiveMods','GameModIds')) {
                try {
                    $value = Get-UGSMGameArkSEIniValue -Path $iniPath -Section $section -Key $key -DefaultValue ''
                    if (-not [string]::IsNullOrWhiteSpace([string]$value)) { [void]$candidateValues.Add([string]$value) }
                } catch {}
            }
        }
    }

    $ids = @(Convert-UGSMGameArkSEModIdList -InputObject ([string[]]$candidateValues.ToArray()))
    if ($ids.Count -eq 0) {
        $ids = @(Get-UGSMGameArkSEManagedModIds -Instance $Instance)
    }
    return [string[]]$ids
}

function Sync-UGSMGameArkSEWorkshopMods {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$Instance,
        [AllowNull()][AllowEmptyCollection()][string[]]$ModIds = @(),
        [switch]$SkipDownload
    )

    $ids = @()
    if ($PSBoundParameters.ContainsKey('ModIds') -and @($ModIds).Count -gt 0) {
        $ids = @(Convert-UGSMGameArkSEModIdList -InputObject $ModIds)
    }
    else {
        $ids = @(Get-UGSMGameArkSEActiveModIds -Instance $Instance)
    }
    $instanceId = Get-UGSMGameArkSEInstanceLabel -Instance $Instance
    if ($ids.Count -eq 0) {
        [void](Save-UGSMGameArkSEManagedMods -Instance $Instance -ModIds @())
        Write-UGSMGameArkSELog -Level 'DEBUG' -Message ("No active ARKSE mods configured. InstanceId={0}" -f $instanceId)
        return [pscustomobject]@{ Success=$true; ModIds=@(); Downloaded=0; Skipped=$true }
    }

    Write-UGSMGameArkSELog -Level 'INFO' -Message ("ARKSE mod sync requested. InstanceId={0}; ModCount={1}; SkipDownload={2}; Mods={3}" -f $instanceId, $ids.Count, [bool]$SkipDownload, ($ids -join ','))
    $downloaded = 0
    if (-not $SkipDownload) {
        foreach ($id in $ids) {
            try {
                if (Get-Command -Name Invoke-UGSMSteamCMD -ErrorAction SilentlyContinue) {
                    Write-UGSMGameArkSELog -Level 'INFO' -Message ("Downloading ARKSE workshop mod with anonymous SteamCMD login. InstanceId={0}; WorkshopId={1}" -f $instanceId, $id)
                    $args = @('+login','anonymous','+workshop_download_item','346110',[string]$id,'validate','+quit')
                    $null = Invoke-UGSMSteamCMD -ArgumentList $args -TimeoutSeconds 7200
                    $downloaded++
                }
                elseif (Get-Command -Name Install-UGSMSteamCMDWorkshopItem -ErrorAction SilentlyContinue) {
                    # Fallback for older service builds. This may use configured credentials.
                    $null = Install-UGSMSteamCMDWorkshopItem -AppId '346110' -WorkshopId ([string]$id) -TimeoutSeconds 7200
                    $downloaded++
                }
                else {
                    Write-UGSMGameArkSELog -Level 'WARN' -Message ("SteamCMD workshop helper is not loaded; cannot download ARKSE mod. InstanceId={0}; WorkshopId={1}" -f $instanceId, $id)
                }
            }
            catch {
                Write-UGSMGameArkSELog -Level 'ERROR' -Message ("ARKSE workshop mod download failed. InstanceId={0}; WorkshopId={1}" -f $instanceId, $id) -Exception $_.Exception
                throw
            }
        }
    }

    [void](Save-UGSMGameArkSEManagedMods -Instance $Instance -ModIds $ids)
    [void](Set-UGSMGameArkSEActiveModIds -Instance $Instance -ModIds $ids)
    Write-UGSMGameArkSELog -Level 'INFO' -Message ("ARKSE mod sync completed. InstanceId={0}; ModCount={1}; Downloaded={2}" -f $instanceId, $ids.Count, $downloaded)
    return [pscustomobject]@{ Success=$true; ModIds=$ids; Downloaded=$downloaded; Skipped=$false }
}


function Test-UGSMGameArkSETruthy {
    [CmdletBinding()]
    param([object]$Value)

    $text = [string]$Value
    return ($text -match '^(?i:true|1|yes|enabled|checked)$')
}

function Get-UGSMGameArkSEProfileClusterSettings {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$GameUserSettingsPath
    )

    $data = Read-UGSMGameArkSEIniFile -Path $GameUserSettingsPath
    $clusterId = [string](Get-UGSMGameArkSEIniValue -IniData $data -Section 'ServerSettings' -Key 'UGSMClusterId' -DefaultValue '')
    $clusterDir = [string](Get-UGSMGameArkSEIniValue -IniData $data -Section 'ServerSettings' -Key 'UGSMClusterDirectory' -DefaultValue '')
    $clusterEnabled = Test-UGSMGameArkSETruthy (Get-UGSMGameArkSEIniValue -IniData $data -Section 'ServerSettings' -Key 'UGSMClusterEnabled' -DefaultValue 'False')
    $noTransfer = Test-UGSMGameArkSETruthy (Get-UGSMGameArkSEIniValue -IniData $data -Section 'ServerSettings' -Key 'UGSMNoTransferFromFiltering' -DefaultValue 'False')
    $useSharedMods = Test-UGSMGameArkSETruthy (Get-UGSMGameArkSEIniValue -IniData $data -Section 'ServerSettings' -Key 'UGSMUseSharedClusterMods' -DefaultValue 'False')
    $activeMods = @(Convert-UGSMGameArkSEModIdList -InputObject @(
        [string](Get-UGSMGameArkSEIniValue -IniData $data -Section 'ServerSettings' -Key 'ActiveMods' -DefaultValue ''),
        [string](Get-UGSMGameArkSEIniValue -IniData $data -Section 'ServerSettings' -Key 'GameModIds' -DefaultValue '')
    ))

    return [pscustomobject]@{
        ClusterEnabled = [bool]$clusterEnabled
        ClusterId = [string]$clusterId
        ClusterDirectory = [string]$clusterDir
        NoTransferFromFiltering = [bool]$noTransfer
        UseSharedClusterMods = [bool]$useSharedMods
        ActiveMods = [string[]]$activeMods
    }
}

function Get-UGSMGameArkSEClusterProfiles {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$SourceInstance,
        [Parameter(Mandatory)][string]$ClusterId
    )

    $results = New-Object System.Collections.Generic.List[object]
    $arkProfilesRoot = Join-Path (Get-UGSMGameArkSEProfileBaseRoot) 'ArkSE'
    if ([string]::IsNullOrWhiteSpace($ClusterId) -or -not (Test-Path -LiteralPath $arkProfilesRoot -PathType Container)) {
        return [object[]]$results.ToArray()
    }

    $sourceProfileRoot = (Get-UGSMGameArkSEProfilePaths -Instance $SourceInstance).ProfileRoot

    foreach ($profileDir in @(Get-ChildItem -LiteralPath $arkProfilesRoot -Directory -Force -ErrorAction SilentlyContinue)) {
        $profileRoot = [string]$profileDir.FullName
        $configRoot = Join-Path $profileRoot 'ShooterGame\Saved\Config\WindowsServer'
        $gusPath = Join-Path $configRoot 'GameUserSettings.ini'
        $gameIniPath = Join-Path $configRoot 'Game.ini'

        if (-not (Test-Path -LiteralPath $gusPath -PathType Leaf)) { continue }

        $settings = Get-UGSMGameArkSEProfileClusterSettings -GameUserSettingsPath $gusPath
        if ([string]$settings.ClusterId -ne [string]$ClusterId) { continue }

        $isSource = $false
        try {
            $isSource = ([System.IO.Path]::GetFullPath($profileRoot).TrimEnd('\') -ieq [System.IO.Path]::GetFullPath($sourceProfileRoot).TrimEnd('\'))
        } catch {}

        [void]$results.Add([pscustomobject]@{
            Name = [string]$profileDir.Name
            ProfileRoot = $profileRoot
            GameUserSettingsPath = $gusPath
            GameIniPath = $gameIniPath
            Settings = $settings
            IsSource = [bool]$isSource
        })
    }

    return [object[]]$results.ToArray()
}


function Test-UGSMGameArkSEClusterSyncExcludedIniKey {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$FileName,
        [Parameter(Mandatory)][string]$Section,
        [Parameter(Mandatory)][string]$Key
    )

    $keyLower = ([string]$Key).Trim().ToLowerInvariant()
    $sectionLower = ([string]$Section).Trim().ToLowerInvariant()

    # Cluster sync intentionally keeps maps/ports/server identity independent per server.
    # Save identity is also protected so one map/profile cannot overwrite another map/profile save folder.
    $alwaysSkip = @(
        'servermap',
        'map',
        'mapname',
        'mapmodid',
        'mapmodids',
        'custommapname',
        'officialmapname',
        'lastmapname',
        'arkmap',
        'sessionname',
        'servername',
        'serverdisplayname',
        'servertitle',
        'serverbrowsername',
        'hostname',
        'name',
        'port',
        'gameport',
        'peerport',
        'queryport',
        'rconport',
        'rconserverport',
        'spectatorport',
        'rawsocketport',
        'altsavedirectoryname',
        'savedirectoryname',
        'savefolder',
        'savepath'
    )

    if ($alwaysSkip -contains $keyLower) { return $true }

    # Do not sync bind-specific network identity values between servers.
    if ($keyLower -eq 'multihome') { return $true }

    return $false
}


function Get-UGSMGameArkSEClusterProtectedIniValues {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$FileName,
        [string]$ProfileRoot = ''
    )

    $protected = @{}
    if (Test-Path -LiteralPath $Path -PathType Leaf) {
        try {
            $data = Read-UGSMGameArkSEIniFile -Path $Path
            foreach ($sectionName in @($data.Keys)) {
                $sectionData = $data[$sectionName]
                if ($null -eq $sectionData) { continue }
                foreach ($keyName in @($sectionData.Keys)) {
                    if (Test-UGSMGameArkSEClusterSyncExcludedIniKey -FileName $FileName -Section ([string]$sectionName) -Key ([string]$keyName)) {
                        $compoundKey = ('{0}|{1}' -f [string]$sectionName, [string]$keyName)
                        $protected[$compoundKey] = [pscustomobject]@{
                            Section = [string]$sectionName
                            Key     = [string]$keyName
                            Value   = [string]$sectionData[$keyName]
                        }
                    }
                }
            }
        }
        catch {
            Write-UGSMGameArkSELog -Level 'WARN' -Message ("Failed to snapshot protected ArkSE cluster values. File={0}; Path={1}" -f $FileName, $Path) -Exception $_.Exception
        }
    }

    # If the map was not present in GameUserSettings.ini yet, try to recover it from the profile JSON.
    # This prevents cluster sync from allowing an editor default map to replace a target server's own map.
    if ($FileName -ieq 'GameUserSettings.ini' -and -not $protected.ContainsKey('ServerSettings|ServerMap')) {
        $mapValue = ''
        if (-not [string]::IsNullOrWhiteSpace($ProfileRoot) -and (Test-Path -LiteralPath $ProfileRoot -PathType Container)) {
            foreach ($jsonFile in @(Get-ChildItem -LiteralPath $ProfileRoot -Filter '*.json' -File -Force -ErrorAction SilentlyContinue)) {
                try {
                    $json = Get-Content -LiteralPath $jsonFile.FullName -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
                    foreach ($candidate in @('ServerMap','Map','MapName','ArkMap','World')) {
                        if ($json.PSObject.Properties.Name -contains $candidate -and -not [string]::IsNullOrWhiteSpace([string]$json.$candidate)) {
                            $mapValue = [string]$json.$candidate
                            break
                        }
                    }
                    if ([string]::IsNullOrWhiteSpace($mapValue) -and $json.PSObject.Properties.Name -contains 'Settings' -and $json.Settings) {
                        foreach ($candidate in @('ServerMap','Map','MapName','ArkMap','World')) {
                            if ($json.Settings.PSObject.Properties.Name -contains $candidate -and -not [string]::IsNullOrWhiteSpace([string]$json.Settings.$candidate)) {
                                $mapValue = [string]$json.Settings.$candidate
                                break
                            }
                        }
                    }
                    if (-not [string]::IsNullOrWhiteSpace($mapValue)) { break }
                } catch { }
            }
        }
        if (-not [string]::IsNullOrWhiteSpace($mapValue)) {
            $protected['ServerSettings|ServerMap'] = [pscustomobject]@{ Section = 'ServerSettings'; Key = 'ServerMap'; Value = $mapValue }
        }
    }

    return $protected
}

function Restore-UGSMGameArkSEClusterProtectedIniValues {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Path,
        [AllowNull()]$ProtectedValues
    )

    $restored = 0
    if ($null -eq $ProtectedValues) { return 0 }

    foreach ($entry in @($ProtectedValues.Values)) {
        if ($null -eq $entry) { continue }
        try {
            Set-UGSMArkSEIniValue -Path $Path -Section ([string]$entry.Section) -Key ([string]$entry.Key) -Value ([string]$entry.Value)
            $restored++
        }
        catch {
            Write-UGSMGameArkSELog -Level 'WARN' -Message ("Failed to restore protected ArkSE cluster value. Path={0}; Section={1}; Key={2}" -f $Path, [string]$entry.Section, [string]$entry.Key) -Exception $_.Exception
        }
    }

    return $restored
}

function Copy-UGSMGameArkSEClusterIniSettings {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$SourcePath,
        [Parameter(Mandatory)][string]$TargetPath,
        [Parameter(Mandatory)][string]$FileName
    )

    $copied = 0
    $skipped = 0

    if (-not (Test-Path -LiteralPath $SourcePath -PathType Leaf)) {
        return [pscustomobject]@{ Copied = 0; Skipped = 0; SourceMissing = $true }
    }

    $targetParent = Split-Path -Parent $TargetPath
    if (-not (Test-Path -LiteralPath $targetParent -PathType Container)) {
        New-Item -ItemType Directory -Path $targetParent -Force | Out-Null
    }
    if (-not (Test-Path -LiteralPath $TargetPath -PathType Leaf)) {
        New-Item -ItemType File -Path $TargetPath -Force | Out-Null
    }

    $data = Read-UGSMGameArkSEIniFile -Path $SourcePath
    foreach ($sectionName in @($data.Keys)) {
        $sectionData = $data[$sectionName]
        if ($null -eq $sectionData) { continue }

        foreach ($keyName in @($sectionData.Keys)) {
            if (Test-UGSMGameArkSEClusterSyncExcludedIniKey -FileName $FileName -Section ([string]$sectionName) -Key ([string]$keyName)) {
                $skipped++
                continue
            }

            $value = [string]$sectionData[$keyName]
            Set-UGSMArkSEIniValue -Path $TargetPath -Section ([string]$sectionName) -Key ([string]$keyName) -Value $value
            $copied++
        }
    }

    return [pscustomobject]@{ Copied = $copied; Skipped = $skipped; SourceMissing = $false }
}

function Sync-UGSMGameArkSEClusterProfiles {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$Instance
    )

    $syncStopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    $instanceId = Get-UGSMGameArkSEInstanceLabel -Instance $Instance
    $paths = Get-UGSMGameArkSEProfilePaths -Instance $Instance

    if (-not (Test-Path -LiteralPath $paths.GameUserSettingsPath -PathType Leaf)) {
        throw "GameUserSettings.ini was not found for ARKSE cluster sync: $($paths.GameUserSettingsPath)"
    }

    $sourceSettings = Get-UGSMGameArkSEProfileClusterSettings -GameUserSettingsPath $paths.GameUserSettingsPath
    if (-not $sourceSettings.ClusterEnabled) {
        throw 'Enable Cross-ARK Cluster before syncing cluster profiles.'
    }
    if ([string]::IsNullOrWhiteSpace([string]$sourceSettings.ClusterId)) {
        throw 'Cluster ID is required before syncing cluster profiles.'
    }

    $activeMods = @(Get-UGSMGameArkSEActiveModIds -Instance $Instance)
    if ($activeMods.Count -eq 0) {
        $activeMods = @($sourceSettings.ActiveMods)
    }

    $profiles = @(Get-UGSMGameArkSEClusterProfiles -SourceInstance $Instance -ClusterId ([string]$sourceSettings.ClusterId))
    $targets = @($profiles | Where-Object { -not $_.IsSource })

    Write-UGSMGameArkSELog -Level 'INFO' -Message ("Cluster profile sync requested. InstanceId={0}; ClusterId={1}; TargetCount={2}; ModCount={3}; Mode=AllSettingsExceptMapPorts" -f $instanceId, [string]$sourceSettings.ClusterId, @($targets).Count, $activeMods.Count)

    $updated = 0
    $totalCopiedGus = 0
    $totalSkippedGus = 0
    $totalCopiedGame = 0
    $totalSkippedGame = 0

    foreach ($target in $targets) {
        try {
            # Sync every ARK setting that affects player/dino/game state consistency,
            # while keeping each server's map, ports, bind IP, and save identity independent.
            # Snapshot protected values first, then restore them after the copy as a hard safety block.
            $protectedGus = Get-UGSMGameArkSEClusterProtectedIniValues -Path $target.GameUserSettingsPath -FileName 'GameUserSettings.ini' -ProfileRoot ([string]$target.ProfileRoot)
            $protectedGame = Get-UGSMGameArkSEClusterProtectedIniValues -Path $target.GameIniPath -FileName 'Game.ini' -ProfileRoot ([string]$target.ProfileRoot)

            $gusResult = Copy-UGSMGameArkSEClusterIniSettings -SourcePath $paths.GameUserSettingsPath -TargetPath $target.GameUserSettingsPath -FileName 'GameUserSettings.ini'
            $gameResult = Copy-UGSMGameArkSEClusterIniSettings -SourcePath $paths.GameIniPath -TargetPath $target.GameIniPath -FileName 'Game.ini'

            $restoredGus = Restore-UGSMGameArkSEClusterProtectedIniValues -Path $target.GameUserSettingsPath -ProtectedValues $protectedGus
            $restoredGame = Restore-UGSMGameArkSEClusterProtectedIniValues -Path $target.GameIniPath -ProtectedValues $protectedGame

            $totalCopiedGus += [int]$gusResult.Copied
            $totalSkippedGus += [int]$gusResult.Skipped
            $totalCopiedGame += [int]$gameResult.Copied
            $totalSkippedGame += [int]$gameResult.Skipped

            # Always sync active mod IDs/manifest for cluster profile consistency.
            $targetInstance = [pscustomobject]@{
                Id = [string]$target.Name
                Name = [string]$target.Name
                GameId = 'ArkSE'
                ProfilePath = [string]$target.ProfileRoot
            }
            [void](Set-UGSMGameArkSEActiveModIds -Instance $targetInstance -ModIds $activeMods)
            [void](Save-UGSMGameArkSEManagedMods -Instance $targetInstance -ModIds $activeMods)

            # Reapply UGSM-assigned target ports after sync so the editor/config cannot inherit source ports.
            try { Sync-UGSMGameArkSEAssignedPortsToConfig -Instance $targetInstance -Paths (Get-UGSMGameArkSEProfilePaths -Instance $targetInstance) } catch { }

            $updated++
            Write-UGSMGameArkSELog -Level 'INFO' -Message ("Cluster profile synced. SourceInstanceId={0}; TargetProfile={1}; CopiedGUS={2}; SkippedGUS={3}; RestoredGUS={4}; CopiedGameIni={5}; SkippedGameIni={6}; RestoredGameIni={7}; ModCount={8}" -f $instanceId, [string]$target.Name, [int]$gusResult.Copied, [int]$gusResult.Skipped, [int]$restoredGus, [int]$gameResult.Copied, [int]$gameResult.Skipped, [int]$restoredGame, $activeMods.Count)
        }
        catch {
            Write-UGSMGameArkSELog -Level 'ERROR' -Message ("Cluster profile sync failed for target. SourceInstanceId={0}; TargetProfile={1}" -f $instanceId, [string]$target.Name) -Exception $_.Exception
            throw
        }
    }

    $syncStopwatch.Stop()
    Write-UGSMGameArkSELog -Level 'INFO' -Message ("Cluster profile sync completed. InstanceId={0}; ClusterId={1}; Updated={2}; CopiedGUS={3}; SkippedGUS={4}; CopiedGameIni={5}; SkippedGameIni={6}; DurationMs={7}" -f $instanceId, [string]$sourceSettings.ClusterId, $updated, $totalCopiedGus, $totalSkippedGus, $totalCopiedGame, $totalSkippedGame, $syncStopwatch.ElapsedMilliseconds)
    return [pscustomobject]@{
        Success = $true
        ClusterId = [string]$sourceSettings.ClusterId
        Updated = $updated
        ModCount = $activeMods.Count
        CopiedGameUserSettings = $totalCopiedGus
        SkippedGameUserSettings = $totalSkippedGus
        CopiedGameIni = $totalCopiedGame
        SkippedGameIni = $totalSkippedGame
    }
}


function Get-UGSMGameArkSELaunchSettings {
    [CmdletBinding()]
    param([Parameter(Mandatory)][object]$Instance)

    $paths = Get-UGSMGameArkSEProfilePaths -Instance $Instance
    try { Sync-UGSMGameArkSEAssignedPortsToConfig -Instance $Instance -Paths $paths } catch { }
    $iniPath = $paths.GameUserSettingsPath
    if (-not (Test-Path -LiteralPath $iniPath -PathType Leaf) -and (Test-Path -LiteralPath $paths.RuntimeGameUserSettingsPath -PathType Leaf)) {
        $iniPath = $paths.RuntimeGameUserSettingsPath
    }

    $get = {
        param($section,$key,$default)
        try { return [string](Get-UGSMGameArkSEIniValue -Path $iniPath -Section $section -Key $key -DefaultValue $default) } catch { return [string]$default }
    }

    $map = & $get 'ServerSettings' 'ServerMap' 'TheIsland'
    if ([string]::IsNullOrWhiteSpace($map)) { $map = 'TheIsland' }
    $sessionName = & $get 'SessionSettings' 'SessionName' ([string]$Instance.Name)
    if ([string]::IsNullOrWhiteSpace($sessionName)) { $sessionName = [string]$Instance.Name }
    $activeMods = @(Get-UGSMGameArkSEActiveModIds -Instance $Instance)

    $clusterEnabledText = & $get 'ServerSettings' 'UGSMClusterEnabled' 'False'
    $clusterEnabled = ($clusterEnabledText -match '^(?i:true|1|yes|enabled)$')
    $clusterId = & $get 'ServerSettings' 'UGSMClusterId' ''
    $clusterDir = & $get 'ServerSettings' 'UGSMClusterDirectory' ''
    $noTransferText = & $get 'ServerSettings' 'UGSMNoTransferFromFiltering' 'False'
    $noTransfer = ($noTransferText -match '^(?i:true|1|yes|enabled)$')

    if ($clusterEnabled -and [string]::IsNullOrWhiteSpace($clusterId)) {
        $clusterId = 'UGSMCluster'
    }
    if ($clusterEnabled -and [string]::IsNullOrWhiteSpace($clusterDir)) {
        $safeClusterId = [string]$clusterId
        if ([string]::IsNullOrWhiteSpace($safeClusterId)) { $safeClusterId = 'UGSMCluster' }
        $safeClusterId = ($safeClusterId -replace '[\\/:*?"<>|]', '_').Trim()
        if ([string]::IsNullOrWhiteSpace($safeClusterId)) { $safeClusterId = 'UGSMCluster' }
        $clusterDir = Join-Path (Get-UGSMGameArkSEProfileBaseRoot) (Join-Path 'ARKSE\Clusters' $safeClusterId)
    }
    if ($clusterEnabled -and -not (Test-Path -LiteralPath $clusterDir -PathType Container)) {
        New-Item -ItemType Directory -Path $clusterDir -Force | Out-Null
    }

    return [pscustomobject]@{
        Map = [string]$map
        SessionName = [string]$sessionName
        ActiveMods = [string[]]$activeMods
        ClusterEnabled = [bool]$clusterEnabled
        ClusterId = [string]$clusterId
        ClusterDirectory = [string]$clusterDir
        NoTransferFromFiltering = [bool]$noTransfer
    }
}

function New-UGSMGameArkSELaunchArguments {
    [CmdletBinding()]
    param([Parameter(Mandatory)][object]$Instance)

    $settings = Get-UGSMGameArkSELaunchSettings -Instance $Instance
    $url = [string]$settings.Map
    if ([string]::IsNullOrWhiteSpace($url)) { $url = 'TheIsland' }
    $url += '?listen'
    if (-not [string]::IsNullOrWhiteSpace($settings.SessionName)) { $url += '?SessionName=' + [string]$settings.SessionName }
    if (@($settings.ActiveMods).Count -gt 0) { $url += '?GameModIds=' + ((@($settings.ActiveMods) | ForEach-Object { [string]$_ }) -join ',') }

    $args = New-Object System.Collections.Generic.List[string]
    [void]$args.Add($url)
    if ($settings.ClusterEnabled) {
        if (-not [string]::IsNullOrWhiteSpace($settings.ClusterId)) { [void]$args.Add('-clusterid=' + [string]$settings.ClusterId) }
        if (-not [string]::IsNullOrWhiteSpace($settings.ClusterDirectory)) { [void]$args.Add('-ClusterDirOverride=' + [string]$settings.ClusterDirectory) }
        if ($settings.NoTransferFromFiltering) { [void]$args.Add('-NoTransferFromFiltering') }
    }
    [void]$args.Add('-log')
    [void]$args.Add('-NoBattlEye')
    return [string[]]$args.ToArray()
}

function Test-UGSMGameArkSEInstall {
    [CmdletBinding()]
    param(
        [string]$InstallPath
    )

    $definition = Get-UGSMGameArkSEInstallDefinition -InstallPath $InstallPath
    if (-not $definition -or [string]::IsNullOrWhiteSpace([string]$definition.InstallPath)) {
        throw 'ArkSE validation failed: InstallPath could not be resolved.'
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
        GameId                 = 'ArkSE'
        InstallPath            = $installPath
        InstallPathExists      = $installPathExists
        ServerExecutablePath   = $serverExecutablePath
        ServerExecutableExists = $exeExists
        ConfigRootPath         = [string]$definition.ConfigRootPath
        SaveRootPath           = [string]$definition.SaveRootPath
        LogRootPath            = [string]$definition.LogRootPath
        MainConfigPath         = [string]$definition.MainConfigPath
        SecondaryConfigPath    = [string]$definition.SecondaryConfigPath
        MissingItems           = @($missing)
        IsInstalled            = ($installPathExists -and $exeExists)
        IsValid                = ($installPathExists -and $exeExists -and $missing.Count -eq 0)
        NeedsRepair            = ($installPathExists -and ($missing.Count -gt 0))
    }
}

function Start-UGSMArkSEInstance {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Instance
    )

    if (-not $Instance) {
        throw 'ArkSE start failed: Instance was null.'
    }

    $arkStartStopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    $arkInstanceId = Get-UGSMGameArkSEInstanceLabel -Instance $Instance
    Write-UGSMGameArkSELog -Level 'INFO' -Message ("Start requested. InstanceId={0}; InstallPath={1}" -f $arkInstanceId, [string]$Instance.InstallPath)

    $validation = Test-UGSMGameArkSEInstall -InstallPath $Instance.InstallPath
    if (-not $validation -or -not $validation.IsInstalled -or -not $validation.ServerExecutableExists) {
        throw 'ArkSE start failed: ArkSE is not installed or the server executable is missing.'
    }

    $installDef = Get-UGSMGameArkSEInstallDefinition -InstallPath $Instance.InstallPath -Instance $Instance
    if (-not $installDef) {
        throw 'ArkSE start failed: Install definition could not be resolved.'
    }

    $profilePath = $null
    if ($Instance.PSObject.Properties.Name -contains 'ProfilePath' -and -not [string]::IsNullOrWhiteSpace([string]$Instance.ProfilePath)) {
        $profilePath = [string]$Instance.ProfilePath
    }
    else {
        $profilePath = Get-UGSMGameArkSEProfileRoot -ProfileName ([string]$Instance.Name)
    }

    if ([string]::IsNullOrWhiteSpace($profilePath) -or -not (Test-Path -LiteralPath $profilePath -PathType Container)) {
        throw "ArkSE start failed: Profile path was not found: $profilePath"
    }

    $runtime = Ensure-UGSMArkSERuntimeLayout -Instance $Instance -InstallDefinition $installDef

    $runtimeConfigRoot = [string]$runtime.RuntimeConfigRootPath
    $runtimeSaveRoot = [string]$runtime.RuntimeSaveRootPath
    $serverSettingsPath = Join-Path $runtimeConfigRoot 'GameUserSettings.ini'

    if (-not (Test-Path -LiteralPath $runtimeConfigRoot -PathType Container)) {
        New-Item -ItemType Directory -Path $runtimeConfigRoot -Force | Out-Null
    }

    if (-not (Test-Path -LiteralPath $runtimeSaveRoot -PathType Container)) {
        New-Item -ItemType Directory -Path $runtimeSaveRoot -Force | Out-Null
    }

    if (-not (Test-Path -LiteralPath $serverSettingsPath -PathType Leaf)) {
        throw "ArkSE start failed: Runtime GameUserSettings.ini was not found: $serverSettingsPath"
    }

    $serverExe = [string]$runtime.RuntimeServerExePath
    $workingDirectory = Split-Path -Parent $serverExe
    if (-not (Test-Path -LiteralPath $serverExe -PathType Leaf)) {
        throw "ArkSE start failed: Runtime server executable was not found: $serverExe"
    }

    $modSync = Sync-UGSMGameArkSEWorkshopMods -Instance $Instance
    $arkLaunchArgs = New-UGSMGameArkSELaunchArguments -Instance $Instance
    $arkLaunchSettings = Get-UGSMGameArkSELaunchSettings -Instance $Instance
    Write-UGSMGameArkSELog -Level 'INFO' -Message ("Launching process. InstanceId={0}; Exe={1}; WorkingDirectory={2}; Map={3}; Mods={4}; ClusterEnabled={5}; ClusterId={6}; Args={7}" -f $arkInstanceId, $serverExe, $workingDirectory, [string]$arkLaunchSettings.Map, (@($arkLaunchSettings.ActiveMods) -join ','), [bool]$arkLaunchSettings.ClusterEnabled, [string]$arkLaunchSettings.ClusterId, ($arkLaunchArgs -join ' '))

    $proc = Start-Process `
        -FilePath $serverExe `
        -ArgumentList $arkLaunchArgs `
        -WorkingDirectory $workingDirectory `
        -PassThru

    if (-not $proc -or -not $proc.Id) {
        throw 'ArkSE start failed: Start-Process did not return a valid process.'
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
            GameId            = 'ArkSE'
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

    $arkStartStopwatch.Stop()
    Write-UGSMGameArkSELog -Level 'INFO' -Message ("Start completed. InstanceId={0}; Pid={1}; RuntimeRoot={2}; DurationMs={3}" -f $arkInstanceId, $gamePid, [string]$runtime.RuntimeRoot, $arkStartStopwatch.ElapsedMilliseconds)

    return [pscustomobject]@{
        Instance = $Instance
        Pid      = $gamePid
        Status   = 'Running'
        Runtime  = $runtime
    }
}

function Stop-UGSMGameArkSEInstance {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Instance
    )

    if (-not $Instance) {
        throw 'ArkSE stop failed: Instance was null.'
    }

    $arkStopStopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    $arkInstanceId = Get-UGSMGameArkSEInstanceLabel -Instance $Instance
    Write-UGSMGameArkSELog -Level 'INFO' -Message ("Stop requested. InstanceId={0}; Pid={1}" -f $arkInstanceId, [string]$Instance.Pid)

    $installDef = Get-UGSMGameArkSEInstallDefinition -InstallPath $Instance.InstallPath -Instance $Instance
    if (-not $installDef) {
        throw 'ArkSE stop failed: Install definition could not be resolved.'
    }

    $runtime = Get-UGSMGameArkSERuntimeDefinition -Instance $Instance -InstallDefinition $installDef

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
        throw ("ArkSE stop failed: Process {0} is still running." -f $targetProcessId)
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

    $arkStopStopwatch.Stop()
    Write-UGSMGameArkSELog -Level 'INFO' -Message ("Stop completed. InstanceId={0}; Pid={1}; Stopped={2}; DurationMs={3}" -f $arkInstanceId, $targetProcessId, ($null -ne $stopResult -and [bool]$stopResult.Stopped), $arkStopStopwatch.ElapsedMilliseconds)

    return [pscustomobject]@{
        Instance = $Instance
        Status   = 'Stopped'
        Runtime  = $runtime
    }
}


function Test-UGSMArkSEInstance {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Instance
    )

    $installValidation = $null
    try {
        $installValidation = Test-UGSMGameArkSEInstall -InstallPath ([string]$Instance.InstallPath)
    }
    catch {
        $installValidation = $null
    }

    $paths = Get-UGSMGameArkSEProfilePaths -Instance $Instance
    $profileExists = Test-Path -LiteralPath $paths.ProfileRoot -PathType Container
    $mainConfigExists = (Test-Path -LiteralPath $paths.GameUserSettingsPath -PathType Leaf) -or (Test-Path -LiteralPath $paths.RuntimeGameUserSettingsPath -PathType Leaf)

    [pscustomobject]@{
        GameId           = 'ArkSE'
        InstanceId       = if ($Instance.PSObject.Properties['Id']) { [string]$Instance.Id } else { $null }
        Name             = if ($Instance.PSObject.Properties['Name']) { [string]$Instance.Name } else { $null }
        InstallPath      = if ($Instance.PSObject.Properties['InstallPath']) { [string]$Instance.InstallPath } else { $null }
        ProfilePath      = $paths.ProfileRoot
        ProfileExists    = $profileExists
        MainConfigPath   = $paths.GameUserSettingsPath
        MainConfigExists = $mainConfigExists
        IsInstalled      = [bool]($installValidation -and $installValidation.IsInstalled)
        IsValid          = [bool]($installValidation -and $installValidation.IsInstalled -and $profileExists)
        RuntimeActive    = [bool]$paths.IsRuntimeActive
    }
}

function Register-UGSMGameArkSEModule {
    [CmdletBinding()]
    param()

    $metadata = Get-UGSMGameArkSEMetadata

    return [pscustomobject]@{
        Id       = [string]$metadata.Id
        Metadata = $metadata
        Handlers = [pscustomobject]@{
            GetMetadata       = 'Get-UGSMGameArkSEMetadata'
            TestInstall       = 'Test-UGSMGameArkSEInstall'
            TestInstance      = 'Test-UGSMArkSEInstance'
            EnsureArkSE       = 'Ensure-UGSMGameArkSEArkSE'
            InitializeProfile = 'Initialize-UGSMGameArkSEProfile'
            Start             = 'Start-UGSMArkSEInstance'
            Stop              = 'Stop-UGSMGameArkSEInstance'
            BuildEditor       = 'New-UGSMGameArkSEInstanceEditor'
            SaveEditor        = 'Save-UGSMGameArkSEInstanceEditor'
        }
    }
}

function Get-UGSMGameArkSEProfilePaths {
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
        $profileRoot = Get-UGSMGameArkSEProfileRoot -ProfileName ([string]$Instance.Name)
    }
    elseif (Get-Command -Name Get-UGSMDefaultInstanceProfilePath -ErrorAction SilentlyContinue) {
        $profileRoot = Get-UGSMDefaultInstanceProfilePath -GameId 'ArkSE' -Name ([string]$Instance.Name)
    }

    if ([string]::IsNullOrWhiteSpace([string]$profileRoot)) {
        throw 'ArkSE profile paths could not be resolved for the selected instance.'
    }

    $profileGameRoot = Join-Path $profileRoot 'ShooterGame'
    $profileSavedRoot = Join-Path $profileGameRoot 'Saved'
    $profileConfigRoot = Join-Path $profileSavedRoot 'Config\WindowsServer'
    $profileSaveRoot = Join-Path $profileSavedRoot 'SavedArks'
    $profileLogRoot = Join-Path $profileSavedRoot 'Logs'

    $runtimeRoot = Get-UGSMGameArkSERuntimeRoot -Instance $Instance
    $runtimeSavedRoot = Join-Path $runtimeRoot 'ShooterGame\Saved'
    $runtimeConfigRoot = Join-Path $runtimeSavedRoot 'Config\WindowsServer'
    $runtimeSaveRoot = Join-Path $runtimeSavedRoot 'SavedArks'
    $runtimeLogRoot = Join-Path $runtimeSavedRoot 'Logs'

    $runtimeMarkerPath = Join-Path $runtimeSaveRoot 'UGSM.Runtime.json'

    [pscustomobject]@{
        ProfileRoot                 = $profileRoot
        ProfileGameRoot             = $profileGameRoot
        ProfileSavedRoot            = $profileSavedRoot
        ProfileConfigRoot           = $profileConfigRoot
        ProfileSaveRoot             = $profileSaveRoot
        ProfileLogRoot              = $profileLogRoot

        RuntimeRoot                 = $runtimeRoot
        RuntimeConfigRoot           = $runtimeConfigRoot
        RuntimeSaveRoot             = $runtimeSaveRoot
        RuntimeLogRoot              = $runtimeLogRoot
        RuntimeMarkerPath           = $runtimeMarkerPath
        IsRuntimeActive             = (Test-Path -LiteralPath $runtimeMarkerPath -PathType Leaf)

        ConfigRoot                  = if (Test-Path -LiteralPath $runtimeMarkerPath -PathType Leaf) { $runtimeConfigRoot } else { $profileConfigRoot }
        SaveRoot                    = if (Test-Path -LiteralPath $runtimeMarkerPath -PathType Leaf) { $runtimeSaveRoot } else { $profileSaveRoot }
        LogRoot                     = if (Test-Path -LiteralPath $runtimeMarkerPath -PathType Leaf) { $runtimeLogRoot } else { $profileLogRoot }

        PrimaryIniPath              = Join-Path $profileConfigRoot 'GameUserSettings.ini'
        SecondaryIniPath            = Join-Path $profileConfigRoot 'Game.ini'
        RuntimePrimaryIniPath       = Join-Path $runtimeConfigRoot 'GameUserSettings.ini'
        RuntimeSecondaryIniPath     = Join-Path $runtimeConfigRoot 'Game.ini'

        GameUserSettingsPath        = Join-Path $profileConfigRoot 'GameUserSettings.ini'
        GameIniPath                 = Join-Path $profileConfigRoot 'Game.ini'
        RuntimeGameUserSettingsPath = Join-Path $runtimeConfigRoot 'GameUserSettings.ini'
        RuntimeGameIniPath          = Join-Path $runtimeConfigRoot 'Game.ini'

        AdminUsersPath              = Join-Path $profileSavedRoot 'AllowedCheaterSteamIDs.txt'
        RuntimeAdminUsersPath       = Join-Path (Join-Path $runtimeRoot 'ShooterGame\Saved') 'AllowedCheaterSteamIDs.txt'

        # compatibility aliases for the current editor/actions code
        ServerSettingsPath          = Join-Path $profileConfigRoot 'GameUserSettings.ini'
        RuntimeServerSettingsPath   = Join-Path $runtimeConfigRoot 'GameUserSettings.ini'

        ProfileDatabasePath         = $null
        RuntimeDatabasePath         = $null
        DatabasePath                = $null
    }
}


function Read-UGSMGameArkSEIniFile {
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

function Get-UGSMGameArkSEIniValue {
    [CmdletBinding(DefaultParameterSetName='Data')]
    param(
        [Parameter(ParameterSetName='Data')]
        $IniData,

        [Parameter(ParameterSetName='Path')]
        [string]$Path,

        [Parameter(Mandatory)]
        [string]$Section,

        [Parameter(Mandatory)]
        [string]$Key,

        $DefaultValue = $null
    )

    if ($PSCmdlet.ParameterSetName -eq 'Path') {
        if (-not [string]::IsNullOrWhiteSpace($Path) -and (Test-Path -LiteralPath $Path -PathType Leaf)) {
            $IniData = Read-UGSMGameArkSEIniFile -Path $Path
        }
    }

    try {
        if ($IniData -and $IniData.Contains($Section) -and $IniData[$Section].Contains($Key)) {
            return $IniData[$Section][$Key]
        }
    } catch {}

    return $DefaultValue
}

function Set-UGSMArkSEIniValue {
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


function Get-UGSMArkSEIniFieldTargetPath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Paths,
        [Parameter(Mandatory)][hashtable]$Field
    )

    $fileName = [string]$Field.File
    switch -Regex ($fileName) {
        '^Game\.ini$' { return [string]$Paths.GameIniPath }
        '^GameUserSettings\.ini$' { return [string]$Paths.GameUserSettingsPath }
        default { return [string]$Paths.GameUserSettingsPath }
    }
}

function Get-UGSMArkSEIniDataForField {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][hashtable]$Field,
        $GameUserSettingsIniData,
        $GameIniData
    )

    $fileName = [string]$Field.File
    switch -Regex ($fileName) {
        '^Game\.ini$' { return $GameIniData }
        '^GameUserSettings\.ini$' { return $GameUserSettingsIniData }
        default { return $GameUserSettingsIniData }
    }
}

function Get-UGSMArkSEIniRepeatedValues {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Section,
        [Parameter(Mandatory)][string]$Key
    )

    $values = [System.Collections.Generic.List[string]]::new()
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        return @()
    }

    $sectionRegex = '^\s*\[' + [regex]::Escape($Section) + '\]\s*$'
    $keyRegex = '^\s*' + [regex]::Escape($Key) + '\s*=\s*(.*)$'
    $inSection = $false

    foreach ($line in @(Get-Content -LiteralPath $Path -ErrorAction SilentlyContinue)) {
        if ($line -match '^\s*\[(.+?)\]\s*$') {
            $inSection = ($line -match $sectionRegex)
            continue
        }

        if ($inSection -and $line -match $keyRegex) {
            [void]$values.Add([string]$matches[1])
        }
    }

    return @($values)
}

function Set-UGSMArkSEIniRepeatedValues {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Section,
        [Parameter(Mandatory)][string]$Key,
        [string[]]$Values
    )

    Ensure-UGSMArkSEParentDirectory -Path $Path

    $lines = [System.Collections.Generic.List[string]]::new()
    if (Test-Path -LiteralPath $Path -PathType Leaf) {
        foreach ($existingLine in @(Get-Content -LiteralPath $Path -ErrorAction SilentlyContinue)) {
            [void]$lines.Add([string]$existingLine)
        }
    }

    $cleanValues = @(
        $Values |
        ForEach-Object { [string]$_ } |
        Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
    )

    if ($lines.Count -eq 0) {
        $lines.Add('[' + $Section + ']')
        foreach ($value in $cleanValues) {
            $lines.Add($Key + '=' + $value)
        }
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
        foreach ($value in $cleanValues) {
            $lines.Add($Key + '=' + $value)
        }
        Set-Content -LiteralPath $Path -Value $lines -Encoding UTF8
        return
    }

    for ($i = $sectionEnd - 1; $i -gt $sectionStart; $i--) {
        if ($lines[$i] -match $keyRegex) {
            $lines.RemoveAt($i)
        }
    }

    $insertIndex = $sectionStart + 1
    while ($insertIndex -lt $lines.Count -and $lines[$insertIndex] -notmatch '^\s*\[.+\]\s*$') {
        $insertIndex++
    }
    foreach ($value in $cleanValues) {
        $lines.Insert($insertIndex, $Key + '=' + $value)
        $insertIndex++
    }

    Set-Content -LiteralPath $Path -Value $lines -Encoding UTF8
}

function Read-UGSMArkSEStringListFile {
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

function Write-UGSMArkSEStringListFile {
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
        ForEach-Object { [string]$_.Trim() } |
        Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
        Select-Object -Unique
    )

    Set-Content -LiteralPath $Path -Value $cleanValues -Encoding UTF8
}


function Ensure-UGSMArkSEParentDirectory {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Path
    )

    $parent = Split-Path -Parent $Path
    if (-not [string]::IsNullOrWhiteSpace($parent) -and -not (Test-Path -LiteralPath $parent -PathType Container)) {
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
    }
}

function Read-UGSMArkSEJsonFile {
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

function Write-UGSMArkSEJsonFile {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Path,
        [AllowNull()]$Value
    )

    Ensure-UGSMArkSEParentDirectory -Path $Path
    $json = $null
    if ($null -eq $Value) {
        $json = "{}"
    }
    else {
        $json = ($Value | ConvertTo-Json -Depth 100)
    }

    Set-Content -LiteralPath $Path -Value $json -Encoding UTF8
}

function Read-UGSMArkSEXmlFile {
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

function Write-UGSMArkSEXmlFile {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][xml]$Xml
    )

    Ensure-UGSMArkSEParentDirectory -Path $Path
    $Xml.Save($Path)
}

function Read-UGSMArkSECfgFile {
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

function Set-UGSMArkSECfgValue {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Key,
        [AllowNull()][string]$Value
    )

    Ensure-UGSMArkSEParentDirectory -Path $Path

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
function Test-UGSMArkSEPSSQLiteInstalled {
    [CmdletBinding()]
    param()

    return ($null -ne (Get-Module -ListAvailable -Name PSSQLite | Select-Object -First 1))
}

function Install-UGSMArkSEPSSQLite {
    [CmdletBinding()]
    param()

    Install-Module -Name PSSQLite -Scope CurrentUser -Force -Confirm:$false -ErrorAction Stop
    return (Test-UGSMArkSEPSSQLiteInstalled)
}

function Get-UGSMGameArkSEElevatedUsers {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$DatabasePath
    )

    if (-not (Test-UGSMArkSEPSSQLiteInstalled)) {
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

function Save-UGSMArkSEElevatedUsers {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$DatabasePath,
        [string[]]$UserIds
    )

    if (-not (Test-UGSMArkSEPSSQLiteInstalled)) {
        throw 'PSSQLite is not installed.'
    }

    if (-not (Test-Path -LiteralPath $DatabasePath -PathType Leaf)) {
        throw 'ArkSE.db was not found.'
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


function Resolve-UGSMArkSEEditorFieldPath {
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

function ConvertTo-UGSMArkSEEditorFieldValue {
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
        'RepeatedIniValues' {
            return @(
                $Control.Lines |
                ForEach-Object { [string]$_ } |
                Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
            )
        }
        'InstanceText' {
            return [string]$Control.Text
        }
        default {
            return [string]$Control.Text
        }
    }
}


function Get-UGSMGameArkSEInstanceDefinitionPath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$Instance
    )

    foreach ($propertyName in @('DefinitionPath', 'JsonPath', 'ConfigPath', 'InstancePath', 'Path', 'SourcePath', 'FilePath')) {
        if ($Instance.PSObject.Properties.Name -contains $propertyName) {
            $value = [string]$Instance.$propertyName
            if (-not [string]::IsNullOrWhiteSpace($value) -and ($value -like '*.json')) {
                return $value
            }
        }
    }

    return $null
}

function Save-UGSMGameArkSEInstanceDefinition {
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

    $definitionPath = Get-UGSMGameArkSEInstanceDefinitionPath -Instance $Instance
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

function Save-UGSMGameArkSEInstanceEditor {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$Instance,
        [Parameter(Mandatory)][hashtable]$EditorState
    )

    $arkSaveStopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    $arkInstanceId = Get-UGSMGameArkSEInstanceLabel -Instance $Instance
    Write-UGSMGameArkSELog -Level 'INFO' -Message ("Editor save requested. InstanceId={0}; FieldCount={1}" -f $arkInstanceId, @($EditorState.Keys).Count)

    $paths = Get-UGSMGameArkSEProfilePaths -Instance $Instance
    $updatedInstance = $Instance
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

    foreach ($entry in $EditorState.GetEnumerator()) {
        $item = $entry.Value
        if (-not $item) { continue }

        $field = $item.Field
        $control = $item.Control
        if (-not $field -or -not $control) { continue }

        switch ([string]$field.Type) {
            'StringList' {
                $targetPath = Resolve-UGSMArkSEEditorFieldPath -Field $field -Paths $paths -TargetSet Runtime
                if ([string]::IsNullOrWhiteSpace([string]$targetPath)) {
                    $targetPath = Resolve-UGSMArkSEEditorFieldPath -Field $field -Paths $paths
                }

                if ([string]::IsNullOrWhiteSpace([string]$targetPath)) {
                    throw ("ArkSE save failed: no runtime path could be resolved for string list field '{0}'." -f [string]$field.Id)
                }

                $values = @($control.Lines | ForEach-Object { [string]$_ })
                Write-UGSMArkSEStringListFile -Path $targetPath -Values $values
                $saveSummary.StringListsWritten++
                $saveSummary.RuntimeCopiesUpdated++
            }

            'Boolean' {
                $value = ConvertTo-UGSMArkSEEditorFieldValue -Field $field -Control $control
                $targetIniPath = Get-UGSMArkSEIniFieldTargetPath -Paths $paths -Field $field
                Set-UGSMArkSEIniValue -Path $targetIniPath -Section ([string]$field.Section) -Key ([string]$field.Key) -Value $value
                $saveSummary.IniKeysWritten++
                $saveSummary.RuntimeCopiesUpdated++
            }

            'Number' {
                $value = ConvertTo-UGSMArkSEEditorFieldValue -Field $field -Control $control
                $targetIniPath = Get-UGSMArkSEIniFieldTargetPath -Paths $paths -Field $field
                Set-UGSMArkSEIniValue -Path $targetIniPath -Section ([string]$field.Section) -Key ([string]$field.Key) -Value $value
                $saveSummary.IniKeysWritten++
                $saveSummary.RuntimeCopiesUpdated++
            }

            'MultilineText' {
                $value = ConvertTo-UGSMArkSEEditorFieldValue -Field $field -Control $control
                $targetIniPath = Get-UGSMArkSEIniFieldTargetPath -Paths $paths -Field $field
                Set-UGSMArkSEIniValue -Path $targetIniPath -Section ([string]$field.Section) -Key ([string]$field.Key) -Value $value
                $saveSummary.IniKeysWritten++
                $saveSummary.RuntimeCopiesUpdated++
            }

            'Text' {
                $value = ConvertTo-UGSMArkSEEditorFieldValue -Field $field -Control $control
                $targetIniPath = Get-UGSMArkSEIniFieldTargetPath -Paths $paths -Field $field
                Set-UGSMArkSEIniValue -Path $targetIniPath -Section ([string]$field.Section) -Key ([string]$field.Key) -Value $value
                $saveSummary.IniKeysWritten++
                $saveSummary.RuntimeCopiesUpdated++
            }

            'Combo' {
                $value = ConvertTo-UGSMArkSEEditorFieldValue -Field $field -Control $control
                $targetIniPath = Get-UGSMArkSEIniFieldTargetPath -Paths $paths -Field $field
                Set-UGSMArkSEIniValue -Path $targetIniPath -Section ([string]$field.Section) -Key ([string]$field.Key) -Value $value
                $saveSummary.IniKeysWritten++
                $saveSummary.RuntimeCopiesUpdated++
                if ([string]$field.Id -eq 'ServerMap') {
                    Write-UGSMGameArkSELog -Level 'INFO' -Message ("Editor map saved. InstanceId={0}; Map={1}" -f $arkInstanceId, [string]$value)
                }
            }

            'RepeatedIniValues' {
                $values = @(ConvertTo-UGSMArkSEEditorFieldValue -Field $field -Control $control)
                $targetIniPath = Get-UGSMArkSEIniFieldTargetPath -Paths $paths -Field $field
                Set-UGSMArkSEIniRepeatedValues -Path $targetIniPath -Section ([string]$field.Section) -Key ([string]$field.Key) -Values $values
                $saveSummary.IniKeysWritten += $values.Count
                $saveSummary.RuntimeCopiesUpdated++
            }

            'InstanceText' {
                $value = [string](ConvertTo-UGSMArkSEEditorFieldValue -Field $field -Control $control)
                if ([string]$field.Model -eq 'Discord') {
                    $discordInput[[string]$field.Property] = $value
                    $hasDiscordChanges = $true
                }
            }

            'InstanceBoolean' {
                $value = [bool](ConvertTo-UGSMArkSEEditorFieldValue -Field $field -Control $control)
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
            [void](Save-UGSMGameArkSEInstanceDefinition -Instance $PersistedInstance)
        }

        $discordResult = Save-UGSMInstanceDiscordSettingsModel -Instance $updatedInstance -InputObject ([pscustomobject]$discordInput) -PersistInstance $persistScript
        if ($discordResult -and $discordResult.PSObject.Properties['Instance']) {
            $updatedInstance = $discordResult.Instance
            $saveSummary.InstanceSettingsSaved++
        }
    }

    $arkSaveStopwatch.Stop()
    Write-UGSMGameArkSELog -Level 'INFO' -Message ("Editor save completed. InstanceId={0}; IniKeys={1}; StringLists={2}; InstanceSettings={3}; DurationMs={4}" -f $arkInstanceId, $saveSummary.IniKeysWritten, $saveSummary.StringListsWritten, $saveSummary.InstanceSettingsSaved, $arkSaveStopwatch.ElapsedMilliseconds)

    return [pscustomobject]@{
        Success  = $true
        Message  = ("Saved ArkSE runtime settings. INI keys: {0}. User lists: {1}. Instance settings: {2}." -f $saveSummary.IniKeysWritten, $saveSummary.StringListsWritten, $saveSummary.InstanceSettingsSaved)
        Summary  = [pscustomobject]$saveSummary
        Instance = $updatedInstance
    }
}

function New-UGSMGameArkSEInstanceEditor {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$Instance,
        [Parameter(Mandatory)][hashtable]$Theme,
        [Parameter(Mandatory)][System.Windows.Forms.Panel]$HostPanel,
        [AllowNull()][System.Windows.Forms.Label]$StatusLabel
    )

    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing

    $arkEditorStopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    $arkInstanceId = Get-UGSMGameArkSEInstanceLabel -Instance $Instance
    Write-UGSMGameArkSELog -Level 'INFO' -Message ("Editor creation started. InstanceId={0}" -f $arkInstanceId)

    $paths = Get-UGSMGameArkSEProfilePaths -Instance $Instance
    try { Sync-UGSMGameArkSEAssignedPortsToConfig -Instance $Instance -Paths $paths } catch { }
    $schema = Get-UGSMGameArkSEEditorSchema
    $gameUserSettingsIniData = Read-UGSMGameArkSEIniFile -Path $paths.GameUserSettingsPath
    $gameIniData = Read-UGSMGameArkSEIniFile -Path $paths.GameIniPath
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

    function Save-UGSMArkSEInstanceEditor {
        [CmdletBinding()]
        param(
            [Parameter(Mandatory)][object]$Instance,
            [Parameter(Mandatory)][hashtable]$EditorState
        )

        Save-UGSMGameArkSEInstanceEditor -Instance $Instance -EditorState $EditorState
    }

    function New-UGSMArkSEInstanceEditor {
        [CmdletBinding()]
        param(
            [Parameter(Mandatory)][object]$Instance,
            [Parameter(Mandatory)][hashtable]$Theme,
            [Parameter(Mandatory)][System.Windows.Forms.Panel]$HostPanel,
            [AllowNull()][System.Windows.Forms.Label]$StatusLabel
        )

        New-UGSMGameArkSEInstanceEditor -Instance $Instance -Theme $Theme -HostPanel $HostPanel -StatusLabel $StatusLabel
    }

    function Get-ArkSESafeIniValue {
        param([hashtable]$Field)
        try {
            if (@('Port','GamePort','PeerPort','QueryPort','RCONPort','RconPort') -contains [string]$Field.Id) {
                $assignedPortValue = Get-UGSMGameArkSEAssignedPortValue -Instance $Instance -FieldId ([string]$Field.Id)
                if ($null -ne $assignedPortValue -and -not [string]::IsNullOrWhiteSpace([string]$assignedPortValue)) {
                    return [string]$assignedPortValue
                }
            }
            $targetIniData = Get-UGSMArkSEIniDataForField -Field $Field -GameUserSettingsIniData $gameUserSettingsIniData -GameIniData $gameIniData
            return [string]( Get-UGSMGameArkSEIniValue -IniData $targetIniData -Section $Field.Section -Key $Field.Key -DefaultValue $Field.DefaultValue)
        }
        catch {
            if ($StatusLabel) { $StatusLabel.Text = 'ArkSE field load failed for ' + [string]$Field.Id + ': ' + $_.Exception.Message }
            return [string]$(if ($Field.ContainsKey('DefaultValue')) { $Field.DefaultValue } else { '' })
        }
    }

    function Get-ArkSESafeInstanceValue {
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
            if ($StatusLabel) { $StatusLabel.Text = 'ArkSE instance field load failed for ' + [string]$Field.Id + ': ' + $_.Exception.Message }
        }

        if ($Field.ContainsKey('DefaultValue')) {
            return $Field.DefaultValue
        }

        return $null
    }

    function New-ArkSETextBox {
        param(
            [int]$Width = 340,
            [switch]$Multiline,
            [int]$Height = 24
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
            }
        }
        finally {
            $tb.ResumeLayout($false)
        }

        return $tb
    }

    function New-ArkSEStretchTextBox {
        param(
            [switch]$Multiline,
            [int]$Height = 24
        )

        $tb = New-ArkSETextBox -Width $layout.ControlWidth -Multiline:$Multiline -Height $Height
        $tb.Width = $layout.ControlWidth
        $tb.Anchor = 'Left,Right,Top'
        return $tb
    }

    function New-ArkSENarrowHost {
        $panel = New-Object System.Windows.Forms.Panel
        $panel.Dock = 'Top'
        $panel.Height = 26
        $panel.Margin = New-Object System.Windows.Forms.Padding(0)
        $panel.Padding = New-Object System.Windows.Forms.Padding(0)
        return $panel
    }

    function New-ArkSEElevatedUsersControl {
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

        $status = New-UGSMLabel -Text 'Checks for PSSQLite and edits ArkSE.db in the selected profile.' -X 0 -Y 0 -Width 420 -Height 28 -FontSize 8.5 -Color $Theme.Muted
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
            $moduleInstalled = Test-UGSMArkSEPSSQLiteInstalled
            $btnInstallSql.Visible = -not $moduleInstalled
            if (-not $moduleInstalled) {
                [void]$list.Items.Add('PSSQLite is not installed.')
                [void]$list.Items.Add('Install it to edit elevated users in ArkSE.db.')
                return
            }

            $dbPath = Resolve-UGSMArkSEDatabasePath -Instance $Instance -PreferRuntime
            if ([string]::IsNullOrWhiteSpace([string]$dbPath)) {
                [void]$list.Items.Add('ArkSE.db path could not be resolved for this profile.')
                return
            }

            if (-not (Test-Path -LiteralPath $dbPath -PathType Leaf)) {
                [void]$list.Items.Add('ArkSE.db was not found yet for this instance.')
                [void]$list.Items.Add($dbPath)
                return
            }

            try {
                $ids = @( Get-UGSMGameArkSEElevatedUsers -DatabasePath $dbPath)
                if ($ids.Count -eq 0) {
                    [void]$list.Items.Add('No elevated users were found.')
                }
                else {
                    foreach ($id in $ids) { [void]$list.Items.Add($id) }
                }
            }
            catch {
                [void]$list.Items.Add('Error reading ArkSE.db: ' + $_.Exception.Message)
            }
        }.GetNewClosure()

        $btnInstallSql.Add_Click({
                try {
                    Install-UGSMArkSEPSSQLite | Out-Null
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
                    $dbPath = Resolve-UGSMArkSEDatabasePath -Instance $Instance -PreferRuntime
                    if ([string]::IsNullOrWhiteSpace([string]$dbPath)) { throw 'ArkSE.db path could not be resolved for this instance.' }
                    Save-UGSMArkSEElevatedUsers -DatabasePath $dbPath -UserIds $userIds
                    if ($StatusLabel) { $StatusLabel.Text = 'Saved elevated users to ArkSE.db: ' + $dbPath }
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

    function Add-ArkSEFieldRow {
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
                    $fieldHost = New-ArkSENarrowHost
                    $control = New-Object System.Windows.Forms.CheckBox
                    $control.AutoSize = $true
                    $control.Anchor = 'Left'
                    $control.Margin = New-Object System.Windows.Forms.Padding(0)
                    $control.BackColor = [System.Drawing.Color]::Transparent
                    $control.ForeColor = New-UGSMColor $Theme.Text
                    $control.Checked = ([string](Get-ArkSESafeIniValue -Field $Field) -match '^(?i:true|1|yes)$')
                    [void]$fieldHost.Controls.Add($control)
                    [void]$row.Controls.Add($fieldHost, 1, 0)
                    $controlMap[$Field.Id] = @{ Field = $Field; Control = $control }
                }
                'InstanceBoolean' {
                    $fieldHost = New-ArkSENarrowHost
                    $control = New-Object System.Windows.Forms.CheckBox
                    $control.AutoSize = $true
                    $control.Anchor = 'Left'
                    $control.Margin = New-Object System.Windows.Forms.Padding(0)
                    $control.BackColor = [System.Drawing.Color]::Transparent
                    $control.ForeColor = New-UGSMColor $Theme.Text
                    $instanceValue = Get-ArkSESafeInstanceValue -Field $Field
                    $control.Checked = [bool]$instanceValue
                    [void]$fieldHost.Controls.Add($control)
                    [void]$row.Controls.Add($fieldHost, 1, 0)
                    $controlMap[$Field.Id] = @{ Field = $Field; Control = $control }
                }
                'Number' {
                    $numberHost = New-ArkSENarrowHost
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
                    $rawValue = Get-ArkSESafeIniValue -Field $Field
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
                    $control = New-ArkSEStretchTextBox -Multiline -Height $layout.MultilineHeight
                    $control.Text = [string](Get-ArkSESafeIniValue -Field $Field)
                    [void]$row.Controls.Add($control, 1, 0)
                    $controlMap[$Field.Id] = @{ Field = $Field; Control = $control }
                }
                'RepeatedIniValues' {
                    $control = New-ArkSETextBox -Width $layout.WideControlWidth -Multiline -Height $layout.StringListHeight
                    $repeatedTargetPath = Get-UGSMArkSEIniFieldTargetPath -Paths $paths -Field $Field
                    $control.Tag = [string]$repeatedTargetPath
                    $control.ScrollBars = 'Vertical'
                    $control.AcceptsReturn = $true
                    $control.Lines = @(Get-UGSMArkSEIniRepeatedValues -Path $repeatedTargetPath -Section ([string]$Field.Section) -Key ([string]$Field.Key))
                    [void]$row.Controls.Add($control, 1, 0)
                    $controlMap[$Field.Id] = @{ Field = $Field; Control = $control; Path = $repeatedTargetPath }
                }
                'InstanceText' {
                    $control = New-ArkSEStretchTextBox
                    $control.Text = [string](Get-ArkSESafeInstanceValue -Field $Field)
                    [void]$row.Controls.Add($control, 1, 0)
                    $controlMap[$Field.Id] = @{ Field = $Field; Control = $control }
                }
                'StringList' {
                    $control = New-ArkSETextBox -Width $layout.WideControlWidth -Multiline -Height $layout.StringListHeight
                    $resolvedListPath = Resolve-UGSMArkSEEditorFieldPath -Field $Field -Paths $paths
                    $control.Tag = [string]$resolvedListPath
                    $control.ScrollBars = 'Vertical'
                    $control.AcceptsReturn = $true
                    if (-not [string]::IsNullOrWhiteSpace([string]$resolvedListPath) -and (Test-Path -LiteralPath $resolvedListPath -PathType Leaf)) {
                        $control.Lines = @(Get-Content -LiteralPath $resolvedListPath -ErrorAction SilentlyContinue)
                    }
                    [void]$row.Controls.Add($control, 1, 0)
                    $controlMap[$Field.Id] = @{ Field = $Field; Control = $control; Path = $resolvedListPath }
                }
                'Combo' {
                    $comboHost = New-ArkSENarrowHost
                    $control = New-Object System.Windows.Forms.ComboBox
                    $control.Margin = New-Object System.Windows.Forms.Padding(0)
                    $control.Width = $layout.WideControlWidth
                    $control.Anchor = 'Left'
                    $control.DropDownStyle = if ($Field.ContainsKey('AllowCustom') -and [bool]$Field.AllowCustom) { 'DropDown' } else { 'DropDownList' }
                    $control.AutoCompleteMode = 'SuggestAppend'
                    $control.AutoCompleteSource = 'ListItems'
                    if ($Field.ContainsKey('Options')) {
                        foreach ($option in @($Field.Options)) {
                            [void]$control.Items.Add([string]$option)
                        }
                    }
                    $selectedValue = [string](Get-ArkSESafeIniValue -Field $Field)
                    if ([string]::IsNullOrWhiteSpace($selectedValue) -and $Field.ContainsKey('DefaultValue')) {
                        $selectedValue = [string]$Field.DefaultValue
                    }
                    if (-not [string]::IsNullOrWhiteSpace($selectedValue)) {
                        if ($control.Items.Contains($selectedValue)) {
                            $control.SelectedItem = $selectedValue
                        }
                        elseif ($control.DropDownStyle -eq 'DropDown') {
                            $control.Text = $selectedValue
                        }
                        elseif ($control.Items.Count -gt 0) {
                            $control.SelectedIndex = 0
                        }
                    }
                    elseif ($control.Items.Count -gt 0) {
                        $control.SelectedIndex = 0
                    }
                    [void]$comboHost.Controls.Add($control)
                    [void]$row.Controls.Add($comboHost, 1, 0)
                    $controlMap[$Field.Id] = @{ Field = $Field; Control = $control }
                }
                'ActionButton' {
                    $buttonHost = New-ArkSENarrowHost
                    $control = New-UGSMButton -Text ([string]$Field.ButtonText) -X 0 -Y 0 -Width 220 -Height 30 -BackColor '#253341'
                    $action = $Field.Action
                    $actionFieldId = [string]$Field.Id

                    # Store every value the click handler needs on the button itself. This avoids
                    # PowerShell/WinForms closure loss where nested editor variables can become $null
                    # when the event fires later.
                    $control.Tag = [pscustomobject]@{
                        Instance    = $Instance
                        Paths       = $paths
                        StatusLabel = $StatusLabel
                        ControlMap  = $controlMap
                        Action      = $action
                        ActionId    = $actionFieldId
                        InstanceId  = $arkInstanceId
                    }

                    $control.Add_Click({
                            param($sender, $eventArgs)
                            $state = $sender.Tag
                            $stateInstanceId = if ($state -and -not [string]::IsNullOrWhiteSpace([string]$state.InstanceId)) { [string]$state.InstanceId } else { 'unknown' }
                            $stateActionId = if ($state -and -not [string]::IsNullOrWhiteSpace([string]$state.ActionId)) { [string]$state.ActionId } else { 'unknown' }
                            try {
                                if (-not $state) { throw 'ArkSE editor action state was not attached to the button.' }
                                if (-not $state.Instance) { throw 'ArkSE editor action instance was not attached to the button.' }
                                if (-not $state.Action) { throw 'ArkSE editor action script was not attached to the button.' }

                                Write-UGSMGameArkSELog -Level 'INFO' -Message ("Editor action clicked. InstanceId={0}; ActionId={1}" -f $stateInstanceId, $stateActionId)

                                # Action buttons such as Download Active Mods must use the latest text currently
                                # typed into the editor, even if the user has not clicked Save All yet.
                                if ($stateActionId -in @('SyncActiveMods','SyncClusterProfiles')) {
                                    if (-not $state.ControlMap) { throw 'ArkSE editor action control map was not attached to the button.' }
                                    [void](Save-UGSMGameArkSEInstanceEditor -Instance $state.Instance -EditorState $state.ControlMap)
                                    Write-UGSMGameArkSELog -Level 'DEBUG' -Message ("Editor state saved before action. InstanceId={0}; ActionId={1}" -f $stateInstanceId, $stateActionId)

                                    if ($stateActionId -eq 'SyncClusterProfiles') {
                                        $result = Sync-UGSMGameArkSEClusterProfiles -Instance $state.Instance
                                        if ($state.StatusLabel) { $state.StatusLabel.Text = ('ARKSE cluster sync completed. Profiles updated: {0}; Mods: {1}' -f [int]$result.Updated, [int]$result.ModCount) }
                                        return
                                    }

                                    $activeModsText = ''
                                    try {
                                        if ($state.ControlMap.ContainsKey('ActiveMods')) {
                                            $activeModsControl = $state.ControlMap['ActiveMods'].Control
                                            if ($activeModsControl) { $activeModsText = [string]$activeModsControl.Text }
                                        }
                                    } catch {}

                                    $activeModIds = @(Convert-UGSMGameArkSEModIdList -InputObject @($activeModsText))
                                    Write-UGSMGameArkSELog -Level 'INFO' -Message ("Editor active mods parsed for sync. InstanceId={0}; RawLength={1}; ModCount={2}; Mods={3}" -f $stateInstanceId, $activeModsText.Length, $activeModIds.Count, ($activeModIds -join ','))
                                    $result = Sync-UGSMGameArkSEWorkshopMods -Instance $state.Instance -ModIds $activeModIds
                                    if ($state.StatusLabel) { $state.StatusLabel.Text = ('ARKSE mod sync completed. Mods: {0}' -f (@($result.ModIds).Count)) }
                                    return
                                }

                                & $state.Action $state.Instance $state.Paths $state.StatusLabel
                            }
                            catch {
                                Write-UGSMGameArkSELog -Level 'ERROR' -Message ("Editor action failed. InstanceId={0}; ActionId={1}" -f $stateInstanceId, $stateActionId) -Exception $_.Exception
                                if ($state -and $state.StatusLabel) { $state.StatusLabel.Text = 'ArkSE action failed: ' + $_.Exception.Message }
                            }
                        })
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

                    New-ArkSEElevatedUsersControl -Instance $Instance -Parent $elevatedHost -StatusLabel $StatusLabel | Out-Null
                    [void]$row.Controls.Add($elevatedHost, 1, 0)
                }
                default {
                    $control = New-ArkSEStretchTextBox
                    $control.Text = [string](Get-ArkSESafeIniValue -Field $Field)
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
            $errorLabel = New-UGSMLabel -Text ('ArkSE field row failed: ' + $_.Exception.Message) -X 0 -Y 0 -Width 700 -Height 18 -FontSize 8.5 -Color '#FF7B72'
            $errorLabel.Margin = New-Object System.Windows.Forms.Padding(0, 4, 0, 0)
            [void]$row.Controls.Add($errorLabel, 1, 0)
        }

        [void]$Parent.Controls.Add($row)
    }

    function New-ArkSEEditorContent {
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
            Add-ArkSEFieldRow -Parent $content -Field $field -Instance $Instance -StatusLabel $StatusLabel
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

        $title = New-UGSMLabel -Text ('ArkSE Profile Editor - ' + [string]$Instance.Name) -X 12 -Y 10 -Width 420 -Height 18 -FontSize 10 -Style Bold -Color $Theme.Text
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

            if ($tabDef.PSObject.Properties.Name -contains 'SubTabs' -and @($tabDef.SubTabs).Count -gt 0) {
                $subTabs = New-Object System.Windows.Forms.TabControl
                $subTabs.Dock = 'Fill'
                [void]$tabPage.Controls.Add($subTabs)

                foreach ($subDef in @($tabDef.SubTabs)) {
                    $subPage = New-Object System.Windows.Forms.TabPage
                    $subPage.Text = [string]$subDef.Title
                    $subPage.BackColor = New-UGSMColor '#0B121D'
                    [void]$subTabs.TabPages.Add($subPage)
                    New-ArkSEEditorContent -Parent $subPage -Description ([string]$(if ($subDef.PSObject.Properties.Name -contains 'Description') { $subDef.Description } else { '' })) -Fields @($subDef.Fields)
                }
            }
            else {
                New-ArkSEEditorContent -Parent $tabPage -Description ([string]$(if ($tabDef.PSObject.Properties.Name -contains 'Description') { $tabDef.Description } else { '' })) -Fields @($tabDef.Fields)
            }
        }

        $btnSave.Add_Click({
                try {
                    Write-UGSMGameArkSELog -Level 'INFO' -Message ("Save clicked from editor. InstanceId={0}" -f $arkInstanceId)
                    $result = Save-UGSMGameArkSEInstanceEditor -Instance $Instance -EditorState $controlMap
                    if ($StatusLabel) {
                        $StatusLabel.Text = [string]$(if ($result -and $result.PSObject.Properties.Name -contains 'Message') { $result.Message } else { 'Saved ArkSE profile settings.' })
                    }
                }
                catch {
                    Write-UGSMGameArkSELog -Level 'ERROR' -Message ("Editor save failed. InstanceId={0}" -f $arkInstanceId) -Exception $_.Exception
                    if ($StatusLabel) { $StatusLabel.Text = 'ArkSE save failed: ' + $_.Exception.Message }
                }
            }.GetNewClosure())

        $btnReload.Add_Click({
                try {
                    Write-UGSMGameArkSELog -Level 'INFO' -Message ("Editor reload clicked. InstanceId={0}" -f $arkInstanceId)
                    New-UGSMGameArkSEInstanceEditor -Instance $Instance -Theme $Theme -HostPanel $HostPanel -StatusLabel $StatusLabel | Out-Null
                    if ($StatusLabel) { $StatusLabel.Text = 'ArkSE profile editor reloaded.' }
                }
                catch {
                    Write-UGSMGameArkSELog -Level 'ERROR' -Message ("Editor reload failed. InstanceId={0}" -f $arkInstanceId) -Exception $_.Exception
                    if ($StatusLabel) { $StatusLabel.Text = 'ArkSE reload failed: ' + $_.Exception.Message }
                }
            }.GetNewClosure())

        $root.Tag = [pscustomobject]@{
            Instance   = $Instance
            Paths      = $paths
            ControlMap = $controlMap
            Schema     = $schema
            Status     = $StatusLabel
        }

        if ($StatusLabel) { $StatusLabel.Text = 'ArkSE profile editor loaded.' }
        $arkEditorStopwatch.Stop()
        Write-UGSMGameArkSELog -Level 'INFO' -Message ("Editor creation finished. InstanceId={0}; Tabs={1}; DurationMs={2}" -f $arkInstanceId, @($schema.Tabs).Count, $arkEditorStopwatch.ElapsedMilliseconds)
        return $root
    }
    finally {
        $HostPanel.ResumeLayout()
    }
}

function Invoke-UGSMArkSEOpenPath {
    [CmdletBinding()]
    param(
        [AllowEmptyString()][AllowNull()][string]$Path,
        [switch]$EnsureFile,
        [switch]$EnsureFolder,
        [AllowNull()][System.Windows.Forms.Label]$StatusLabel,
        [string]$OpenedMessage = 'Opened path.'
    )

    if ([string]::IsNullOrWhiteSpace([string]$Path)) {
        throw 'ArkSE open failed: target path was blank.'
    }

    if ($EnsureFolder) {
        if (-not (Test-Path -LiteralPath $Path -PathType Container)) {
            throw ("ArkSE open failed: folder does not exist: {0}" -f $Path)
        }

        Start-Process -FilePath 'explorer.exe' -ArgumentList @($Path) -ErrorAction Stop | Out-Null
        if ($StatusLabel) { $StatusLabel.Text = $OpenedMessage }
        return
    }

    if ($EnsureFile) {
        $parent = Split-Path -Parent $Path
        if ([string]::IsNullOrWhiteSpace([string]$parent)) {
            throw 'ArkSE open failed: file parent path could not be resolved.'
        }

        if (-not (Test-Path -LiteralPath $parent -PathType Container)) {
            throw ("ArkSE open failed: folder does not exist: {0}" -f $parent)
        }

        if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
            throw ("ArkSE open failed: file does not exist: {0}" -f $Path)
        }

        Start-Process -FilePath 'notepad.exe' -ArgumentList @($Path) -ErrorAction Stop | Out-Null
        if ($StatusLabel) { $StatusLabel.Text = $OpenedMessage }
        return
    }

    Start-Process -FilePath 'explorer.exe' -ArgumentList @($Path) -ErrorAction Stop | Out-Null
    if ($StatusLabel) { $StatusLabel.Text = $OpenedMessage }
}

function Resolve-UGSMArkSEEditorPath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$Instance,
        [AllowNull()]$Paths,
        [Parameter(Mandatory)][string]$Target
    )

    if (-not $Instance) {
        throw 'ArkSE action failed: selected instance was null.'
    }

    if (-not $Paths) {
        $Paths = Get-UGSMGameArkSEProfilePaths -Instance $Instance
    }

    if (-not $Paths) {
        throw ("ArkSE action failed: could not resolve paths for '{0}'." -f $Target)
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
        throw ("ArkSE action failed: could not resolve path for '{0}'." -f $Target)
    }

    return [string]$candidate
}

function Invoke-UGSMArkSEEditorAction {
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

    $resolvedPath = Resolve-UGSMArkSEEditorPath -Instance $Instance -Paths $Paths -Target $Target

    Invoke-UGSMArkSEOpenPath `
        -Path $resolvedPath `
        -EnsureFile:$EnsureFile `
        -EnsureFolder:$EnsureFolder `
        -StatusLabel $StatusLabel `
        -OpenedMessage $OpenedMessage
}

function Get-UGSMGameArkSEEditorSchema {
    [CmdletBinding()]
    param()

    $actions = @{
        OpenGameUserSettings          = { param($Instance, $Paths, $StatusLabel) Invoke-UGSMArkSEEditorAction -Instance $Instance -Paths $Paths -Target 'PrimaryIni'     -EnsureFile   -StatusLabel $StatusLabel -OpenedMessage 'Opened GameUserSettings.ini.' }
        OpenGameIni                   = { param($Instance, $Paths, $StatusLabel) Invoke-UGSMArkSEEditorAction -Instance $Instance -Paths $Paths -Target 'SecondaryIni'   -EnsureFile   -StatusLabel $StatusLabel -OpenedMessage 'Opened Game.ini.' }
        OpenProfileFolder             = { param($Instance, $Paths, $StatusLabel) Invoke-UGSMArkSEEditorAction -Instance $Instance -Paths $Paths -Target 'ProfileFolder'  -EnsureFolder -StatusLabel $StatusLabel -OpenedMessage 'Opened the ArkSE profile folder.' }
        OpenConfigFolder              = { param($Instance, $Paths, $StatusLabel) Invoke-UGSMArkSEEditorAction -Instance $Instance -Paths $Paths -Target 'ConfigFolder'   -EnsureFolder -StatusLabel $StatusLabel -OpenedMessage 'Opened the config folder.' }
        OpenDinoCustomizationBuilder  = { param($Instance, $Paths, $StatusLabel) Invoke-UGSMGameArkSEDinoCustomizationBuilder -Instance $Instance -Paths $Paths -StatusLabel $StatusLabel }
        OpenResourceMultiplierBuilder = { param($Instance, $Paths, $StatusLabel) Invoke-UGSMGameArkSEResourceMultiplierBuilder -Instance $Instance -Paths $Paths -StatusLabel $StatusLabel }
    }

    $playerStats = @(
        @{ Suffix = 'Health'; Index = 0 }
        @{ Suffix = 'Stamina'; Index = 1 }
        @{ Suffix = 'Torpidity'; Index = 2 }
        @{ Suffix = 'Oxygen'; Index = 3 }
        @{ Suffix = 'Food'; Index = 4 }
        @{ Suffix = 'Water'; Index = 5 }
        @{ Suffix = 'Temperature'; Index = 6 }
        @{ Suffix = 'Weight'; Index = 7 }
        @{ Suffix = 'MeleeDamage'; Index = 8 }
        @{ Suffix = 'Speed'; Index = 9 }
        @{ Suffix = 'Fortitude'; Index = 10 }
        @{ Suffix = 'CraftingSkill'; Index = 11 }
    )

    $dinoStats = @(
        @{ Suffix = 'Health'; Index = 0 }
        @{ Suffix = 'Stamina'; Index = 1 }
        @{ Suffix = 'Torpidity'; Index = 2 }
        @{ Suffix = 'Oxygen'; Index = 3 }
        @{ Suffix = 'Food'; Index = 4 }
        @{ Suffix = 'Water'; Index = 5 }
        @{ Suffix = 'Temperature'; Index = 6 }
        @{ Suffix = 'Weight'; Index = 7 }
        @{ Suffix = 'MeleeDamage'; Index = 8 }
        @{ Suffix = 'Speed'; Index = 9 }
    )

    $playerStatFields = @(
        foreach ($stat in $playerStats) {
            @{ Id = ('PerLevelStatsMultiplier_Player_{0}' -f $stat.Suffix); Type = 'Number'; File = 'Game.ini'; Section = '/Script/ShooterGame.ShooterGameMode'; Key = ('PerLevelStatsMultiplier_Player[{0}]' -f $stat.Index); Label = ('Player Stat Per-Level Multiplier - ' + $stat.Suffix); DefaultValue = 1; Min = 0; Max = 1000; Decimals = 6; Hint = 'Per-level player stat multiplier.' }
        }
    )

    $dinoWildStatFields = @(
        foreach ($stat in $dinoStats) {
            @{ Id = ('PerLevelStatsMultiplier_DinoWild_{0}' -f $stat.Suffix); Type = 'Number'; File = 'Game.ini'; Section = '/Script/ShooterGame.ShooterGameMode'; Key = ('PerLevelStatsMultiplier_DinoWild[{0}]' -f $stat.Index); Label = ('Wild Dino Stat Per-Level Multiplier - ' + $stat.Suffix); DefaultValue = 1; Min = 0; Max = 1000; Decimals = 6; Hint = 'Per-level wild dino stat multiplier.' }
        }
    )

    $dinoTamedStatFields = @(
        foreach ($stat in $dinoStats) {
            @{ Id = ('PerLevelStatsMultiplier_DinoTamed_{0}' -f $stat.Suffix); Type = 'Number'; File = 'Game.ini'; Section = '/Script/ShooterGame.ShooterGameMode'; Key = ('PerLevelStatsMultiplier_DinoTamed[{0}]' -f $stat.Index); Label = ('Tamed Dino Stat Per-Level Multiplier - ' + $stat.Suffix); DefaultValue = 1; Min = 0; Max = 1000; Decimals = 6; Hint = 'Per-level tamed dino stat multiplier.' }
        }
    )

    $dinoTamedAddFields = @(
        foreach ($stat in $dinoStats) {
            @{ Id = ('PerLevelStatsMultiplier_DinoTamed_Add_{0}' -f $stat.Suffix); Type = 'Number'; File = 'Game.ini'; Section = '/Script/ShooterGame.ShooterGameMode'; Key = ('PerLevelStatsMultiplier_DinoTamed_Add[{0}]' -f $stat.Index); Label = ('Tamed Dino Add Per-Level Multiplier - ' + $stat.Suffix); DefaultValue = 1; Min = 0; Max = 1000; Decimals = 6; Hint = 'Per-level additive tamed dino stat multiplier.' }
        }
    )

    $dinoTamedAffinityFields = @(
        foreach ($stat in $dinoStats) {
            @{ Id = ('PerLevelStatsMultiplier_DinoTamed_Affinity_{0}' -f $stat.Suffix); Type = 'Number'; File = 'Game.ini'; Section = '/Script/ShooterGame.ShooterGameMode'; Key = ('PerLevelStatsMultiplier_DinoTamed_Affinity[{0}]' -f $stat.Index); Label = ('Tamed Dino Affinity Multiplier - ' + $stat.Suffix); DefaultValue = 1; Min = 0; Max = 1000; Decimals = 6; Hint = 'Taming affinity stat multiplier.' }
        }
    )

    return [pscustomobject]@{
        Tabs = @(
            [pscustomobject]@{
                Title       = 'General'
                Description = 'Core browser, access, and quality-of-life settings from GameUserSettings.ini.'
                Fields      = @(
                    @{ Id = 'SessionName'; Type = 'Text'; File = 'GameUserSettings.ini'; Section = 'SessionSettings'; Key = 'SessionName'; Label = 'Server Name'; DefaultValue = 'ArkSE Server'; Hint = 'Server name shown in the browser.' }
                    @{ Id = 'ServerMap'; Type = 'Combo'; File = 'GameUserSettings.ini'; Section = 'ServerSettings'; Key = 'ServerMap'; Label = 'Server Map'; DefaultValue = 'TheIsland'; AllowCustom = $true; Options = @('TheIsland', 'TheCenter', 'ScorchedEarth_P', 'Ragnarok', 'Aberration_P', 'Extinction', 'Valguero_P', 'Genesis', 'Gen2', 'CrystalIsles', 'LostIsland', 'Fjordur'); Hint = 'Pick a standard ARK map or type a custom map token for mod maps.' }
                    @{ Id = 'ServerPassword'; Type = 'Text'; File = 'GameUserSettings.ini'; Section = 'ServerSettings'; Key = 'ServerPassword'; Label = 'Server Password'; DefaultValue = ''; Hint = 'Leave blank for a public server.' }
                    @{ Id = 'SpectatorPassword'; Type = 'Text'; File = 'GameUserSettings.ini'; Section = 'ServerSettings'; Key = 'SpectatorPassword'; Label = 'Spectator Password'; DefaultValue = ''; Hint = 'Optional spectator password.' }
                    @{ Id = 'MaxPlayers'; Type = 'Number'; File = 'GameUserSettings.ini'; Section = '/Script/Engine.GameSession'; Key = 'MaxPlayers'; Label = 'Max Players'; DefaultValue = 70; Min = 1; Max = 256; Decimals = 0; Hint = 'Maximum player count.' }
                    @{ Id = 'ServerPVE'; Type = 'Boolean'; File = 'GameUserSettings.ini'; Section = 'ServerSettings'; Key = 'ServerPVE'; Label = 'Enable PVE'; DefaultValue = $false; Hint = 'Turns the server into PVE mode.' }
                    @{ Id = 'ServerHardcore'; Type = 'Boolean'; File = 'GameUserSettings.ini'; Section = 'ServerSettings'; Key = 'ServerHardcore'; Label = 'Enable Hardcore'; DefaultValue = $false; Hint = 'Hardcore mode changes respawn and survivor handling.' }
                    @{ Id = 'PreventOfflinePvP'; Type = 'Boolean'; File = 'GameUserSettings.ini'; Section = 'ServerSettings'; Key = 'PreventOfflinePvP'; Label = 'Prevent Offline PVP'; DefaultValue = $false; Hint = 'Prevents PVP damage against offline tribes when enabled.' }
                    @{ Id = 'PreventOfflinePvPInterval'; Type = 'Number'; File = 'GameUserSettings.ini'; Section = 'ServerSettings'; Key = 'PreventOfflinePvPInterval'; Label = 'Prevent Offline PVP Interval'; DefaultValue = 0; Min = 0; Max = 86400; Decimals = 0; Hint = 'Delay before offline PVP protection applies.' }
                    @{ Id = 'AllowAnyoneBabyImprintCuddle'; Type = 'Boolean'; File = 'GameUserSettings.ini'; Section = 'ServerSettings'; Key = 'AllowAnyoneBabyImprintCuddle'; Label = 'Allow Anyone Baby Imprint Cuddle'; DefaultValue = $false; Hint = 'Lets tribe members imprint babies started by someone else.' }
                    @{ Id = 'DisableStructurePlacementCollision'; Type = 'Boolean'; File = 'GameUserSettings.ini'; Section = 'ServerSettings'; Key = 'DisableStructurePlacementCollision'; Label = 'Disable Structure Placement Collision'; DefaultValue = $false; Hint = 'Loosens build placement restrictions.' }
                    @{ Id = 'FastDecayUnsnappedCoreStructures'; Type = 'Boolean'; File = 'GameUserSettings.ini'; Section = 'ServerSettings'; Key = 'FastDecayUnsnappedCoreStructures'; Label = 'Fast Decay Unsnapped Core Structures'; DefaultValue = $false; Hint = 'Speeds decay on unsupported structures.' }
                    @{ Id = 'UseCorpseLocator'; Type = 'Boolean'; File = 'GameUserSettings.ini'; Section = 'ServerSettings'; Key = 'UseCorpseLocator'; Label = 'Use Corpse Locator'; DefaultValue = $false; Hint = 'Shows corpse recovery beam or locator support.' }
                    @{ Id = 'AllowCaveBuildingPvE'; Type = 'Boolean'; File = 'GameUserSettings.ini'; Section = 'ServerSettings'; Key = 'AllowCaveBuildingPvE'; Label = 'Allow Cave Building PVE'; DefaultValue = $false; Hint = 'Allows cave building in PVE.' }
                    @{ Id = 'AllowCaveBuildingPvP'; Type = 'Boolean'; File = 'GameUserSettings.ini'; Section = 'ServerSettings'; Key = 'AllowCaveBuildingPvP'; Label = 'Allow Cave Building PVP'; DefaultValue = $false; Hint = 'Allows cave building in PVP.' }
                    @{ Id = 'AdminLogging'; Type = 'Boolean'; File = 'GameUserSettings.ini'; Section = 'ServerSettings'; Key = 'AdminLogging'; Label = 'Admin Logging'; DefaultValue = $false; Hint = 'Write admin commands to the logs.' }
                    @{ Id = 'MessageOfTheDayMessage'; Type = 'MultilineText'; File = 'GameUserSettings.ini'; Section = 'MessageOfTheDay'; Key = 'Message'; Label = 'Message Of The Day'; DefaultValue = ''; Hint = 'Server MOTD text.' }
                    @{ Id = 'MessageOfTheDayDuration'; Type = 'Number'; File = 'GameUserSettings.ini'; Section = 'MessageOfTheDay'; Key = 'Duration'; Label = 'MOTD Duration'; DefaultValue = 20; Min = 0; Max = 600; Decimals = 0; Hint = 'How long the message of the day displays.' }
                )
            }

            [pscustomobject]@{
                Title       = 'Mods & Cluster'
                Description = 'ARK workshop mods and cross-ARK cluster settings. Active mods are downloaded once through SteamCMD and launched by Workshop ID.'
                Fields      = @(
                    @{ Id = 'ActiveMods'; Type = 'Text'; File = 'GameUserSettings.ini'; Section = 'ServerSettings'; Key = 'ActiveMods'; Label = 'Active Mod IDs / Workshop URLs'; DefaultValue = ''; Hint = 'Comma-separated Steam Workshop mod IDs or full Steam Workshop URLs. UGSM extracts the IDs and passes them as GameModIds on launch.' }
                    @{ Id = 'SyncActiveMods'; Type = 'ActionButton'; Label = 'Download / Sync Active Mods'; ButtonText = 'Download Active Mods'; Action = { param($Instance, $Paths, $StatusLabel) try { $result = Sync-UGSMGameArkSEWorkshopMods -Instance $Instance; if ($StatusLabel) { $StatusLabel.Text = ('ARKSE mod sync completed. Mods: {0}' -f (@($result.ModIds).Count)) } } catch { if ($StatusLabel) { $StatusLabel.Text = 'ARKSE mod sync failed: ' + $_.Exception.Message }; throw } }; Hint = 'Downloads every Workshop ID or full Steam Workshop URL listed in Active Mod IDs using SteamCMD.' }
                    @{ Id = 'UGSMClusterEnabled'; Type = 'Boolean'; File = 'GameUserSettings.ini'; Section = 'ServerSettings'; Key = 'UGSMClusterEnabled'; Label = 'Enable Cross-ARK Cluster'; DefaultValue = $false; Hint = 'Adds cluster launch arguments when the server starts.' }
                    @{ Id = 'UGSMClusterId'; Type = 'Text'; File = 'GameUserSettings.ini'; Section = 'ServerSettings'; Key = 'UGSMClusterId'; Label = 'Cluster ID'; DefaultValue = ''; Hint = 'Shared cluster ID for every map in the same ARK cluster.' }
                    @{ Id = 'UGSMClusterDirectory'; Type = 'Text'; File = 'GameUserSettings.ini'; Section = 'ServerSettings'; Key = 'UGSMClusterDirectory'; Label = 'Cluster Directory'; DefaultValue = ''; Hint = 'Shared transfer folder. Leave blank to auto-use %UGSM_PROFILES%\ARKSE\Clusters\<Cluster ID>.' }
                    @{ Id = 'UGSMNoTransferFromFiltering'; Type = 'Boolean'; File = 'GameUserSettings.ini'; Section = 'ServerSettings'; Key = 'UGSMNoTransferFromFiltering'; Label = 'No Transfer From Filtering'; DefaultValue = $false; Hint = 'Adds -NoTransferFromFiltering to allow transfers from other servers in the cluster.' }
                    @{ Id = 'UGSMUseSharedClusterMods'; Type = 'Boolean'; File = 'GameUserSettings.ini'; Section = 'ServerSettings'; Key = 'UGSMUseSharedClusterMods'; Label = 'Use Shared Cluster Mods'; DefaultValue = $true; Hint = 'Cluster sync now always copies active mods for same-cluster profiles. Map and port values are never synced.' }
                    @{ Id = 'SyncClusterProfiles'; Type = 'ActionButton'; Label = 'Sync Cluster Profiles'; ButtonText = 'Sync Cluster Mods / Settings'; Action = { param($Instance, $Paths, $StatusLabel) try { $result = Sync-UGSMGameArkSEClusterProfiles -Instance $Instance; if ($StatusLabel) { $StatusLabel.Text = ('ARKSE cluster sync completed. Profiles updated: {0}; Mods: {1}; Settings: {2}' -f [int]$result.Updated, [int]$result.ModCount, ([int]$result.CopiedGameUserSettings + [int]$result.CopiedGameIni)) } } catch { if ($StatusLabel) { $StatusLabel.Text = 'ARKSE cluster sync failed: ' + $_.Exception.Message }; throw } }; Hint = 'Copies all cluster-safe ARK settings and active mod IDs to other ARKSE profiles with the same Cluster ID. Map, ports, bind IP, and save identity are never synced.' }
                )
            }

            [pscustomobject]@{
                Title       = 'Network & Save'
                Description = 'Ports, RCON, save cycle, browser network values, and session info.'
                Fields      = @(
                    @{ Id = 'Port'; Type = 'Number'; File = 'GameUserSettings.ini'; Section = 'ServerSettings'; Key = 'Port'; Label = 'Game Port'; DefaultValue = 7777; Min = 1; Max = 65535; Decimals = 0; Hint = 'Main game port. Read from UGSM assigned ports.' }
                    @{ Id = 'QueryPort'; Type = 'Number'; File = 'GameUserSettings.ini'; Section = 'ServerSettings'; Key = 'QueryPort'; Label = 'Query Port'; DefaultValue = 27015; Min = 1; Max = 65535; Decimals = 0; Hint = 'Steam query port. Read from UGSM assigned ports.' }
                    @{ Id = 'PeerPort'; Type = 'Number'; File = 'GameUserSettings.ini'; Section = 'ServerSettings'; Key = 'PeerPort'; Label = 'Peer Port'; DefaultValue = 7778; Min = 1; Max = 65535; Decimals = 0; Hint = 'ARK peer/raw UDP port. Read from UGSM assigned ports.' }
                    @{ Id = 'MultiHome'; Type = 'Text'; File = 'GameUserSettings.ini'; Section = 'SessionSettings'; Key = 'MultiHome'; Label = 'MultiHome'; DefaultValue = ''; Hint = 'Optional bind IP address.' }
                    @{ Id = 'RCONEnabled'; Type = 'Boolean'; File = 'GameUserSettings.ini'; Section = 'ServerSettings'; Key = 'RCONEnabled'; Label = 'Enable RCON'; DefaultValue = $true; Hint = 'Required for remote console access.' }
                    @{ Id = 'RCONPort'; Type = 'Number'; File = 'GameUserSettings.ini'; Section = 'ServerSettings'; Key = 'RCONPort'; Label = 'RCON Port'; DefaultValue = 27020; Min = 1; Max = 65535; Decimals = 0; Hint = 'RCON port number. Read from UGSM assigned ports.' }
                    @{ Id = 'RCONServerGameLogBuffer'; Type = 'Number'; File = 'GameUserSettings.ini'; Section = 'ServerSettings'; Key = 'RCONServerGameLogBuffer'; Label = 'RCON Server Game Log Buffer'; DefaultValue = 600; Min = 0; Max = 100000; Decimals = 0; Hint = 'RCON log history buffer size.' }
                    @{ Id = 'AutoSavePeriodMinutes'; Type = 'Number'; File = 'GameUserSettings.ini'; Section = 'ServerSettings'; Key = 'AutoSavePeriodMinutes'; Label = 'Auto-Save Period (Minutes)'; DefaultValue = 15; Min = 1; Max = 1440; Decimals = 0; Hint = 'Server auto-save period in minutes.' }
                    @{ Id = 'KickIdlePlayersPeriod'; Type = 'Number'; File = 'GameUserSettings.ini'; Section = 'ServerSettings'; Key = 'KickIdlePlayersPeriod'; Label = 'Idle Kick Period'; DefaultValue = 3600; Min = 0; Max = 86400; Decimals = 0; Hint = 'Seconds before idle players are kicked.' }
                    @{ Id = 'AltSaveDirectoryName'; Type = 'Text'; File = 'GameUserSettings.ini'; Section = 'ServerSettings'; Key = 'AltSaveDirectoryName'; Label = 'Alternate Save Directory Name'; DefaultValue = ''; Hint = 'Usually blank. Only set if you intentionally need an alternate save directory.' }
                    @{ Id = 'ListenServerTetherDistanceMultiplier'; Type = 'Number'; File = 'GameUserSettings.ini'; Section = 'ServerSettings'; Key = 'ListenServerTetherDistanceMultiplier'; Label = 'Listen Server Tether Distance Multiplier'; DefaultValue = 1; Min = 0; Max = 1000; Decimals = 6; Hint = 'Mostly unused on dedicated, but included for parity.' }
                    @{ Id = 'AllowSharedConnections'; Type = 'Boolean'; File = 'GameUserSettings.ini'; Section = 'ServerSettings'; Key = 'AllowSharedConnections'; Label = 'Allow Shared Connections'; DefaultValue = $true; Hint = 'Allows multiple players from the same public IP.' }
                )
            }

            [pscustomobject]@{
                Title       = 'Player Rules'
                Description = 'Common player experience toggles from GameUserSettings.ini and Game.ini.'
                Fields      = @(
                    @{ Id = 'ShowMapPlayerLocation'; Type = 'Boolean'; File = 'GameUserSettings.ini'; Section = 'ServerSettings'; Key = 'ShowMapPlayerLocation'; Label = 'Show Player Map Location'; DefaultValue = $true; Hint = 'Show player location on the map.' }
                    @{ Id = 'AllowThirdPersonPlayer'; Type = 'Boolean'; File = 'GameUserSettings.ini'; Section = 'ServerSettings'; Key = 'AllowThirdPersonPlayer'; Label = 'Allow Third Person'; DefaultValue = $true; Hint = 'Allow third-person camera.' }
                    @{ Id = 'ServerCrosshair'; Type = 'Boolean'; File = 'GameUserSettings.ini'; Section = 'ServerSettings'; Key = 'ServerCrosshair'; Label = 'Enable Crosshair'; DefaultValue = $true; Hint = 'Show the crosshair.' }
                    @{ Id = 'AllowFlyerCarryPvE'; Type = 'Boolean'; File = 'GameUserSettings.ini'; Section = 'ServerSettings'; Key = 'AllowFlyerCarryPvE'; Label = 'Allow Flyer Carry In PVE'; DefaultValue = $false; Hint = 'Lets flyers carry creatures or players in PVE.' }
                    @{ Id = 'DisableDinoDecayPvE'; Type = 'Boolean'; File = 'GameUserSettings.ini'; Section = 'ServerSettings'; Key = 'DisableDinoDecayPvE'; Label = 'Disable Dino Decay In PVE'; DefaultValue = $false; Hint = 'Prevents dino auto-decay in PVE.' }
                    @{ Id = 'AllowHitMarkers'; Type = 'Boolean'; File = 'GameUserSettings.ini'; Section = 'ServerSettings'; Key = 'AllowHitMarkers'; Label = 'Allow Hit Markers'; DefaultValue = $true; Hint = 'Shows hit markers when damage is dealt.' }
                    @{ Id = 'AlwaysNotifyPlayerJoined'; Type = 'Boolean'; File = 'GameUserSettings.ini'; Section = 'ServerSettings'; Key = 'AlwaysNotifyPlayerJoined'; Label = 'Always Notify Player Joined'; DefaultValue = $false; Hint = 'Forces join notifications.' }
                    @{ Id = 'AlwaysNotifyPlayerLeft'; Type = 'Boolean'; File = 'GameUserSettings.ini'; Section = 'ServerSettings'; Key = 'AlwaysNotifyPlayerLeft'; Label = 'Always Notify Player Left'; DefaultValue = $false; Hint = 'Forces leave notifications.' }
                    @{ Id = 'bPvEDisableFriendlyFire'; Type = 'Boolean'; File = 'GameUserSettings.ini'; Section = 'ServerSettings'; Key = 'bPvEDisableFriendlyFire'; Label = 'Disable Friendly Fire In PVE'; DefaultValue = $false; Hint = 'Blocks tribe or friendly damage in PVE.' }
                    @{ Id = 'bDisableFriendlyFire'; Type = 'Boolean'; File = 'Game.ini'; Section = '/Script/ShooterGame.ShooterGameMode'; Key = 'bDisableFriendlyFire'; Label = 'Disable Friendly Fire'; DefaultValue = $false; Hint = 'Game.ini friendly fire override.' }
                    @{ Id = 'bAllowUnlimitedRespecs'; Type = 'Boolean'; File = 'Game.ini'; Section = '/Script/ShooterGame.ShooterGameMode'; Key = 'bAllowUnlimitedRespecs'; Label = 'Allow Unlimited Respecs'; DefaultValue = $false; Hint = 'Allows players to use mindwipe repeatedly.' }
                    @{ Id = 'bAllowCustomRecipes'; Type = 'Boolean'; File = 'Game.ini'; Section = '/Script/ShooterGame.ShooterGameMode'; Key = 'bAllowCustomRecipes'; Label = 'Allow Custom Recipes'; DefaultValue = $true; Hint = 'Enables custom recipe crafting.' }
                    @{ Id = 'bAllowFlyerSpeedLeveling'; Type = 'Boolean'; File = 'Game.ini'; Section = '/Script/ShooterGame.ShooterGameMode'; Key = 'bAllowFlyerSpeedLeveling'; Label = 'Allow Flyer Speed Leveling'; DefaultValue = $false; Hint = 'Lets flyers level movement speed again.' }
                    @{ Id = 'bUseDinoLevelUpAnimations'; Type = 'Boolean'; File = 'Game.ini'; Section = '/Script/ShooterGame.ShooterGameMode'; Key = 'bUseDinoLevelUpAnimations'; Label = 'Use Dino Level Up Animations'; DefaultValue = $true; Hint = 'Keep level-up animation behavior enabled.' }
                    @{ Id = 'PlayerCharacterWaterDrainMultiplier'; Type = 'Number'; File = 'GameUserSettings.ini'; Section = 'ServerSettings'; Key = 'PlayerCharacterWaterDrainMultiplier'; Label = 'Player Water Drain Multiplier'; DefaultValue = 1; Min = 0; Max = 1000; Decimals = 6; Hint = 'Multiplier for player water drain.' }
                    @{ Id = 'PlayerCharacterFoodDrainMultiplier'; Type = 'Number'; File = 'GameUserSettings.ini'; Section = 'ServerSettings'; Key = 'PlayerCharacterFoodDrainMultiplier'; Label = 'Player Food Drain Multiplier'; DefaultValue = 1; Min = 0; Max = 1000; Decimals = 6; Hint = 'Multiplier for player food drain.' }
                    @{ Id = 'PlayerCharacterStaminaDrainMultiplier'; Type = 'Number'; File = 'GameUserSettings.ini'; Section = 'ServerSettings'; Key = 'PlayerCharacterStaminaDrainMultiplier'; Label = 'Player Stamina Drain Multiplier'; DefaultValue = 1; Min = 0; Max = 1000; Decimals = 6; Hint = 'Multiplier for player stamina drain.' }
                    @{ Id = 'PlayerCharacterHealthRecoveryMultiplier'; Type = 'Number'; File = 'GameUserSettings.ini'; Section = 'ServerSettings'; Key = 'PlayerCharacterHealthRecoveryMultiplier'; Label = 'Player Health Recovery Multiplier'; DefaultValue = 1; Min = 0; Max = 1000; Decimals = 6; Hint = 'Multiplier for passive health recovery.' }
                )
            }

            [pscustomobject]@{
                Title       = 'Rates'
                Description = 'High-use gameplay and world rate multipliers.'
                Fields      = @(
                    @{ Id = 'XPMultiplier'; Type = 'Number'; File = 'GameUserSettings.ini'; Section = 'ServerSettings'; Key = 'XPMultiplier'; Label = 'XP Multiplier'; DefaultValue = 1; Min = 0; Max = 1000; Decimals = 6; Hint = 'Global XP gain multiplier.' }
                    @{ Id = 'TamingSpeedMultiplier'; Type = 'Number'; File = 'GameUserSettings.ini'; Section = 'ServerSettings'; Key = 'TamingSpeedMultiplier'; Label = 'Taming Speed Multiplier'; DefaultValue = 1; Min = 0; Max = 1000; Decimals = 6; Hint = 'Multiplier for taming speed.' }
                    @{ Id = 'HarvestAmountMultiplier'; Type = 'Number'; File = 'GameUserSettings.ini'; Section = 'ServerSettings'; Key = 'HarvestAmountMultiplier'; Label = 'Harvest Amount Multiplier'; DefaultValue = 1; Min = 0; Max = 1000; Decimals = 6; Hint = 'Multiplier for harvested item amount.' }
                    @{ Id = 'HarvestHealthMultiplier'; Type = 'Number'; File = 'GameUserSettings.ini'; Section = 'ServerSettings'; Key = 'HarvestHealthMultiplier'; Label = 'Harvest Health Multiplier'; DefaultValue = 1; Min = 0; Max = 1000; Decimals = 6; Hint = 'Multiplier for node health.' }
                    @{ Id = 'PlayerHarvestingDamageMultiplier'; Type = 'Number'; File = 'Game.ini'; Section = '/Script/ShooterGame.ShooterGameMode'; Key = 'PlayerHarvestingDamageMultiplier'; Label = 'Player Harvesting Damage Multiplier'; DefaultValue = 1; Min = 0; Max = 1000; Decimals = 6; Hint = 'Multiplier for harvesting with players.' }
                    @{ Id = 'DinoHarvestingDamageMultiplier'; Type = 'Number'; File = 'Game.ini'; Section = '/Script/ShooterGame.ShooterGameMode'; Key = 'DinoHarvestingDamageMultiplier'; Label = 'Dino Harvesting Damage Multiplier'; DefaultValue = 1; Min = 0; Max = 1000; Decimals = 6; Hint = 'Multiplier for harvesting with dinos.' }
                    @{ Id = 'PlayerDamageMultiplier'; Type = 'Number'; File = 'GameUserSettings.ini'; Section = 'ServerSettings'; Key = 'PlayerDamageMultiplier'; Label = 'Player Damage Multiplier'; DefaultValue = 1; Min = 0; Max = 1000; Decimals = 6; Hint = 'Global player outgoing damage multiplier.' }
                    @{ Id = 'PlayerResistanceMultiplier'; Type = 'Number'; File = 'GameUserSettings.ini'; Section = 'ServerSettings'; Key = 'PlayerResistanceMultiplier'; Label = 'Player Resistance Multiplier'; DefaultValue = 1; Min = 0; Max = 1000; Decimals = 6; Hint = 'Global player incoming damage resistance multiplier.' }
                    @{ Id = 'DinoDamageMultiplier'; Type = 'Number'; File = 'GameUserSettings.ini'; Section = 'ServerSettings'; Key = 'DinoDamageMultiplier'; Label = 'Dino Damage Multiplier'; DefaultValue = 1; Min = 0; Max = 1000; Decimals = 6; Hint = 'Global dino outgoing damage multiplier.' }
                    @{ Id = 'DinoResistanceMultiplier'; Type = 'Number'; File = 'GameUserSettings.ini'; Section = 'ServerSettings'; Key = 'DinoResistanceMultiplier'; Label = 'Dino Resistance Multiplier'; DefaultValue = 1; Min = 0; Max = 1000; Decimals = 6; Hint = 'Global dino resistance multiplier.' }
                    @{ Id = 'ResourceRespawnPeriodMultiplier'; Type = 'Number'; File = 'GameUserSettings.ini'; Section = 'ServerSettings'; Key = 'ResourceRespawnPeriodMultiplier'; Label = 'Resource Respawn Period Multiplier'; DefaultValue = 1; Min = 0; Max = 1000; Decimals = 6; Hint = 'Resource respawn timer multiplier.' }
                    @{ Id = 'SupplyCrateLootQualityMultiplier'; Type = 'Number'; File = 'Game.ini'; Section = '/Script/ShooterGame.ShooterGameMode'; Key = 'SupplyCrateLootQualityMultiplier'; Label = 'Supply Crate Loot Quality Multiplier'; DefaultValue = 1; Min = 0; Max = 1000; Decimals = 6; Hint = 'Global crate quality multiplier.' }
                    @{ Id = 'FishingLootQualityMultiplier'; Type = 'Number'; File = 'Game.ini'; Section = '/Script/ShooterGame.ShooterGameMode'; Key = 'FishingLootQualityMultiplier'; Label = 'Fishing Loot Quality Multiplier'; DefaultValue = 1; Min = 0; Max = 1000; Decimals = 6; Hint = 'Fishing loot quality multiplier.' }
                    @{ Id = 'FuelConsumptionIntervalMultiplier'; Type = 'Number'; File = 'Game.ini'; Section = '/Script/ShooterGame.ShooterGameMode'; Key = 'FuelConsumptionIntervalMultiplier'; Label = 'Fuel Consumption Interval Multiplier'; DefaultValue = 1; Min = 0; Max = 1000; Decimals = 6; Hint = 'Multiplier for fuel burn interval.' }
                    @{ Id = 'GlobalPoweredBatteryDurabilityDecreasePerSecond'; Type = 'Number'; File = 'Game.ini'; Section = '/Script/ShooterGame.ShooterGameMode'; Key = 'GlobalPoweredBatteryDurabilityDecreasePerSecond'; Label = 'Powered Battery Durability Decrease Per Second'; DefaultValue = 0; Min = 0; Max = 1000; Decimals = 6; Hint = 'Override for battery durability drain.' }
                    @{ Id = 'DayCycleSpeedScale'; Type = 'Number'; File = 'GameUserSettings.ini'; Section = 'ServerSettings'; Key = 'DayCycleSpeedScale'; Label = 'Day Cycle Speed Scale'; DefaultValue = 1; Min = 0; Max = 1000; Decimals = 6; Hint = 'How quickly the full day progresses.' }
                    @{ Id = 'DayTimeSpeedScale'; Type = 'Number'; File = 'GameUserSettings.ini'; Section = 'ServerSettings'; Key = 'DayTimeSpeedScale'; Label = 'Day Time Speed Scale'; DefaultValue = 1; Min = 0; Max = 1000; Decimals = 6; Hint = 'How quickly daytime progresses.' }
                    @{ Id = 'NightTimeSpeedScale'; Type = 'Number'; File = 'GameUserSettings.ini'; Section = 'ServerSettings'; Key = 'NightTimeSpeedScale'; Label = 'Night Time Speed Scale'; DefaultValue = 1; Min = 0; Max = 1000; Decimals = 6; Hint = 'How quickly nighttime progresses.' }
                )
            }

            [pscustomobject]@{
                Title       = 'Breeding'
                Description = 'Breeding, mating, and baby raising values.'
                Fields      = @(
                    @{ Id = 'MatingIntervalMultiplier'; Type = 'Number'; File = 'Game.ini'; Section = '/Script/ShooterGame.ShooterGameMode'; Key = 'MatingIntervalMultiplier'; Label = 'Mating Interval Multiplier'; DefaultValue = 1; Min = 0; Max = 1000; Decimals = 6; Hint = 'Time between mating attempts.' }
                    @{ Id = 'MatingSpeedMultiplier'; Type = 'Number'; File = 'Game.ini'; Section = '/Script/ShooterGame.ShooterGameMode'; Key = 'MatingSpeedMultiplier'; Label = 'Mating Speed Multiplier'; DefaultValue = 1; Min = 0; Max = 1000; Decimals = 6; Hint = 'How quickly mating progresses.' }
                    @{ Id = 'EggHatchSpeedMultiplier'; Type = 'Number'; File = 'Game.ini'; Section = '/Script/ShooterGame.ShooterGameMode'; Key = 'EggHatchSpeedMultiplier'; Label = 'Egg Hatch Speed Multiplier'; DefaultValue = 1; Min = 0; Max = 1000; Decimals = 6; Hint = 'Egg hatch speed multiplier.' }
                    @{ Id = 'BabyMatureSpeedMultiplier'; Type = 'Number'; File = 'Game.ini'; Section = '/Script/ShooterGame.ShooterGameMode'; Key = 'BabyMatureSpeedMultiplier'; Label = 'Baby Mature Speed Multiplier'; DefaultValue = 1; Min = 0; Max = 1000; Decimals = 6; Hint = 'Baby growth speed multiplier.' }
                    @{ Id = 'BabyImprintingStatScaleMultiplier'; Type = 'Number'; File = 'Game.ini'; Section = '/Script/ShooterGame.ShooterGameMode'; Key = 'BabyImprintingStatScaleMultiplier'; Label = 'Baby Imprinting Stat Scale Multiplier'; DefaultValue = 1; Min = 0; Max = 1000; Decimals = 6; Hint = 'Bonus scaling from imprinting.' }
                    @{ Id = 'BabyCuddleIntervalMultiplier'; Type = 'Number'; File = 'GameUserSettings.ini'; Section = 'ServerSettings'; Key = 'BabyCuddleIntervalMultiplier'; Label = 'Baby Cuddle Interval Multiplier'; DefaultValue = 1; Min = 0; Max = 1000; Decimals = 6; Hint = 'Time between cuddle requests.' }
                    @{ Id = 'BabyCuddleGracePeriodMultiplier'; Type = 'Number'; File = 'GameUserSettings.ini'; Section = 'ServerSettings'; Key = 'BabyCuddleGracePeriodMultiplier'; Label = 'Baby Cuddle Grace Period Multiplier'; DefaultValue = 1; Min = 0; Max = 1000; Decimals = 6; Hint = 'Grace period around cuddle windows.' }
                    @{ Id = 'BabyCuddleLoseImprintQualitySpeedMultiplier'; Type = 'Number'; File = 'GameUserSettings.ini'; Section = 'ServerSettings'; Key = 'BabyCuddleLoseImprintQualitySpeedMultiplier'; Label = 'Baby Cuddle Lose Imprint Quality Speed Multiplier'; DefaultValue = 1; Min = 0; Max = 1000; Decimals = 6; Hint = 'How fast missed cuddles lose imprint quality.' }
                    @{ Id = 'BabyFoodConsumptionSpeedMultiplier'; Type = 'Number'; File = 'GameUserSettings.ini'; Section = 'ServerSettings'; Key = 'BabyFoodConsumptionSpeedMultiplier'; Label = 'Baby Food Consumption Speed Multiplier'; DefaultValue = 1; Min = 0; Max = 1000; Decimals = 6; Hint = 'Baby food drain multiplier.' }
                    @{ Id = 'LayEggIntervalMultiplier'; Type = 'Number'; File = 'GameUserSettings.ini'; Section = 'ServerSettings'; Key = 'LayEggIntervalMultiplier'; Label = 'Lay Egg Interval Multiplier'; DefaultValue = 1; Min = 0; Max = 1000; Decimals = 6; Hint = 'How often creatures lay eggs.' }
                    @{ Id = 'PoopIntervalMultiplier'; Type = 'Number'; File = 'GameUserSettings.ini'; Section = 'ServerSettings'; Key = 'PoopIntervalMultiplier'; Label = 'Poop Interval Multiplier'; DefaultValue = 1; Min = 0; Max = 1000; Decimals = 6; Hint = 'How often creatures poop.' }
                )
            }

            [pscustomobject]@{
                Title       = 'Creature Multipliers'
                Description = 'Creature limits, tame controls, and core creature/world progression values.'
                Fields      = @(
                    @{ Id = 'DinoCountMultiplier'; Type = 'Number'; File = 'GameUserSettings.ini'; Section = 'ServerSettings'; Key = 'DinoCountMultiplier'; Label = 'Dino Count Multiplier'; DefaultValue = 1; Min = 0; Max = 1000; Decimals = 6; Hint = 'Overall creature population multiplier.' }
                    @{ Id = 'MaxTamedDinos'; Type = 'Number'; File = 'GameUserSettings.ini'; Section = 'ServerSettings'; Key = 'MaxTamedDinos'; Label = 'Max Tamed Dinos'; DefaultValue = 5000; Min = 0; Max = 1000000; Decimals = 0; Hint = 'Server tame cap.' }
                    @{ Id = 'MaxPersonalTamedDinos'; Type = 'Number'; File = 'GameUserSettings.ini'; Section = 'ServerSettings'; Key = 'MaxPersonalTamedDinos'; Label = 'Max Personal Tamed Dinos'; DefaultValue = 0; Min = 0; Max = 1000000; Decimals = 0; Hint = 'Per-player tame cap if used.' }
                    @{ Id = 'TamedDinoCharacterFoodDrainMultiplier'; Type = 'Number'; File = 'GameUserSettings.ini'; Section = 'ServerSettings'; Key = 'TamedDinoCharacterFoodDrainMultiplier'; Label = 'Tamed Dino Food Drain Multiplier'; DefaultValue = 1; Min = 0; Max = 1000; Decimals = 6; Hint = 'Food drain multiplier for tamed dinos.' }
                    @{ Id = 'WildDinoCharacterFoodDrainMultiplier'; Type = 'Number'; File = 'GameUserSettings.ini'; Section = 'ServerSettings'; Key = 'WildDinoCharacterFoodDrainMultiplier'; Label = 'Wild Dino Food Drain Multiplier'; DefaultValue = 1; Min = 0; Max = 1000; Decimals = 6; Hint = 'Food drain multiplier for wild dinos.' }
                    @{ Id = 'TamedDinoCharacterStaminaDrainMultiplier'; Type = 'Number'; File = 'GameUserSettings.ini'; Section = 'ServerSettings'; Key = 'TamedDinoCharacterStaminaDrainMultiplier'; Label = 'Tamed Dino Stamina Drain Multiplier'; DefaultValue = 1; Min = 0; Max = 1000; Decimals = 6; Hint = 'Stamina drain multiplier for tamed dinos.' }
                    @{ Id = 'DinoCharacterHealthRecoveryMultiplier'; Type = 'Number'; File = 'GameUserSettings.ini'; Section = 'ServerSettings'; Key = 'DinoCharacterHealthRecoveryMultiplier'; Label = 'Dino Health Recovery Multiplier'; DefaultValue = 1; Min = 0; Max = 1000; Decimals = 6; Hint = 'Health recovery multiplier for dinos.' }
                    @{ Id = 'DinoCharacterFoodDrainMultiplier'; Type = 'Number'; File = 'GameUserSettings.ini'; Section = 'ServerSettings'; Key = 'DinoCharacterFoodDrainMultiplier'; Label = 'Dino Food Drain Multiplier'; DefaultValue = 1; Min = 0; Max = 1000; Decimals = 6; Hint = 'General dino food drain multiplier.' }
                    @{ Id = 'OverrideOfficialDifficulty'; Type = 'Number'; File = 'GameUserSettings.ini'; Section = 'ServerSettings'; Key = 'OverrideOfficialDifficulty'; Label = 'Override Official Difficulty'; DefaultValue = 0; Min = 0; Max = 1000; Decimals = 6; Hint = 'Common difficulty override value.' }
                    @{ Id = 'DifficultyOffset'; Type = 'Number'; File = 'GameUserSettings.ini'; Section = 'ServerSettings'; Key = 'DifficultyOffset'; Label = 'Difficulty Offset'; DefaultValue = 1; Min = 0; Max = 1000; Decimals = 6; Hint = 'General level distribution difficulty.' }
                    @{ Id = 'bUseSingleplayerSettings'; Type = 'Boolean'; File = 'GameUserSettings.ini'; Section = 'ServerSettings'; Key = 'bUseSingleplayerSettings'; Label = 'Use Singleplayer Settings'; DefaultValue = $false; Hint = 'Applies singleplayer tuned values to the dedicated server.' }
                    @{ Id = 'bAllowUnclaimDinos'; Type = 'Boolean'; File = 'Game.ini'; Section = '/Script/ShooterGame.ShooterGameMode'; Key = 'bAllowUnclaimDinos'; Label = 'Allow Unclaim Dinos'; DefaultValue = $true; Hint = 'Allow players to unclaim tamed dinos.' }
                    @{ Id = 'bDisableLootCrates'; Type = 'Boolean'; File = 'Game.ini'; Section = '/Script/ShooterGame.ShooterGameMode'; Key = 'bDisableLootCrates'; Label = 'Disable Loot Crates'; DefaultValue = $false; Hint = 'Disable standard loot crates globally.' }
                ) + $playerStatFields + $dinoWildStatFields + $dinoTamedStatFields + $dinoTamedAddFields + $dinoTamedAffinityFields
            }

            [pscustomobject]@{
                Title       = 'Structures & Tribe'
                Description = 'Building, tribe limits, and structure behavior.'
                Fields      = @(
                    @{ Id = 'TheMaxStructuresInRange'; Type = 'Number'; File = 'GameUserSettings.ini'; Section = 'ServerSettings'; Key = 'TheMaxStructuresInRange'; Label = 'Max Structures In Range'; DefaultValue = 10500; Min = 0; Max = 100000000; Decimals = 0; Hint = 'Local structure cap.' }
                    @{ Id = 'StructurePreventResourceRadiusMultiplier'; Type = 'Number'; File = 'GameUserSettings.ini'; Section = 'ServerSettings'; Key = 'StructurePreventResourceRadiusMultiplier'; Label = 'Structure Prevent Resource Radius Multiplier'; DefaultValue = 1; Min = 0; Max = 1000; Decimals = 6; Hint = 'Build radius that blocks resource respawn.' }
                    @{ Id = 'PlatformSaddleBuildAreaBoundsMultiplier'; Type = 'Number'; File = 'GameUserSettings.ini'; Section = 'ServerSettings'; Key = 'PlatformSaddleBuildAreaBoundsMultiplier'; Label = 'Platform Saddle Build Area Bounds Multiplier'; DefaultValue = 1; Min = 0; Max = 1000; Decimals = 6; Hint = 'Platform saddle build area size.' }
                    @{ Id = 'PerPlatformMaxStructuresMultiplier'; Type = 'Number'; File = 'GameUserSettings.ini'; Section = 'ServerSettings'; Key = 'PerPlatformMaxStructuresMultiplier'; Label = 'Per Platform Max Structures Multiplier'; DefaultValue = 1; Min = 0; Max = 1000; Decimals = 6; Hint = 'Platform structure cap multiplier.' }
                    @{ Id = 'StructurePickupTimeAfterPlacement'; Type = 'Number'; File = 'GameUserSettings.ini'; Section = 'ServerSettings'; Key = 'StructurePickupTimeAfterPlacement'; Label = 'Structure Pickup Time After Placement'; DefaultValue = 30; Min = 0; Max = 1000000; Decimals = 6; Hint = 'How long newly placed structures can be picked up.' }
                    @{ Id = 'StructurePickupHoldDuration'; Type = 'Number'; File = 'GameUserSettings.ini'; Section = 'ServerSettings'; Key = 'StructurePickupHoldDuration'; Label = 'Structure Pickup Hold Duration'; DefaultValue = 0.5; Min = 0; Max = 1000000; Decimals = 6; Hint = 'How long the pickup interaction must be held.' }
                    @{ Id = 'AllowIntegratedSPlusStructures'; Type = 'Boolean'; File = 'GameUserSettings.ini'; Section = 'ServerSettings'; Key = 'AllowIntegratedSPlusStructures'; Label = 'Allow Integrated S+ Structures'; DefaultValue = $false; Hint = 'Enable integrated S+ building pieces where supported.' }
                    @{ Id = 'AllowCrateSpawnsOnTopOfStructures'; Type = 'Boolean'; File = 'GameUserSettings.ini'; Section = 'ServerSettings'; Key = 'AllowCrateSpawnsOnTopOfStructures'; Label = 'Allow Crate Spawns On Top Of Structures'; DefaultValue = $false; Hint = 'Allows drops to spawn even if structures are beneath them.' }
                    @{ Id = 'MaxNumberOfPlayersInTribe'; Type = 'Number'; File = 'Game.ini'; Section = '/Script/ShooterGame.ShooterGameMode'; Key = 'MaxNumberOfPlayersInTribe'; Label = 'Max Players In Tribe'; DefaultValue = 0; Min = 0; Max = 1000000; Decimals = 0; Hint = '0 leaves the default tribe player cap.' }
                    @{ Id = 'MaxAlliancesPerTribe'; Type = 'Number'; File = 'Game.ini'; Section = '/Script/ShooterGame.ShooterGameMode'; Key = 'MaxAlliancesPerTribe'; Label = 'Max Alliances Per Tribe'; DefaultValue = 0; Min = 0; Max = 1000000; Decimals = 0; Hint = '0 leaves the default alliance cap.' }
                    @{ Id = 'MaxTribesPerAlliance'; Type = 'Number'; File = 'Game.ini'; Section = '/Script/ShooterGame.ShooterGameMode'; Key = 'MaxTribesPerAlliance'; Label = 'Max Tribes Per Alliance'; DefaultValue = 0; Min = 0; Max = 1000000; Decimals = 0; Hint = '0 leaves the default alliance size cap.' }
                    @{ Id = 'TribeNameChangeCooldown'; Type = 'Number'; File = 'GameUserSettings.ini'; Section = 'ServerSettings'; Key = 'TribeNameChangeCooldown'; Label = 'Tribe Name Change Cooldown'; DefaultValue = 15; Min = 0; Max = 1000000; Decimals = 0; Hint = 'Cooldown in minutes before tribes can rename again.' }
                    @{ Id = 'TribeLogDestroyedEnemyStructures'; Type = 'Boolean'; File = 'GameUserSettings.ini'; Section = 'ServerSettings'; Key = 'TribeLogDestroyedEnemyStructures'; Label = 'Tribe Log Destroyed Enemy Structures'; DefaultValue = $false; Hint = 'Record destroyed enemy structures in tribe log.' }
                )
            }

            [pscustomobject]@{
                Title       = 'PVP & Events'
                Description = 'PVP timing, warfare, and event/world toggles.'
                Fields      = @(
                    @{ Id = 'bIncreasePvPRespawnInterval'; Type = 'Boolean'; File = 'Game.ini'; Section = '/Script/ShooterGame.ShooterGameMode'; Key = 'bIncreasePvPRespawnInterval'; Label = 'Increase PVP Respawn Interval'; DefaultValue = $false; Hint = 'Increase spawn delay after repeated deaths in PVP.' }
                    @{ Id = 'bAutoPvETimer'; Type = 'Boolean'; File = 'Game.ini'; Section = '/Script/ShooterGame.ShooterGameMode'; Key = 'bAutoPvETimer'; Label = 'Auto PVE Timer'; DefaultValue = $false; Hint = 'Automatically switch between PVE and PVP using a timer.' }
                    @{ Id = 'bAutoPvEUseSystemTime'; Type = 'Boolean'; File = 'Game.ini'; Section = '/Script/ShooterGame.ShooterGameMode'; Key = 'bAutoPvEUseSystemTime'; Label = 'Auto PVE Use System Time'; DefaultValue = $false; Hint = 'Use system time for auto PVE schedule.' }
                    @{ Id = 'AutoPvEStartTimeSeconds'; Type = 'Number'; File = 'Game.ini'; Section = '/Script/ShooterGame.ShooterGameMode'; Key = 'AutoPvEStartTimeSeconds'; Label = 'Auto PVE Start Time Seconds'; DefaultValue = 0; Min = 0; Max = 86400; Decimals = 0; Hint = 'Start of the automatic PVE period.' }
                    @{ Id = 'AutoPvEStopTimeSeconds'; Type = 'Number'; File = 'Game.ini'; Section = '/Script/ShooterGame.ShooterGameMode'; Key = 'AutoPvEStopTimeSeconds'; Label = 'Auto PVE Stop Time Seconds'; DefaultValue = 0; Min = 0; Max = 86400; Decimals = 0; Hint = 'End of the automatic PVE period.' }
                    @{ Id = 'bPvEAllowTribeWar'; Type = 'Boolean'; File = 'Game.ini'; Section = '/Script/ShooterGame.ShooterGameMode'; Key = 'bPvEAllowTribeWar'; Label = 'PVE Allow Tribe War'; DefaultValue = $false; Hint = 'Allow tribe wars while in PVE.' }
                    @{ Id = 'bPvEAllowTribeWarCancel'; Type = 'Boolean'; File = 'Game.ini'; Section = '/Script/ShooterGame.ShooterGameMode'; Key = 'bPvEAllowTribeWarCancel'; Label = 'PVE Allow Tribe War Cancel'; DefaultValue = $false; Hint = 'Allow tribe wars to be cancelled.' }
                    @{ Id = 'bDisableGenesisMissions'; Type = 'Boolean'; File = 'Game.ini'; Section = '/Script/ShooterGame.ShooterGameMode'; Key = 'bDisableGenesisMissions'; Label = 'Disable Genesis Missions'; DefaultValue = $false; Hint = 'Disable Genesis mission gameplay.' }
                    @{ Id = 'bDisableDefaultMapItemSets'; Type = 'Boolean'; File = 'Game.ini'; Section = '/Script/ShooterGame.ShooterGameMode'; Key = 'bDisableDefaultMapItemSets'; Label = 'Disable Default Map Item Sets'; DefaultValue = $false; Hint = 'Disable default map item sets.' }
                    @{ Id = 'bDisableWorldBuffs'; Type = 'Boolean'; File = 'Game.ini'; Section = '/Script/ShooterGame.ShooterGameMode'; Key = 'bDisableWorldBuffs'; Label = 'Disable World Buffs'; DefaultValue = $false; Hint = 'Disable rotating world buffs.' }
                    @{ Id = 'bEnableWorldBuffScaling'; Type = 'Boolean'; File = 'Game.ini'; Section = '/Script/ShooterGame.ShooterGameMode'; Key = 'bEnableWorldBuffScaling'; Label = 'Enable World Buff Scaling'; DefaultValue = $false; Hint = 'Scale world buffs to progression.' }
                    @{ Id = 'AdjustableMutagenSpawnDelayMultiplier'; Type = 'Number'; File = 'Game.ini'; Section = '/Script/ShooterGame.ShooterGameMode'; Key = 'AdjustableMutagenSpawnDelayMultiplier'; Label = 'Adjustable Mutagen Spawn Delay Multiplier'; DefaultValue = 1; Min = 0; Max = 1000; Decimals = 6; Hint = 'Mutagen spawn delay multiplier.' }
                    @{ Id = 'BaseHexagonRewardMultiplier'; Type = 'Number'; File = 'Game.ini'; Section = '/Script/ShooterGame.ShooterGameMode'; Key = 'BaseHexagonRewardMultiplier'; Label = 'Base Hexagon Reward Multiplier'; DefaultValue = 1; Min = 0; Max = 1000; Decimals = 6; Hint = 'Genesis hexagon reward multiplier.' }
                    @{ Id = 'HexagonCostMultiplier'; Type = 'Number'; File = 'Game.ini'; Section = '/Script/ShooterGame.ShooterGameMode'; Key = 'HexagonCostMultiplier'; Label = 'Hexagon Cost Multiplier'; DefaultValue = 1; Min = 0; Max = 1000; Decimals = 6; Hint = 'Genesis hexagon cost multiplier.' }
                )
            }

            [pscustomobject]@{
                Title       = 'Engrams & Progression'
                Description = 'Experience, level caps, engrams, and progression overrides.'
                Fields      = @(
                    @{ Id = 'OverrideMaxExperiencePointsPlayer'; Type = 'Number'; File = 'Game.ini'; Section = '/Script/ShooterGame.ShooterGameMode'; Key = 'OverrideMaxExperiencePointsPlayer'; Label = 'Override Max Experience Points Player'; DefaultValue = 0; Min = 0; Max = 100000000; Decimals = 0; Hint = 'Leave at 0 to let the game use defaults.' }
                    @{ Id = 'OverrideMaxExperiencePointsDino'; Type = 'Number'; File = 'Game.ini'; Section = '/Script/ShooterGame.ShooterGameMode'; Key = 'OverrideMaxExperiencePointsDino'; Label = 'Override Max Experience Points Dino'; DefaultValue = 0; Min = 0; Max = 100000000; Decimals = 0; Hint = 'Leave at 0 to let the game use defaults.' }
                    @{ Id = 'OverridePlayerLevelEngramPoints'; Type = 'RepeatedIniValues'; File = 'Game.ini'; Section = '/Script/ShooterGame.ShooterGameMode'; Key = 'OverridePlayerLevelEngramPoints'; Label = 'Override Player Level Engram Points'; Hint = 'One value per line, for example: 8 or 12. Each line becomes its own OverridePlayerLevelEngramPoints entry.' }
                    @{ Id = 'EngramEntryAutoUnlocks'; Type = 'RepeatedIniValues'; File = 'Game.ini'; Section = '/Script/ShooterGame.ShooterGameMode'; Key = 'EngramEntryAutoUnlocks'; Label = 'Engram Entry Auto Unlocks'; Hint = 'One full entry per line, for example: (EngramClassName="EngramEntry_StoneWall_C",LevelToAutoUnlock=10)' }
                    @{ Id = 'OverrideNamedEngramEntries'; Type = 'RepeatedIniValues'; File = 'Game.ini'; Section = '/Script/ShooterGame.ShooterGameMode'; Key = 'OverrideNamedEngramEntries'; Label = 'Override Named Engram Entries'; Hint = 'One full entry per line, for example: (EngramClassName="EngramEntry_TekReplicator_C",EngramHidden=False,EngramPointsCost=0,EngramLevelRequirement=1,RemoveEngramPreReq=False)' }
                )
            }

            [pscustomobject]@{
                Title       = 'Dino Spawns'
                Description = 'ASM-style repeated Game.ini entries for dino spawn editing and replacement.'
                Fields      = @(
                    @{ Id = 'NPCReplacements'; Type = 'RepeatedIniValues'; File = 'Game.ini'; Section = '/Script/ShooterGame.ShooterGameMode'; Key = 'NPCReplacements'; Label = 'NPC Replacements'; Hint = 'One full entry per line, for example: (FromClassName="Dodo_Character_BP_C",ToClassName="Rex_Character_BP_C")' }
                    @{ Id = 'OpenDinoCustomizationBuilder'; Type = 'ActionButton'; Label = 'Dino Customization Builder'; ButtonText = 'Open Dino Customization Builder'; Action = $actions.OpenDinoCustomizationBuilder; Hint = 'Loads Game.ini overrides first, then fills the rest from the shared dino catalog for the current map.' }
                    @{ Id = 'ConfigAddNPCSpawnEntriesContainer'; Type = 'RepeatedIniValues'; File = 'Game.ini'; Section = '/Script/ShooterGame.ShooterGameMode'; Key = 'ConfigAddNPCSpawnEntriesContainer'; Label = 'Add NPC Spawn Entries Container'; Hint = 'One full entry per line. Use full ARK syntax from ASM or wiki examples.' }
                    @{ Id = 'ConfigSubtractNPCSpawnEntriesContainer'; Type = 'RepeatedIniValues'; File = 'Game.ini'; Section = '/Script/ShooterGame.ShooterGameMode'; Key = 'ConfigSubtractNPCSpawnEntriesContainer'; Label = 'Subtract NPC Spawn Entries Container'; Hint = 'One full entry per line to remove spawns from a container.' }
                    @{ Id = 'DinoSpawnWeightMultipliers'; Type = 'RepeatedIniValues'; File = 'Game.ini'; Section = '/Script/ShooterGame.ShooterGameMode'; Key = 'DinoSpawnWeightMultipliers'; Label = 'Dino Spawn Weight Multipliers'; Hint = 'One full entry per line, for example: (DinoNameTag="Rex",SpawnWeightMultiplier=2.0,OverrideSpawnLimitPercentage=True,SpawnLimitPercentage=0.5)' }
                )
            }

            [pscustomobject]@{
                Title       = 'Resource Multipliers'
                Description = 'Per-resource harvest amount multipliers with a simple editor for the shared resource catalog.'
                Fields      = @(
                    @{ Id = 'OpenResourceMultiplierBuilder'; Type = 'ActionButton'; Label = 'Resource Multiplier Builder'; ButtonText = 'Open Resource Multiplier Builder'; Action = $actions.OpenResourceMultiplierBuilder; Hint = 'Shows one row per resource with name, class, and amount multiplier.' }
                    @{ Id = 'HarvestResourceItemAmountClassMultipliers'; Type = 'RepeatedIniValues'; File = 'Game.ini'; Section = '/Script/ShooterGame.ShooterGameMode'; Key = 'HarvestResourceItemAmountClassMultipliers'; Label = 'Harvest Resource Item Amount Class Multipliers (Raw)'; Hint = 'Optional raw fallback. The builder above writes these same entries for you.' }
                )
            }

            [pscustomobject]@{
                Title       = 'Loot Overrides'
                Description = 'Raw loot and related advanced override entries until a dedicated loot builder is added.'
                Fields      = @(
                    @{ Id = 'ConfigOverrideSupplyCrateItems'; Type = 'RepeatedIniValues'; File = 'Game.ini'; Section = '/Script/ShooterGame.ShooterGameMode'; Key = 'ConfigOverrideSupplyCrateItems'; Label = 'Config Override Supply Crate Items'; Hint = 'One full entry per line using the full supply-crate override syntax. For mod-specific crate sections, keep using the raw GameUserSettings.ini file until section-aware UI is added.' }
                    @{ Id = 'ConfigOverrideItemCraftingCosts'; Type = 'RepeatedIniValues'; File = 'Game.ini'; Section = '/Script/ShooterGame.ShooterGameMode'; Key = 'ConfigOverrideItemCraftingCosts'; Label = 'Config Override Item Crafting Costs'; Hint = 'One full entry per line using the full crafting-cost tuple syntax from ASM.' }
                    @{ Id = 'HarvestResourceItemDamageClassMultipliers'; Type = 'RepeatedIniValues'; File = 'Game.ini'; Section = '/Script/ShooterGame.ShooterGameMode'; Key = 'HarvestResourceItemDamageClassMultipliers'; Label = 'Harvest Resource Item Damage Class Multipliers'; Hint = 'One full entry per line, for example: (ClassName="PrimalItemResource_Stone_C",Multiplier=0.5)' }
                )
            }

            [pscustomobject]@{
                Title       = 'Admin'
                Description = 'Admin password and AllowedCheaterSteamIDs.txt editing. Enter one Steam64 ID per line.'
                Fields      = @(
                    @{ Id = 'ServerAdminPassword'; Type = 'Text'; File = 'GameUserSettings.ini'; Section = 'ServerSettings'; Key = 'ServerAdminPassword'; Label = 'Admin Password'; DefaultValue = ''; Hint = 'Remote admin password used for cheat/admin access.' }
                    @{ Id = 'AdminUsers'; Type = 'StringList'; Label = 'Allowed Admin IDs'; DefaultValue = ''; Hint = 'Saved to ShooterGame\Saved\AllowedCheaterSteamIDs.txt. Enter one Steam64 ID per line.' }
                    @{ Id = 'OpenAdminUsers'; Type = 'ActionButton'; Label = 'AllowedCheaterSteamIDs.txt'; ButtonText = 'Open AllowedCheaterSteamIDs.txt'; Action = { param($Instance, $Paths, $StatusLabel) Invoke-UGSMArkSEEditorAction -Instance $Instance -Paths $Paths -Target 'AdminUsers' -EnsureFile -StatusLabel $StatusLabel -OpenedMessage 'Opened AllowedCheaterSteamIDs.txt.' }; Hint = 'Opens the AllowedCheaterSteamIDs.txt file for manual editing.' }
                )
            }

            [pscustomobject]@{
                Title       = 'Files & Advanced'
                Description = 'Quick access for anything not yet surfaced in the form.'
                Fields      = @(
                    @{ Id = 'OpenGameUserSettings'; Type = 'ActionButton'; Label = 'GameUserSettings.ini'; ButtonText = 'Open GameUserSettings.ini'; Action = $actions.OpenGameUserSettings; Hint = 'Opens the main ARK settings file for manual editing.' }
                    @{ Id = 'OpenGameIni'; Type = 'ActionButton'; Label = 'Game.ini'; ButtonText = 'Open Game.ini'; Action = $actions.OpenGameIni; Hint = 'Opens the advanced ARK gameplay config for manual editing.' }
                    @{ Id = 'OpenConfigFolder'; Type = 'ActionButton'; Label = 'Config Folder'; ButtonText = 'Open Config Folder'; Action = $actions.OpenConfigFolder; Hint = 'Opens the ARK config folder.' }
                    @{ Id = 'OpenProfileFolder'; Type = 'ActionButton'; Label = 'Profile Folder'; ButtonText = 'Open Profile Folder'; Action = $actions.OpenProfileFolder; Hint = 'Opens the selected ARK profile folder in Explorer.' }
                )
            }

            [pscustomobject]@{
                Title       = 'Discord'
                Description = 'Per-server Discord override settings. Leave the webhook blank to fall back to the global webhook configured in Settings.'
                Fields      = @(
                    @{ Id = 'DiscordWebhookUrl'; Type = 'InstanceText'; Model = 'Discord'; Property = 'WebhookUrl'; Label = 'Discord Webhook URL'; DefaultValue = ''; Hint = 'Optional per-server webhook override. Blank uses the global webhook.' }
                    @{ Id = 'DiscordNotifyStart'; Type = 'InstanceBoolean'; Model = 'Discord'; Property = 'NotifyOnStart'; Label = 'Notify On Start'; DefaultValue = $false; Hint = 'Send a Discord notification when this server starts.' }
                    @{ Id = 'DiscordNotifyStop'; Type = 'InstanceBoolean'; Model = 'Discord'; Property = 'NotifyOnStop'; Label = 'Notify On Stop'; DefaultValue = $false; Hint = 'Send a Discord notification when this server stops.' }
                    @{ Id = 'DiscordVisible'; Type = 'InstanceBoolean'; Model = 'Discord'; Property = 'ShowInDashboard'; Label = 'Show In Dashboard'; DefaultValue = $false; Hint = 'Marks this server as visible for Discord or dashboard status integrations.' }

                    @{
                        Id         = 'DiscordTestWebhook'
                        Type       = 'ActionButton'
                        Label      = 'Test Discord Webhook'
                        ButtonText = 'Send Test Message'
                        Hint       = 'Sends a test message using the per-server webhook if set, otherwise the global webhook.'
                        Action     = {
                            param($Instance, $Paths, $StatusLabel)

                            try {
                                $discordModel = Get-UGSMInstanceDiscordSettingsModel -Instance $Instance

                                if (-not $discordModel.HasWebhook) {
                                    if ($StatusLabel) { $StatusLabel.Text = 'Discord test skipped: no webhook is configured for this server and no global webhook is available.' }
                                    return
                                }

                                $result = Test-UGSMDiscordWebhook -WebhookUrl $discordModel.EffectiveWebhookUrl -Label ('ArkSE ' + [string]$Instance.Name)

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
}

function Get-UGSMGameArkSEDinoCatalogForPaths {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][pscustomobject]$Paths
    )

    $gusData = Read-UGSMGameArkSEIniFile -Path $Paths.GameUserSettingsPath
    $mapName = [string](Get-UGSMGameArkSEIniValue -IniData $gusData -Section 'ServerSettings' -Key 'ServerMap')

    if ([string]::IsNullOrWhiteSpace($mapName)) { $mapName = 'TheIsland' }
    return @(Get-UGSMArkDinoCatalog -GameId 'ArkSE' -MapName $mapName)
}

function ConvertFrom-UGSMArkSENpcReplacementLine {
    [CmdletBinding()]
    param([string]$Line)
    if ([string]::IsNullOrWhiteSpace($Line)) { return $null }
    $from = ''; $to = ''
    $m1 = [regex]::Match($Line, 'FromClassName\s*=\s*"([^"]*)"', 'IgnoreCase')
    if ($m1.Success) { $from = $m1.Groups[1].Value }
    $m2 = [regex]::Match($Line, 'ToClassName\s*=\s*"([^"]*)"', 'IgnoreCase')
    if ($m2.Success) { $to = $m2.Groups[1].Value }
    if ([string]::IsNullOrWhiteSpace($from) -and [string]::IsNullOrWhiteSpace($to)) { return $null }
    [pscustomobject]@{ FromClassName = $from; ToClassName = $to }
}

function ConvertFrom-UGSMArkSEDinoSpawnWeightLine {
    [CmdletBinding()]
    param([string]$Line)

    if ([string]::IsNullOrWhiteSpace($Line)) { return $null }

    $tag = ''
    $weight = ''
    $override = ''
    $limit = ''

    $m1 = [regex]::Match($Line, 'DinoNameTag\s*=\s*"?([^,\)"\s]+)"?', 'IgnoreCase')
    if ($m1.Success) { $tag = $m1.Groups[1].Value }

    $m2 = [regex]::Match($Line, 'SpawnWeightMultiplier\s*=\s*([^,\)]+)', 'IgnoreCase')
    if ($m2.Success) { $weight = $m2.Groups[1].Value.Trim() }

    $m3 = [regex]::Match($Line, 'OverrideSpawnLimitPercentage\s*=\s*([^,\)]+)', 'IgnoreCase')
    if ($m3.Success) { $override = $m3.Groups[1].Value.Trim() }

    $m4 = [regex]::Match($Line, '(?:^|[,(])\s*SpawnLimitPercentage\s*=\s*([^,\)]+)', 'IgnoreCase')
    if ($m4.Success) { $limit = $m4.Groups[1].Value.Trim() }

    if ([string]::IsNullOrWhiteSpace($tag)) { return $null }

    [pscustomobject]@{
        DinoNameTag                  = $tag
        SpawnWeightMultiplier        = $weight
        OverrideSpawnLimitPercentage = $override
        SpawnLimitPercentage         = $limit
    }
}

function ConvertTo-UGSMArkSENpcReplacementLine {
    [CmdletBinding()]
    param([string]$FromClassName, [string]$ToClassName)
    if ([string]::IsNullOrWhiteSpace($FromClassName)) { return $null }
    '(FromClassName="{0}",ToClassName="{1}")' -f $FromClassName, ([string]$ToClassName)
}

function ConvertTo-UGSMArkSEDinoSpawnWeightLine {
    [CmdletBinding()]
    param([string]$DinoNameTag, [string]$SpawnWeightMultiplier, [string]$OverrideSpawnLimitPercentage, [string]$SpawnLimitPercentage)
    if ([string]::IsNullOrWhiteSpace($DinoNameTag)) { return $null }
    if ([string]::IsNullOrWhiteSpace($SpawnWeightMultiplier)) { return $null }
    $overrideText = if ([string]::IsNullOrWhiteSpace($OverrideSpawnLimitPercentage)) { 'False' } else { [string]$OverrideSpawnLimitPercentage }
    $limitText = if ([string]::IsNullOrWhiteSpace($SpawnLimitPercentage)) { '1.0' } else { [string]$SpawnLimitPercentage }
    '(DinoNameTag="{0}",SpawnWeightMultiplier={1},OverrideSpawnLimitPercentage={2},SpawnLimitPercentage={3})' -f $DinoNameTag, $SpawnWeightMultiplier, $overrideText, $limitText
}

function ConvertFrom-UGSMArkSEDinoClassMultiplierLine {
    [CmdletBinding()]
    param([string]$Line)
    if ([string]::IsNullOrWhiteSpace($Line)) { return $null }
    $className = ''
    $multiplier = ''
    $m1 = [regex]::Match($Line, 'ClassName\s*=\s*"([^"]*)"', 'IgnoreCase')
    if ($m1.Success) { $className = $m1.Groups[1].Value }
    $m2 = [regex]::Match($Line, 'Multiplier\s*=\s*([^,\)]+)', 'IgnoreCase')
    if ($m2.Success) { $multiplier = $m2.Groups[1].Value.Trim() }
    if ([string]::IsNullOrWhiteSpace($className)) { return $null }
    [pscustomobject]@{ ClassName = $className; Multiplier = $multiplier }
}

function ConvertTo-UGSMArkSEDinoClassMultiplierLine {
    [CmdletBinding()]
    param([string]$ClassName, [string]$Multiplier)
    if ([string]::IsNullOrWhiteSpace($ClassName)) { return $null }
    if ([string]::IsNullOrWhiteSpace($Multiplier)) { return $null }
    '(ClassName="{0}",Multiplier={1})' -f $ClassName, $Multiplier
}


function Get-UGSMGameArkSEResourceCatalog {
    [CmdletBinding()]
    param()

    return @(
        [pscustomobject]@{ DisplayName = 'Snail Paste'; ClassName = 'PrimalItemResource_SnailPaste_C' }
        [pscustomobject]@{ DisplayName = 'Common Mushroom'; ClassName = 'PrimalItemResource_CommonMushroom_C' }
        [pscustomobject]@{ DisplayName = 'Apex Drop Allosaurus'; ClassName = 'PrimalItemResource_ApexDrop_Allo_C' }
        [pscustomobject]@{ DisplayName = 'Apex Drop Basilisk Alpha'; ClassName = 'PrimalItemResource_ApexDrop_Basilisk_Alpha_C' }
        [pscustomobject]@{ DisplayName = 'Apex Drop Crab Claw'; ClassName = 'PrimalItemResource_ApexDrop_CrabClaw_C' }
        [pscustomobject]@{ DisplayName = 'Apex Drop Reaper Barb'; ClassName = 'PrimalItemResource_ApexDrop_ReaperBarb_C' }
        [pscustomobject]@{ DisplayName = 'Seed Amarberry'; ClassName = 'PrimalItemConsumable_Seed_Amarberry_C' }
        [pscustomobject]@{ DisplayName = 'Berry Amarberry'; ClassName = 'PrimalItemConsumable_Berry_Amarberry_C' }
        [pscustomobject]@{ DisplayName = 'Ammonite Blood'; ClassName = 'PrimalItemResource_AmmoniteBlood_C' }
        [pscustomobject]@{ DisplayName = 'Angler Gel'; ClassName = 'PrimalItemResource_AnglerGel_C' }
        [pscustomobject]@{ DisplayName = 'Mushroom Aquatic'; ClassName = 'PrimalItemConsumable_Mushroom_Aquatic_C' }
        [pscustomobject]@{ DisplayName = 'Apex Drop Argentavis'; ClassName = 'PrimalItemResource_ApexDrop_Argentavis_C' }
        [pscustomobject]@{ DisplayName = 'Mushroom Ascerbic'; ClassName = 'PrimalItemConsumable_Mushroom_Ascerbic_C' }
        [pscustomobject]@{ DisplayName = 'Mushroom Auric'; ClassName = 'PrimalItemConsumable_Mushroom_Auric_C' }
        [pscustomobject]@{ DisplayName = 'Seed Azulberry'; ClassName = 'PrimalItemConsumable_Seed_Azulberry_C' }
        [pscustomobject]@{ DisplayName = 'Berry Azulberry'; ClassName = 'PrimalItemConsumable_Berry_Azulberry_C' }
        [pscustomobject]@{ DisplayName = 'Seed Barley'; ClassName = 'PrimalItemConsumable_Seed_Barley_C' }
        [pscustomobject]@{ DisplayName = 'Apex Drop Basilisk'; ClassName = 'PrimalItemResource_ApexDrop_Basilisk_C' }
        [pscustomobject]@{ DisplayName = 'Apex Drop Basilosaurus'; ClassName = 'PrimalItemResource_ApexDrop_Basilo_C' }
        [pscustomobject]@{ DisplayName = 'Jelly Venom'; ClassName = 'PrimalItemConsumable_JellyVenom_C' }
        [pscustomobject]@{ DisplayName = 'Black Pearl'; ClassName = 'PrimalItemResource_BlackPearl_C' }
        [pscustomobject]@{ DisplayName = 'Blue Sap'; ClassName = 'PrimalItemResource_BlueSap_C' }
        [pscustomobject]@{ DisplayName = 'Gem Biolum'; ClassName = 'PrimalItemResource_Gem_BioLum_C' }
        [pscustomobject]@{ DisplayName = 'Seed Lettuce'; ClassName = 'PrimalItemConsumable_Seed_Lettuce_C' }
        [pscustomobject]@{ DisplayName = 'Cactus Sap'; ClassName = 'PrimalItemConsumable_CactusSap_C' }
        [pscustomobject]@{ DisplayName = 'Seed Tea'; ClassName = 'PrimalItemConsumable_Seed_Tea_C' }
        [pscustomobject]@{ DisplayName = 'Carbon'; ClassName = 'PrimalItemResource_Carbon_C' }
        [pscustomobject]@{ DisplayName = 'Seed Cashew'; ClassName = 'PrimalItemConsumable_Seed_Cashew_C' }
        [pscustomobject]@{ DisplayName = 'Chitin Paste'; ClassName = 'PrimalItemResource_ChitinPaste_C' }
        [pscustomobject]@{ DisplayName = 'Charcoal'; ClassName = 'PrimalItemResource_Charcoal_C' }
        [pscustomobject]@{ DisplayName = 'Chitin Or Keratin'; ClassName = 'PrimalItemResource_ChitinOrKeratin_C' }
        [pscustomobject]@{ DisplayName = 'Chitin'; ClassName = 'PrimalItemResource_Chitin_C' }
        [pscustomobject]@{ DisplayName = 'Seed Citronal'; ClassName = 'PrimalItemConsumable_Seed_Citronal_C' }
        [pscustomobject]@{ DisplayName = 'Veggie Citronal'; ClassName = 'PrimalItemConsumable_Veggie_Citronal_C' }
        [pscustomobject]@{ DisplayName = 'Claystone'; ClassName = 'PrimalItemResource_Claystone_C' }
        [pscustomobject]@{ DisplayName = 'Seed Coffee'; ClassName = 'PrimalItemConsumable_Seed_Coffee_C' }
        [pscustomobject]@{ DisplayName = 'Condensed Gas'; ClassName = 'PrimalItemResource_CondensedGas_C' }
        [pscustomobject]@{ DisplayName = 'Gas'; ClassName = 'PrimalItemResource_Gas_C' }
        [pscustomobject]@{ DisplayName = 'Rare Drop Corrupt Heart'; ClassName = 'PrimalItemResource_RareDrop_CorruptHeart_C' }
        [pscustomobject]@{ DisplayName = 'Corrupted Polymer'; ClassName = 'PrimalItemResource_CorruptedPolymer_C' }
        [pscustomobject]@{ DisplayName = 'Corrupted Wood'; ClassName = 'PrimalItemResource_CorruptedWood_C' }
        [pscustomobject]@{ DisplayName = 'Crystal'; ClassName = 'PrimalItemResource_Crystal_C' }
        [pscustomobject]@{ DisplayName = 'Keratin Spike'; ClassName = 'PrimalItemResource_KeratinSpike_C' }
        [pscustomobject]@{ DisplayName = 'ARK Bone'; ClassName = 'PrimalItemResource_ARKBone_C' }
        [pscustomobject]@{ DisplayName = 'Drone Bee'; ClassName = 'PrimalItemResource_DroneBee_C' }
        [pscustomobject]@{ DisplayName = 'Electronics'; ClassName = 'PrimalItemResource_Electronics_C' }
        [pscustomobject]@{ DisplayName = 'Element Dust'; ClassName = 'PrimalItemResource_ElementDust_C' }
        [pscustomobject]@{ DisplayName = 'Element Ore'; ClassName = 'PrimalItemResource_ElementOre_C' }
        [pscustomobject]@{ DisplayName = 'Element Shard'; ClassName = 'PrimalItemResource_ElementShard_C' }
        [pscustomobject]@{ DisplayName = 'Element'; ClassName = 'PrimalItemResource_Element_C' }
        [pscustomobject]@{ DisplayName = 'Feathers'; ClassName = 'PrimalItemResource_Feathers_C' }
        [pscustomobject]@{ DisplayName = 'Fibers'; ClassName = 'PrimalItemResource_Fibers_C' }
        [pscustomobject]@{ DisplayName = 'Apex Drop Fire Wyvern'; ClassName = 'PrimalItemResource_ApexDrop_FireWyvern_C' }
        [pscustomobject]@{ DisplayName = 'Flint'; ClassName = 'PrimalItemResource_Flint_C' }
        [pscustomobject]@{ DisplayName = 'Fractured Gem'; ClassName = 'PrimalItemResource_FracturedGem_C' }
        [pscustomobject]@{ DisplayName = 'Fresh Bacon'; ClassName = 'PrimalItemConsumable_FreshBacon_C' }
        [pscustomobject]@{ DisplayName = 'Fresh Animal Fat'; ClassName = 'PrimalItemConsumable_FreshAnimalFat_C' }
        [pscustomobject]@{ DisplayName = 'Fresh Fillet'; ClassName = 'PrimalItemConsumable_FreshFillet_C' }
        [pscustomobject]@{ DisplayName = 'Fresh Poultry'; ClassName = 'PrimalItemConsumable_FreshPoultry_C' }
        [pscustomobject]@{ DisplayName = 'Fresh Ribs'; ClassName = 'PrimalItemConsumable_FreshRibs_C' }
        [pscustomobject]@{ DisplayName = 'Fungal Wood'; ClassName = 'PrimalItemResource_FungalWood_C' }
        [pscustomobject]@{ DisplayName = 'Apex Drop Gas Bag'; ClassName = 'PrimalItemResource_ApexDrop_GasBag_C' }
        [pscustomobject]@{ DisplayName = 'Apex Drop Giganotosaurus'; ClassName = 'PrimalItemResource_ApexDrop_Giga_C' }
        [pscustomobject]@{ DisplayName = 'Seed Grape'; ClassName = 'PrimalItemConsumable_Seed_Grape_C' }
        [pscustomobject]@{ DisplayName = 'Gem Fertile'; ClassName = 'PrimalItemResource_Gem_Fertile_C' }
        [pscustomobject]@{ DisplayName = 'Hide'; ClassName = 'PrimalItemResource_Hide_C' }
        [pscustomobject]@{ DisplayName = 'Honey'; ClassName = 'PrimalItemConsumable_Honey_C' }
        [pscustomobject]@{ DisplayName = 'Hair'; ClassName = 'PrimalItemResource_Hair_C' }
        [pscustomobject]@{ DisplayName = 'Keratin'; ClassName = 'PrimalItemResource_Keratin_C' }
        [pscustomobject]@{ DisplayName = 'Leech Blood'; ClassName = 'PrimalItemResource_LeechBlood_C' }
        [pscustomobject]@{ DisplayName = 'Apex Drop Lightning Wyvern'; ClassName = 'PrimalItemResource_ApexDrop_LightningWyvern_C' }
        [pscustomobject]@{ DisplayName = 'Limestone'; ClassName = 'PrimalItemResource_Limestone_C' }
        [pscustomobject]@{ DisplayName = 'Seed Longrass'; ClassName = 'PrimalItemConsumable_Seed_Longrass_C' }
        [pscustomobject]@{ DisplayName = 'Veggie Longrass'; ClassName = 'PrimalItemConsumable_Veggie_Longrass_C' }
        [pscustomobject]@{ DisplayName = 'Apex Drop Megalania'; ClassName = 'PrimalItemResource_ApexDrop_Megalania_C' }
        [pscustomobject]@{ DisplayName = 'Apex Drop Megalodon'; ClassName = 'PrimalItemResource_ApexDrop_Megalodon_C' }
        [pscustomobject]@{ DisplayName = 'Seed Mejoberry'; ClassName = 'PrimalItemConsumable_Seed_Mejoberry_C' }
        [pscustomobject]@{ DisplayName = 'Berry Mejoberry'; ClassName = 'PrimalItemConsumable_Berry_Mejoberry_C' }
        [pscustomobject]@{ DisplayName = 'Metal'; ClassName = 'PrimalItemResource_Metal_C' }
        [pscustomobject]@{ DisplayName = 'Nameless Venom'; ClassName = 'PrimalItemConsumable_NamelessVenom_C' }
        [pscustomobject]@{ DisplayName = 'Seed Narcoberry'; ClassName = 'PrimalItemConsumable_Seed_Narcoberry_C' }
        [pscustomobject]@{ DisplayName = 'Berry Narcoberry'; ClassName = 'PrimalItemConsumable_Berry_Narcoberry_C' }
        [pscustomobject]@{ DisplayName = 'Obsidian'; ClassName = 'PrimalItemResource_Obsidian_C' }
        [pscustomobject]@{ DisplayName = 'Squid Oil'; ClassName = 'PrimalItemResource_SquidOil_C' }
        [pscustomobject]@{ DisplayName = 'Oil'; ClassName = 'PrimalItemResource_Oil_C' }
        [pscustomobject]@{ DisplayName = 'Polymer Organic'; ClassName = 'PrimalItemResource_Polymer_Organic_C' }
        [pscustomobject]@{ DisplayName = 'Pelt Or Hair'; ClassName = 'PrimalItemResource_PeltOrHair_C' }
        [pscustomobject]@{ DisplayName = 'Pelt'; ClassName = 'PrimalItemResource_Pelt_C' }
        [pscustomobject]@{ DisplayName = 'Seed Defense Plant'; ClassName = 'PrimalItemConsumable_Seed_DefensePlant_C' }
        [pscustomobject]@{ DisplayName = 'Seed Plant Species Y'; ClassName = 'PrimalItemConsumable_Seed_PlantSpeciesY_C' }
        [pscustomobject]@{ DisplayName = 'Seed Plant Species Z'; ClassName = 'PrimalItemConsumable_Seed_PlantSpeciesZ_C' }
        [pscustomobject]@{ DisplayName = 'Apex Drop Poison Wyvern'; ClassName = 'PrimalItemResource_ApexDrop_PoisonWyvern_C' }
        [pscustomobject]@{ DisplayName = 'Preserving Salt'; ClassName = 'PrimalItemResource_PreservingSalt_C' }
        [pscustomobject]@{ DisplayName = 'Queen Bee'; ClassName = 'PrimalItemResource_QueenBee_C' }
        [pscustomobject]@{ DisplayName = 'Rare Flower'; ClassName = 'PrimalItemResource_RareFlower_C' }
        [pscustomobject]@{ DisplayName = 'Rare Mushroom'; ClassName = 'PrimalItemResource_RareMushroom_C' }
        [pscustomobject]@{ DisplayName = 'Raw Meat Fish'; ClassName = 'PrimalItemConsumable_RawMeat_Fish_C' }
        [pscustomobject]@{ DisplayName = 'Raw Meat'; ClassName = 'PrimalItemConsumable_RawMeat_C' }
        [pscustomobject]@{ DisplayName = 'Raw Mutton'; ClassName = 'PrimalItemConsumable_RawMutton_C' }
        [pscustomobject]@{ DisplayName = 'Raw Prime Meat Fish'; ClassName = 'PrimalItemConsumable_RawPrimeMeat_Fish_C' }
        [pscustomobject]@{ DisplayName = 'Raw Prime Meat'; ClassName = 'PrimalItemConsumable_RawPrimeMeat_C' }
        [pscustomobject]@{ DisplayName = 'Raw Salt'; ClassName = 'PrimalItemResource_RawSalt_C' }
        [pscustomobject]@{ DisplayName = 'Xenomorph Pheromone Gland'; ClassName = 'PrimalItemResource_XenomorphPheromoneGland_C' }
        [pscustomobject]@{ DisplayName = 'Red Sap'; ClassName = 'PrimalItemResource_RedSap_C' }
        [pscustomobject]@{ DisplayName = 'Gem Element'; ClassName = 'PrimalItemResource_Gem_Element_C' }
        [pscustomobject]@{ DisplayName = 'Seed Rice'; ClassName = 'PrimalItemConsumable_Seed_Rice_C' }
        [pscustomobject]@{ DisplayName = 'Apex Drop Rock Drake'; ClassName = 'PrimalItemResource_ApexDrop_RockDrake_C' }
        [pscustomobject]@{ DisplayName = 'Seed Rockarrot'; ClassName = 'PrimalItemConsumable_Seed_Rockarrot_C' }
        [pscustomobject]@{ DisplayName = 'Veggie Rockarrot'; ClassName = 'PrimalItemConsumable_Veggie_Rockarrot_C' }
        [pscustomobject]@{ DisplayName = 'Sand'; ClassName = 'PrimalItemResource_Sand_C' }
        [pscustomobject]@{ DisplayName = 'Sap'; ClassName = 'PrimalItemResource_Sap_C' }
        [pscustomobject]@{ DisplayName = 'Apex Drop Sarcosuchus'; ClassName = 'PrimalItemResource_ApexDrop_Sarco_C' }
        [pscustomobject]@{ DisplayName = 'Apex Drop Sauropod Vertebra'; ClassName = 'PrimalItemResource_ApexDrop_Sauro_C' }
        [pscustomobject]@{ DisplayName = 'Seed Savoroot'; ClassName = 'PrimalItemConsumable_Seed_Savoroot_C' }
        [pscustomobject]@{ DisplayName = 'Veggie Savoroot'; ClassName = 'PrimalItemConsumable_Veggie_Savoroot_C' }
        [pscustomobject]@{ DisplayName = 'Scrap Metal'; ClassName = 'PrimalItemResource_ScrapMetal_C' }
        [pscustomobject]@{ DisplayName = 'Silicon'; ClassName = 'PrimalItemResource_Silicon_C' }
        [pscustomobject]@{ DisplayName = 'Silicate'; ClassName = 'PrimalItemResource_Silicate_C' }
        [pscustomobject]@{ DisplayName = 'Silk'; ClassName = 'PrimalItemResource_Silk_C' }
        [pscustomobject]@{ DisplayName = 'Apex Drop Spinosaurus'; ClassName = 'PrimalItemResource_ApexDrop_Spino_C' }
        [pscustomobject]@{ DisplayName = 'Seed Stimberry'; ClassName = 'PrimalItemConsumable_Seed_Stimberry_C' }
        [pscustomobject]@{ DisplayName = 'Berry Stimberry'; ClassName = 'PrimalItemConsumable_Berry_Stimberry_C' }
        [pscustomobject]@{ DisplayName = 'Stone'; ClassName = 'PrimalItemResource_Stone_C' }
        [pscustomobject]@{ DisplayName = 'Seed Sugar'; ClassName = 'PrimalItemConsumable_Seed_Sugar_C' }
        [pscustomobject]@{ DisplayName = 'Sulfur'; ClassName = 'PrimalItemResource_Sulfur_C' }
        [pscustomobject]@{ DisplayName = 'Thatch'; ClassName = 'PrimalItemResource_Thatch_C' }
        [pscustomobject]@{ DisplayName = 'Apex Drop Therizinosaurus'; ClassName = 'PrimalItemResource_ApexDrop_Theriz_C' }
        [pscustomobject]@{ DisplayName = 'Apex Drop Thylacoleo'; ClassName = 'PrimalItemResource_ApexDrop_Thylaco_C' }
        [pscustomobject]@{ DisplayName = 'Seed Tintoberry'; ClassName = 'PrimalItemConsumable_Seed_Tintoberry_C' }
        [pscustomobject]@{ DisplayName = 'Berry Tintoberry'; ClassName = 'PrimalItemConsumable_Berry_Tintoberry_C' }
        [pscustomobject]@{ DisplayName = 'Apex Drop Titanoboa'; ClassName = 'PrimalItemResource_ApexDrop_Boa_C' }
        [pscustomobject]@{ DisplayName = 'Seed Tobacco'; ClassName = 'PrimalItemConsumable_Seed_Tobacco_C' }
        [pscustomobject]@{ DisplayName = 'Seed Tomato'; ClassName = 'PrimalItemConsumable_Seed_Tomato_C' }
        [pscustomobject]@{ DisplayName = 'Apex Drop Tusoteuthis'; ClassName = 'PrimalItemResource_ApexDrop_Tuso_C' }
        [pscustomobject]@{ DisplayName = 'Apex Drop Rex'; ClassName = 'PrimalItemResource_ApexDrop_Rex_C' }
        [pscustomobject]@{ DisplayName = 'Seed Wheat'; ClassName = 'PrimalItemConsumable_Seed_Wheat_C' }
        [pscustomobject]@{ DisplayName = 'Wood'; ClassName = 'PrimalItemResource_Wood_C' }
        [pscustomobject]@{ DisplayName = 'Wool'; ClassName = 'PrimalItemResource_Wool_C' }
        [pscustomobject]@{ DisplayName = 'Horn'; ClassName = 'PrimalItemResource_Horn_C' }
        [pscustomobject]@{ DisplayName = 'Wyvern Milk'; ClassName = 'PrimalItemConsumable_WyvernMilk_C' }
        [pscustomobject]@{ DisplayName = 'Apex Drop Yutyrannus'; ClassName = 'PrimalItemResource_ApexDrop_Yuty_C' }
    )
}

function ConvertFrom-UGSMArkSEResourceMultiplierLine {
    [CmdletBinding()]
    param([AllowNull()][string]$Line)

    if ([string]::IsNullOrWhiteSpace($Line)) { return $null }

    $match = [regex]::Match($Line, 'ClassName\s*=\s*"(?<ClassName>[^"]+)"\s*,\s*Multiplier\s*=\s*(?<Multiplier>[^\)]+)')
    if (-not $match.Success) { return $null }

    return [pscustomobject]@{
        ClassName  = [string]$match.Groups['ClassName'].Value
        Multiplier = [string]$match.Groups['Multiplier'].Value.Trim()
    }
}

function ConvertTo-UGSMArkSEResourceMultiplierLine {
    [CmdletBinding()]
    param(
        [AllowNull()][string]$ClassName,
        [AllowNull()][string]$Multiplier
    )

    if ([string]::IsNullOrWhiteSpace($ClassName) -or [string]::IsNullOrWhiteSpace($Multiplier)) {
        return $null
    }

    return '(ClassName="' + $ClassName.Trim() + '",Multiplier=' + $Multiplier.Trim() + ')'
}

function Invoke-UGSMGameArkSEResourceMultiplierBuilder {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$Instance,
        [AllowNull()][pscustomobject]$Paths,
        [AllowNull()][System.Windows.Forms.Label]$StatusLabel
    )

    if ($null -eq $Paths) {
        try { $Paths = Get-UGSMGameArkSEProfilePaths -Instance $Instance }
        catch {
            [System.Windows.Forms.MessageBox]::Show('Could not resolve ARK server paths for the resource builder: ' + $_.Exception.Message, 'ARK Resource Multipliers', [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error) | Out-Null
            return
        }
    }

    $catalog = @(Get-UGSMGameArkSEResourceCatalog)
    $gameIniPath = [string]$Paths.GameIniPath
    $sectionName = '/Script/ShooterGame.ShooterGameMode'
    $existingLines = @(Get-UGSMArkSEIniRepeatedValues -Path $gameIniPath -Section $sectionName -Key 'HarvestResourceItemAmountClassMultipliers')

    $rowsByClass = @{}
    foreach ($entry in $catalog) {
        $className = [string]$entry.ClassName
        if ([string]::IsNullOrWhiteSpace($className)) { continue }
        $rowsByClass[$className] = [ordered]@{
            DisplayName = [string]$entry.DisplayName
            ClassName   = $className
            Multiplier  = ''
        }
    }

    foreach ($line in $existingLines) {
        $parsed = ConvertFrom-UGSMArkSEResourceMultiplierLine -Line $line
        if ($null -eq $parsed) { continue }
        $className = [string]$parsed.ClassName
        if (-not $rowsByClass.ContainsKey($className)) {
            $rowsByClass[$className] = [ordered]@{
                DisplayName = $className
                ClassName   = $className
                Multiplier  = ''
            }
        }
        $rowsByClass[$className].Multiplier = [string]$parsed.Multiplier
    }

    $form = New-Object System.Windows.Forms.Form
    $form.Text = 'ARK Resource Multipliers'
    $form.StartPosition = 'CenterParent'
    $form.Size = New-Object System.Drawing.Size(980, 760)
    $form.MinimumSize = New-Object System.Drawing.Size(900, 620)

    $intro = New-Object System.Windows.Forms.Label
    $intro.Left = 12; $intro.Top = 12; $intro.Width = 940; $intro.Height = 36
    $intro.Text = 'Edit HarvestResourceItemAmountClassMultipliers with one row per resource. Leave the multiplier blank to remove that override.'
    [void]$form.Controls.Add($intro)

    $grid = New-Object System.Windows.Forms.DataGridView
    $grid.Left = 12; $grid.Top = 52; $grid.Width = 940; $grid.Height = 620
    $grid.Anchor = 'Top,Bottom,Left,Right'
    $grid.AllowUserToAddRows = $false
    $grid.AllowUserToDeleteRows = $false
    $grid.RowHeadersVisible = $false
    $grid.SelectionMode = 'FullRowSelect'
    $grid.MultiSelect = $false
    $grid.AutoSizeRowsMode = 'None'
    $grid.EditMode = 'EditOnEnter'
    $grid.AutoGenerateColumns = $false
    $grid.AutoSizeColumnsMode = 'None'

    $nameCol = New-Object System.Windows.Forms.DataGridViewTextBoxColumn
    $nameCol.Name = 'DisplayName'; $nameCol.HeaderText = 'Resource'; $nameCol.ReadOnly = $true; $nameCol.Width = 300
    [void]$grid.Columns.Add($nameCol)

    $classCol = New-Object System.Windows.Forms.DataGridViewTextBoxColumn
    $classCol.Name = 'ClassName'; $classCol.HeaderText = 'Class'; $classCol.ReadOnly = $true; $classCol.Width = 470
    [void]$grid.Columns.Add($classCol)

    $multCol = New-Object System.Windows.Forms.DataGridViewTextBoxColumn
    $multCol.Name = 'Multiplier'; $multCol.HeaderText = 'Multiplier'; $multCol.Width = 120
    [void]$grid.Columns.Add($multCol)
    [void]$form.Controls.Add($grid)

    $sorted = @($rowsByClass.Values | Sort-Object DisplayName, ClassName)
    foreach ($row in $sorted) {
        $idx = $grid.Rows.Add()
        $grid.Rows[$idx].Cells['DisplayName'].Value = [string]$row.DisplayName
        $grid.Rows[$idx].Cells['ClassName'].Value = [string]$row.ClassName
        $grid.Rows[$idx].Cells['Multiplier'].Value = [string]$row.Multiplier
    }

    $btnCancel = New-Object System.Windows.Forms.Button
    $btnCancel.Text = 'Cancel'; $btnCancel.Left = 772; $btnCancel.Top = 680; $btnCancel.Width = 84; $btnCancel.Height = 28
    $btnCancel.Anchor = 'Bottom,Right'
    $btnCancel.Add_Click({ $form.Close() })
    [void]$form.Controls.Add($btnCancel)

    $btnSave = New-Object System.Windows.Forms.Button
    $btnSave.Text = 'Save'; $btnSave.Left = 864; $btnSave.Top = 680; $btnSave.Width = 88; $btnSave.Height = 28
    $btnSave.Anchor = 'Bottom,Right'
    $btnSave.Add_Click({
            $outLines = New-Object System.Collections.Generic.List[string]
            foreach ($r in $grid.Rows) {
                if ($r.IsNewRow) { continue }
                $className = [string]$r.Cells['ClassName'].Value
                $multiplier = [string]$r.Cells['Multiplier'].Value
                $line = ConvertTo-UGSMArkSEResourceMultiplierLine -ClassName $className -Multiplier $multiplier
                if (-not [string]::IsNullOrWhiteSpace([string]$line)) {
                    [void]$outLines.Add($line)
                }
            }

            Set-UGSMArkSEIniRepeatedValues -Path $gameIniPath -Section $sectionName -Key 'HarvestResourceItemAmountClassMultipliers' -Values $outLines.ToArray()
            if ($StatusLabel) {
                $StatusLabel.Text = 'Saved resource amount multipliers.'
            }
            $form.DialogResult = [System.Windows.Forms.DialogResult]::OK
            $form.Close()
        })
    [void]$form.Controls.Add($btnSave)

    [void]$form.ShowDialog()
}

function Invoke-UGSMGameArkSEDinoCustomizationBuilder {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$Instance,
        [AllowNull()][pscustomobject]$Paths,
        [AllowNull()][System.Windows.Forms.Label]$StatusLabel
    )

    if ($null -eq $Paths) {
        try { $Paths = Get-UGSMGameArkSEProfilePaths -Instance $Instance }
        catch {
            [System.Windows.Forms.MessageBox]::Show('Could not resolve ARK server paths for the dino builder: ' + $_.Exception.Message, 'ARK Dino Customization', [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error) | Out-Null
            return
        }
    }

    try { $catalog = @(Get-UGSMGameArkSEDinoCatalogForPaths -Paths $Paths) }
    catch {
        [System.Windows.Forms.MessageBox]::Show('Could not load the ARK dino catalog: ' + $_.Exception.Message, 'ARK Dino Customization', [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error) | Out-Null
        return
    }

    $gameIniPath = [string]$Paths.GameIniPath
    $sectionName = '/Script/ShooterGame.ShooterGameMode'
    $npcLines = @(Get-UGSMArkSEIniRepeatedValues -Path $gameIniPath -Section $sectionName -Key 'NPCReplacements')
    $weightLines = @(Get-UGSMArkSEIniRepeatedValues -Path $gameIniPath -Section $sectionName -Key 'DinoSpawnWeightMultipliers')
    $tamedDamageLines = @(Get-UGSMArkSEIniRepeatedValues -Path $gameIniPath -Section $sectionName -Key 'TamedDinoClassDamageMultipliers')
    $tamedResistanceLines = @(Get-UGSMArkSEIniRepeatedValues -Path $gameIniPath -Section $sectionName -Key 'TamedDinoClassResistanceMultipliers')
    $wildDamageLines = @(Get-UGSMArkSEIniRepeatedValues -Path $gameIniPath -Section $sectionName -Key 'DinoClassDamageMultipliers')
    $wildResistanceLines = @(Get-UGSMArkSEIniRepeatedValues -Path $gameIniPath -Section $sectionName -Key 'DinoClassResistanceMultipliers')
    $preventTameLines = @(Get-UGSMArkSEIniRepeatedValues -Path $gameIniPath -Section $sectionName -Key 'PreventDinoTameClassNames')
    $preventBreedLines = @(Get-UGSMArkSEIniRepeatedValues -Path $gameIniPath -Section $sectionName -Key 'PreventBreedingForClassNames')

    $rowsByClass = @{}
    foreach ($entry in $catalog) {
        $key = [string]$entry.ClassName
        if ([string]::IsNullOrWhiteSpace($key)) { continue }
        $rowsByClass[$key] = [ordered]@{
            DisplayName                  = [string]$entry.DisplayName
            ClassName                    = [string]$entry.ClassName
            DinoNameTag                  = [string]$entry.DinoNameTag
            VariantGroup                 = [string]$entry.VariantGroup
            Expansion                    = [string]$entry.Expansion
            ReplaceWith                  = ''
            SpawnWeightMultiplier        = ''
            OverrideSpawnLimitPercentage = 'False'
            SpawnLimitPercentage         = ''
            TamedDamageMultiplier        = ''
            TamedResistanceMultiplier    = ''
            WildDamageMultiplier         = ''
            WildResistanceMultiplier     = ''
            Tameable                     = if ($null -ne $entry.CanTame) { [bool]$entry.CanTame } else { $true }
            Breedable                    = if ($null -ne $entry.CanBreed) { [bool]$entry.CanBreed } else { $true }
        }
    }

    foreach ($line in $npcLines) {
        $parsed = ConvertFrom-UGSMArkSENpcReplacementLine -Line $line
        if ($null -eq $parsed) { continue }
        $from = [string]$parsed.FromClassName
        if (-not $rowsByClass.ContainsKey($from)) {
            $rowsByClass[$from] = [ordered]@{ DisplayName = $from; ClassName = $from; DinoNameTag = ''; VariantGroup = ''; Expansion = 'Custom'; ReplaceWith = ''; SpawnWeightMultiplier = ''; OverrideSpawnLimitPercentage = 'False'; SpawnLimitPercentage = ''; TamedDamageMultiplier = ''; TamedResistanceMultiplier = ''; WildDamageMultiplier = ''; WildResistanceMultiplier = ''; Tameable = $true; Breedable = $true }
        }
        $rowsByClass[$from].ReplaceWith = [string]$parsed.ToClassName
    }

    foreach ($line in $weightLines) {
        $parsed = ConvertFrom-UGSMArkSEDinoSpawnWeightLine -Line $line
        if ($null -eq $parsed) { continue }
        $tag = [string]$parsed.DinoNameTag
        $match = $null
        foreach ($row in $rowsByClass.Values) {
            if ([string]$row.DinoNameTag -eq $tag) { $match = $row; break }
        }
        if ($null -eq $match) {
            $key = '__tag__' + $tag
            $rowsByClass[$key] = [ordered]@{ DisplayName = $tag; ClassName = ''; DinoNameTag = $tag; VariantGroup = ''; Expansion = 'Custom'; ReplaceWith = ''; SpawnWeightMultiplier = ''; OverrideSpawnLimitPercentage = 'False'; SpawnLimitPercentage = ''; TamedDamageMultiplier = ''; TamedResistanceMultiplier = ''; WildDamageMultiplier = ''; WildResistanceMultiplier = ''; Tameable = $true; Breedable = $true }
            $match = $rowsByClass[$key]
        }
        $match.SpawnWeightMultiplier = [string]$parsed.SpawnWeightMultiplier
        $match.OverrideSpawnLimitPercentage = [string]$parsed.OverrideSpawnLimitPercentage
        $match.SpawnLimitPercentage = [string]$parsed.SpawnLimitPercentage
    }

    foreach ($line in $tamedDamageLines) {
        $parsed = ConvertFrom-UGSMArkSEDinoClassMultiplierLine -Line $line
        if ($null -eq $parsed) { continue }
        $className = [string]$parsed.ClassName
        if (-not $rowsByClass.ContainsKey($className)) {
            $rowsByClass[$className] = [ordered]@{ DisplayName = $className; ClassName = $className; DinoNameTag = ''; VariantGroup = ''; Expansion = 'Custom'; ReplaceWith = ''; SpawnWeightMultiplier = ''; OverrideSpawnLimitPercentage = 'False'; SpawnLimitPercentage = ''; TamedDamageMultiplier = ''; TamedResistanceMultiplier = ''; WildDamageMultiplier = ''; WildResistanceMultiplier = ''; Tameable = $true; Breedable = $true }
        }
        $rowsByClass[$className].TamedDamageMultiplier = [string]$parsed.Multiplier
    }
    foreach ($line in $tamedResistanceLines) {
        $parsed = ConvertFrom-UGSMArkSEDinoClassMultiplierLine -Line $line
        if ($null -eq $parsed) { continue }
        $className = [string]$parsed.ClassName
        if (-not $rowsByClass.ContainsKey($className)) {
            $rowsByClass[$className] = [ordered]@{ DisplayName = $className; ClassName = $className; DinoNameTag = ''; VariantGroup = ''; Expansion = 'Custom'; ReplaceWith = ''; SpawnWeightMultiplier = ''; OverrideSpawnLimitPercentage = 'False'; SpawnLimitPercentage = ''; TamedDamageMultiplier = ''; TamedResistanceMultiplier = ''; WildDamageMultiplier = ''; WildResistanceMultiplier = ''; Tameable = $true; Breedable = $true }
        }
        $rowsByClass[$className].TamedResistanceMultiplier = [string]$parsed.Multiplier
    }
    foreach ($line in $wildDamageLines) {
        $parsed = ConvertFrom-UGSMArkSEDinoClassMultiplierLine -Line $line
        if ($null -eq $parsed) { continue }
        $className = [string]$parsed.ClassName
        if (-not $rowsByClass.ContainsKey($className)) {
            $rowsByClass[$className] = [ordered]@{ DisplayName = $className; ClassName = $className; DinoNameTag = ''; VariantGroup = ''; Expansion = 'Custom'; ReplaceWith = ''; SpawnWeightMultiplier = ''; OverrideSpawnLimitPercentage = 'False'; SpawnLimitPercentage = ''; TamedDamageMultiplier = ''; TamedResistanceMultiplier = ''; WildDamageMultiplier = ''; WildResistanceMultiplier = ''; Tameable = $true; Breedable = $true }
        }
        $rowsByClass[$className].WildDamageMultiplier = [string]$parsed.Multiplier
    }
    foreach ($line in $wildResistanceLines) {
        $parsed = ConvertFrom-UGSMArkSEDinoClassMultiplierLine -Line $line
        if ($null -eq $parsed) { continue }
        $className = [string]$parsed.ClassName
        if (-not $rowsByClass.ContainsKey($className)) {
            $rowsByClass[$className] = [ordered]@{ DisplayName = $className; ClassName = $className; DinoNameTag = ''; VariantGroup = ''; Expansion = 'Custom'; ReplaceWith = ''; SpawnWeightMultiplier = ''; OverrideSpawnLimitPercentage = 'False'; SpawnLimitPercentage = ''; TamedDamageMultiplier = ''; TamedResistanceMultiplier = ''; WildDamageMultiplier = ''; WildResistanceMultiplier = ''; Tameable = $true; Breedable = $true }
        }
        $rowsByClass[$className].WildResistanceMultiplier = [string]$parsed.Multiplier
    }

    foreach ($line in $preventTameLines) {
        $className = [string]$line
        if ([string]::IsNullOrWhiteSpace($className)) { continue }
        $className = $className.Trim().Trim('"')
        if ([string]::IsNullOrWhiteSpace($className)) { continue }
        if (-not $rowsByClass.ContainsKey($className)) {
            $rowsByClass[$className] = [ordered]@{ DisplayName = $className; ClassName = $className; DinoNameTag = ''; VariantGroup = ''; Expansion = 'Custom'; ReplaceWith = ''; SpawnWeightMultiplier = ''; OverrideSpawnLimitPercentage = 'False'; SpawnLimitPercentage = ''; TamedDamageMultiplier = ''; TamedResistanceMultiplier = ''; WildDamageMultiplier = ''; WildResistanceMultiplier = ''; Tameable = $true; Breedable = $true }
        }
        $rowsByClass[$className].Tameable = $false
    }

    foreach ($line in $preventBreedLines) {
        $className = [string]$line
        if ([string]::IsNullOrWhiteSpace($className)) { continue }
        $className = $className.Trim().Trim('"')
        if ([string]::IsNullOrWhiteSpace($className)) { continue }
        if (-not $rowsByClass.ContainsKey($className)) {
            $rowsByClass[$className] = [ordered]@{ DisplayName = $className; ClassName = $className; DinoNameTag = ''; VariantGroup = ''; Expansion = 'Custom'; ReplaceWith = ''; SpawnWeightMultiplier = ''; OverrideSpawnLimitPercentage = 'False'; SpawnLimitPercentage = ''; TamedDamageMultiplier = ''; TamedResistanceMultiplier = ''; WildDamageMultiplier = ''; WildResistanceMultiplier = ''; Tameable = $true; Breedable = $true }
        }
        $rowsByClass[$className].Breedable = $false
    }

    $form = New-Object System.Windows.Forms.Form
    $form.Text = 'ARK Dino Customization'
    $form.StartPosition = 'CenterParent'
    $form.Width = 1450
    $form.Height = 760
    $form.BackColor = New-UGSMColor '#11161C'
    $form.ForeColor = New-UGSMColor '#F5F7FA'

    $info = New-Object System.Windows.Forms.Label
    $info.Left = 12; $info.Top = 12; $info.Width = 1410; $info.Height = 36
    $info.ForeColor = New-UGSMColor '#C7D0D9'
    $info.Text = 'This grid loads existing Game.ini changes first, then fills in the remaining dinos from the shared catalog for the current map. Save writes NPCReplacements, DinoSpawnWeightMultipliers, the four dino class multiplier groups, and tame/breed restriction lists.'
    [void]$form.Controls.Add($info)

    $grid = New-Object System.Windows.Forms.DataGridView
    $grid.Left = 12; $grid.Top = 56; $grid.Width = 1410; $grid.Height = 610
    $grid.AllowUserToAddRows = $false
    $grid.AllowUserToDeleteRows = $false
    $grid.AutoSizeColumnsMode = 'Fill'
    $grid.BackgroundColor = [System.Drawing.Color]::White
    $grid.ForeColor = [System.Drawing.Color]::Black
    $grid.SelectionMode = 'FullRowSelect'
    $grid.MultiSelect = $false
    $grid.RowHeadersVisible = $false
    [void]$grid.Columns.Add('DisplayName', 'Dino')
    [void]$grid.Columns.Add('ClassName', 'Class Name')
    [void]$grid.Columns.Add('DinoNameTag', 'Dino Tag')
    $replaceCol = New-Object System.Windows.Forms.DataGridViewComboBoxColumn
    $replaceCol.Name = 'ReplaceWith'
    $replaceCol.HeaderText = 'Replace With'
    $replaceCol.DisplayStyle = 'DropDownButton'
    $replaceCol.FlatStyle = 'Standard'
    $replaceCol.AutoComplete = $true
    [void]$grid.Columns.Add($replaceCol)
    [void]$grid.Columns.Add('SpawnWeightMultiplier', 'Spawn Weight')
    $overrideCol = New-Object System.Windows.Forms.DataGridViewCheckBoxColumn
    $overrideCol.Name = 'OverrideSpawnLimitPercentage'; $overrideCol.HeaderText = 'Override Limit'
    [void]$grid.Columns.Add($overrideCol)
    [void]$grid.Columns.Add('SpawnLimitPercentage', 'Spawn Limit')
    [void]$grid.Columns.Add('TamedDamageMultiplier', 'Tamed Damage')
    [void]$grid.Columns.Add('TamedResistanceMultiplier', 'Tamed Resistance')
    [void]$grid.Columns.Add('WildDamageMultiplier', 'Wild Damage')
    [void]$grid.Columns.Add('WildResistanceMultiplier', 'Wild Resistance')
    $tameableCol = New-Object System.Windows.Forms.DataGridViewCheckBoxColumn
    $tameableCol.Name = 'Tameable'; $tameableCol.HeaderText = 'Tameable'
    [void]$grid.Columns.Add($tameableCol)
    $breedableCol = New-Object System.Windows.Forms.DataGridViewCheckBoxColumn
    $breedableCol.Name = 'Breedable'; $breedableCol.HeaderText = 'Breedable'
    [void]$grid.Columns.Add($breedableCol)
    [void]$grid.Columns.Add('Expansion', 'Expansion')
    [void]$form.Controls.Add($grid)

    $sorted = @($rowsByClass.Values | Sort-Object DisplayName, ClassName)
    $catalogByDisplay = @{}
    $catalogByClass = @{}
    $replaceChoices = New-Object System.Collections.Generic.List[string]
    [void]$replaceChoices.Add('')
    [void]$replaceChoices.Add('[Disable Spawn]')

    foreach ($entry in ($catalog | Sort-Object DisplayName, ClassName)) {
        $display = [string]$entry.DisplayName
        $class = [string]$entry.ClassName
        if ([string]::IsNullOrWhiteSpace($display) -or [string]::IsNullOrWhiteSpace($class)) { continue }
        if (-not $catalogByDisplay.ContainsKey($display)) {
            $catalogByDisplay[$display] = $class
            [void]$replaceChoices.Add($display)
        }
        if (-not $catalogByClass.ContainsKey($class)) {
            $catalogByClass[$class] = $display
        }
    }
    foreach ($choice in $replaceChoices) {
        [void]$replaceCol.Items.Add($choice)
    }

    foreach ($row in $sorted) {
        $idx = $grid.Rows.Add()
        $grid.Rows[$idx].Cells['DisplayName'].Value = [string]$row.DisplayName
        $grid.Rows[$idx].Cells['ClassName'].Value = [string]$row.ClassName
        $grid.Rows[$idx].Cells['DinoNameTag'].Value = [string]$row.DinoNameTag
        $replaceWithClass = [string]$row.ReplaceWith
        if ([string]::IsNullOrWhiteSpace($replaceWithClass)) {
            $grid.Rows[$idx].Cells['ReplaceWith'].Value = ''
        }
        elseif ($catalogByClass.ContainsKey($replaceWithClass)) {
            $grid.Rows[$idx].Cells['ReplaceWith'].Value = [string]$catalogByClass[$replaceWithClass]
        }
        else {
            $grid.Rows[$idx].Cells['ReplaceWith'].Value = '[Disable Spawn]'
        }
        $grid.Rows[$idx].Cells['SpawnWeightMultiplier'].Value = [string]$row.SpawnWeightMultiplier
        $grid.Rows[$idx].Cells['OverrideSpawnLimitPercentage'].Value = ([string]$row.OverrideSpawnLimitPercentage).ToLowerInvariant() -eq 'true'
        $grid.Rows[$idx].Cells['SpawnLimitPercentage'].Value = [string]$row.SpawnLimitPercentage
        $grid.Rows[$idx].Cells['TamedDamageMultiplier'].Value = [string]$row.TamedDamageMultiplier
        $grid.Rows[$idx].Cells['TamedResistanceMultiplier'].Value = [string]$row.TamedResistanceMultiplier
        $grid.Rows[$idx].Cells['WildDamageMultiplier'].Value = [string]$row.WildDamageMultiplier
        $grid.Rows[$idx].Cells['WildResistanceMultiplier'].Value = [string]$row.WildResistanceMultiplier
        $grid.Rows[$idx].Cells['Tameable'].Value = [bool]$row.Tameable
        $grid.Rows[$idx].Cells['Breedable'].Value = [bool]$row.Breedable
        $grid.Rows[$idx].Cells['Expansion'].Value = [string]$row.Expansion
    }

    $btnCancel = New-Object System.Windows.Forms.Button
    $btnCancel.Text = 'Cancel'; $btnCancel.Left = 1240; $btnCancel.Top = 676; $btnCancel.Width = 84; $btnCancel.Height = 28
    $btnCancel.Add_Click({ $form.Close() })
    [void]$form.Controls.Add($btnCancel)

    $btnSave = New-Object System.Windows.Forms.Button
    $btnSave.Text = 'Save'; $btnSave.Left = 1334; $btnSave.Top = 676; $btnSave.Width = 88; $btnSave.Height = 28
    $btnSave.Add_Click({
            $npcOut = New-Object System.Collections.Generic.List[string]
            $weightOut = New-Object System.Collections.Generic.List[string]
            $tamedDamageOut = New-Object System.Collections.Generic.List[string]
            $tamedResistanceOut = New-Object System.Collections.Generic.List[string]
            $wildDamageOut = New-Object System.Collections.Generic.List[string]
            $wildResistanceOut = New-Object System.Collections.Generic.List[string]
            $preventTameOut = New-Object System.Collections.Generic.List[string]
            $preventBreedOut = New-Object System.Collections.Generic.List[string]
            foreach ($r in $grid.Rows) {
                if ($r.IsNewRow) { continue }
                $className = [string]$r.Cells['ClassName'].Value
                $tag = [string]$r.Cells['DinoNameTag'].Value
                $replaceWithSelection = [string]$r.Cells['ReplaceWith'].Value
                $replaceMode = 'None'
                $replaceWith = ''
                if ([string]::IsNullOrWhiteSpace($replaceWithSelection)) {
                    $replaceMode = 'None'
                }
                elseif ($replaceWithSelection -eq '[Disable Spawn]') {
                    $replaceMode = 'Disable'
                    $replaceWith = ''
                }
                elseif ($catalogByDisplay.ContainsKey($replaceWithSelection)) {
                    $replaceMode = 'Replace'
                    $replaceWith = [string]$catalogByDisplay[$replaceWithSelection]
                }
                $spawnWeight = [string]$r.Cells['SpawnWeightMultiplier'].Value
                $override = if ([bool]$r.Cells['OverrideSpawnLimitPercentage'].Value) { 'True' } else { 'False' }
                $spawnLimit = [string]$r.Cells['SpawnLimitPercentage'].Value
                $tamedDamage = [string]$r.Cells['TamedDamageMultiplier'].Value
                $tamedResistance = [string]$r.Cells['TamedResistanceMultiplier'].Value
                $wildDamage = [string]$r.Cells['WildDamageMultiplier'].Value
                $wildResistance = [string]$r.Cells['WildResistanceMultiplier'].Value
                $tameable = [bool]$r.Cells['Tameable'].Value
                $breedable = [bool]$r.Cells['Breedable'].Value

                if ($replaceMode -eq 'Replace') {
                    $npcLine = ConvertTo-UGSMArkSENpcReplacementLine -FromClassName $className -ToClassName $replaceWith
                    if (-not [string]::IsNullOrWhiteSpace([string]$npcLine)) { [void]$npcOut.Add($npcLine) }
                }
                elseif ($replaceMode -eq 'Disable' -and -not [string]::IsNullOrWhiteSpace($className)) {
                    [void]$npcOut.Add('(FromClassName="' + $className + '",ToClassName="")')
                }

                $weightLine = ConvertTo-UGSMArkSEDinoSpawnWeightLine -DinoNameTag $tag -SpawnWeightMultiplier $spawnWeight -OverrideSpawnLimitPercentage $override -SpawnLimitPercentage $spawnLimit
                if (-not [string]::IsNullOrWhiteSpace([string]$spawnWeight) -and -not [string]::IsNullOrWhiteSpace([string]$weightLine)) { [void]$weightOut.Add($weightLine) }

                $line = ConvertTo-UGSMArkSEDinoClassMultiplierLine -ClassName $className -Multiplier $tamedDamage
                if (-not [string]::IsNullOrWhiteSpace([string]$line)) { [void]$tamedDamageOut.Add($line) }
                $line = ConvertTo-UGSMArkSEDinoClassMultiplierLine -ClassName $className -Multiplier $tamedResistance
                if (-not [string]::IsNullOrWhiteSpace([string]$line)) { [void]$tamedResistanceOut.Add($line) }
                $line = ConvertTo-UGSMArkSEDinoClassMultiplierLine -ClassName $className -Multiplier $wildDamage
                if (-not [string]::IsNullOrWhiteSpace([string]$line)) { [void]$wildDamageOut.Add($line) }
                $line = ConvertTo-UGSMArkSEDinoClassMultiplierLine -ClassName $className -Multiplier $wildResistance
                if (-not [string]::IsNullOrWhiteSpace([string]$line)) { [void]$wildResistanceOut.Add($line) }

                if (-not [string]::IsNullOrWhiteSpace($className)) {
                    if (-not $tameable) { [void]$preventTameOut.Add('"' + $className + '"') }
                    if (-not $breedable) { [void]$preventBreedOut.Add('"' + $className + '"') }
                }
            }
            Set-UGSMArkSEIniRepeatedValues -Path $gameIniPath -Section $sectionName -Key 'NPCReplacements' -Values $npcOut.ToArray()
            Set-UGSMArkSEIniRepeatedValues -Path $gameIniPath -Section $sectionName -Key 'DinoSpawnWeightMultipliers' -Values $weightOut.ToArray()
            Set-UGSMArkSEIniRepeatedValues -Path $gameIniPath -Section $sectionName -Key 'TamedDinoClassDamageMultipliers' -Values $tamedDamageOut.ToArray()
            Set-UGSMArkSEIniRepeatedValues -Path $gameIniPath -Section $sectionName -Key 'TamedDinoClassResistanceMultipliers' -Values $tamedResistanceOut.ToArray()
            Set-UGSMArkSEIniRepeatedValues -Path $gameIniPath -Section $sectionName -Key 'DinoClassDamageMultipliers' -Values $wildDamageOut.ToArray()
            Set-UGSMArkSEIniRepeatedValues -Path $gameIniPath -Section $sectionName -Key 'DinoClassResistanceMultipliers' -Values $wildResistanceOut.ToArray()
            Set-UGSMArkSEIniRepeatedValues -Path $gameIniPath -Section $sectionName -Key 'PreventDinoTameClassNames' -Values $preventTameOut.ToArray()
            Set-UGSMArkSEIniRepeatedValues -Path $gameIniPath -Section $sectionName -Key 'PreventBreedingForClassNames' -Values $preventBreedOut.ToArray()
            if ($StatusLabel) { $StatusLabel.Text = 'Saved ARK dino customization changes.' }
            [System.Windows.Forms.MessageBox]::Show('Saved NPC replacements, spawn weights, dino damage/resistance multipliers, and tame/breed restrictions.', 'ARK Dino Customization', [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information) | Out-Null
            $form.Close()
        })
    [void]$form.Controls.Add($btnSave)

    [void]$form.ShowDialog()
}


# Shared dino catalog for ArkSE and ArkSA
# Intended for builder windows and filtering, not for direct INI storage.

function Get-UGSMArkDinoCatalog {
    [CmdletBinding()]
    param(
        [string]$GameId,
        [string]$MapName
    )

    $catalog = New-Object System.Collections.Generic.List[pscustomobject]

    $AddDino = {
        param(
            [string]$CatalogId,
            [string]$DisplayName,
            [string]$ClassName,
            [string]$Tag,
            [string[]]$Games,
            [string[]]$Maps,
            [string]$Expansion,
            [string]$VariantGroup,
            [string]$SpawnSource,
            [bool]$Spawn,
            [bool]$Tame,
            [bool]$Breed
        )

        $catalog.Add([pscustomobject]@{
                CatalogId         = $CatalogId
                DisplayName       = $DisplayName
                ClassName         = $ClassName
                DinoNameTag       = $Tag
                Games             = $Games
                Maps              = $Maps
                Expansion         = $Expansion
                VariantGroup      = $VariantGroup
                SpawnSource       = $SpawnSource
                CanSpawnNaturally = $Spawn
                CanTame           = $Tame
                CanBreed          = $Breed
            })
    }

    # Canonical map tokens used by ARK launch/config.
    $AllMaps = @('TheIsland', 'TheCenter', 'ScorchedEarth_P', 'Ragnarok', 'Aberration_P', 'Extinction', 'Valguero_P', 'Genesis', 'CrystalIsles', 'Gen2', 'LostIsland', 'Fjordur')
    $IslandPlus = @('TheIsland', 'TheCenter', 'Ragnarok', 'Valguero_P', 'CrystalIsles', 'LostIsland', 'Fjordur')
    $ScorchedPlus = @('ScorchedEarth_P', 'Ragnarok', 'Valguero_P', 'CrystalIsles', 'LostIsland', 'Fjordur')
    $AberrationSet = @('Aberration_P', 'Valguero_P', 'Fjordur')

    # --- BASE GAME / COMMON ---
    & $AddDino 'AberrantAngler'            'Aberrant Angler'            'Angler_Character_BP_Aberrant_C'        'Angler'        @('ArkSE', 'ArkSA') @('Aberration_P', 'Valguero_P', 'CrystalIsles', 'Gen2', 'Fjordur') 'Aberration'      'Aberrant'  'Natural' $true  $true  $false
    & $AddDino 'AberrantAnkylo'            'Aberrant Ankylosaurus'      'Ankylo_Character_BP_Aberrant_C'        'Anky'          @('ArkSE', 'ArkSA') @('Aberration_P', 'Valguero_P', 'CrystalIsles', 'Gen2', 'Fjordur') 'Aberration'      'Aberrant'  'Natural' $true  $true  $true
    & $AddDino 'AberrantAraneo'            'Aberrant Araneo'            'SpiderS_Character_BP_Aberrant_C'       'SpiderS'       @('ArkSE', 'ArkSA') @('Aberration_P', 'Valguero_P', 'CrystalIsles', 'Gen2', 'Fjordur') 'Aberration'      'Aberrant'  'Natural' $true  $true  $true
    & $AddDino 'AberrantArthro'            'Aberrant Arthropluera'      'Arthro_Character_BP_Aberrant_C'        'Arthro'        @('ArkSE', 'ArkSA') @('Aberration_P', 'Valguero_P', 'CrystalIsles', 'Gen2', 'Fjordur') 'Aberration'      'Aberrant'  'Natural' $true  $true  $true
    & $AddDino 'AberrantBaryonyx'          'Aberrant Baryonyx'          'Baryonyx_Character_BP_Aberrant_C'      'Baryonyx'      @('ArkSE', 'ArkSA') @('Aberration_P', 'Valguero_P', 'CrystalIsles', 'Gen2', 'Fjordur') 'Aberration'      'Aberrant'  'Natural' $true  $true  $true
    & $AddDino 'AberrantBeelzebufo'        'Aberrant Beelzebufo'        'Toad_Character_BP_Aberrant_C'          'Toad'          @('ArkSE', 'ArkSA') @('Aberration_P', 'Valguero_P', 'CrystalIsles', 'Gen2', 'Fjordur') 'Aberration'      'Aberrant'  'Natural' $true  $true  $true
    & $AddDino 'AberrantCarbonemys'        'Aberrant Carbonemys'        'Turtle_Character_BP_Aberrant_C'        'Turtle'        @('ArkSE', 'ArkSA') @('Aberration_P', 'Valguero_P', 'CrystalIsles', 'Gen2', 'Fjordur') 'Aberration'      'Aberrant'  'Natural' $true  $true  $true
    & $AddDino 'AberrantCarno'             'Aberrant Carnotaurus'       'Carno_Character_BP_Aberrant_C'         'Carno'         @('ArkSE', 'ArkSA') @('Aberration_P', 'Valguero_P', 'CrystalIsles', 'Gen2', 'Fjordur') 'Aberration'      'Aberrant'  'Natural' $true  $true  $true
    & $AddDino 'AberrantCnidaria'          'Aberrant Cnidaria'          'Cnidaria_Character_BP_Aberrant_C'      'Cnidaria'      @('ArkSE', 'ArkSA') @('Aberration_P', 'Valguero_P', 'CrystalIsles', 'Gen2', 'Fjordur') 'Aberration'      'Aberrant'  'Natural' $true  $false $false
    & $AddDino 'AberrantCoel'              'Aberrant Coelacanth'        'Coel_Character_BP_Aberrant_C'          'Coel'          @('ArkSE', 'ArkSA') @('Aberration_P', 'Valguero_P', 'CrystalIsles', 'Gen2', 'Fjordur') 'Aberration'      'Aberrant'  'Natural' $true  $false $false
    & $AddDino 'AberrantDimetrodon'        'Aberrant Dimetrodon'        'Dimetro_Character_BP_Aberrant_C'       'Dimetro'       @('ArkSE', 'ArkSA') @('Aberration_P', 'Valguero_P', 'CrystalIsles', 'Gen2', 'Fjordur') 'Aberration'      'Aberrant'  'Natural' $true  $true  $true
    & $AddDino 'AberrantDimorphodon'       'Aberrant Dimorphodon'       'Dimorph_Character_BP_Aberrant_C'       'Dimorph'       @('ArkSE', 'ArkSA') @('Aberration_P', 'Valguero_P', 'CrystalIsles', 'Gen2', 'Fjordur') 'Aberration'      'Aberrant'  'Natural' $true  $true  $true
    & $AddDino 'AberrantDiplocaulus'       'Aberrant Diplocaulus'       'Diplocaulus_Character_BP_Aberrant_C'   'Diplocaulus'   @('ArkSE', 'ArkSA') @('Aberration_P', 'Valguero_P', 'CrystalIsles', 'Gen2', 'Fjordur') 'Aberration'      'Aberrant'  'Natural' $true  $true  $true
    & $AddDino 'AberrantDiplodocus'        'Aberrant Diplodocus'        'Diplodocus_Character_BP_Aberrant_C'    'Diplodocus'    @('ArkSE', 'ArkSA') @('Aberration_P', 'Valguero_P', 'CrystalIsles', 'Gen2', 'Fjordur') 'Aberration'      'Aberrant'  'Natural' $true  $true  $true
    & $AddDino 'AberrantDirebear'          'Aberrant Direbear'          'Direbear_Character_BP_Aberrant_C'      'Direbear'      @('ArkSE', 'ArkSA') @('Aberration_P', 'Valguero_P', 'CrystalIsles', 'Gen2', 'Fjordur') 'Aberration'      'Aberrant'  'Natural' $true  $true  $true
    & $AddDino 'AberrantDodo'              'Aberrant Dodo'              'Dodo_Character_BP_Aberrant_C'          'Dodo'          @('ArkSE', 'ArkSA') @('Aberration_P', 'Valguero_P', 'CrystalIsles', 'Gen2', 'Fjordur') 'Aberration'      'Aberrant'  'Natural' $true  $true  $true
    & $AddDino 'AberrantDoed'              'Aberrant Doedicurus'        'Doed_Character_BP_Aberrant_C'          'Doed'          @('ArkSE', 'ArkSA') @('Aberration_P', 'Valguero_P', 'CrystalIsles', 'Gen2', 'Fjordur') 'Aberration'      'Aberrant'  'Natural' $true  $true  $true
    & $AddDino 'AberrantDungBeetle'        'Aberrant Dung Beetle'       'DungBeetle_Character_BP_Aberrant_C'    'DungBeetle'    @('ArkSE', 'ArkSA') @('Aberration_P', 'Valguero_P', 'CrystalIsles', 'Gen2', 'Fjordur') 'Aberration'      'Aberrant'  'Natural' $true  $true  $false
    & $AddDino 'AberrantEel'               'Aberrant Electrophorus'     'Eel_Character_BP_Aberrant_C'           'Eel'           @('ArkSE', 'ArkSA') @('Aberration_P', 'Valguero_P', 'CrystalIsles', 'Gen2', 'Fjordur') 'Aberration'      'Aberrant'  'Natural' $true  $true  $false
    & $AddDino 'AberrantEquus'             'Aberrant Equus'             'Equus_Character_BP_Aberrant_C'         'Equus'         @('ArkSE', 'ArkSA') @('Aberration_P', 'Valguero_P', 'CrystalIsles', 'Gen2', 'Fjordur') 'Aberration'      'Aberrant'  'Natural' $true  $true  $true
    & $AddDino 'AberrantBigfoot'           'Aberrant Gigantopithecus'   'Bigfoot_Character_BP_Aberrant_C'       'Bigfoot'       @('ArkSE', 'ArkSA') @('Aberration_P', 'Valguero_P', 'CrystalIsles', 'Gen2', 'Fjordur') 'Aberration'      'Aberrant'  'Natural' $true  $true  $false
    & $AddDino 'AberrantIguanodon'         'Aberrant Iguanodon'         'Iguanodon_Character_BP_Aberrant_C'     'Iguanodon'     @('ArkSE', 'ArkSA') @('Aberration_P', 'Valguero_P', 'CrystalIsles', 'Gen2', 'Fjordur') 'Aberration'      'Aberrant'  'Natural' $true  $true  $true
    & $AddDino 'AberrantLystro'            'Aberrant Lystrosaurus'      'Lystro_Character_BP_Aberrant_C'        'Lystro'        @('ArkSE', 'ArkSA') @('Aberration_P', 'Valguero_P', 'CrystalIsles', 'Gen2', 'Fjordur') 'Aberration'      'Aberrant'  'Natural' $true  $true  $true
    & $AddDino 'AberrantManta'             'Aberrant Manta'             'Manta_Character_BP_Aberrant_C'         'Manta'         @('ArkSE', 'ArkSA') @('Aberration_P', 'Valguero_P', 'CrystalIsles', 'Gen2', 'Fjordur') 'Aberration'      'Aberrant'  'Natural' $true  $true  $false
    & $AddDino 'AberrantMegalania'         'Aberrant Megalania'         'Megalania_Character_BP_Aberrant_C'     'Megalania'     @('ArkSE', 'ArkSA') @('Aberration_P', 'Valguero_P', 'CrystalIsles', 'Gen2', 'Fjordur') 'Aberration'      'Aberrant'  'Natural' $true  $true  $true
    & $AddDino 'AberrantMegalosaurus'      'Aberrant Megalosaurus'      'Megalosaurus_Character_BP_Aberrant_C'  'Megalosaurus'  @('ArkSE', 'ArkSA') @('Aberration_P', 'Valguero_P', 'CrystalIsles', 'Gen2', 'Fjordur') 'Aberration'      'Aberrant'  'Natural' $true  $true  $true
    & $AddDino 'AberrantMeganeura'         'Aberrant Meganeura'         'Dragonfly_Character_BP_Aberrant_C'     'Dragonfly'     @('ArkSE', 'ArkSA') @('Aberration_P', 'Valguero_P', 'CrystalIsles', 'Gen2', 'Fjordur') 'Aberration'      'Aberrant'  'Natural' $true  $false $false
    & $AddDino 'AberrantMoschops'          'Aberrant Moschops'          'Moschops_Character_BP_Aberrant_C'      'Moschops'      @('ArkSE', 'ArkSA') @('Aberration_P', 'Valguero_P', 'CrystalIsles', 'Gen2', 'Fjordur') 'Aberration'      'Aberrant'  'Natural' $true  $true  $true
    & $AddDino 'AberrantOtter'             'Aberrant Otter'             'Otter_Character_BP_Aberrant_C'         'Otter'         @('ArkSE', 'ArkSA') @('Aberration_P', 'Valguero_P', 'CrystalIsles', 'Gen2', 'Fjordur') 'Aberration'      'Aberrant'  'Natural' $true  $true  $true
    & $AddDino 'AberrantOvis'              'Aberrant Ovis'              'Sheep_Character_BP_Aberrant_C'         'Sheep'         @('ArkSE', 'ArkSA') @('Aberration_P', 'Valguero_P', 'CrystalIsles', 'Gen2', 'Fjordur') 'Aberration'      'Aberrant'  'Natural' $true  $true  $true
    & $AddDino 'AberrantParacer'           'Aberrant Paraceratherium'   'Paracer_Character_BP_Aberrant_C'       'Paracer'       @('ArkSE', 'ArkSA') @('Aberration_P', 'Valguero_P', 'CrystalIsles', 'Gen2', 'Fjordur') 'Aberration'      'Aberrant'  'Natural' $true  $true  $true
    & $AddDino 'AberrantPara'              'Aberrant Parasaurolophus'   'Para_Character_BP_Aberrant_C'          'Para'          @('ArkSE', 'ArkSA') @('Aberration_P', 'Valguero_P', 'CrystalIsles', 'Gen2', 'Fjordur') 'Aberration'      'Aberrant'  'Natural' $true  $true  $true
    & $AddDino 'AberrantPiranha'           'Aberrant Piranha'           'Piranha_Character_BP_Aberrant_C'       'Piranha'       @('ArkSE', 'ArkSA') @('Aberration_P', 'Valguero_P', 'CrystalIsles', 'Gen2', 'Fjordur') 'Aberration'      'Aberrant'  'Natural' $true  $false $false
    & $AddDino 'AberrantScorpion'          'Aberrant Pulmonoscorpius'   'Scorpion_Character_BP_Aberrant_C'      'Scorpion'      @('ArkSE', 'ArkSA') @('Aberration_P', 'Valguero_P', 'CrystalIsles', 'Gen2', 'Fjordur') 'Aberration'      'Aberrant'  'Natural' $true  $true  $false
    & $AddDino 'AberrantPurlovia'          'Aberrant Purlovia'          'Purlovia_Character_BP_Aberrant_C'      'Purlovia'      @('ArkSE', 'ArkSA') @('Aberration_P', 'Valguero_P', 'CrystalIsles', 'Gen2', 'Fjordur') 'Aberration'      'Aberrant'  'Natural' $true  $true  $false
    & $AddDino 'AberrantRaptor'            'Aberrant Raptor'            'Raptor_Character_BP_Aberrant_C'        'Raptor'        @('ArkSE', 'ArkSA') @('Aberration_P', 'Valguero_P', 'CrystalIsles', 'Gen2', 'Fjordur') 'Aberration'      'Aberrant'  'Natural' $true  $true  $true
    & $AddDino 'AberrantSalmon'            'Aberrant Sabertooth Salmon' 'Salmon_Character_Aberrant_C'           'Salmon'        @('ArkSE', 'ArkSA') @('Aberration_P', 'Valguero_P', 'CrystalIsles', 'Gen2', 'Fjordur') 'Aberration'      'Aberrant'  'Natural' $true  $false $false
    & $AddDino 'AberrantSarco'             'Aberrant Sarcosuchus'       'Sarco_Character_BP_Aberrant_C'         'Sarco'         @('ArkSE', 'ArkSA') @('Aberration_P', 'Valguero_P', 'CrystalIsles', 'Gen2', 'Fjordur') 'Aberration'      'Aberrant'  'Natural' $true  $true  $true
    & $AddDino 'AberrantSpino'             'Aberrant Spinosaurus'       'Spino_Character_BP_Aberrant_C'         'Spino'         @('ArkSE', 'ArkSA') @('Aberration_P', 'Valguero_P', 'CrystalIsles', 'Gen2', 'Fjordur') 'Aberration'      'Aberrant'  'Natural' $true  $true  $true
    & $AddDino 'AberrantStego'             'Aberrant Stegosaurus'       'Stego_Character_BP_Aberrant_C'         'Stego'         @('ArkSE', 'ArkSA') @('Aberration_P', 'Valguero_P', 'CrystalIsles', 'Gen2', 'Fjordur') 'Aberration'      'Aberrant'  'Natural' $true  $true  $true
    & $AddDino 'AberrantTitanoboa'         'Aberrant Titanoboa'         'BoaFrill_Character_BP_Aberrant_C'      'BoaFrill'      @('ArkSE', 'ArkSA') @('Aberration_P', 'Valguero_P', 'CrystalIsles', 'Gen2', 'Fjordur') 'Aberration'      'Aberrant'  'Natural' $true  $true  $false
    & $AddDino 'AberrantTrike'             'Aberrant Triceratops'       'Trike_Character_BP_Aberrant_C'         'Trike'         @('ArkSE', 'ArkSA') @('Aberration_P', 'Valguero_P', 'CrystalIsles', 'Gen2', 'Fjordur') 'Aberration'      'Aberrant'  'Natural' $true  $true  $true
    & $AddDino 'AberrantTrilobite'         'Aberrant Trilobite'         'Trilobite_Character_Aberrant_C'        'Trilobite'     @('ArkSE', 'ArkSA') @('Aberration_P', 'Valguero_P', 'CrystalIsles', 'Gen2', 'Fjordur') 'Aberration'      'Aberrant'  'Natural' $true  $false $false
    & $AddDino 'Achatina'                  'Achatina'                   'Achatina_Character_BP_C'               'Achatina'      @('ArkSE', 'ArkSA') $AllMaps         'Base Game'       'Standard'  'Natural' $true  $true  $true
    & $AddDino 'Allosaurus'                'Allosaurus'                 'Allo_Character_BP_C'                   'Allo'          @('ArkSE', 'ArkSA') $AllMaps         'Base Game'       'Standard'  'Natural' $true  $true  $true
    & $AddDino 'AlphaBasilisk'             'Alpha Basilisk'             'MegaBasilisk_Character_BP_C'           'MegaBasilisk'  @('ArkSE', 'ArkSA') @('Aberration_P') 'Aberration'      'Alpha'     'Natural' $true  $false $false
    & $AddDino 'AlphaBloodWyvern'          'Alpha Blood Crystal Wyvern' 'CrystalWyvern_Character_BP_Mega_C'     'CrystalWyvern' @('ArkSE', 'ArkSA') @('CrystalIsles') 'Crystal Isles'   'Alpha'     'Natural' $true  $false $false
    & $AddDino 'AlphaCarno'                'Alpha Carnotaurus'          'MegaCarno_Character_BP_C'              'MegaCarno'     @('ArkSE', 'ArkSA') $AllMaps         'Base Game'       'Alpha'     'Natural' $true  $false $false
    & $AddDino 'AlphaDeathworm'            'Alpha Deathworm'            'MegaDeathworm_Character_BP_C'          'MegaDeathworm' @('ArkSE', 'ArkSA') @('ScorchedEarth_P') 'Scorched Earth'  'Alpha'     'Natural' $true  $false $false
    & $AddDino 'AlphaFireWyvern'           'Alpha Fire Wyvern'          'MegaWyvern_Character_BP_Fire_C'        'MegaWyvern'    @('ArkSE', 'ArkSA') @('ScorchedEarth_P') 'Scorched Earth'  'Alpha'     'Natural' $true  $false $false
    & $AddDino 'AlphaKarkinos'             'Alpha Karkinos'             'MegaCrab_Character_BP_C'               'MegaCrab'      @('ArkSE', 'ArkSA') @('Aberration_P') 'Aberration'      'Alpha'     'Natural' $true  $false $false
    & $AddDino 'AlphaLeeds'                'Alpha Leedsichthys'         'Alpha_Leedsichthys_Character_BP_C'     'Alpha_Leeds'   @('ArkSE', 'ArkSA') $AllMaps         'Base Game'       'Alpha'     'Natural' $true  $false $false
    & $AddDino 'AlphaMegalodon'            'Alpha Megalodon'            'MegaMegalodon_Character_BP_C'          'MegaMegalodon' @('ArkSE', 'ArkSA') $AllMaps         'Base Game'       'Alpha'     'Natural' $true  $false $false
    & $AddDino 'AlphaMosa'                 'Alpha Mosasaur'             'Mosa_Character_BP_Mega_C'              'MegaMosa'      @('ArkSE', 'ArkSA') $AllMaps         'Base Game'       'Alpha'     'Natural' $true  $false $false
    & $AddDino 'AlphaMosaCave'             'Alpha Mosasaur (Cave)'      'Mosa_Character_BP_Mega_Cave_C'         'MegaMosa'      @('ArkSE', 'ArkSA') $AllMaps         'Base Game'       'Alpha'     'Natural' $true  $false $false
    & $AddDino 'AlphaRaptor'               'Alpha Raptor'               'MegaRaptor_Character_BP_C'             'MegaRaptor'    @('ArkSE', 'ArkSA') $AllMaps         'Base Game'       'Alpha'     'Natural' $true  $false $false
    & $AddDino 'AlphaRex'                  'Alpha Rex'                  'MegaRex_Character_BP_C'                'MegaRex'       @('ArkSE', 'ArkSA') $AllMaps         'Base Game'       'Alpha'     'Natural' $true  $false $false
    & $AddDino 'AlphaReaperKing'           'Alpha Surface Reaper King'  'MegaXenomorph_Character_BP_Male_Surface_C' 'MegaXeno' @('ArkSE', 'ArkSA') @('Aberration_P') 'Aberration'      'Alpha'     'Natural' $true  $false $false
    & $AddDino 'AlphaTuso'                 'Alpha Tusoteuthis'          'Mega_Tusoteuthis_Character_BP_C'       'MegaTuso'      @('ArkSE', 'ArkSA') $AllMaps         'Base Game'       'Alpha'     'Natural' $true  $false $false
    & $AddDino 'Amargasaurus'              'Amargasaurus'               'Amargasaurus_Character_BP_C'           'Amargasaur'    @('ArkSE', 'ArkSA') @('LostIsland')   'Lost Island'     'Standard'  'Natural' $true  $true  $true
    & $AddDino 'AmargasaurusMinion'        'Amargasaurus (Minion)'      'Amargasaurus_Character_BP_Minion_C'    'Amargasaur'    @('ArkSE', 'ArkSA') @('LostIsland')   'Lost Island'     'Minion'    'Natural' $false $false $false
    & $AddDino 'Ammonite'                  'Ammonite'                   'Ammonite_Character_C'                  'Ammonite'      @('ArkSE', 'ArkSA') $AllMaps         'Base Game'       'Standard'  'Natural' $true  $false $false
    & $AddDino 'Andrewsarchus'             'Andrewsarchus'              'Andrewsarchus_Character_BP_C'          'Andrewsarch'   @('ArkSE', 'ArkSA') @('Fjordur')      'Fjordur'         'Standard'  'Natural' $true  $true  $true
    & $AddDino 'Angler'                    'Angler'                     'Angler_Character_BP_C'                 'Angler'        @('ArkSE', 'ArkSA') $AllMaps         'Base Game'       'Standard'  'Natural' $true  $true  $false
    & $AddDino 'Ankylosaurus'              'Ankylosaurus'               'Ankylo_Character_BP_C'                 'Anky'          @('ArkSE', 'ArkSA') $AllMaps         'Base Game'       'Standard'  'Natural' $true  $true  $true
    & $AddDino 'AnyInsect'                 'Any Insect'                 'Insect_Character_Base_C'               'Insect'        @('ArkSE', 'ArkSA') $AllMaps         'Base Game'       'Standard'  'Natural' $true  $false $false
    & $AddDino 'AnyJugBug'                 'Any Jug Bug'                'Jugbug_Character_BaseBP_C'             'Jugbug'        @('ArkSE', 'ArkSA') @('ScorchedEarth_P') 'Scorched Earth'  'Standard'  'Natural' $true  $false $false
    & $AddDino 'AnyTitanomyrma'            'Any Titanomyrma'            'Ant_Character_Base_C'                  'Ant'           @('ArkSE', 'ArkSA') $AllMaps         'Base Game'       'Standard'  'Natural' $true  $false $false
    & $AddDino 'Araneo'                    'Araneo'                     'SpiderS_Character_BP_C'                'SpiderS'       @('ArkSE', 'ArkSA') $AllMaps         'Base Game'       'Standard'  'Natural' $true  $true  $true
    & $AddDino 'AraneoBossMinionAlpha'     'Araneo (Boss Minion) (Alpha)' 'SpiderS_Character_BP_Aggressive_Hard_C' 'SpiderS'       @('ArkSE', 'ArkSA') $AllMaps         'Base Game'       'Minion'    'Boss'    $false $false $false
    & $AddDino 'AraneoBossMinionBeta'      'Araneo (Boss Minion) (Beta)' 'SpiderS_Character_BP_Aggressive_Med_C'  'SpiderS'       @('ArkSE', 'ArkSA') $AllMaps         'Base Game'       'Minion'    'Boss'    $false $false $false
    & $AddDino 'AraneoBossMinionGamma'     'Araneo (Boss Minion) (Gamma)' 'SpiderS_Character_BP_Aggressive_C'      'SpiderS'       @('ArkSE', 'ArkSA') $AllMaps         'Base Game'       'Minion'    'Boss'    $false $false $false
    & $AddDino 'Archaeopteryx'             'Archaeopteryx'              'Archa_Character_BP_C'                  'Archa'         @('ArkSE', 'ArkSA') $AllMaps         'Base Game'       'Standard'  'Natural' $true  $true  $false
    & $AddDino 'Argentavis'                'Argentavis'                 'Argent_Character_BP_C'                 'Argent'        @('ArkSE', 'ArkSA') $AllMaps         'Base Game'       'Standard'  'Natural' $true  $true  $true
    & $AddDino 'Arthropluera'              'Arthropluera'               'Arthro_Character_BP_C'                 'Arthro'        @('ArkSE', 'ArkSA') $AllMaps         'Base Game'       'Standard'  'Natural' $true  $true  $true
    & $AddDino 'Astrocetus'                'Astrocetus'                 'SpaceWhale_Character_BP_C'             'SpaceWhale'    @('ArkSE', 'ArkSA') @('Genesis')      'Genesis Part 1'  'Standard'  'Natural' $true  $true  $false
    & $AddDino 'Astrodelphis'              'Astrodelphis'               'SpaceDolphin_Character_BP_C'           'SpaceDolphin'  @('ArkSE', 'ArkSA') @('Gen2')         'Genesis Part 2'  'Standard'  'Natural' $true  $true  $false
    & $AddDino 'Baryonyx'                  'Baryonyx'                   'Baryonyx_Character_BP_C'               'Baryonyx'      @('ArkSE', 'ArkSA') $AllMaps         'Base Game'       'Standard'  'Natural' $true  $true  $true
    & $AddDino 'Basilisk'                  'Basilisk'                   'Basilisk_Character_BP_C'               'Basilisk'      @('ArkSE', 'ArkSA') @('Aberration_P') 'Aberration'      'Standard'  'Natural' $true  $true  $false
    & $AddDino 'BasiliskGhost'             'Basilisk Ghost'             'Ghost_Basilisk_Character_BP_C'         'Basilisk'      @('ArkSE', 'ArkSA') @('Aberration_P') 'Aberration'      'Ghost'     'Event'   $true  $false $false
    & $AddDino 'Basilosaurus'              'Basilosaurus'               'Basilosaurus_Character_BP_C'           'Basilosaur'    @('ArkSE', 'ArkSA') $AllMaps         'Base Game'       'Standard'  'Natural' $true  $true  $false
    & $AddDino 'Beelzebufo'                'Beelzebufo'                 'Toad_Character_BP_C'                   'Toad'          @('ArkSE', 'ArkSA') $AllMaps         'Base Game'       'Standard'  'Natural' $true  $true  $true
    & $AddDino 'Beyla'                     'Beyla'                      'Beyla_Character_BP_C'                  'Beyla'         @('ArkSE', 'ArkSA') @('Fjordur')      'Fjordur'         'Boss'      'Boss'    $false $false $false
    & $AddDino 'BeylaMinion'               'Beyla Minion'               'BeylaMinion_Character_BP_C'            'Beyla'         @('ArkSE', 'ArkSA') @('Fjordur')      'Fjordur'         'Minion'    'Boss'    $false $false $false
    & $AddDino 'BloodCrystalWyvern'        'Blood Crystal Wyvern'       'CrystalWyvern_Character_BP_Blood_C'    'CrystalWyvern' @('ArkSE', 'ArkSA') @('CrystalIsles') 'Crystal Isles'   'Standard'  'Natural' $true  $true  $true
    & $AddDino 'BloodCrystalWyvernHeir'    'Blood Crystal Wyvern Heir'  'CrystalWyvern_Character_BP_Minion_Blood_C' 'CrystalWyvern' @('ArkSE', 'ArkSA') @('CrystalIsles') 'Crystal Isles'   'Minion'    'Natural' $false $false $false
    & $AddDino 'Bloodstalker'              'Bloodstalker'               'BogSpider_Character_BP_C'              'BogSpider'     @('ArkSE', 'ArkSA') @('Genesis')      'Genesis Part 1'  'Standard'  'Natural' $true  $true  $true
    & $AddDino 'Brontosaurus'              'Brontosaurus'               'Sauropod_Character_BP_C'               'Sauropod'      @('ArkSE', 'ArkSA') $AllMaps         'Base Game'       'Standard'  'Natural' $true  $true  $true
    & $AddDino 'BroodmotherAlpha'          'Broodmother (Alpha)'        'SpiderL_Character_BP_Hard_C'           'SpiderL'       @('ArkSE', 'ArkSA') @('TheIsland')    'Base Game'       'Boss'      'Boss'    $false $false $false
    & $AddDino 'BroodmotherAlphaCenter'    'Broodmother (Alpha) Center' 'SpiderL_Character_BP_TheCenterHard_C' 'SpiderL'       @('ArkSE', 'ArkSA') @('TheCenter')    'Base Game'       'Boss'      'Boss'    $false $false $false
    & $AddDino 'BroodmotherBeta'           'Broodmother (Beta)'         'SpiderL_Character_BP_Medium_C'         'SpiderL'       @('ArkSE', 'ArkSA') @('TheIsland')    'Base Game'       'Boss'      'Boss'    $false $false $false
    & $AddDino 'BroodmotherBetaCenter'     'Broodmother (Beta) Center'  'SpiderL_Character_BP_TheCenterMedium_C' 'SpiderL'       @('ArkSE', 'ArkSA') @('TheCenter')    'Base Game'       'Boss'      'Boss'    $false $false $false
    & $AddDino 'BroodmotherGamma'          'Broodmother (Gamma)'        'SpiderL_Character_BP_Easy_C'           'SpiderL'       @('ArkSE', 'ArkSA') @('TheIsland')    'Base Game'       'Boss'      'Boss'    $false $false $false
    & $AddDino 'BroodmotherGammaCenter'    'Broodmother (Gamma) Center' 'SpiderL_Character_BP_TheCenter_C'      'SpiderL'       @('ArkSE', 'ArkSA') @('TheCenter')    'Base Game'       'Boss'      'Boss'    $false $false $false
    & $AddDino 'BroodmotherLysrixAlpha'    'Broodmother Lysrix (Alpha)'  'SpiderL_Character_BP_Hard_FJ_C'        'SpiderL'       @('ArkSE', 'ArkSA') @('Fjordur')      'Fjordur'         'Boss'      'Boss'    $false $false $false
    & $AddDino 'BroodmotherLysrixBeta'     'Broodmother Lysrix (Beta)'   'SpiderL_Character_BP_Medium_FJ_C'      'SpiderL'       @('ArkSE', 'ArkSA') @('Fjordur')      'Fjordur'         'Boss'      'Boss'    $false $false $false
    & $AddDino 'BroodmotherLysrixGamma'    'Broodmother Lysrix (Gamma)'  'SpiderL_Character_BP_Easy_FJ_C'        'SpiderL'       @('ArkSE', 'ArkSA') @('Fjordur')      'Fjordur'         'Boss'      'Boss'    $false $false $false
    & $AddDino 'BroodmotherValguero'       'Broodmother (Valguero)'     'SpiderL_VAL_Character_BP_C'            'SpiderL'       @('ArkSE', 'ArkSA') @('Valguero_P')   'Valguero'        'Boss'      'Boss'    $false $false $false
    & $AddDino 'Bulbdog'                   'Bulbdog'                    'LanternPug_Character_BP_C'             'LanternPug'    @('ArkSE', 'ArkSA') @('Aberration_P') 'Aberration'      'Standard'  'Natural' $true  $true  $true
    & $AddDino 'BulbdogGhost'              'Bulbdog Ghost'              'Ghost_LanternPug_Character_BP_C'       'LanternPug'    @('ArkSE', 'ArkSA') @('Aberration_P') 'Aberration'      'Ghost'     'Event'   $true  $false $false
    & $AddDino 'BunnyDodo'                 'Bunny Dodo'                 'Dodo_Character_BP_Bunny_C'             'Dodo'          @('ArkSE', 'ArkSA') $AllMaps         'Base Game'       'Event'     'Event'   $true  $false $false
    & $AddDino 'BunnyOviraptor'            'Bunny Oviraptor'            'BunnyOviraptor_Character_BP_C'         'Oviraptor'     @('ArkSE', 'ArkSA') $AllMaps         'Base Game'       'Event'     'Event'   $true  $false $false
    & $AddDino 'Carbonemys'                'Carbonemys'                 'Turtle_Character_BP_C'                 'Turtle'        @('ArkSE', 'ArkSA') $AllMaps         'Base Game'       'Standard'  'Natural' $true  $true  $true
    & $AddDino 'Carcharodontosaurus'       'Carcharodontosaurus'        'Carcha_Character_BP_C'                 'Carcha'        @('ArkSE', 'ArkSA') $AllMaps         'Base Game'       'Standard'  'Natural' $true  $true  $true
    & $AddDino 'Carnotaurus'               'Carnotaurus'                'Carno_Character_BP_C'                  'Carno'         @('ArkSE', 'ArkSA') $AllMaps         'Base Game'       'Standard'  'Natural' $true  $true  $true
    & $AddDino 'Castoroides'               'Castoroides'                'Beaver_Character_BP_C'                 'Beaver'        @('ArkSE', 'ArkSA') $AllMaps         'Base Game'       'Standard'  'Natural' $true  $true  $true
    & $AddDino 'Chalicotherium'            'Chalicotherium'             'Chalico_Character_BP_C'                'Chalico'       @('ArkSE', 'ArkSA') $AllMaps         'Base Game'       'Standard'  'Natural' $true  $true  $true
    & $AddDino 'ChalkGolem'                'Chalk Golem'                'ChalkGolem_Character_BP_C'             'RockGolem'     @('ArkSE', 'ArkSA') @('Valguero_P')   'Valguero'        'Standard'  'Natural' $true  $true  $false
    & $AddDino 'Cnidaria'                  'Cnidaria'                   'Cnidaria_Character_BP_C'               'Cnidaria'      @('ArkSE', 'ArkSA') $AllMaps         'Base Game'       'Standard'  'Natural' $true  $false $false
    & $AddDino 'Coelacanth'                'Coelacanth'                 'Coel_Character_BP_C'                   'Coel'          @('ArkSE', 'ArkSA') $AllMaps         'Base Game'       'Standard'  'Natural' $true  $false $false
    & $AddDino 'CoelacanthOcean'           'Coelacanth (Deep Sea)'      'Coel_Character_BP_Ocean_C'             'Coel'          @('ArkSE', 'ArkSA') $AllMaps         'Base Game'       'Standard'  'Natural' $true  $false $false
    & $AddDino 'Compsognathus'             'Compsognathus'              'Compy_Character_BP_C'                  'Compy'         @('ArkSE', 'ArkSA') $AllMaps         'Base Game'       'Standard'  'Natural' $true  $true  $true
    & $AddDino 'CorruptArthroMinion'       'Corrupt Arthro (Minion)'     'Corrupt_Arthro_Character_BP_C'         'Arthro'        @('ArkSE')         @('Extinction')   'Extinction'      'Minion'    'Boss'    $false $false $false
    & $AddDino 'CorruptedArthro'           'Corrupted Arthropluera'     'Arthro_Character_BP_Corrupt_C'         'Arthro'        @('ArkSE')         @('Extinction')   'Extinction'      'Corrupted' 'Natural' $true  $false $false
    & $AddDino 'CorruptedAvatar'           'Corrupted Avatar'           'Bot_Character_BP_C'                    'Bot'           @('ArkSE')         @('Genesis')      'Genesis Part 1'  'Corrupted' 'Natural' $false $false $false
    & $AddDino 'CorruptedAvatarBow'        'Corrupted Avatar (Bow)'     'Bot_WithBow_BP_C'                      'Bot'           @('ArkSE')         @('Genesis')      'Genesis Part 1'  'Corrupted' 'Natural' $false $false $false
    & $AddDino 'CorruptedAvatarSpear'      'Corrupted Avatar (Spear)'   'Bot_WithSpear_BP_C'                    'Bot'           @('ArkSE')         @('Genesis')      'Genesis Part 1'  'Corrupted' 'Natural' $false $false $false
    & $AddDino 'CorruptedAvatarGrenades'   'Corrupted Avatar (Grenades)' 'Bot_WithTekGrenades_BP_C'              'Bot'           @('ArkSE')         @('Genesis')      'Genesis Part 1'  'Corrupted' 'Natural' $false $false $false
    & $AddDino 'CorruptedAvatarRifle'      'Corrupted Avatar (Rifle)'    'Bot_WithTekRifle_BP_C'                 'Bot'           @('ArkSE')         @('Genesis')      'Genesis Part 1'  'Corrupted' 'Natural' $false $false $false
    & $AddDino 'CorruptedCarno'            'Corrupted Carnotaurus'      'Carno_Character_BP_Corrupt_C'          'Carno'         @('ArkSE')         @('Extinction')   'Extinction'      'Corrupted' 'Natural' $true  $false $false
    & $AddDino 'CorruptedChalico'          'Corrupted Chalicotherium'   'Chalico_Character_BP_Corrupt_C'        'Chalico'       @('ArkSE')         @('Extinction')   'Extinction'      'Corrupted' 'Natural' $true  $false $false
    & $AddDino 'CorruptedDeathworm'        'Corrupted Deathworm'        'Deathworm_Character_BP_Corrupt_C'      'Deathworm'     @('ArkSE')         @('Extinction')   'Extinction'      'Corrupted' 'Natural' $true  $false $false
    & $AddDino 'CorruptedDilo'             'Corrupted Dilophosaur'      'Dilo_Character_BP_Corrupt_C'           'Dilo'          @('ArkSE')         @('Extinction')   'Extinction'      'Corrupted' 'Natural' $true  $false $false
    & $AddDino 'CorruptedDimorph'          'Corrupted Dimorphodon'      'Dimorph_Character_BP_Corrupt_C'        'Dimorph'       @('ArkSE')         @('Extinction')   'Extinction'      'Corrupted' 'Natural' $true  $false $false
    & $AddDino 'CorruptedDrone'            'Corrupted Attack Drone'     'VREndDrone_Character_BP_C'             'EndDrone'      @('ArkSE')         @('Genesis')      'Genesis Part 1'  'Corrupted' 'Natural' $false $false $false
    & $AddDino 'CorruptedDaeodon'          'Corrupted Daeodon'          'VRDaeodon_Character_BP_C'              'Daeodon'       @('ArkSE')         @('Genesis')      'Genesis Part 1'  'Corrupted' 'Natural' $false $false $false
    & $AddDino 'CorruptedGiganotoVR'       'Corrupted VR Giganoto'      'VRGigant_Character_BP_C'               'Gigant'        @('ArkSE')         @('Genesis')      'Genesis Part 1'  'Corrupted' 'Natural' $false $false $false
    & $AddDino 'CorruptedRaptorVR'         'Corrupted VR Raptor'        'VRRaptor_Character_BP_C'               'Raptor'        @('ArkSE')         @('Genesis')      'Genesis Part 1'  'Corrupted' 'Natural' $false $false $false
    & $AddDino 'CorruptedReaperVR'         'Corrupted VR Reaper'        'VRXenomorph_Character_BP_Male_Minion_C' 'Xenomorph'    @('ArkSE')         @('Genesis')      'Genesis Part 1'  'Corrupted' 'Natural' $false $false $false
    & $AddDino 'CorruptedRexVR'            'Corrupted VR Rex'           'VRRex_Character_BP_C'                  'Rex'           @('ArkSE')         @('Genesis')      'Genesis Part 1'  'Corrupted' 'Natural' $false $false $false
    & $AddDino 'CorruptedTrikeVR'          'Corrupted VR Triceratops'    'VRTrike_Character_BP_C'                'Trike'         @('ArkSE')         @('Genesis')      'Genesis Part 1'  'Corrupted' 'Natural' $false $false $false
    & $AddDino 'CorruptedYutyVR'           'Corrupted VR Yutyrannus'    'VRYutyrannus_Character_BP_C'           'Yuty'          @('ArkSE')         @('Genesis')      'Genesis Part 1'  'Corrupted' 'Natural' $false $false $false
    & $AddDino 'CorruptedGiganotosaurus'   'Corrupted Giganotosaurus'   'Gigant_Character_BP_Corrupt_C'         'Gigant'        @('ArkSE')         @('Extinction')   'Extinction'      'Corrupted' 'Natural' $true  $false $false
    & $AddDino 'MasterControllerAlpha'     'Master Controller (Alpha)'  'VRMainBoss_Character_Hard_C'           'VRMainBoss'    @('ArkSE')         @('Genesis')      'Genesis Part 1'  'Boss'      'Boss'    $false $false $false
    & $AddDino 'MasterControllerBeta'      'Master Controller (Beta)'   'VRMainBoss_Character_Medium_C'         'VRMainBoss'    @('ArkSE')         @('Genesis')      'Genesis Part 1'  'Boss'      'Boss'    $false $false $false
    & $AddDino 'MasterControllerGamma'     'Master Controller (Gamma)'  'VRMainBoss_Character_Easy_C'           'VRMainBoss'    @('ArkSE')         @('Genesis')      'Genesis Part 1'  'Boss'      'Boss'    $false $false $false
    & $AddDino 'CorruptedParacer'          'Corrupted Paracer'          'Paracer_Character_BP_Corrupt_C'        'Paracer'       @('ArkSE')         @('Extinction')   'Extinction'      'Corrupted' 'Natural' $true  $false $false
    & $AddDino 'CorruptedPteranodon'       'Corrupted Pteranodon'       'Ptero_Character_BP_Corrupt_C'          'Ptero'         @('ArkSE')         @('Extinction')   'Extinction'      'Corrupted' 'Natural' $true  $false $false
    & $AddDino 'CorruptedRaptor'           'Corrupted Raptor'           'Raptor_Character_BP_Corrupt_C'         'Raptor'        @('ArkSE')         @('Extinction')   'Extinction'      'Corrupted' 'Natural' $true  $false $false
    & $AddDino 'CorruptedReaperKing'       'Corrupted Reaper King'      'Xenomorph_Character_BP_Male_Tamed_Corrupt_C' 'Xenomorph' @('ArkSE')         @('Extinction')   'Extinction'      'Corrupted' 'Natural' $true  $false $false
    & $AddDino 'CorruptedRex'              'Corrupted Rex'              'Rex_Character_BP_Corrupt_C'            'Rex'           @('ArkSE')         @('Extinction')   'Extinction'      'Corrupted' 'Natural' $true  $false $false
    & $AddDino 'CorruptedRockDrake'        'Corrupted Rock Drake'       'RockDrake_Character_BP_Corrupt_C'      'RockDrake'     @('ArkSE')         @('Extinction')   'Extinction'      'Corrupted' 'Natural' $true  $false $false
    & $AddDino 'CorruptedSpino'            'Corrupted Spinosaurus'      'Spino_Character_BP_Corrupt_C'          'Spino'         @('ArkSE')         @('Extinction')   'Extinction'      'Corrupted' 'Natural' $true  $false $false
    & $AddDino 'CorruptedStego'            'Corrupted Stegosaurus'      'Stego_Character_BP_Corrupt_C'          'Stego'         @('ArkSE')         @('Extinction')   'Extinction'      'Corrupted' 'Natural' $true  $false $false
    & $AddDino 'CorruptedSurvivor'         'Corrupted Survivor'         'RockwellSpawn_Character_BP_C'          'Survivor'      @('ArkSE')         @('Gen2')         'Genesis Part 2'  'Corrupted' 'Natural' $false $false $false
    & $AddDino 'CorruptedSurvivorAlpha'    'Corrupted Survivor (Alpha)' 'RockwellSpawn_Character_BP_Alpha_C'    'Survivor'      @('ArkSE')         @('Gen2')         'Genesis Part 2'  'Corrupted' 'Natural' $false $false $false
    & $AddDino 'CorruptedSurvivorAlt'      'Corrupted Survivor (Alt)'   'RockwellSpawn_Character_BP_AltAnim_C'  'Survivor'      @('ArkSE')         @('Gen2')         'Genesis Part 2'  'Corrupted' 'Natural' $false $false $false
    & $AddDino 'CorruptedSurvivorAltAlpha' 'Corrupted Surv (Alt Alpha)' 'RockwellSpawn_Character_BP_AltAnim_Alpha_C' 'Survivor' @('ArkSE')         @('Gen2')         'Genesis Part 2'  'Corrupted' 'Natural' $false $false $false
    & $AddDino 'CorruptedSurvivorAltBeta'  'Corrupted Surv (Alt Beta)'  'RockwellSpawn_Character_BP_AltAnim_Beta_C'  'Survivor' @('ArkSE')         @('Gen2')         'Genesis Part 2'  'Corrupted' 'Natural' $false $false $false
    & $AddDino 'CorruptedSurvivorAltGamma' 'Corrupted Surv (Alt Gamma)' 'RockwellSpawn_Character_BP_AltAnim_Gamma_C' 'Survivor' @('ArkSE')         @('Gen2')         'Genesis Part 2'  'Corrupted' 'Natural' $false $false $false
    & $AddDino 'CorruptedSurvivorBeta'     'Corrupted Survivor (Beta)'  'RockwellSpawn_Character_BP_Beta_C'     'Survivor'      @('ArkSE')         @('Gen2')         'Genesis Part 2'  'Corrupted' 'Natural' $false $false $false
    & $AddDino 'CorruptedSurvivorGamma'    'Corrupted Survivor (Gamma)' 'RockwellSpawn_Character_BP_Gamma_C'    'Survivor'      @('ArkSE')         @('Gen2')         'Genesis Part 2'  'Corrupted' 'Natural' $false $false $false
    & $AddDino 'CorruptedSurvivorRifle'    'Corrupted Surv (Rifle)'     'CorruptHuman_WithTekRifle_Character_BP_C' 'Survivor'   @('ArkSE')         @('Gen2')         'Genesis Part 2'  'Corrupted' 'Natural' $false $false $false
    & $AddDino 'CorruptedTriceratops'      'Corrupted Triceratops'      'Trike_Character_BP_Corrupt_C'          'Trike'         @('ArkSE')         @('Extinction')   'Extinction'      'Corrupted' 'Natural' $true  $false $false
    & $AddDino 'CorruptedWyvernExt'        'Corrupted Wyvern'           'Wyvern_Character_BP_Fire_Corrupt_C'    'Wyvern'        @('ArkSE')         @('Extinction')   'Extinction'      'Corrupted' 'Natural' $true  $false $false
    & $AddDino 'CorruptTumor'              'Corrupt Tumor'              'CorruptTumor_Character_BP_C'           'Tumor'         @('ArkSE')         @('Extinction')   'Extinction'      'Corrupted' 'Natural' $false $false $false
    & $AddDino 'CrystalWyvernHeir'         'Crystal Wyvern Heir'        'CrystalWyvern_Character_BP_Minion_C'   'CrystalWyvern' @('ArkSE', 'ArkSA') @('CrystalIsles') 'Crystal Isles'   'Minion'    'Natural' $false $false $false
    & $AddDino 'CrystalWyvernQueen'        'Crystal Wyvern Queen'       'CrystalWyvern_Character_BP_Boss_C'     'CrystalWyvern' @('ArkSE', 'ArkSA') @('CrystalIsles') 'Crystal Isles'   'Boss'      'Boss'    $false $false $false
    & $AddDino 'CrystalWyvernQueenAlpha'   'Crystal Wyvern Q (Alpha)'   'CrystalWyvern_Character_BP_Boss_Hard_C' 'CrystalWyvern' @('ArkSE', 'ArkSA') @('CrystalIsles') 'Crystal Isles'   'Boss'      'Boss'    $false $false $false
    & $AddDino 'CrystalWyvernQueenBeta'    'Crystal Wyvern Q (Beta)'    'CrystalWyvern_Character_BP_Boss_Medium_C' 'CrystalWyvern' @('ArkSE', 'ArkSA') @('CrystalIsles') 'Crystal Isles'   'Boss'      'Boss'    $false $false $false
    & $AddDino 'CrystalWyvernQueenGamma'   'Crystal Wyvern Q (Gamma)'   'CrystalWyvern_Character_BP_Boss_Easy_C' 'CrystalWyvern' @('ArkSE', 'ArkSA') @('CrystalIsles') 'Crystal Isles'   'Boss'      'Boss'    $false $false $false
    & $AddDino 'Daeodon'                   'Daeodon'                    'Daeodon_Character_BP_C'                'Daeodon'       @('ArkSE', 'ArkSA') $AllMaps         'Base Game'       'Standard'  'Natural' $true  $true  $true
    & $AddDino 'Deathworm'                 'Deathworm'                  'Deathworm_Character_BP_C'              'Deathworm'     @('ArkSE', 'ArkSA') @('ScorchedEarth_P', 'Ragnarok', 'Valguero_P', 'CrystalIsles', 'LostIsland', 'Fjordur') 'Scorched Earth'  'Standard'  'Natural' $true  $false $false
    & $AddDino 'DeathwormMinion'           'Deathworm (Minion)'         'Deathworm_Character_Minion_BP_C'       'Deathworm'     @('ArkSE', 'ArkSA') @('ScorchedEarth_P') 'Scorched Earth'  'Minion'    'Natural' $false $false $false
    & $AddDino 'DefenseUnit'               'Defense Unit'               'Defender_Character_BP_C'               'Defender'      @('ArkSE')         @('Extinction')   'Extinction'      'Robot'     'Natural' $true  $false $false
    & $AddDino 'Deinonychus'               'Deinonychus'                'Deinonychus_Character_BP_C'            'Deinonychus'   @('ArkSE', 'ArkSA') @('Valguero_P', 'Fjordur') 'Valguero'        'Standard'  'Natural' $true  $true  $true
    & $AddDino 'DesertTitan'               'Desert Titan'               'DesertKaiju_Character_BP_C'            'DesertKaiju'   @('ArkSE')         @('Extinction')   'Extinction'      'Titan'     'Natural' $true  $true  $false
    & $AddDino 'DesertTitanFlock'          'Desert Titan Flock'         'DesertKaiju_FirstFlockChar_BP_C'       'DesertKaiju'   @('ArkSE')         @('Extinction')   'Extinction'      'Titan'     'Natural' $true  $false $false
    & $AddDino 'Desmodus'                  'Desmodus'                   'Desmodus_Character_BP_C'               'Desmodus'      @('ArkSE', 'ArkSA') @('Fjordur')      'Fjordur'         'Standard'  'Natural' $true  $true  $true
    & $AddDino 'Dilophosaurus'             'Dilophosaurus'              'Dilo_Character_BP_C'                   'Dilo'          @('ArkSE', 'ArkSA') $AllMaps         'Base Game'       'Standard'  'Natural' $true  $true  $true
    & $AddDino 'Dimetrodon'                'Dimetrodon'                 'Dimetro_Character_BP_C'                'Dimetro'       @('ArkSE', 'ArkSA') $AllMaps         'Base Game'       'Standard'  'Natural' $true  $true  $true
    & $AddDino 'Dimorphodon'               'Dimorphodon'                'Dimorph_Character_BP_C'                'Dimorph'       @('ArkSE', 'ArkSA') $AllMaps         'Base Game'       'Standard'  'Natural' $true  $true  $true
    & $AddDino 'DimorphBossMinionAlpha'    'Dimorph (Boss Minion) Alpha' 'Dimorph_Character_BP_Aggressive_DragonBoss_Hard_C' 'Dimorph' @('ArkSE', 'ArkSA') $AllMaps         'Base Game'       'Minion'    'Boss'    $false $false $false
    & $AddDino 'DimorphBossMinionBeta'     'Dimorph (Boss Minion) Beta'  'Dimorph_Character_BP_Aggressive_DragonBoss_Med_C' 'Dimorph' @('ArkSE', 'ArkSA') $AllMaps         'Base Game'       'Minion'    'Boss'    $false $false $false
    & $AddDino 'DimorphBossMinionGamma'    'Dimorph (Boss Minion) Gamma' 'Dimorph_Character_BP_Aggressive_DragonBoss_C' 'Dimorph' @('ArkSE', 'ArkSA') $AllMaps         'Base Game'       'Minion'    'Boss'    $false $false $false
    & $AddDino 'Dinopithecus'              'Dinopithecus'               'Dinopithecus_Character_BP_C'           'Dinopithecus'  @('ArkSE', 'ArkSA') @('LostIsland')   'Lost Island'     'Standard'  'Natural' $true  $true  $true
    & $AddDino 'DinopithecusKingAlpha'     'Dinopithecus King (Alpha)'  'BossDinopithecus_Character_BP_Hard_C'  'Dinopithecus'  @('ArkSE', 'ArkSA') @('LostIsland')   'Lost Island'     'Boss'      'Boss'    $false $false $false
    & $AddDino 'DinopithecusKingBeta'      'Dinopithecus King (Beta)'   'BossDinopithecus_Character_BP_Medium_C' 'Dinopithecus'  @('ArkSE', 'ArkSA') @('LostIsland')   'Lost Island'     'Boss'      'Boss'    $false $false $false
    & $AddDino 'DinopithecusKingGamma'     'Dinopithecus King (Gamma)'  'BossDinopithecus_Character_BP_Easy_C'  'Dinopithecus'  @('ArkSE', 'ArkSA') @('LostIsland')   'Lost Island'     'Boss'      'Boss'    $false $false $false
    & $AddDino 'DinopithecusMinion'        'Dinopithecus (Minion)'      'Dinopithecus_Character_BP_Minion_C'    'Dinopithecus'  @('ArkSE', 'ArkSA') @('LostIsland')   'Lost Island'     'Minion'    'Natural' $false $false $false
    & $AddDino 'TekGigant'                 'Tek Giganotosaurus'         'TekGigant_Character_BP_C'              'Gigant'        @('ArkSE', 'ArkSA') $AllMaps         'Base Game'       'Tek'       'Natural' $true  $true  $true
    & $AddDino 'TekMosa'                   'Tek Mosasaur'               'TekMosa_Character_BP_C'                'Mosa'          @('ArkSE', 'ArkSA') $AllMaps         'Base Game'       'Tek'       'Natural' $true  $true  $false
    & $AddDino 'TekPara'                   'Tek Parasaur'               'TekPara_Character_BP_C'                'Para'          @('ArkSE', 'ArkSA') $AllMaps         'Base Game'       'Tek'       'Natural' $true  $true  $true
    & $AddDino 'TekQuetz'                  'Tek Quetzal'                'TekQuetz_Character_BP_C'               'Quetz'         @('ArkSE', 'ArkSA') $AllMaps         'Base Game'       'Tek'       'Natural' $true  $true  $true
    & $AddDino 'TekRaptor'                 'Tek Raptor'                 'TekRaptor_Character_BP_C'              'Raptor'        @('ArkSE', 'ArkSA') $AllMaps         'Base Game'       'Tek'       'Natural' $true  $true  $true
    & $AddDino 'TekRex'                    'Tek Rex'                    'TekRex_Character_BP_C'                 'Rex'           @('ArkSE', 'ArkSA') $AllMaps         'Base Game'       'Tek'       'Natural' $true  $true  $true
    & $AddDino 'TekStego'                  'Tek Stegosaurus'            'TekStego_Character_BP_C'               'Stego'         @('ArkSE', 'ArkSA') $AllMaps         'Base Game'       'Tek'       'Natural' $true  $true  $true
    & $AddDino 'TekTrike'                  'Tek Triceratops'            'TekTrike_Character_BP_C'               'Trike'         @('ArkSE', 'ArkSA') $AllMaps         'Base Game'       'Tek'       'Natural' $true  $true  $true
    & $AddDino 'Diplocaulus'               'Diplocaulus'                'Diplocaulus_Character_BP_C'            'Diplocaulus'   @('ArkSE', 'ArkSA') $AllMaps         'Base Game'       'Standard'  'Natural' $true  $true  $true
    & $AddDino 'Diplodocus'                'Diplodocus'                 'Diplodocus_Character_BP_C'             'Diplodocus'    @('ArkSE', 'ArkSA') $AllMaps         'Base Game'       'Standard'  'Natural' $true  $true  $true
    & $AddDino 'Direbear'                  'Direbear'                   'Direbear_Character_BP_C'               'Direbear'      @('ArkSE', 'ArkSA') $AllMaps         'Base Game'       'Standard'  'Natural' $true  $true  $true
    & $AddDino 'DirebearLL'                'Direbear (Labyrinth)'       'Direbear_LL_Character_BP_C'            'Direbear'      @('ArkSE', 'ArkSA') @('Ragnarok')     'Ragnarok'        'Standard'  'Natural' $true  $true  $false
    & $AddDino 'PolarBear'                 'Dire Polar Bear'            'Polar_Bear_C'                          'PolarBear'     @('ArkSE', 'ArkSA') @('Valguero_P', 'Fjordur', 'TheIsland') 'Base Game' 'Standard' 'Natural' $true $true $false
    & $AddDino 'Direwolf'                  'Direwolf'                   'Direwolf_Character_BP_C'               'Direwolf'      @('ArkSE', 'ArkSA') $AllMaps         'Base Game'       'Standard'  'Natural' $true  $true  $true
    & $AddDino 'DirewolfGhost'             'Direwolf Ghost'             'Ghost_Direwolf_Character_BP_C'         'Direwolf'      @('ArkSE', 'ArkSA') $AllMaps         'Base Game'       'Ghost'     'Event'   $true  $false $false
    & $AddDino 'DirewolfLL'                'Direwolf (Labyrinth)'       'Direwolf_LL_Character_BP_C'            'Direwolf'      @('ArkSE', 'ArkSA') @('Ragnarok')     'Ragnarok'        'Standard'  'Natural' $true  $true  $false
    & $AddDino 'LeechDiseased'             'Diseased Leech'             'Leech_Character_Diseased_C'            'Leech'         @('ArkSE', 'ArkSA') $AllMaps         'Base Game'       'Standard'  'Natural' $true  $false $false
    & $AddDino 'Dodo'                      'Dodo'                       'Dodo_Character_BP_C'                   'Dodo'          @('ArkSE', 'ArkSA') $AllMaps         'Base Game'       'Standard'  'Natural' $true  $true  $true
    & $AddDino 'DodoRex'                   'DodoRex'                    'DodoRex_Character_BP_C'                'DodoRex'       @('ArkSE', 'ArkSA') $AllMaps         'Base Game'       'Boss'      'Event'   $true  $false $false
    & $AddDino 'DodoRexTurkey'             'DodoRex (Turkey Trials)'    'DodoRex_Character_BP_TurkeyTrials_C'   'DodoRex'       @('ArkSE', 'ArkSA') $AllMaps         'Base Game'       'Boss'      'Event'   $true  $false $false
    & $AddDino 'DodoRexFear'               'DodoRex (Fear Evolved)'     'DodoRex_Character_BP_FearEvolved_C'    'DodoRex'       @('ArkSE', 'ArkSA') $AllMaps         'Base Game'       'Boss'      'Event'   $true  $false $false
    & $AddDino 'DodoWyvern'                'Dodo Wyvern'                'DodoWyvern_Character_BP_C'             'DodoWyvern'    @('ArkSE', 'ArkSA') @('ScorchedEarth_P') 'Scorched Earth'  'Boss'      'Event'   $true  $false $false
    & $AddDino 'Doedicurus'                'Doedicurus'                 'Doed_Character_BP_C'                   'Doed'          @('ArkSE', 'ArkSA') $AllMaps         'Base Game'       'Standard'  'Natural' $true  $true  $true
    & $AddDino 'DragonAlpha'               'Dragon (Alpha)'             'Dragon_Character_BP_Boss_Hard_C'       'Dragon'        @('ArkSE', 'ArkSA') @('TheIsland', 'TheCenter', 'Valguero_P') 'Base Game' 'Boss' 'Boss' $false $false $false
    & $AddDino 'DragonAlphaFjordur'        'Dragon (Alpha) FJ'          'Dragon_Character_BP_Boss_Hard_FJ_C'    'Dragon'        @('ArkSE', 'ArkSA') @('Fjordur')      'Fjordur'         'Boss'      'Boss'    $false $false $false
    & $AddDino 'DragonAlphaRagnarok'       'Dragon (Alpha) Rag'         'Dragon_Character_BP_Boss_Hard_Ragnarok_C' 'Dragon'      @('ArkSE', 'ArkSA') @('Ragnarok')     'Ragnarok'        'Boss'      'Boss'    $false $false $false
    & $AddDino 'DragonBetaFJ'              'Dragon (Beta) FJ'           'Dragon_Character_BP_Boss_Medium_FJ_C'  'Dragon'        @('ArkSE', 'ArkSA') @('Fjordur')      'Fjordur'         'Boss'      'Boss'    $false $false $false
    & $AddDino 'DragonBeta'                'Dragon (Beta)'              'Dragon_Character_BP_Boss_Medium_C'     'Dragon'        @('ArkSE', 'ArkSA') @('TheIsland', 'TheCenter', 'Valguero_P') 'Base Game' 'Boss' 'Boss' $false $false $false
    & $AddDino 'DragonBetaRagnarok'        'Dragon (Beta) Rag'          'Dragon_Character_BP_Boss_Medium_Ragnarok_C' 'Dragon'    @('ArkSE', 'ArkSA') @('Ragnarok')     'Ragnarok'        'Boss'      'Boss'    $false $false $false
    & $AddDino 'DragonGammaFjordur'        'Dragon (Gamma) FJ'          'Dragon_Character_BP_Boss_Easy_FJ_C'    'Dragon'        @('ArkSE', 'ArkSA') @('Fjordur')      'Fjordur'         'Boss'      'Boss'    $false $false $false
    & $AddDino 'DragonGamma'               'Dragon (Gamma)'             'Dragon_Character_BP_Boss_Easy_C'       'Dragon'        @('ArkSE', 'ArkSA') @('TheIsland', 'TheCenter', 'Valguero_P') 'Base Game' 'Boss' 'Boss' $false $false $false
    & $AddDino 'DragonGammaRagnarok'       'Dragon (Gamma) Rag'         'Dragon_Character_BP_Boss_Easy_Ragnarok_C' 'Dragon'      @('ArkSE', 'ArkSA') @('Ragnarok')     'Ragnarok'        'Boss'      'Boss'    $false $false $false
    & $AddDino 'DroneLunar'                'Drone'                      'EndDrone_Lunar_Character_BP_C'         'EndDrone'      @('ArkSE', 'ArkSA') @('Genesis')      'Genesis Part 1'  'Robot'     'Natural' $false $false $false
    & $AddDino 'DroneTankLunar'            'Drone (Tank)'               'EndTank_Lunar_Character_BP_C'          'EndTank'       @('ArkSE', 'ArkSA') @('Genesis')      'Genesis Part 1'  'Robot'     'Natural' $false $false $false
    & $AddDino 'DungBeetle'                'Dung Beetle'                'DungBeetle_Character_BP_C'             'DungBeetle'    @('ArkSE', 'ArkSA') $AllMaps         'Base Game'       'Standard'  'Natural' $true  $true  $false
    & $AddDino 'Dunkleosteus'              'Dunkleosteus'               'Dunkle_Character_BP_C'                 'Dunkle'        @('ArkSE', 'ArkSA') $AllMaps         'Base Game'       'Standard'  'Natural' $true  $true  $false
    & $AddDino 'RockwellAlpha'             'Rockwell (Alpha)'           'Rockwell_Character_BP_Hard_C'          'Rockwell'      @('ArkSE', 'ArkSA') @('Aberration_P') 'Aberration'      'Boss'      'Boss'    $false $false $false
    & $AddDino 'RockwellBase'              'Rockwell (Base)'            'Rockwell_Character_BP_C'               'Rockwell'      @('ArkSE', 'ArkSA') @('Aberration_P') 'Aberration'      'Boss'      'Boss'    $false $false $false
    & $AddDino 'RockwellBeta'              'Rockwell (Beta)'            'Rockwell_Character_BP_Medium_C'        'Rockwell'      @('ArkSE', 'ArkSA') @('Aberration_P') 'Aberration'      'Boss'      'Boss'    $false $false $false
    & $AddDino 'RockwellGamma'             'Rockwell (Gamma)'           'Rockwell_Character_BP_Easy_C'          'Rockwell'      @('ArkSE', 'ArkSA') @('Aberration_P') 'Aberration'      'Boss'      'Boss'    $false $false $false
    & $AddDino 'EelMinionAlpha'            'Eel Minion (Alpha)'         'EelMinion_Character_BP_Hard_C'         'Eel'           @('ArkSE', 'ArkSA') @('Genesis')      'Genesis Part 1'  'Minion'    'Boss'    $false $false $false
    & $AddDino 'EelMinionBeta'             'Eel Minion (Beta)'          'EelMinion_Character_BP_Medium_C'       'Eel'           @('ArkSE', 'ArkSA') @('Genesis')      'Genesis Part 1'  'Minion'    'Boss'    $false $false $false
    & $AddDino 'EelMinionGamma'            'Eel Minion (Gamma)'         'EelMinion_Character_BP_Easy_C'         'Eel'           @('ArkSE', 'ArkSA') @('Genesis')      'Genesis Part 1'  'Minion'    'Boss'    $false $false $false
    & $AddDino 'Electrophorus'             'Electrophorus'              'Eel_Character_BP_C'                    'Eel'           @('ArkSE', 'ArkSA') $AllMaps         'Base Game'       'Standard'  'Natural' $true  $true  $false
    & $AddDino 'ElementalReaperKing'       'Elemental Reaper King'      'Xenomorph_Character_BP_Male_Minion_C'  'Xenomorph'     @('ArkSE', 'ArkSA') @('Aberration_P') 'Aberration'      'Minion'    'Natural' $false $false $false
    & $AddDino 'EmberCrystalWyvern'        'Ember Crystal Wyvern'       'CrystalWyvern_Character_BP_Ember_C'    'CrystalWyvern' @('ArkSE', 'ArkSA') @('CrystalIsles') 'Crystal Isles'   'Standard'  'Natural' $true  $true  $true
    & $AddDino 'EmberCrystalWyvernHeir'    'Ember Crystal Wyvern Heir'  'CrystalWyvern_Character_BP_Minion_Ember_C' 'CrystalWyvern' @('ArkSE', 'ArkSA') @('CrystalIsles') 'Crystal Isles'   'Minion'    'Natural' $false $false $false
    & $AddDino 'EndBossDroneAlpha'         'End Boss Drone (Alpha)'     'EndDrone_Character_BP_Hard_C'          'EndDrone'      @('ArkSE', 'ArkSA') @('TheIsland')    'Base Game'       'Robot'     'Boss'    $false $false $false
    & $AddDino 'EndBossDroneBeta'          'End Boss Drone (Beta)'      'EndDrone_Character_BP_Med_C'           'EndDrone'      @('ArkSE', 'ArkSA') @('TheIsland')    'Base Game'       'Robot'     'Boss'    $false $false $false
    & $AddDino 'EndBossDroneGamma'         'End Boss Drone (Gamma)'     'EndDrone_Character_BP_C'               'EndDrone'      @('ArkSE', 'ArkSA') @('TheIsland')    'Base Game'       'Robot'     'Boss'    $false $false $false
    & $AddDino 'EndBossTankAlpha'          'End Boss Tank (Alpha)'      'EndTank_Character_BP_Hard_C'           'EndTank'       @('ArkSE', 'ArkSA') @('TheIsland')    'Base Game'       'Robot'     'Boss'    $false $false $false
    & $AddDino 'EndBossTankBeta'           'End Boss Tank (Beta)'       'EndTank_Character_BP_Med_C'            'EndTank'       @('ArkSE', 'ArkSA') @('TheIsland')    'Base Game'       'Robot'     'Boss'    $false $false $false
    & $AddDino 'EndBossTankGamma'          'End Boss Tank (Gamma)'      'EndTank_Character_BP_C'                'EndTank'       @('ArkSE', 'ArkSA') @('TheIsland')    'Base Game'       'Robot'     'Boss'    $false $false $false
    & $AddDino 'Enforcer'                  'Enforcer'                   'Enforcer_Character_BP_C'               'Enforcer'      @('ArkSE', 'ArkSA') @('Extinction', 'Gen2') 'Extinction' 'Robot'     'Natural' $true  $true  $false
    & $AddDino 'EnragedCorruptedRex'       'Enraged Corrupted Rex'      'MegaRex_Character_BP_Corrupt_C'        'MegaRex'       @('ArkSE', 'ArkSA') @('Extinction')   'Extinction'      'Corrupted' 'Natural' $false $false $false
    & $AddDino 'EnragedTriceratops'        'Enraged Triceratops'        'MegaTrike_Character_BP_Corrupt_C'      'MegaTrike'     @('ArkSE', 'ArkSA') @('Extinction')   'Extinction'      'Corrupted' 'Natural' $false $false $false
    & $AddDino 'Equus'                     'Equus'                      'Equus_Character_BP_C'                  'Equus'         @('ArkSE', 'ArkSA') $AllMaps         'Base Game'       'Standard'  'Natural' $true  $true  $true
    & $AddDino 'Eurypterid'                'Eurypterid'                 'Euryp_Character_C'                     'Euryp'         @('ArkSE', 'ArkSA') $AllMaps         'Base Game'       'Standard'  'Natural' $true  $false $false
    & $AddDino 'ExoMekRTS'                 'Exo-Mek (RTS)'              'Exosuit_RTS_Character_BP_C'            'Exosuit'       @('ArkSE', 'ArkSA') @('Gen2')         'Genesis Part 2'  'Robot'     'Natural' $false $false $false
    & $AddDino 'ExoMek'                    'Exo-Mek'                    'Exosuit_Character_BP_C'                'Exosuit'       @('ArkSE', 'ArkSA') @('Gen2')         'Genesis Part 2'  'Robot'     'Natural' $true  $false $false
    & $AddDino 'ExoMekFinal'               'Exo-Mek (Final Fight)'      'Exosuit_Character_BP_FinalFight_C'     'Exosuit'       @('ArkSE', 'ArkSA') @('Gen2')         'Genesis Part 2'  'Robot'     'Boss'    $false $false $false
    & $AddDino 'Featherlight'              'Featherlight'               'LanternBird_Character_BP_C'            'LanternBird'   @('ArkSE', 'ArkSA') @('Aberration_P', 'Valguero_P', 'Gen2', 'Fjordur') 'Aberration' 'Standard' 'Natural' $true $true $true
    & $AddDino 'Fenrir'                    'Fenrir'                     'Fenrir_Character_BP_C'                 'Fenrir'        @('ArkSE', 'ArkSA') @('Fjordur')      'Fjordur'         'Standard'  'Natural' $true  $true  $false
    & $AddDino 'FenrirMiniBoss'            'Fenrir Mini Boss'           'Fenrir_Character_BP_MiniBoss_C'        'Fenrir'        @('ArkSE', 'ArkSA') @('Fjordur')      'Fjordur'         'Boss'      'Boss'    $false $false $false
    & $AddDino 'FenrirMinion'              'Fenrir Minion'              'Fenrir_Character_BP_Minion_C'          'Fenrir'        @('ArkSE', 'ArkSA') @('Fjordur')      'Fjordur'         'Minion'    'Boss'    $false $false $false
    & $AddDino 'FenrisulfrAlpha'           'Fenrisúlfr (Alpha)'         'Fenrir_Character_BP_Boss_Hard_C'       'Fenrir'        @('ArkSE', 'ArkSA') @('Fjordur')      'Fjordur'         'Boss'      'Boss'    $false $false $false
    & $AddDino 'FenrisulfrBeta'            'Fenrisúlfr (Beta)'          'Fenrir_Character_BP_Boss_Medium_C'     'Fenrir'        @('ArkSE', 'ArkSA') @('Fjordur')      'Fjordur'         'Boss'      'Boss'    $false $false $false
    & $AddDino 'FenrisulfrGamma'           'Fenrisúlfr (Gamma)'         'Fenrir_Character_BP_Boss_Easy_C'       'Fenrir'        @('ArkSE', 'ArkSA') @('Fjordur')      'Fjordur'         'Boss'      'Boss'    $false $false $false
    & $AddDino 'FeroxLarge'                'Ferox (Large)'              'Shapeshifter_Large_Character_BP_C'     'Shapeshifter'  @('ArkSE', 'ArkSA') @('Genesis', 'Gen2', 'Fjordur') 'Genesis Part 1' 'Standard' 'Natural' $true $true $true
    & $AddDino 'FeroxSmall'                'Ferox (Small)'              'Shapeshifter_Small_Character_BP_C'     'Shapeshifter'  @('ArkSE', 'ArkSA') @('Genesis', 'Gen2', 'Fjordur') 'Genesis Part 1' 'Standard' 'Natural' $true $true $true
    & $AddDino 'FireWyvern'                'Fire Wyvern'                'Wyvern_Character_BP_Fire_C'            'Wyvern'        @('ArkSE', 'ArkSA') @('ScorchedEarth_P', 'Ragnarok', 'Valguero_P', 'CrystalIsles', 'LostIsland', 'Fjordur') 'Scorched Earth' 'Standard' 'Natural' $true $true $false
    & $AddDino 'FireWyvernRag'             'Fire Wyvern (Rag)'          'Ragnarok_Wyvern_Override_C'            'Wyvern'        @('ArkSE', 'ArkSA') @('Ragnarok')     'Ragnarok'        'Standard'  'Natural' $true  $true  $false
    & $AddDino 'Fjordhawk'                 'Fjordhawk'                  'Fjordhawk_Character_BP_C'              'Fjordhawk'     @('ArkSE', 'ArkSA') @('Fjordur')      'Fjordur'         'Standard'  'Natural' $true  $true  $true
    & $AddDino 'ForestTitan'               'Forest Titan'               'ForestKaiju_Character_BP_C'            'ForestKaiju'   @('ArkSE', 'ArkSA') @('Extinction')   'Extinction'      'Titan'     'Natural' $true  $true  $false
    & $AddDino 'ForestWyvern'              'Forest Wyvern'              'Wyvern_Character_BP_Fire_Minion_C'     'Wyvern'        @('ArkSE', 'ArkSA') @('Extinction')   'Extinction'      'Minion'    'Natural' $false $false $false
    & $AddDino 'Gacha'                     'Gacha'                      'Gacha_Character_BP_C'                  'Gacha'         @('ArkSE', 'ArkSA') @('Extinction', 'Gen2', 'Fjordur') 'Extinction' 'Standard' 'Natural' $true $true $true
    & $AddDino 'GachaClaus'                'GachaClaus'                 'Gacha_Claus_Character_BP_C'            'Gacha'         @('ArkSE', 'ArkSA') $AllMaps         'Base Game'       'Event'     'Event'   $true  $false $false
    & $AddDino 'Gallimimus'                'Gallimimus'                 'Galli_Character_BP_C'                  'Galli'         @('ArkSE', 'ArkSA') $AllMaps         'Base Game'       'Standard'  'Natural' $true  $true  $true
    & $AddDino 'GasBag'                    'Gasbags'                    'GasBags_Character_BP_C'                'GasBags'       @('ArkSE', 'ArkSA') @('Extinction', 'Gen2', 'Fjordur') 'Extinction' 'Standard' 'Natural' $true $true $true
    & $AddDino 'GiantBeeDrone'             'Giant Bee Drone'            'Bee_Character_BP_C'                    'Bee'           @('ArkSE', 'ArkSA') $AllMaps         'Base Game'       'Standard'  'Natural' $true  $false $false
    & $AddDino 'GiantBeeQueen'             'Giant Bee Queen'            'Bee_Queen_Character_BP_C'              'Bee'           @('ArkSE', 'ArkSA') $AllMaps         'Base Game'       'Standard'  'Natural' $true  $true  $false
    & $AddDino 'GiantWorkerBee'            'Giant Worker Bee'           'HoneyBee_Character_BP_C'               'Bee'           @('ArkSE', 'ArkSA') @('CrystalIsles') 'Crystal Isles'   'Standard'  'Natural' $true  $false $false
    & $AddDino 'Giganotosaurus'            'Giganotosaurus'             'Gigant_Character_BP_C'                 'Gigant'        @('ArkSE', 'ArkSA') $AllMaps         'Base Game'       'Standard'  'Natural' $true  $true  $true
    & $AddDino 'GiganotosaurusTekCave'     'Giganoto (Tek Cave)'        'Gigant_Character_BP_TekCave_C'         'Gigant'        @('ArkSE', 'ArkSA') @('TheIsland')    'Base Game'       'Standard'  'Natural' $false $false $false
    & $AddDino 'Gigantopithecus'           'Gigantopithecus'            'Bigfoot_Character_BP_C'                'Bigfoot'       @('ArkSE', 'ArkSA') $AllMaps         'Base Game'       'Standard'  'Natural' $true  $true  $false
    & $AddDino 'GigantopithecusMinionAlpha' 'Gigantopithecus (Minion Alpha)' 'Bigfoot_Character_BP_Aggressive_Hard_C' 'Bigfoot' @('ArkSE', 'ArkSA') @('TheIsland')    'Base Game'       'Minion'    'Boss'    $false $false $false
    & $AddDino 'GigantopithecusMinionBeta' 'Gigantopithecus (Minion Beta)'  'Bigfoot_Character_BP_Aggressive_Med_C'  'Bigfoot' @('ArkSE', 'ArkSA') @('TheIsland')    'Base Game'       'Minion'    'Boss'    $false $false $false
    & $AddDino 'GigantopithecusMinionGamma' 'Gigantopithecus (Minion Gamma)' 'Bigfoot_Character_BP_Aggressive_C'      'Bigfoot' @('ArkSE', 'ArkSA') @('TheIsland')    'Base Game'       'Minion'    'Boss'    $false $false $false
    & $AddDino 'Glowbug'                   'Glowbug'                    'Lightbug_Character_BaseBP_C'           'Lightbug'      @('ArkSE', 'ArkSA') @('Aberration_P', 'Valguero_P', 'Gen2', 'Fjordur') 'Aberration' 'Standard' 'Natural' $true $false $false
    & $AddDino 'Glowtail'                  'Glowtail'                   'LanternLizard_Character_BP_C'          'LanternLizard' @('ArkSE', 'ArkSA') @('Aberration_P', 'Valguero_P', 'Gen2', 'Fjordur') 'Aberration' 'Standard' 'Natural' $true $true $true
    & $AddDino 'Griffin'                   'Griffin'                    'Griffin_Character_BP_C'                'Griffin'       @('ArkSE', 'ArkSA') @('Ragnarok', 'CrystalIsles', 'LostIsland', 'Fjordur') 'Ragnarok' 'Standard' 'Natural' $true $true $false
    & $AddDino 'GriffinMinion'             'Griffin (Minion)'           'Griffin_Character_Minion_BP_C'         'Griffin'       @('ArkSE', 'ArkSA') @('Ragnarok')     'Ragnarok'        'Minion'    'Boss'    $false $false $false
    & $AddDino 'Hati'                      'Hati'                       'Fenrir_Character_BP_MiniBoss_Hati_C'   'Fenrir'        @('ArkSE', 'ArkSA') @('Fjordur')      'Fjordur'         'Boss'      'Boss'    $false $false $false
    & $AddDino 'Hesperornis'               'Hesperornis'                'Hesperornis_Character_BP_C'            'Hesperornis'   @('ArkSE', 'ArkSA') $AllMaps         'Base Game'       'Standard'  'Natural' $true  $true  $false
    & $AddDino 'Hyaenodon'                 'Hyaenodon'                  'Hyaenodon_Character_BP_C'              'Hyaenodon'     @('ArkSE', 'ArkSA') $AllMaps         'Base Game'       'Standard'  'Natural' $true  $true  $true
    & $AddDino 'IceGolem'                  'Ice Golem'                  'IceGolem_Character_BP_C'               'RockGolem'     @('ArkSE', 'ArkSA') @('Valguero_P', 'Ragnarok') 'Ragnarok'  'Standard'  'Natural' $true  $true  $false
    & $AddDino 'IceTitan'                  'Ice Titan'                  'IceKaiju_Character_BP_C'               'IceKaiju'      @('ArkSE', 'ArkSA') @('Extinction')   'Extinction'      'Titan'     'Natural' $true  $true  $false
    & $AddDino 'IcewormMale'               'Iceworm Male'               'Iceworm_Character_Minion_BP_smaller_C' 'Iceworm'       @('ArkSE', 'ArkSA') @('Ragnarok')     'Ragnarok'        'Minion'    'Natural' $false $false $false
    & $AddDino 'IceWormQueen'                       'Ice Worm Queen'                     'Iceworm_Queen_Character_BP_C'                 'Iceworm_Queen'      @('ArkSE', 'ArkSA') @('Ragnarok')                                                                           'Ragnarok'       'Boss'          'Boss'    $false $false $false
    & $AddDino 'IceWyvern (Lost Island)'            'Ice Wyvern (Lost Island)'           'Ragnarok_Wyvern_Override_Ice_C'               'Wyvern'             @('ArkSE', 'ArkSA') @('LostIsland')                                                                         'Lost Island'    'Standard'      'Natural' $true  $true  $false
    & $AddDino 'Ichthyornis'                        'Ichthyornis'                        'Ichthyornis_Character_BP_C'                   'Ichthyornis'        @('ArkSE', 'ArkSA') $AllMaps                                                                                'Ark Prime'      'Standard'      'Natural' $true  $true  $true 
    & $AddDino 'Ichthyosaurus'                      'Ichthyosaurus'                      'Dolphin_Character_BP_C'                       'Dolphin'            @('ArkSE', 'ArkSA') $AllMaps                                                                                'Ark Prime'      'Standard'      'Natural' $true  $true  $true 
    & $AddDino 'Iguanodon'                          'Iguanodon'                          'Iguanodon_Character_BP_C'                     'Iguanodon'          @('ArkSE', 'ArkSA') $AllMaps                                                                                'Ark Prime'      'Standard'      'Natural' $true  $true  $true 
    & $AddDino 'Insect Swarm'                       'Insect Swarm'                       'InsectSwarmChar_BP_C'                         'InsectSwarmChar'    @('ArkSE', 'ArkSA') @('Genesis', 'CrystalIsles', 'LostIsland')                                              'Genesis'        'Standard'      'Natural' $true  $false $false
    & $AddDino 'Jerboa'                             'Jerboa'                             'Jerboa_Character_BP_C'                        'Jerboa'             @('ArkSE', 'ArkSA') @('ScorchedEarth_P', 'Ragnarok', 'Valguero_P', 'CrystalIsles', 'LostIsland', 'Fjordur') 'Scorched Earth' 'Standard'      'Natural' $true  $true  $true 
    & $AddDino 'Kairuku'                            'Kairuku'                            'Kairuku_Character_BP_C'                       'Kairuku'            @('ArkSE', 'ArkSA') $AllMaps                                                                                'Ark Prime'      'Standard'      'Natural' $true  $true  $true 
    & $AddDino 'Kaprosuchus'                        'Kaprosuchus'                        'Kaprosuchus_Character_BP_C'                   'Kaprosuchus'        @('ArkSE', 'ArkSA') $AllMaps                                                                                'Ark Prime'      'Standard'      'Natural' $true  $true  $true 
    & $AddDino 'Karkinos'                           'Karkinos'                           'Crab_Character_BP_C'                          'Crab'               @('ArkSE', 'ArkSA') @('Aberration_P', 'Valguero_P', 'CrystalIsles', 'Gen2', 'Fjordur')                      'Aberration'     'Standard'      'Natural' $true  $true  $true 
    & $AddDino 'Kentrosaurus'                       'Kentrosaurus'                       'Kentro_Character_BP_C'                        'Kentro'             @('ArkSE', 'ArkSA') $AllMaps                                                                                'Ark Prime'      'Standard'      'Natural' $true  $true  $true 
    & $AddDino 'King Titan (Alpha)'                 'King Titan (Alpha)'                 'KingKaiju_Character_BP_Alpha_C'               'KingKaiju'          @('ArkSE', 'ArkSA') @('Extinction')                                                                         'Extinction'     'Boss'          'Boss'    $false $false $false
    & $AddDino 'King Titan (Beta)'                  'King Titan (Beta)'                  'KingKaiju_Character_BP_Beta_C'                'KingKaiju'          @('ArkSE', 'ArkSA') @('Extinction')                                                                         'Extinction'     'Boss'          'Boss'    $false $false $false
    & $AddDino 'King Titan (Gamma)'                 'King Titan (Gamma)'                 'KingKaiju_Character_BP_C'                     'KingKaiju'          @('ArkSE', 'ArkSA') @('Extinction')                                                                         'Extinction'     'Boss'          'Boss'    $false $false $false
    & $AddDino 'Lamprey'                            'Lamprey'                            'Lamprey_Character_C'                          'Lamprey'            @('ArkSE', 'ArkSA') @('Aberration_P', 'Valguero_P', 'CrystalIsles', 'Gen2', 'Fjordur')                      'Aberration'     'Standard'      'Natural' $true  $false $false
    & $AddDino 'Lava Elemental'                     'Lava Elemental'                     'LavaGolem_Character_BP_C'                     'LavaGolem'          @('ArkSE', 'ArkSA') @('Ragnarok')                                                                           'Ragnarok'       'Boss'          'Boss'    $false $false $false
    & $AddDino 'Leech'                              'Leech'                              'Leech_Character_C'                            'Leech'              @('ArkSE', 'ArkSA') $AllMaps                                                                                'Ark Prime'      'Standard'      'Natural' $true  $false $false
    & $AddDino 'Leedsichthys'                       'Leedsichthys'                       'Leedsichthys_Character_BP_C'                  'Leedsichthys'       @('ArkSE', 'ArkSA') $AllMaps                                                                                'Ark Prime'      'Standard'      'Natural' $true  $false $false
    & $AddDino 'Lightning Wyvern'                   'Lightning Wyvern'                   'Wyvern_Character_BP_Lightning_C'              'Wyvern'             @('ArkSE', 'ArkSA') @('ScorchedEarth_P', 'Ragnarok', 'Valguero_P', 'CrystalIsles', 'LostIsland', 'Fjordur') 'Scorched Earth' 'Standard'      'Natural' $true  $true  $true 
    & $AddDino 'Liopleurodon'                       'Liopleurodon'                       'Liopleurodon_Character_BP_C'                  'Liopleurodon'       @('ArkSE', 'ArkSA') $AllMaps                                                                                'Ark Prime'      'Standard'      'Natural' $true  $true  $true 
    & $AddDino 'Lunar Reaper King'                  'Lunar Reaper King'                  'Xenomorph_Character_BP_Male_Lunar_C'          'Xenomorph'          @('ArkSE', 'ArkSA') @('Aberration_P', 'Valguero_P', 'CrystalIsles', 'Gen2', 'Fjordur')                      'Aberration'     'Lunar'         'Natural' $true  $true  $true 
    & $AddDino 'Lymantria'                          'Lymantria'                          'Moth_Character_BP_C'                          'Moth'               @('ArkSE', 'ArkSA') @('ScorchedEarth_P', 'Ragnarok', 'Valguero_P', 'CrystalIsles', 'LostIsland', 'Fjordur') 'Scorched Earth' 'Standard'      'Natural' $true  $true  $true 
    & $AddDino 'Lystrosaurus'                       'Lystrosaurus'                       'Lystro_Character_BP_C'                        'Lystro'             @('ArkSE', 'ArkSA') $AllMaps                                                                                'Ark Prime'      'Standard'      'Natural' $true  $true  $true 
    & $AddDino 'Macrophage'                         'Macrophage'                         'Macrophage_Swarm_Character_C'                 'Macrophage_Swarm'   @('ArkSE', 'ArkSA') @('Gen2')                                                                               'Gen2'           'Standard'      'Natural' $true  $true  $true 
    & $AddDino 'Maewing'                            'Maewing'                            'MilkGlider_Character_BP_C'                    'MilkGlider'         @('ArkSE', 'ArkSA') @('Gen2')                                                                               'Gen2'           'Standard'      'Natural' $true  $true  $true 
    & $AddDino 'Magmasaur'                          'Magmasaur'                          'Cherufe_Character_BP_C'                       'Cherufe'            @('ArkSE', 'ArkSA') @('Genesis', 'CrystalIsles', 'LostIsland')                                              'Genesis'        'Standard'      'Natural' $true  $true  $true 
    & $AddDino 'Malfunctioned Attack Drone'         'Malfunctioned Attack Drone'         'EndDrone_Character_BP_Malfunctioned_C'        'EndDrone'           @('ArkSE', 'ArkSA') $AllMaps                                                                                'Ark Prime'      'Malfunctioned' 'Boss'    $false $false $false
    & $AddDino 'Malfunctioned Defense Unit'         'Malfunctioned Defense Unit'         'EndTank_Character_BP_Malfunctioned_C'         'EndTank'            @('ArkSE', 'ArkSA') $AllMaps                                                                                'Ark Prime'      'Malfunctioned' 'Boss'    $false $false $false
    & $AddDino 'Malfunctioned Enforcer'             'Malfunctioned Enforcer'             'Enforcer_Character_BP_Malfunctioned_C'        'Enforcer'           @('ArkSE', 'ArkSA') @('Extinction', 'Genesis', 'Gen2', 'Fjordur')                                           'Extinction'     'Malfunctioned' 'Boss'    $false $false $false
    & $AddDino 'Malfunctioned Tek Giganotosaurus'   'Malfunctioned Tek Giganotosaurus'   'BionicGigant_Character_BP_Malfunctioned_C'    'BionicGigant'       @('ArkSE', 'ArkSA') $AllMaps                                                                                'Ark Prime'      'Malfunctioned' 'Boss'    $false $false $false
    & $AddDino 'Malfunctioned Tek Parasaur'         'Malfunctioned Tek Parasaur'         'BionicPara_Character_BP_Malfunctioned_C'      'BionicPara'         @('ArkSE', 'ArkSA') $AllMaps                                                                                'Ark Prime'      'Malfunctioned' 'Boss'    $false $false $false
    & $AddDino 'Malfunctioned Tek Quetzal'          'Malfunctioned Tek Quetzal'          'BionicQuetz_Character_BP_Malfunctioned_C'     'BionicQuetz'        @('ArkSE', 'ArkSA') $AllMaps                                                                                'Ark Prime'      'Malfunctioned' 'Boss'    $false $false $false
    & $AddDino 'Malfunctioned Tek Raptor'           'Malfunctioned Tek Raptor'           'BionicRaptor_Character_BP_Malfunctioned_C'    'BionicRaptor'       @('ArkSE', 'ArkSA') $AllMaps                                                                                'Ark Prime'      'Malfunctioned' 'Boss'    $false $false $false
    & $AddDino 'Malfunctioned Tek Rex'              'Malfunctioned Tek Rex'              'BionicRex_Character_BP_Malfunctioned_C'       'BionicRex'          @('ArkSE', 'ArkSA') $AllMaps                                                                                'Ark Prime'      'Malfunctioned' 'Boss'    $false $false $false
    & $AddDino 'Malfunctioned Tek Stegosaurus'      'Malfunctioned Tek Stegosaurus'      'BionicStego_Character_BP_Malfunctioned_C'     'BionicStego'        @('ArkSE', 'ArkSA') $AllMaps                                                                                'Ark Prime'      'Malfunctioned' 'Boss'    $false $false $false
    & $AddDino 'Malfunctioned Tek Triceratops'      'Malfunctioned Tek Triceratops'      'BionicTrike_Character_BP_Malfunctioned_C'     'BionicTrike'        @('ArkSE', 'ArkSA') $AllMaps                                                                                'Ark Prime'      'Malfunctioned' 'Boss'    $false $false $false
    & $AddDino 'Mammoth'                            'Mammoth'                            'Mammoth_Character_BP_C'                       'Mammoth'            @('ArkSE', 'ArkSA') $AllMaps                                                                                'Ark Prime'      'Standard'      'Natural' $true  $true  $true 
    & $AddDino 'Managarmr'                          'Managarmr'                          'IceJumper_Character_BP_C'                     'IceJumper'          @('ArkSE', 'ArkSA') @('Extinction', 'Genesis', 'Gen2', 'Fjordur')                                           'Extinction'     'Standard'      'Natural' $true  $true  $true 
    & $AddDino 'Manta'                              'Manta'                              'Manta_Character_BP_C'                         'Manta'              @('ArkSE', 'ArkSA') $AllMaps                                                                                'Ark Prime'      'Standard'      'Natural' $true  $true  $true 
    & $AddDino 'Manticore (Alpha)'                  'Manticore (Alpha)'                  'Manticore_Character_BP_Hard_C'                'Manticore'          @('ArkSE', 'ArkSA') $AllMaps                                                                                'Valguero_P'     'Standard'      'Natural' $true  $true  $true 
    & $AddDino 'Manticore (Alpha) (Ragnarok)'       'Manticore (Alpha) (Ragnarok)'       'Manticore_Character_BP_Hard_Ragnarok_C'       'Manticore'          @('ArkSE', 'ArkSA') @('Ragnarok', 'CrystalIsles', 'LostIsland', 'Fjordur')                                  'Ragnarok'       'Standard'      'Natural' $true  $true  $true 
    & $AddDino 'Manticore (Beta)'                   'Manticore (Beta)'                   'Manticore_Character_BP_Medium_C'              'Manticore'          @('ArkSE', 'ArkSA') @('ScorchedEarth_P', 'Ragnarok', 'Valguero_P', 'CrystalIsles', 'LostIsland', 'Fjordur') 'Scorched Earth' 'Standard'      'Natural' $true  $true  $true 
    & $AddDino 'Manticore (Beta) (Ragnarok)'        'Manticore (Beta) (Ragnarok)'        'Manticore_Character_BP_Medium_Ragnarok_C'     'Manticore'          @('ArkSE', 'ArkSA') @('Ragnarok', 'CrystalIsles', 'LostIsland', 'Fjordur')                                  'Ragnarok'       'Standard'      'Natural' $true  $true  $true 
    & $AddDino 'Manticore (Gamma)'                  'Manticore (Gamma)'                  'Manticore_Character_BP_Easy_C'                'Manticore'          @('ArkSE', 'ArkSA') @('ScorchedEarth_P', 'Ragnarok', 'Valguero_P', 'CrystalIsles', 'LostIsland', 'Fjordur') 'Scorched Earth' 'Standard'      'Natural' $true  $true  $true 
    & $AddDino 'Manticore (Gamma) (Ragnarok)'       'Manticore (Gamma) (Ragnarok)'       'Manticore_Character_BP_Easy_Ragnarok_C'       'Manticore'          @('ArkSE', 'ArkSA') @('Ragnarok', 'CrystalIsles', 'LostIsland', 'Fjordur')                                  'Ragnarok'       'Standard'      'Natural' $true  $true  $true 
    & $AddDino 'Mantis'                             'Mantis'                             'Mantis_Character_BP_C'                        'Mantis'             @('ArkSE', 'ArkSA') @('ScorchedEarth_P', 'Ragnarok', 'Valguero_P', 'CrystalIsles', 'LostIsland', 'Fjordur') 'Scorched Earth' 'Standard'      'Natural' $true  $true  $true 
    & $AddDino 'Mantis Ghost'                       'Mantis Ghost'                       'Ghost_Mantis_Character_BP_C'                  'Ghost_Mantis'       @('ArkSE', 'ArkSA') @('ScorchedEarth_P', 'Ragnarok', 'Valguero_P', 'CrystalIsles', 'LostIsland', 'Fjordur') 'Scorched Earth' 'Ghost'         'Event'   $true  $false $false
    & $AddDino 'Megachelon'                         'Megachelon'                         'GiantTurtle_Character_BP_C'                   'GiantTurtle'        @('ArkSE', 'ArkSA') @('Genesis', 'CrystalIsles', 'LostIsland')                                              'Genesis'        'Standard'      'Natural' $true  $true  $true 
    & $AddDino 'Megalania'                          'Megalania'                          'Megalania_Character_BP_C'                     'Megalania'          @('ArkSE', 'ArkSA') $AllMaps                                                                                'Ark Prime'      'Standard'      'Natural' $true  $true  $true 
    & $AddDino 'Megaloceros'                        'Megaloceros'                        'Stag_Character_BP_C'                          'Stag'               @('ArkSE', 'ArkSA') $AllMaps                                                                                'Ark Prime'      'Standard'      'Natural' $true  $true  $true 
    & $AddDino 'Megaloceros (Lifes Labyrinth)'      'Megaloceros (Lifes Labyrinth)'      'Stag_LL_Character_BP_C'                       'Stag_LL'            @('ArkSE', 'ArkSA') @('Ragnarok', 'CrystalIsles', 'LostIsland', 'Fjordur')                                  'Ragnarok'       'Standard'      'Natural' $true  $true  $true 
    & $AddDino 'Megalodon'                          'Megalodon'                          'Megalodon_Character_BP_C'                     'Megalodon'          @('ArkSE', 'ArkSA') $AllMaps                                                                                'Ark Prime'      'Standard'      'Natural' $true  $true  $true 
    & $AddDino 'Megalosaurus'                       'Megalosaurus'                       'Megalosaurus_Character_BP_C'                  'Megalosaurus'       @('ArkSE', 'ArkSA') $AllMaps                                                                                'Ark Prime'      'Standard'      'Natural' $true  $true  $true 
    & $AddDino 'Megalosaurus (Tek Cave)'            'Megalosaurus (Tek Cave)'            'Megalosaurus_Character_BP_TekCave_C'          'Megalosaurus'       @('ArkSE', 'ArkSA') $AllMaps                                                                                'Ark Prime'      'Standard'      'Natural' $true  $true  $true 
    & $AddDino 'Mega Mek'                           'Mega Mek'                           'MegaMek_Character_BP_C'                       'MegaMek'            @('ArkSE', 'ArkSA') @('Extinction', 'Genesis', 'Gen2', 'Fjordur')                                           'Extinction'     'Standard'      'Natural' $true  $true  $true 
    & $AddDino 'Meganeura'                          'Meganeura'                          'Dragonfly_Character_BP_C'                     'Dragonfly'          @('ArkSE', 'ArkSA') $AllMaps                                                                                'Ark Prime'      'Standard'      'Natural' $true  $true  $true 
    & $AddDino 'Megapithecus (Alpha)'               'Megapithecus (Alpha)'               'Gorilla_Character_BP_Hard_FJ_C'               'Gorilla'            @('ArkSE', 'ArkSA') @('Fjordur')                                                                            'Fjordur'        'Standard'      'Natural' $true  $true  $true 
    & $AddDino 'Megapithecus (Alpha)'               'Megapithecus (Alpha)'               'Gorilla_Character_BP_Hard_C'                  'Gorilla'            @('ArkSE', 'ArkSA') $AllMaps                                                                                'Valguero_P'     'Standard'      'Natural' $true  $true  $true 
    & $AddDino 'Megapithecus (Alpha) (The Center)'  'Megapithecus (Alpha) (The Center)'  'Gorilla_Character_BP_TheCenter_Hard_C'        'Gorilla'            @('ArkSE', 'ArkSA') $AllMaps                                                                                'Ark Prime'      'Standard'      'Natural' $true  $true  $true 
    & $AddDino 'Megapithecus (Beta)'                'Megapithecus (Beta)'                'Gorilla_Character_BP_Medium_C'                'Gorilla'            @('ArkSE', 'ArkSA') $AllMaps                                                                                'Ark Prime'      'Standard'      'Natural' $true  $true  $true 
    & $AddDino 'Megapithecus (Beta)'                'Megapithecus (Beta)'                'Gorilla_Character_BP_Medium_FJ_C'             'Gorilla'            @('ArkSE', 'ArkSA') @('Fjordur')                                                                            'Fjordur'        'Standard'      'Natural' $true  $true  $true 
    & $AddDino 'Megapithecus (Beta) (The Center)'   'Megapithecus (Beta) (The Center)'   'Gorilla_Character_BP_TheCenter_Medium_C'      'Gorilla'            @('ArkSE', 'ArkSA') $AllMaps                                                                                'Ark Prime'      'Standard'      'Natural' $true  $true  $true 
    & $AddDino 'Megapithecus (Gamma)'               'Megapithecus (Gamma)'               'Gorilla_Character_BP_Easy_C'                  'Gorilla'            @('ArkSE', 'ArkSA') $AllMaps                                                                                'Valguero_P'     'Standard'      'Natural' $true  $true  $true 
    & $AddDino 'Megapithecus (Gamma)'               'Megapithecus (Gamma)'               'Gorilla_Character_BP_Easy_FJ_C'               'Gorilla'            @('ArkSE', 'ArkSA') @('Fjordur')                                                                            'Fjordur'        'Standard'      'Natural' $true  $true  $true 
    & $AddDino 'Megapithecus (Gamma) (The Center)'  'Megapithecus (Gamma) (The Center)'  'Gorilla_Character_BP_TheCenter_C'             'Gorilla'            @('ArkSE', 'ArkSA') $AllMaps                                                                                'Ark Prime'      'Standard'      'Natural' $true  $true  $true 
    & $AddDino 'Megatherium'                        'Megatherium'                        'Megatherium_Character_BP_C'                   'Megatherium'        @('ArkSE', 'ArkSA') $AllMaps                                                                                'Ark Prime'      'Standard'      'Natural' $true  $true  $true 
    & $AddDino 'Mek'                                'Mek'                                'Mek_Character_BP_C'                           'Mek'                @('ArkSE', 'ArkSA') @('Extinction', 'Genesis', 'Gen2', 'Fjordur')                                           'Extinction'     'Standard'      'Natural' $true  $true  $true 
    & $AddDino 'Mesopithecus'                       'Mesopithecus'                       'Monkey_Character_BP_C'                        'Monkey'             @('ArkSE', 'ArkSA') $AllMaps                                                                                'Ark Prime'      'Standard'      'Natural' $true  $true  $true 
    & $AddDino 'Mesopithecus (Boss Minion) (Alpha)' 'Mesopithecus (Boss Minion) (Alpha)' 'Monkey_Character_BP_Aggressive_Hard_C'        'Monkey'             @('ArkSE', 'ArkSA') $AllMaps                                                                                'Ark Prime'      'Minion'        'Boss'    $false $false $false
    & $AddDino 'Mesopithecus (Boss Minion) (Beta)'  'Mesopithecus (Boss Minion) (Beta)'  'Monkey_Character_BP_Aggressive_Med_C'         'Monkey'             @('ArkSE', 'ArkSA') $AllMaps                                                                                'Ark Prime'      'Minion'        'Boss'    $false $false $false
    & $AddDino 'Mesopithecus (Boss Minion) (Gamma)' 'Mesopithecus (Boss Minion) (Gamma)' 'Monkey_Character_BP_Aggressive_C'             'Monkey'             @('ArkSE', 'ArkSA') $AllMaps                                                                                'Ark Prime'      'Minion'        'Boss'    $false $false $false
    & $AddDino 'Microraptor'                        'Microraptor'                        'Microraptor_Character_BP_C'                   'Microraptor'        @('ArkSE', 'ArkSA') $AllMaps                                                                                'Ark Prime'      'Standard'      'Natural' $true  $true  $true 
    & $AddDino 'Moeder (Alpha)'                     'Moeder (Alpha)'                     'EelBoss_Character_BP_Hard_C'                  'EelBoss'            @('ArkSE', 'ArkSA') @('Genesis', 'CrystalIsles', 'LostIsland')                                              'Genesis'        'Standard'      'Natural' $true  $true  $true 
    & $AddDino 'Moeder (Beta)'                      'Moeder (Beta)'                      'EelBoss_Character_BP_Medium_C'                'EelBoss'            @('ArkSE', 'ArkSA') @('Genesis', 'CrystalIsles', 'LostIsland')                                              'Genesis'        'Standard'      'Natural' $true  $true  $true 
    & $AddDino 'Moeder (Gamma)'                     'Moeder (Gamma)'                     'EelBoss_Character_BP_Easy_C'                  'EelBoss'            @('ArkSE', 'ArkSA') @('Genesis', 'CrystalIsles', 'LostIsland')                                              'Genesis'        'Standard'      'Natural' $true  $true  $true 
    & $AddDino 'Morellatops'                        'Morellatops'                        'camelsaurus_Character_BP_C'                   'camelsaurus'        @('ArkSE', 'ArkSA') @('ScorchedEarth_P', 'Ragnarok', 'Valguero_P', 'CrystalIsles', 'LostIsland', 'Fjordur') 'Scorched Earth' 'Standard'      'Natural' $true  $true  $true 
    & $AddDino 'Mosasaurus'                         'Mosasaurus'                         'Mosa_Character_BP_C'                          'Mosa'               @('ArkSE', 'ArkSA') $AllMaps                                                                                'Ark Prime'      'Standard'      'Natural' $true  $true  $true 
    & $AddDino 'Mosasaurus (Cave)'                  'Mosasaurus (Cave)'                  'Mosa_Character_BP_Cave_C'                     'Mosa'               @('ArkSE', 'ArkSA') $AllMaps                                                                                'Ark Prime'      'Standard'      'Natural' $true  $true  $true 
    & $AddDino 'Moschops'                           'Moschops'                           'Moschops_Character_BP_C'                      'Moschops'           @('ArkSE', 'ArkSA') $AllMaps                                                                                'Ark Prime'      'Standard'      'Natural' $true  $true  $true 
    & $AddDino 'Nameless'                           'Nameless'                           'ChupaCabra_Character_BP_C'                    'ChupaCabra'         @('ArkSE', 'ArkSA') @('Aberration_P', 'Valguero_P', 'CrystalIsles', 'Gen2', 'Fjordur')                      'Aberration'     'Standard'      'Natural' $true  $true  $true 
    & $AddDino 'Nameless (Minion)'                  'Nameless (Minion)'                  'ChupaCabra_Character_BP_Minion_C'             'ChupaCabra'         @('ArkSE', 'ArkSA') @('Aberration_P', 'Valguero_P', 'CrystalIsles', 'Gen2', 'Fjordur')                      'Aberration'     'Minion'        'Boss'    $false $false $false
    & $AddDino 'Nameless (Surface)'                 'Nameless (Surface)'                 'ChupaCabra_Character_BP_Surface_C'            'ChupaCabra'         @('ArkSE', 'ArkSA') @('Aberration_P', 'Valguero_P', 'CrystalIsles', 'Gen2', 'Fjordur')                      'Aberration'     'Surface'       'Natural' $true  $true  $true 
    & $AddDino 'Net Breaking Piranha'               'Net Breaking Piranha'               'Piranha_Character_BP_BreakNet_C'              'Piranha'            @('ArkSE', 'ArkSA') $AllMaps                                                                                'Ark Prime'      'Standard'      'Natural' $true  $false $false
    & $AddDino 'Noglin'                             'Noglin'                             'BrainSlug_Character_BP_C'                     'BrainSlug'          @('ArkSE', 'ArkSA') @('Gen2')                                                                               'Gen2'           'Standard'      'Natural' $true  $true  $true 
    & $AddDino 'Oil Jug Bug'                        'Oil Jug Bug'                        'Jugbug_Oil_Character_BP_C'                    'Jugbug_Oil'         @('ArkSE', 'ArkSA') @('ScorchedEarth_P', 'Ragnarok', 'Valguero_P', 'CrystalIsles', 'LostIsland', 'Fjordur') 'Scorched Earth' 'Standard'      'Natural' $true  $true  $true 
    & $AddDino 'Onychonycteris'                     'Onychonycteris'                     'Bat_Character_BP_C'                           'Bat'                @('ArkSE', 'ArkSA') $AllMaps                                                                                'Ark Prime'      'Standard'      'Natural' $true  $true  $true 
    & $AddDino 'Otter'                              'Otter'                              'Otter_Character_BP_C'                         'Otter'              @('ArkSE', 'ArkSA') $AllMaps                                                                                'Ark Prime'      'Standard'      'Natural' $true  $true  $true 
    & $AddDino 'Overseer (Alpha)'                   'Overseer (Alpha)'                   'EndBoss_Character_Hard_C'                     'EndBoss'            @('ArkSE', 'ArkSA') $AllMaps                                                                                'Ark Prime'      'Boss'          'Boss'    $false $false $false
    & $AddDino 'Overseer (Beta)'                    'Overseer (Beta)'                    'EndBoss_Character_Medium_C'                   'EndBoss'            @('ArkSE', 'ArkSA') $AllMaps                                                                                'Ark Prime'      'Boss'          'Boss'    $false $false $false
    & $AddDino 'Overseer (Dragon Form) (Alpha)'     'Overseer (Dragon Form) (Alpha)'     'EndBossDragon_Character_BP_Hard_C'            'EndBossDragon'      @('ArkSE', 'ArkSA') $AllMaps                                                                                'Ark Prime'      'Boss'          'Boss'    $false $false $false
    & $AddDino 'Overseer (Dragon Form) (Beta)'      'Overseer (Dragon Form) (Beta)'      'EndBossDragon_Character_BP_Medium_C'          'EndBossDragon'      @('ArkSE', 'ArkSA') $AllMaps                                                                                'Ark Prime'      'Boss'          'Boss'    $false $false $false
    & $AddDino 'Overseer (Dragon Form) (Gamma)'     'Overseer (Dragon Form) (Gamma)'     'EndBossDragon_Character_BP_Easy_C'            'EndBossDragon'      @('ArkSE', 'ArkSA') $AllMaps                                                                                'Ark Prime'      'Boss'          'Boss'    $false $false $false
    & $AddDino 'Overseer (Gamma)'                   'Overseer (Gamma)'                   'EndBoss_Character_Easy_C'                     'EndBoss'            @('ArkSE', 'ArkSA') $AllMaps                                                                                'Ark Prime'      'Boss'          'Boss'    $false $false $false
    & $AddDino 'Overseer (Gorilla Form) (Alpha)'    'Overseer (Gorilla Form) (Alpha)'    'EndBossGorilla_Character_BP_Hard_C'           'EndBossGorilla'     @('ArkSE', 'ArkSA') $AllMaps                                                                                'Ark Prime'      'Boss'          'Boss'    $false $false $false
    & $AddDino 'Overseer (Gorilla Form) (Beta)'     'Overseer (Gorilla Form) (Beta)'     'EndBossGorilla_Character_BP_Medium_C'         'EndBossGorilla'     @('ArkSE', 'ArkSA') $AllMaps                                                                                'Ark Prime'      'Boss'          'Boss'    $false $false $false
    & $AddDino 'Overseer (Gorilla Form) (Gamma)'    'Overseer (Gorilla Form) (Gamma)'    'EndBossGorilla_Character_BP_Easy_C'           'EndBossGorilla'     @('ArkSE', 'ArkSA') $AllMaps                                                                                'Ark Prime'      'Boss'          'Boss'    $false $false $false
    & $AddDino 'Overseer (Spider Form) (Alpha)'     'Overseer (Spider Form) (Alpha)'     'EndBossSpiderL_Character_BP_Hard_C'           'EndBossSpiderL'     @('ArkSE', 'ArkSA') $AllMaps                                                                                'Ark Prime'      'Boss'          'Boss'    $false $false $false
    & $AddDino 'Overseer (Spider Form) (Beta)'      'Overseer (Spider Form) (Beta)'      'EndBossSpiderL_Character_BP_Medium_C'         'EndBossSpiderL'     @('ArkSE', 'ArkSA') $AllMaps                                                                                'Ark Prime'      'Boss'          'Boss'    $false $false $false
    & $AddDino 'Overseer (Spider Form) (Gamma)'     'Overseer (Spider Form) (Gamma)'     'EndBossSpiderL_Character_BP_Easy_C'           'EndBossSpiderL'     @('ArkSE', 'ArkSA') $AllMaps                                                                                'Ark Prime'      'Boss'          'Boss'    $false $false $false
    & $AddDino 'Oviraptor'                          'Oviraptor'                          'Oviraptor_Character_BP_C'                     'Oviraptor'          @('ArkSE', 'ArkSA') $AllMaps                                                                                'Ark Prime'      'Standard'      'Natural' $true  $true  $true 
    & $AddDino 'Ovis'                               'Ovis'                               'Sheep_Character_BP_C'                         'Sheep'              @('ArkSE', 'ArkSA') $AllMaps                                                                                'Ark Prime'      'Standard'      'Natural' $true  $true  $true 
    & $AddDino 'Pachycephalosaurus'                 'Pachycephalosaurus'                 'Pachy_Character_BP_C'                         'Pachy'              @('ArkSE', 'ArkSA') $AllMaps                                                                                'Ark Prime'      'Standard'      'Natural' $true  $true  $true 
    & $AddDino 'Pachyrhinosaurus'                   'Pachyrhinosaurus'                   'Pachyrhino_Character_BP_C'                    'Pachyrhino'         @('ArkSE', 'ArkSA') $AllMaps                                                                                'Ark Prime'      'Standard'      'Natural' $true  $true  $true 
    & $AddDino 'Paraceratherium'                    'Paraceratherium'                    'Paracer_Character_BP_C'                       'Paracer'            @('ArkSE', 'ArkSA') $AllMaps                                                                                'Ark Prime'      'Standard'      'Natural' $true  $true  $true 
    & $AddDino 'Parakeet Fish School'               'Parakeet Fish School'               'MicrobeSwarmChar_BP_C'                        'MicrobeSwarmChar'   @('ArkSE', 'ArkSA') @('Genesis', 'CrystalIsles', 'LostIsland')                                              'Genesis'        'Standard'      'Natural' $true  $false $false
    & $AddDino 'Parasaurolophus'                    'Parasaurolophus'                    'Para_Character_BP_C'                          'Para'               @('ArkSE', 'ArkSA') $AllMaps                                                                                'Ark Prime'      'Standard'      'Natural' $true  $true  $true 
    & $AddDino 'Party Dodo'                         'Party Dodo'                         'Dodo_Character_BP_Birthday_C'                 'Dodo'               @('ArkSE', 'ArkSA') $AllMaps                                                                                'Ark Prime'      'Event'         'Event'   $true  $false $false
    & $AddDino 'Pegomastax'                         'Pegomastax'                         'Pegomastax_Character_BP_C'                    'Pegomastax'         @('ArkSE', 'ArkSA') $AllMaps                                                                                'Ark Prime'      'Standard'      'Natural' $true  $true  $true 
    & $AddDino 'Pelagornis'                         'Pelagornis'                         'Pela_Character_BP_C'                          'Pela'               @('ArkSE', 'ArkSA') $AllMaps                                                                                'Ark Prime'      'Standard'      'Natural' $true  $true  $true 
    & $AddDino 'Phiomia'                            'Phiomia'                            'Phiomia_Character_BP_C'                       'Phiomia'            @('ArkSE', 'ArkSA') $AllMaps                                                                                'Ark Prime'      'Standard'      'Natural' $true  $true  $true 
    & $AddDino 'Phoenix'                            'Phoenix'                            'Phoenix_Character_BP_C'                       'Phoenix'            @('ArkSE', 'ArkSA') @('ScorchedEarth_P', 'Ragnarok', 'Valguero_P', 'CrystalIsles', 'LostIsland', 'Fjordur') 'Scorched Earth' 'Standard'      'Natural' $true  $true  $true 
    & $AddDino 'Piranha'                            'Piranha'                            'Piranha_Character_BP_C'                       'Piranha'            @('ArkSE', 'ArkSA') $AllMaps                                                                                'Ark Prime'      'Standard'      'Natural' $true  $false $false
    & $AddDino 'Plesiosaur'                         'Plesiosaur'                         'Plesiosaur_Character_BP_C'                    'Plesiosaur'         @('ArkSE', 'ArkSA') $AllMaps                                                                                'Ark Prime'      'Standard'      'Natural' $true  $true  $true 
    & $AddDino 'Poison Wyvern'                      'Poison Wyvern'                      'Wyvern_Character_BP_Poison_C'                 'Wyvern'             @('ArkSE', 'ArkSA') @('ScorchedEarth_P', 'Ragnarok', 'Valguero_P', 'CrystalIsles', 'LostIsland', 'Fjordur') 'Scorched Earth' 'Standard'      'Natural' $true  $true  $true 
    & $AddDino 'Polar Bear'                         'Polar Bear'                         'Direbear_Character_Polar_C'                   'Direbear'           @('ArkSE', 'ArkSA') $AllMaps                                                                                'Ark Prime'      'Standard'      'Natural' $true  $true  $true 
    & $AddDino 'Procoptodon'                        'Procoptodon'                        'Procoptodon_Character_BP_C'                   'Procoptodon'        @('ArkSE', 'ArkSA') $AllMaps                                                                                'Ark Prime'      'Standard'      'Natural' $true  $true  $true 
    & $AddDino 'Pteranodon'                         'Pteranodon'                         'Ptero_Character_BP_C'                         'Ptero'              @('ArkSE', 'ArkSA') $AllMaps                                                                                'Ark Prime'      'Standard'      'Natural' $true  $true  $true 
    & $AddDino 'Pteranodon (Boss Minion) (Alpha)'   'Pteranodon (Boss Minion) (Alpha)'   'Ptero_Minion_Character_Hard_C'                'Ptero_Minion'       @('ArkSE', 'ArkSA') $AllMaps                                                                                'Ark Prime'      'Minion'        'Boss'    $false $false $false
    & $AddDino 'Pteranodon (Boss Minion) (Beta)'    'Pteranodon (Boss Minion) (Beta)'    'Ptero_Minion_Character_Med_C'                 'Ptero_Minion'       @('ArkSE', 'ArkSA') $AllMaps                                                                                'Ark Prime'      'Minion'        'Boss'    $false $false $false
    & $AddDino 'Pteranodon (Boss Minion) (Gamma)'   'Pteranodon (Boss Minion) (Gamma)'   'Ptero_Minion_Character_BP_C'                  'Ptero_Minion'       @('ArkSE', 'ArkSA') $AllMaps                                                                                'Ark Prime'      'Minion'        'Boss'    $false $false $false
    & $AddDino 'Pulmonoscorpius'                    'Pulmonoscorpius'                    'Scorpion_Character_BP_C'                      'Scorpion'           @('ArkSE', 'ArkSA') $AllMaps                                                                                'Ark Prime'      'Standard'      'Natural' $true  $true  $true 
    & $AddDino 'Purlovia'                           'Purlovia'                           'Purlovia_Character_BP_C'                      'Purlovia'           @('ArkSE', 'ArkSA') $AllMaps                                                                                'Ark Prime'      'Standard'      'Natural' $true  $true  $true 
    & $AddDino 'Purlovia (Polar)'                   'Purlovia (Polar)'                   'Purlovia_Character_BP_Polar_C'                'Purlovia'           @('ArkSE', 'ArkSA') $AllMaps                                                                                'Ark Prime'      'Standard'      'Natural' $true  $true  $true 
    & $AddDino 'Quetzalcoatlus'                     'Quetzalcoatlus'                     'Quetz_Character_BP_C'                         'Quetz'              @('ArkSE', 'ArkSA') $AllMaps                                                                                'Ark Prime'      'Standard'      'Natural' $true  $true  $true 
    & $AddDino 'R-Allosaurus'                       'R-Allosaurus'                       'Allo_Character_BP_Rockwell_C'                 'Allo'               @('ArkSE', 'ArkSA') @('Gen2')                                                                               'Gen2'           'R'             'Natural' $true  $true  $true 
    & $AddDino 'Raptor'                             'Raptor'                             'Raptor_Character_BP_C'                        'Raptor'             @('ArkSE', 'ArkSA') $AllMaps                                                                                'Ark Prime'      'Standard'      'Natural' $true  $true  $true 
    & $AddDino 'Rare Sabertooth Salmon'             'Rare Sabertooth Salmon'             'Salmon_Character_Rare_BP_C'                   'Salmon'             @('ArkSE', 'ArkSA') $AllMaps                                                                                'Ark Prime'      'Rare'          'Natural' $true  $true  $true 
    & $AddDino 'Ravager'                            'Ravager'                            'CaveWolf_Character_BP_C'                      'CaveWolf'           @('ArkSE', 'ArkSA') @('Aberration_P', 'Valguero_P', 'CrystalIsles', 'Gen2', 'Fjordur')                      'Aberration'     'Standard'      'Natural' $true  $true  $true 
    & $AddDino 'R-Brontosaurus'                     'R-Brontosaurus'                     'Sauropod_Character_BP_Rockwell_C'             'Sauropod'           @('ArkSE', 'ArkSA') @('Gen2')                                                                               'Gen2'           'R'             'Natural' $true  $true  $true 
    & $AddDino 'R-Carbonemys'                       'R-Carbonemys'                       'Turtle_Character_BP_Rockwell_C'               'Turtle'             @('ArkSE', 'ArkSA') @('Gen2')                                                                               'Gen2'           'R'             'Natural' $true  $true  $true 
    & $AddDino 'R-Carnotaurus'                      'R-Carnotaurus'                      'Carno_Character_BP_Rockwell_C'                'Carno'              @('ArkSE', 'ArkSA') @('Gen2')                                                                               'Gen2'           'R'             'Natural' $true  $true  $true 
    & $AddDino 'R-Daeodon'                          'R-Daeodon'                          'Daeodon_Character_BP_Eden_C'                  'Daeodon'            @('ArkSE', 'ArkSA') @('Gen2')                                                                               'Gen2'           'R'             'Natural' $true  $true  $true 
    & $AddDino 'R-Dilophosaur'                      'R-Dilophosaur'                      'Dilo_Character_BP_Rockwell_C'                 'Dilo'               @('ArkSE', 'ArkSA') @('Gen2')                                                                               'Gen2'           'R'             'Natural' $true  $true  $true 
    & $AddDino 'R-Dire Bear'                        'R-Dire Bear'                        'Direbear_Character_BP_Rockwell_C'             'Direbear'           @('ArkSE', 'ArkSA') @('Gen2')                                                                               'Gen2'           'R'             'Natural' $true  $true  $true 
    & $AddDino 'R-Direwolf'                         'R-Direwolf'                         'Direwolf_Character_BP_Eden_C'                 'Direwolf'           @('ArkSE', 'ArkSA') @('Gen2')                                                                               'Gen2'           'R'             'Natural' $true  $true  $true 
    & $AddDino 'Reaper King'                        'Reaper King'                        'Xenomorph_Character_BP_Male_Tamed_C'          'Xenomorph'          @('ArkSE', 'ArkSA') @('Aberration_P', 'Valguero_P', 'CrystalIsles', 'Gen2', 'Fjordur')                      'Aberration'     'Standard'      'Natural' $true  $true  $true 
    & $AddDino 'Reaper Queen'                       'Reaper Queen'                       'Xenomorph_Character_BP_Female_C'              'Xenomorph'          @('ArkSE', 'ArkSA') @('Aberration_P', 'Valguero_P', 'CrystalIsles', 'Gen2', 'Fjordur')                      'Aberration'     'Standard'      'Natural' $true  $true  $true 
    & $AddDino 'R-Equus'                            'R-Equus'                            'Equus_Character_BP_Eden_C'                    'Equus'              @('ArkSE', 'ArkSA') @('Gen2')                                                                               'Gen2'           'R'             'Natural' $true  $true  $true 
    & $AddDino 'Rex'                                'Rex'                                'Rex_Character_BP_C'                           'Rex'                @('ArkSE', 'ArkSA') $AllMaps                                                                                'Ark Prime'      'Standard'      'Natural' $true  $true  $true 
    & $AddDino 'Rex Ghost'                          'Rex Ghost'                          'Ghost_Rex_Character_BP_C'                     'Ghost_Rex'          @('ArkSE', 'ArkSA') $AllMaps                                                                                'Ark Prime'      'Ghost'         'Event'   $true  $false $false
    & $AddDino 'R-Gasbags'                          'R-Gasbags'                          'GasBags_Character_BP_Eden_C'                  'GasBags'            @('ArkSE', 'ArkSA') @('Gen2')                                                                               'Gen2'           'R'             'Natural' $true  $true  $true 
    & $AddDino 'R-Giganotosaurus'                   'R-Giganotosaurus'                   'Gigant_Character_BP_Rockwell_C'               'Gigant'             @('ArkSE', 'ArkSA') @('Gen2')                                                                               'Gen2'           'R'             'Natural' $true  $true  $true 
    & $AddDino 'Rhyniognatha'                       'Rhyniognatha'                       'Rhynio_Character_BP_C'                        'Rhynio'             @('ArkSE', 'ArkSA') $AllMaps                                                                                'Ark Prime'      'Standard'      'Natural' $true  $true  $true 
    & $AddDino 'R-Megatherium'                      'R-Megatherium'                      'Megatherium_Character_BP_Eden_C'              'Megatherium'        @('ArkSE', 'ArkSA') @('Gen2')                                                                               'Gen2'           'R'             'Natural' $true  $true  $true 
    & $AddDino 'Rock Drake'                         'Rock Drake'                         'RockDrake_Character_BP_C'                     'RockDrake'          @('ArkSE', 'ArkSA') @('Aberration_P', 'Valguero_P', 'CrystalIsles', 'Gen2', 'Fjordur')                      'Aberration'     'Standard'      'Natural' $true  $true  $true 
    & $AddDino 'Rock Golem'                         'Rock Golem'                         'RockGolem_Character_BP_C'                     'RockGolem'          @('ArkSE', 'ArkSA') @('ScorchedEarth_P', 'Ragnarok', 'Valguero_P', 'CrystalIsles', 'LostIsland', 'Fjordur') 'Scorched Earth' 'Standard'      'Natural' $true  $true  $true 
    & $AddDino 'Rock Golem (Boss Minion)'           'Rock Golem (Boss Minion)'           'RockGolem_Character_Minion_BP_C'              'RockGolem'          @('ArkSE', 'ArkSA') @('ScorchedEarth_P', 'Ragnarok', 'Valguero_P', 'CrystalIsles', 'LostIsland', 'Fjordur') 'Scorched Earth' 'Minion'        'Boss'    $false $false $false
    & $AddDino 'Rockwell Node (Alpha)'              'Rockwell Node (Alpha)'              'RockwellNode_Character_BP_FinalFight_Alpha_C' 'RockwellNode'       @('ArkSE', 'ArkSA') @('Gen2')                                                                               'Gen2'           'Boss'          'Boss'    $false $false $false
    & $AddDino 'Rockwell Node (Beta)'               'Rockwell Node (Beta)'               'RockwellNode_Character_BP_FinalFight_Beta_C'  'RockwellNode'       @('ArkSE', 'ArkSA') @('Gen2')                                                                               'Gen2'           'Boss'          'Boss'    $false $false $false
    & $AddDino 'Rockwell Node (Gamma)'              'Rockwell Node (Gamma)'              'RockwellNode_Character_BP_FinalFight_Gamma_C' 'RockwellNode'       @('ArkSE', 'ArkSA') @('Gen2')                                                                               'Gen2'           'Boss'          'Boss'    $false $false $false
    & $AddDino 'Rockwell Prime (Alpha)'             'Rockwell Prime (Alpha)'             'RockwellNode_Character_BP_Boss_Alpha_C'       'RockwellNode'       @('ArkSE', 'ArkSA') @('Gen2')                                                                               'Gen2'           'Boss'          'Boss'    $false $false $false
    & $AddDino 'Rockwell Prime (Beta)'              'Rockwell Prime (Beta)'              'RockwellNode_Character_BP_Boss_Beta_C'        'RockwellNode'       @('ArkSE', 'ArkSA') @('Gen2')                                                                               'Gen2'           'Boss'          'Boss'    $false $false $false
    & $AddDino 'Rockwell Prime (Gamma)'             'Rockwell Prime (Gamma)'             'RockwellNode_Character_BP_Boss_Gamma_C'       'RockwellNode'       @('ArkSE', 'ArkSA') @('Gen2')                                                                               'Gen2'           'Boss'          'Boss'    $false $false $false
    & $AddDino 'Rockwell Reaper Female'             'Rockwell Reaper Female'             'Xenomorph_Character_BP_Female_Gen2_C'         'Xenomorph'          @('ArkSE', 'ArkSA') @('Gen2')                                                                               'Gen2'           'Boss'          'Boss'    $false $false $false
    & $AddDino 'Rockwell Reaper Male'               'Rockwell Reaper Male'               'Xenomorph_Character_BP_Male_Gen2_C'           'Xenomorph'          @('ArkSE', 'ArkSA') @('Gen2')                                                                               'Gen2'           'Boss'          'Boss'    $false $false $false
    & $AddDino 'Rockwell Tentacle (Alpha)'          'Rockwell Tentacle (Alpha)'          'RockwellTentacle_Character_BP_Alpha_C'        'RockwellTentacle'   @('ArkSE', 'ArkSA') @('Aberration_P', 'Valguero_P', 'CrystalIsles', 'Gen2', 'Fjordur')                      'Aberration'     'Boss'          'Boss'    $false $false $false
    & $AddDino 'Rockwell Tentacle (Base)'           'Rockwell Tentacle (Base)'           'RockwellTentacle_Character_BP_C'              'RockwellTentacle'   @('ArkSE', 'ArkSA') @('Aberration_P', 'Valguero_P', 'CrystalIsles', 'Gen2', 'Fjordur')                      'Aberration'     'Boss'          'Boss'    $false $false $false
    & $AddDino 'Rockwell Tentacle (Beta)'           'Rockwell Tentacle (Beta)'           'RockwellTentacle_Character_BP_Beta_C'         'RockwellTentacle'   @('ArkSE', 'ArkSA') @('Aberration_P', 'Valguero_P', 'CrystalIsles', 'Gen2', 'Fjordur')                      'Aberration'     'Boss'          'Boss'    $false $false $false
    & $AddDino 'Rockwell Tentacle (Gamma)'          'Rockwell Tentacle (Gamma)'          'RockwellTentacle_Character_BP_Gamma_C'        'RockwellTentacle'   @('ArkSE', 'ArkSA') @('Aberration_P', 'Valguero_P', 'CrystalIsles', 'Gen2', 'Fjordur')                      'Aberration'     'Boss'          'Boss'    $false $false $false
    & $AddDino 'Roll Rat'                           'Roll Rat'                           'MoleRat_Character_BP_C'                       'MoleRat'            @('ArkSE', 'ArkSA') @('Aberration_P', 'Valguero_P', 'CrystalIsles', 'Gen2', 'Fjordur')                      'Aberration'     'Standard'      'Natural' $true  $true  $true 
    & $AddDino 'R-Parasaur'                         'R-Parasaur'                         'Para_Character_BP_Eden_C'                     'Para'               @('ArkSE', 'ArkSA') @('Gen2')                                                                               'Gen2'           'R'             'Natural' $true  $true  $true 
    & $AddDino 'R-Procoptodon'                      'R-Procoptodon'                      'Procoptodon_Character_BP_Eden_C'              'Procoptodon'        @('ArkSE', 'ArkSA') @('Gen2')                                                                               'Gen2'           'R'             'Natural' $true  $true  $true 
    & $AddDino 'R-Quetzal'                          'R-Quetzal'                          'Quetz_Character_BP_Rockwell_C'                'Quetz'              @('ArkSE', 'ArkSA') @('Gen2')                                                                               'Gen2'           'R'             'Natural' $true  $true  $true 
    & $AddDino 'R-Snow Owl'                         'R-Snow Owl'                         'Owl_Character_BP_Eden_C'                      'Owl'                @('ArkSE', 'ArkSA') @('Gen2')                                                                               'Gen2'           'R'             'Natural' $true  $true  $true 
    & $AddDino 'R-Thylacoleo'                       'R-Thylacoleo'                       'Thylacoleo_Character_BP_Eden_C'               'Thylacoleo'         @('ArkSE', 'ArkSA') @('Gen2')                                                                               'Gen2'           'R'             'Natural' $true  $true  $true 
    & $AddDino 'Rubble Bear'                        'Rubble Bear'                        'Direbear_Character_BP_SteinbjornMinion_C'     'Direbear'           @('ArkSE', 'ArkSA') @('Fjordur')                                                                            'Fjordur'        'Standard'      'Natural' $true  $true  $true 
    & $AddDino 'Rubble Golem'                       'Rubble Golem'                       'RubbleGolem_Character_BP_C'                   'RubbleGolem'        @('ArkSE', 'ArkSA') @('ScorchedEarth_P', 'Ragnarok', 'Valguero_P', 'CrystalIsles', 'LostIsland', 'Fjordur') 'Scorched Earth' 'Standard'      'Natural' $true  $true  $true 
    & $AddDino 'R-Velonasaur'                       'R-Velonasaur'                       'Spindles_Character_BP_Rockwell_C'             'Spindles'           @('ArkSE', 'ArkSA') @('Gen2')                                                                               'Gen2'           'R'             'Natural' $true  $true  $true 
    & $AddDino 'Sabertooth'                         'Sabertooth'                         'Saber_Character_BP_C'                         'Saber'              @('ArkSE', 'ArkSA') $AllMaps                                                                                'Ark Prime'      'Standard'      'Natural' $true  $true  $true 
    & $AddDino 'Sabertooth Salmon'                  'Sabertooth Salmon'                  'Salmon_Character_BP_C'                        'Salmon'             @('ArkSE', 'ArkSA') $AllMaps                                                                                'Ark Prime'      'Standard'      'Natural' $true  $true  $true 
    & $AddDino 'Sarcosuchus'                        'Sarcosuchus'                        'Sarco_Character_BP_C'                         'Sarco'              @('ArkSE', 'ArkSA') $AllMaps                                                                                'Ark Prime'      'Standard'      'Natural' $true  $true  $true 
    & $AddDino 'Scout'                              'Scout'                              'Scout_Character_BP_C'                         'Scout'              @('ArkSE', 'ArkSA') @('Extinction', 'Genesis', 'Gen2', 'Fjordur')                                           'Extinction'     'Standard'      'Natural' $true  $true  $true 
    & $AddDino 'Seeker'                             'Seeker'                             'Pteroteuthis_Char_BP_C'                       'Pteroteuthis'       @('ArkSE', 'ArkSA') @('Aberration_P', 'Valguero_P', 'CrystalIsles', 'Gen2', 'Fjordur')                      'Aberration'     'Standard'      'Natural' $true  $true  $true 
    & $AddDino 'Seeker (Surface)'                   'Seeker (Surface)'                   'Pteroteuthis_Char_BP_Surface_C'               'Pteroteuthis'       @('ArkSE', 'ArkSA') @('Aberration_P', 'Valguero_P', 'CrystalIsles', 'Gen2', 'Fjordur')                      'Aberration'     'Surface'       'Natural' $true  $true  $true 
    & $AddDino 'Shadowmane'                         'Shadowmane'                         'LionfishLion_Character_BP_C'                  'LionfishLion'       @('ArkSE', 'ArkSA') @('Gen2')                                                                               'Gen2'           'Standard'      'Natural' $true  $true  $true 
    & $AddDino 'Shadowmane Female'                  'Shadowmane Female'                  'LionfishLion_Character_BP_Female_C'           'LionfishLion'       @('ArkSE', 'ArkSA') @('Gen2')                                                                               'Gen2'           'Female'        'Natural' $true  $true  $true 
    & $AddDino 'Shinehorn'                          'Shinehorn'                          'LanternGoat_Character_BP_C'                   'LanternGoat'        @('ArkSE', 'ArkSA') @('Aberration_P', 'Valguero_P', 'CrystalIsles', 'Gen2', 'Fjordur')                      'Aberration'     'Standard'      'Natural' $true  $true  $true 
    & $AddDino 'Sinomacrops'                        'Sinomacrops'                        'Sinomacrops_Character_BP_C'                   'Sinomacrops'        @('ArkSE', 'ArkSA') @('LostIsland')                                                                         'Lost Island'    'Standard'      'Natural' $true  $true  $true 
    & $AddDino 'Sinomacrops (Minion)'               'Sinomacrops (Minion)'               'Sinomacrops_Character_BP_Minion_C'            'Sinomacrops'        @('ArkSE', 'ArkSA') @('LostIsland')                                                                         'Lost Island'    'Minion'        'Boss'    $false $false $false
    & $AddDino 'Skeletal Alpha Rex'                 'Skeletal Alpha Rex'                 'Bone_MegaRex_Character_BP_C'                  'Bone_MegaRex'       @('ArkSE', 'ArkSA') $AllMaps                                                                                'Ark Prime'      'Skeletal'      'Event'   $true  $false $false
    & $AddDino 'Skeletal Bone Fire Wyvern'          'Skeletal Bone Fire Wyvern'          'Bone_MegaWyvern_Character_BP_Fire_C'          'Bone_MegaWyvern'    @('ArkSE', 'ArkSA') @('ScorchedEarth_P', 'Ragnarok', 'Valguero_P', 'CrystalIsles', 'LostIsland', 'Fjordur') 'Scorched Earth' 'Skeletal'      'Event'   $true  $false $false
    & $AddDino 'Skeletal Bronto'                    'Skeletal Bronto'                    'Bone_Sauropod_Character_BP_C'                 'Bone_Sauropod'      @('ArkSE', 'ArkSA') $AllMaps                                                                                'Ark Prime'      'Skeletal'      'Event'   $true  $false $false
    & $AddDino 'Skeletal Carnotaurus'               'Skeletal Carnotaurus'               'Bone_MegaCarno_Character_BP_C'                'Bone_MegaCarno'     @('ArkSE', 'ArkSA') $AllMaps                                                                                'Ark Prime'      'Skeletal'      'Event'   $true  $false $false
    & $AddDino 'Skeletal Giganotosaurus'            'Skeletal Giganotosaurus'            'Bone_Gigant_Character_BP_C'                   'Bone_Gigant'        @('ArkSE', 'ArkSA') $AllMaps                                                                                'Ark Prime'      'Skeletal'      'Event'   $true  $false $false
    & $AddDino 'Skeletal Jerboa'                    'Skeletal Jerboa'                    'Bone_Jerboa_Character_BP_C'                   'Bone_Jerboa'        @('ArkSE', 'ArkSA') @('ScorchedEarth_P', 'Ragnarok', 'Valguero_P', 'CrystalIsles', 'LostIsland', 'Fjordur') 'Scorched Earth' 'Skeletal'      'Event'   $true  $false $false
    & $AddDino 'Skeletal Quetzal'                   'Skeletal Quetzal'                   'Bone_Quetz_Character_BP_C'                    'Bone_Quetz'         @('ArkSE', 'ArkSA') $AllMaps                                                                                'Ark Prime'      'Skeletal'      'Event'   $true  $false $false
    & $AddDino 'Skeletal Raptor'                    'Skeletal Raptor'                    'Bone_MegaRaptor_Character_BP_C'               'Bone_MegaRaptor'    @('ArkSE', 'ArkSA') $AllMaps                                                                                'Ark Prime'      'Skeletal'      'Event'   $true  $false $false
    & $AddDino 'Skeletal Stego'                     'Skeletal Stego'                     'Bone_Stego_Character_BP_C'                    'Bone_Stego'         @('ArkSE', 'ArkSA') $AllMaps                                                                                'Ark Prime'      'Skeletal'      'Event'   $true  $false $false
    & $AddDino 'Skeletal Trike'                     'Skeletal Trike'                     'Bone_Trike_Character_BP_C'                    'Bone_Trike'         @('ArkSE', 'ArkSA') $AllMaps                                                                                'Ark Prime'      'Skeletal'      'Event'   $true  $false $false
    & $AddDino 'Sköll'                              'Sköll'                              'Fenrir_Character_BP_MiniBoss_Skoll_C'         'Fenrir'             @('ArkSE', 'ArkSA') @('Fjordur')                                                                            'Fjordur'        'Boss'          'Boss'    $false $false $false
    & $AddDino 'Snow Owl'                           'Snow Owl'                           'Owl_Character_BP_C'                           'Owl'                @('ArkSE', 'ArkSA') @('Extinction', 'Genesis', 'Gen2', 'Fjordur')                                           'Extinction'     'Standard'      'Natural' $true  $true  $true 
    & $AddDino 'Snow Owl Ghost'                     'Snow Owl Ghost'                     'Ghost_Owl_Character_BP_C'                     'Ghost_Owl'          @('ArkSE', 'ArkSA') @('Extinction', 'Genesis', 'Gen2', 'Fjordur')                                           'Extinction'     'Ghost'         'Event'   $true  $false $false
    & $AddDino 'Spinosaurus'                        'Spinosaurus'                        'Spino_Character_BP_C'                         'Spino'              @('ArkSE', 'ArkSA') $AllMaps                                                                                'Ark Prime'      'Standard'      'Natural' $true  $true  $true 
    & $AddDino 'Stegosaurus'                        'Stegosaurus'                        'Stego_Character_BP_C'                         'Stego'              @('ArkSE', 'ArkSA') $AllMaps                                                                                'Ark Prime'      'Standard'      'Natural' $true  $true  $true 
    & $AddDino 'Steinbjörn'                         'Steinbjörn'                         'Steinbjorn_Character_BP_C'                    'Steinbjorn'         @('ArkSE', 'ArkSA') @('Fjordur')                                                                            'Fjordur'        'Boss'          'Boss'    $false $false $false
    & $AddDino 'Stryder'                            'Stryder'                            'TekStrider_Character_BP_C'                    'TekStrider'         @('ArkSE', 'ArkSA') @('Gen2')                                                                               'Gen2'           'Standard'      'Natural' $true  $true  $true 
    & $AddDino 'Subterranean Reaper King'           'Subterranean Reaper King'           'Xenomorph_Character_BP_Male_Chupa_C'          'Xenomorph'          @('ArkSE', 'ArkSA') @('Aberration_P', 'Valguero_P', 'CrystalIsles', 'Gen2', 'Fjordur')                      'Aberration'     'Standard'      'Natural' $true  $true  $true 
    & $AddDino 'Summoned Aberrant Arthropluera'     'Summoned Aberrant Arthropluera'     'Arthro_Character_BP_Aberrant_Summoned_C'      'Arthro'             @('ArkSE', 'ArkSA') @('Gen2')                                                                               'Gen2'           'Aberrant'      'Natural' $true  $true  $true 
    & $AddDino 'Summoned Araneo'                    'Summoned Araneo'                    'SpiderS_Character_BP_Summoned_C'              'SpiderS'            @('ArkSE', 'ArkSA') @('Gen2')                                                                               'Gen2'           'Summoned'      'Boss'    $false $false $false
    & $AddDino 'Summoned Argentavis'                'Summoned Argentavis'                'Argent_Character_BP_Summoned_C'               'Argent'             @('ArkSE', 'ArkSA') @('Gen2')                                                                               'Gen2'           'Summoned'      'Boss'    $false $false $false
    & $AddDino 'Summoned Baryonyx'                  'Summoned Baryonyx'                  'Baryonyx_Character_BP_Summoned_C'             'Baryonyx'           @('ArkSE', 'ArkSA') @('Gen2')                                                                               'Gen2'           'Summoned'      'Boss'    $false $false $false
    & $AddDino 'Summoned Basilisk'                  'Summoned Basilisk'                  'Basilisk_Character_BP_Summoned_C'             'Basilisk'           @('ArkSE', 'ArkSA') @('Gen2')                                                                               'Gen2'           'Summoned'      'Boss'    $false $false $false
    & $AddDino 'Summoned Bloodstalker'              'Summoned Bloodstalker'              'BogSpider_Character_BP_Summoned_C'            'BogSpider'          @('ArkSE', 'ArkSA') @('Gen2')                                                                               'Gen2'           'Summoned'      'Boss'    $false $false $false
    & $AddDino 'Summoned Dire Bear'                 'Summoned Dire Bear'                 'Direbear_Character_BP_Summoned_C'             'Direbear'           @('ArkSE', 'ArkSA') @('Gen2')                                                                               'Gen2'           'Summoned'      'Boss'    $false $false $false
    & $AddDino 'Summoned Ferox'                     'Summoned Ferox'                     'Shapeshifter_Large_Character_BP_Summoned_C'   'Shapeshifter_Large' @('ArkSE', 'ArkSA') @('Gen2')                                                                               'Gen2'           'Summoned'      'Boss'    $false $false $false
    & $AddDino 'Summoned Kaprosuchus'               'Summoned Kaprosuchus'               'Kaprosuchus_Character_BP_Summoned_C'          'Kaprosuchus'        @('ArkSE', 'ArkSA') @('Gen2')                                                                               'Gen2'           'Summoned'      'Boss'    $false $false $false
    & $AddDino 'Summoned Karkinos'                  'Summoned Karkinos'                  'Crab_Character_BP_Summoned_C'                 'Crab'               @('ArkSE', 'ArkSA') @('Gen2')                                                                               'Gen2'           'Summoned'      'Boss'    $false $false $false
    & $AddDino 'Summoned Magmasaur'                 'Summoned Magmasaur'                 'Cherufe_Character_BP_Summoned_C'              'Cherufe'            @('ArkSE', 'ArkSA') @('Gen2')                                                                               'Gen2'           'Summoned'      'Boss'    $false $false $false
    & $AddDino 'Summoned Managarmr'                 'Summoned Managarmr'                 'IceJumper_Character_BP_Summoned_C'            'IceJumper'          @('ArkSE', 'ArkSA') @('Gen2')                                                                               'Gen2'           'Summoned'      'Boss'    $false $false $false
    & $AddDino 'Summoned Mantis'                    'Summoned Mantis'                    'Mantis_Character_BP_Summoned_C'               'Mantis'             @('ArkSE', 'ArkSA') @('Gen2')                                                                               'Gen2'           'Summoned'      'Boss'    $false $false $false
    & $AddDino 'Summoned Microraptor'               'Summoned Microraptor'               'Microraptor_Character_BP_Summoned_C'          'Microraptor'        @('ArkSE', 'ArkSA') @('Gen2')                                                                               'Gen2'           'Summoned'      'Boss'    $false $false $false
    & $AddDino 'Summoned Onyc'                      'Summoned Onyc'                      'Bat_Character_BP_Summoned_C'                  'Bat'                @('ArkSE', 'ArkSA') @('Gen2')                                                                               'Gen2'           'Summoned'      'Boss'    $false $false $false
    & $AddDino 'Summoned Paraceratherium'           'Summoned Paraceratherium'           'Paracer_Character_BP_Summoned_C'              'Paracer'            @('ArkSE', 'ArkSA') @('Gen2')                                                                               'Gen2'           'Summoned'      'Boss'    $false $false $false
    & $AddDino 'Summoned Pteranodon'                'Summoned Pteranodon'                'Ptero_Character_BP_Summoned_C'                'Ptero'              @('ArkSE', 'ArkSA') @('Gen2')                                                                               'Gen2'           'Summoned'      'Boss'    $false $false $false
    & $AddDino 'Summoned Purlovia'                  'Summoned Purlovia'                  'Purlovia_Character_BP_Summoned_C'             'Purlovia'           @('ArkSE', 'ArkSA') @('Gen2')                                                                               'Gen2'           'Summoned'      'Boss'    $false $false $false
    & $AddDino 'Summoned R-Allosaurus'              'Summoned R-Allosaurus'              'Allo_Character_BP_Rockwell_Summoned_C'        'Allo'               @('ArkSE', 'ArkSA') @('Gen2')                                                                               'Gen2'           'R'             'Natural' $true  $true  $true 
    & $AddDino 'Summoned Ravager'                   'Summoned Ravager'                   'CaveWolf_Character_BP_Summoned_C'             'CaveWolf'           @('ArkSE', 'ArkSA') @('Gen2')                                                                               'Gen2'           'Summoned'      'Boss'    $false $false $false
    & $AddDino 'Summoned R-Brontosaurus'            'Summoned R-Brontosaurus'            'Sauropod_Character_BP_Rockwell_Summoned_C'    'Sauropod'           @('ArkSE', 'ArkSA') @('Gen2')                                                                               'Gen2'           'R'             'Natural' $true  $true  $true 
    & $AddDino 'Summoned R-Carnotaurus'             'Summoned R-Carnotaurus'             'Carno_Character_BP_Rockwell_Summoned_C'       'Carno'              @('ArkSE', 'ArkSA') @('Gen2')                                                                               'Gen2'           'R'             'Natural' $true  $true  $true 
    & $AddDino 'Summoned R-Daeodon'                 'Summoned R-Daeodon'                 'Daeodon_Character_BP_Eden_Summoned_C'         'Daeodon'            @('ArkSE', 'ArkSA') @('Gen2')                                                                               'Gen2'           'R'             'Natural' $true  $true  $true 
    & $AddDino 'Summoned R-Dilophosaur'             'Summoned R-Dilophosaur'             'Dilo_Character_BP_Rockwell_Summoned_C'        'Dilo'               @('ArkSE', 'ArkSA') @('Gen2')                                                                               'Gen2'           'R'             'Natural' $true  $true  $true 
    & $AddDino 'Summoned R-Dire Bear'               'Summoned R-Dire Bear'               'Direbear_Character_BP_Rockwell_Summoned_C'    'Direbear'           @('ArkSE', 'ArkSA') @('Gen2')                                                                               'Gen2'           'R'             'Natural' $true  $true  $true 
    & $AddDino 'Summoned R-Direwolf'                'Summoned R-Direwolf'                'Direwolf_Character_BP_Eden_Summoned_C'        'Direwolf'           @('ArkSE', 'ArkSA') @('Gen2')                                                                               'Gen2'           'R'             'Natural' $true  $true  $true 
    & $AddDino 'Summoned Rex'                       'Summoned Rex'                       'Rex_Character_BP_Summoned_C'                  'Rex'                @('ArkSE', 'ArkSA') @('Gen2')                                                                               'Gen2'           'Summoned'      'Boss'    $false $false $false
    & $AddDino 'Summoned R-Megatherium'             'Summoned R-Megatherium'             'Megatherium_Character_BP_Eden_Summoned_C'     'Megatherium'        @('ArkSE', 'ArkSA') @('Gen2')                                                                               'Gen2'           'R'             'Natural' $true  $true  $true 
    & $AddDino 'Summoned Rock Drake'                'Summoned Rock Drake'                'RockDrake_Character_BP_Summoned_C'            'RockDrake'          @('ArkSE', 'ArkSA') @('Gen2')                                                                               'Gen2'           'Summoned'      'Boss'    $false $false $false
    & $AddDino 'Summoned Rock Elemental'            'Summoned Rock Elemental'            'RockGolem_Character_BP_Summoned_C'            'RockGolem'          @('ArkSE', 'ArkSA') @('Gen2')                                                                               'Gen2'           'Summoned'      'Boss'    $false $false $false
    & $AddDino 'Summoned R-Quetzal'                 'Summoned R-Quetzal'                 'Quetz_Character_BP_Rockwell_Summoned_C'       'Quetz'              @('ArkSE', 'ArkSA') @('Gen2')                                                                               'Gen2'           'R'             'Natural' $true  $true  $true 
    & $AddDino 'Summoned R-Reaper King'             'Summoned R-Reaper King'             'Xenomorph_Character_BP_Male_Gen2_Summoned_C'  'Xenomorph'          @('ArkSE', 'ArkSA') @('Gen2')                                                                               'Gen2'           'Summoned'      'Boss'    $false $false $false
    & $AddDino 'Summoned R-Snow Owl'                'Summoned R-Snow Owl'                'Owl_Character_BP_Eden_Summoned_C'             'Owl'                @('ArkSE', 'ArkSA') @('Gen2')                                                                               'Gen2'           'R'             'Natural' $true  $true  $true 
    & $AddDino 'Summoned R-Thylacoleo'              'Summoned R-Thylacoleo'              'Thylacoleo_Character_BP_Eden_Summoned_C'      'Thylacoleo'         @('ArkSE', 'ArkSA') @('Gen2')                                                                               'Gen2'           'R'             'Natural' $true  $true  $true 
    & $AddDino 'Summoned R-Velonasaur'              'Summoned R-Velonasaur'              'Spindles_Character_BP_Rockwell_Summoned_C'    'Spindles'           @('ArkSE', 'ArkSA') @('Gen2')                                                                               'Gen2'           'R'             'Natural' $true  $true  $true 
    & $AddDino 'Summoned Sabertooth'                'Summoned Sabertooth'                'Saber_Character_BP_Summoned_C'                'Saber'              @('ArkSE', 'ArkSA') @('Gen2')                                                                               'Gen2'           'Summoned'      'Boss'    $false $false $false
    & $AddDino 'Summoned Sarco'                     'Summoned Sarco'                     'Sarco_Character_BP_Summoned_C'                'Sarco'              @('ArkSE', 'ArkSA') @('Gen2')                                                                               'Gen2'           'Summoned'      'Boss'    $false $false $false
    & $AddDino 'Summoned Shadowmane'                'Summoned Shadowmane'                'LionfishLion_Character_BP_Summoned_C'         'LionfishLion'       @('ArkSE', 'ArkSA') @('Gen2')                                                                               'Gen2'           'Summoned'      'Boss'    $false $false $false
    & $AddDino 'Summoned Spino'                     'Summoned Spino'                     'Spino_Character_BP_Summoned_C'                'Spino'              @('ArkSE', 'ArkSA') @('Gen2')                                                                               'Gen2'           'Summoned'      'Boss'    $false $false $false
    & $AddDino 'Summoned Stegosaurus'               'Summoned Stegosaurus'               'Stego_Character_BP_Summoned_C'                'Stego'              @('ArkSE', 'ArkSA') @('Gen2')                                                                               'Gen2'           'Summoned'      'Boss'    $false $false $false
    & $AddDino 'Summoned Terror Bird'               'Summoned Terror Bird'               'TerrorBird_Character_BP_Summoned_C'           'TerrorBird'         @('ArkSE', 'ArkSA') @('Gen2')                                                                               'Gen2'           'Summoned'      'Boss'    $false $false $false
    & $AddDino 'Summoned Therizinosaur'             'Summoned Therizinosaur'             'Therizino_Character_BP_Summoned_C'            'Therizino'          @('ArkSE', 'ArkSA') @('Gen2')                                                                               'Gen2'           'Summoned'      'Boss'    $false $false $false
    & $AddDino 'Summoned Thorny Dragon'             'Summoned Thorny Dragon'             'SpineyLizard_Character_BP_Summoned_C'         'SpineyLizard'       @('ArkSE', 'ArkSA') @('Gen2')                                                                               'Gen2'           'Summoned'      'Boss'    $false $false $false
    & $AddDino 'Summoned Titanoboa'                 'Summoned Titanoboa'                 'BoaFrill_Character_BP_Summoned_C'             'BoaFrill'           @('ArkSE', 'ArkSA') @('Gen2')                                                                               'Gen2'           'Summoned'      'Boss'    $false $false $false
    & $AddDino 'Summoned Triceratops'               'Summoned Triceratops'               'Trike_Character_BP_Summoned_C'                'Trike'              @('ArkSE', 'ArkSA') @('Gen2')                                                                               'Gen2'           'Summoned'      'Boss'    $false $false $false
    & $AddDino 'Summoned Yutyrannus'                'Summoned Yutyrannus'                'Yutyrannus_Character_BP_Summoned_C'           'Yutyrannus'         @('ArkSE', 'ArkSA') @('Gen2')                                                                               'Gen2'           'Summoned'      'Boss'    $false $false $false
    & $AddDino 'Summoner'                           'Summoner'                           'Summoner_Character_BP_C'                      'Summoner'           @('ArkSE', 'ArkSA') @('Gen2')                                                                               'Gen2'           'Standard'      'Natural' $true  $true  $true 
    & $AddDino 'Summoner (Alpha)'                   'Summoner (Alpha)'                   'Summoner_Character_BP_FinalFight_Alpha_C'     'Summoner'           @('ArkSE', 'ArkSA') @('Gen2')                                                                               'Gen2'           'Standard'      'Natural' $true  $true  $true 
    & $AddDino 'Summoner (Beta)'                    'Summoner (Beta)'                    'Summoner_Character_BP_FinalFight_Beta_C'      'Summoner'           @('ArkSE', 'ArkSA') @('Gen2')                                                                               'Gen2'           'Standard'      'Natural' $true  $true  $true 
    & $AddDino 'Summoner (Gamma)'                   'Summoner (Gamma)'                   'Summoner_Character_BP_FinalFight_Gamma_C'     'Summoner'           @('ArkSE', 'ArkSA') @('Gen2')                                                                               'Gen2'           'Standard'      'Natural' $true  $true  $true 
    & $AddDino 'Super Turkey'                       'Super Turkey'                       'Turkey_Character_BP_C'                        'Turkey'             @('ArkSE', 'ArkSA') $AllMaps                                                                                'Ark Prime'      'Standard'      'Natural' $true  $true  $true 
    & $AddDino 'Surface Reaper King'                'Surface Reaper King'                'Xenomorph_Character_BP_Male_Surface_C'        'Xenomorph'          @('ArkSE', 'ArkSA') @('Aberration_P', 'Valguero_P', 'CrystalIsles', 'Gen2', 'Fjordur')                      'Aberration'     'Standard'      'Natural' $true  $true  $true 
    & $AddDino 'Surface Reaper King Ghost'          'Surface Reaper King Ghost'          'Ghost_Xenomorph_Character_BP_Male_Surface_C'  'Ghost_Xenomorph'    @('ArkSE', 'ArkSA') @('Aberration_P', 'Valguero_P', 'CrystalIsles', 'Gen2', 'Fjordur')                      'Aberration'     'Ghost'         'Event'   $true  $false $false
    & $AddDino 'Tamed R-Reaper King'                'Tamed R-Reaper King'                'Xenomorph_Character_BP_Male_Tamed_Gen2_C'     'Xenomorph'          @('ArkSE', 'ArkSA') @('Gen2')                                                                               'Gen2'           'Standard'      'Natural' $true  $true  $true 
    & $AddDino 'Tapejara'                           'Tapejara'                           'Tapejara_Character_BP_C'                      'Tapejara'           @('ArkSE', 'ArkSA') $AllMaps                                                                                'Ark Prime'      'Standard'      'Natural' $true  $true  $true 
    & $AddDino 'Terror Bird'                        'Terror Bird'                        'TerrorBird_Character_BP_C'                    'TerrorBird'         @('ArkSE', 'ArkSA') $AllMaps                                                                                'Ark Prime'      'Standard'      'Natural' $true  $true  $true 
    & $AddDino 'Therizinosaurus'                    'Therizinosaurus'                    'Therizino_Character_BP_C'                     'Therizino'          @('ArkSE', 'ArkSA') $AllMaps                                                                                'Ark Prime'      'Standard'      'Natural' $true  $true  $true 
    & $AddDino 'Thorny Dragon'                      'Thorny Dragon'                      'SpineyLizard_Character_BP_C'                  'SpineyLizard'       @('ArkSE', 'ArkSA') @('ScorchedEarth_P', 'Ragnarok', 'Valguero_P', 'CrystalIsles', 'LostIsland', 'Fjordur') 'Scorched Earth' 'Standard'      'Natural' $true  $true  $true 
    & $AddDino 'Thylacoleo'                         'Thylacoleo'                         'Thylacoleo_Character_BP_C'                    'Thylacoleo'         @('ArkSE', 'ArkSA') $AllMaps                                                                                'Ark Prime'      'Standard'      'Natural' $true  $true  $true 
    & $AddDino 'Titanoboa'                          'Titanoboa'                          'BoaFrill_Character_BP_C'                      'BoaFrill'           @('ArkSE', 'ArkSA') $AllMaps                                                                                'Ark Prime'      'Titan'         'Boss'    $true  $true  $false
    & $AddDino 'Titanomyrma Drone'                  'Titanomyrma Drone'                  'Ant_Character_BP_C'                           'Ant'                @('ArkSE', 'ArkSA') $AllMaps                                                                                'Ark Prime'      'Titan'         'Boss'    $true  $true  $false
    & $AddDino 'Titanomyrma Soldier'                'Titanomyrma Soldier'                'FlyingAnt_Character_BP_C'                     'FlyingAnt'          @('ArkSE', 'ArkSA') $AllMaps                                                                                'Ark Prime'      'Titan'         'Boss'    $true  $true  $false
    & $AddDino 'Titanosaur'                         'Titanosaur'                         'Titanosaur_Character_BP_C'                    'Titanosaur'         @('ArkSE', 'ArkSA') $AllMaps                                                                                'Ark Prime'      'Titan'         'Boss'    $true  $true  $false
    & $AddDino 'Triceratops'                        'Triceratops'                        'Trike_Character_BP_C'                         'Trike'              @('ArkSE', 'ArkSA') $AllMaps                                                                                'Ark Prime'      'Standard'      'Natural' $true  $true  $true 
    & $AddDino 'Trilobite'                          'Trilobite'                          'Trilobite_Character_C'                        'Trilobite'          @('ArkSE', 'ArkSA') $AllMaps                                                                                'Ark Prime'      'Standard'      'Natural' $true  $false $false
    & $AddDino 'Troodon'                            'Troodon'                            'Troodon_Character_BP_C'                       'Troodon'            @('ArkSE', 'ArkSA') $AllMaps                                                                                'Ark Prime'      'Standard'      'Natural' $true  $true  $true 
    & $AddDino 'Tropeognathus'                      'Tropeognathus'                      'Tropeognathus_Character_BP_C'                 'Tropeognathus'      @('ArkSE', 'ArkSA') $AllMaps                                                                                'Ark Prime'      'Standard'      'Natural' $true  $true  $true 
    & $AddDino 'Tropical Crystal Wyvern'            'Tropical Crystal Wyvern'            'CrystalWyvern_Character_BP_WS_C'              'CrystalWyvern'      @('ArkSE', 'ArkSA') @('CrystalIsles')                                                                       'Crystal Isles'  'Standard'      'Natural' $true  $true  $false
    & $AddDino 'Tropical Crystal Wyvern Heir'       'Tropical Crystal Wyvern Heir'       'CrystalWyvern_Character_BP_Minion_WS_C'       'CrystalWyvern'      @('ArkSE', 'ArkSA') @('CrystalIsles')                                                                       'Crystal Isles'  'Heir'          'Boss'    $false $false $false
    & $AddDino 'Tusoteuthis'                        'Tusoteuthis'                        'Tusoteuthis_Character_BP_C'                   'Tusoteuthis'        @('ArkSE', 'ArkSA') $AllMaps                                                                                'Ark Prime'      'Standard'      'Natural' $true  $true  $true 
    & $AddDino 'Tusoteuthis (Cave)'                 'Tusoteuthis (Cave)'                 'Tusoteuthis_Character_BP_Caves_C'             'Tusoteuthis'        @('ArkSE', 'ArkSA') $AllMaps                                                                                'Ark Prime'      'Standard'      'Natural' $true  $true  $true 
    & $AddDino 'Unicorn'                            'Unicorn'                            'Equus_Character_BP_Unicorn_C'                 'Equus'              @('ArkSE', 'ArkSA') $AllMaps                                                                                'Ark Prime'      'Standard'      'Natural' $true  $true  $true 
    & $AddDino 'Valentine''s Aberrant Coelacanth'   'Valentine''s Aberrant Coelacanth'   'Coel_Character_BP_VDay_Aberrant_C'            'Coel'               @('ArkSE', 'ArkSA') $AllMaps                                                                                'Ark Prime'      'Event'         'Event'   $true  $false $false
    & $AddDino 'Valentine''s Coelacanth'            'Valentine''s Coelacanth'            'Coel_Character_BP_VDay_C'                     'Coel'               @('ArkSE', 'ArkSA') $AllMaps                                                                                'Ark Prime'      'Event'         'Event'   $true  $false $false
    & $AddDino 'Valentine''s Coelacanth (Deep Sea)' 'Valentine''s Coelacanth (Deep Sea)' 'Coel_Character_BP_VDay_Ocean_C'               'Coel'               @('ArkSE', 'ArkSA') $AllMaps                                                                                'Ark Prime'      'Event'         'Event'   $true  $false $false
    & $AddDino 'Velonasaur'                         'Velonasaur'                         'Spindles_Character_BP_C'                      'Spindles'           @('ArkSE', 'ArkSA') @('Extinction', 'Genesis', 'Gen2', 'Fjordur')                                           'Extinction'     'Standard'      'Natural' $true  $true  $true 
    & $AddDino 'Voidwyrm'                           'Voidwyrm'                           'TekWyvern_Character_BP_C'                     'TekWyvern'          @('ArkSE', 'ArkSA') @('Gen2')                                                                               'Gen2'           'Standard'      'Natural' $true  $true  $true 
    & $AddDino 'Vulture'                            'Vulture'                            'Vulture_Character_BP_C'                       'Vulture'            @('ArkSE', 'ArkSA') @('ScorchedEarth_P', 'Ragnarok', 'Valguero_P', 'CrystalIsles', 'LostIsland', 'Fjordur') 'Scorched Earth' 'Standard'      'Natural' $true  $true  $true 
    & $AddDino 'Water Jug Bug'                      'Water Jug Bug'                      'Jugbug_Water_Character_BP_C'                  'Jugbug_Water'       @('ArkSE', 'ArkSA') @('ScorchedEarth_P', 'Ragnarok', 'Valguero_P', 'CrystalIsles', 'LostIsland', 'Fjordur') 'Scorched Earth' 'Standard'      'Natural' $true  $true  $true 
    & $AddDino 'Woolly Rhino'                       'Woolly Rhino'                       'Rhino_Character_BP_C'                         'Rhino'              @('ArkSE', 'ArkSA') $AllMaps                                                                                'Ark Prime'      'Standard'      'Natural' $true  $true  $true 
    & $AddDino 'X-Allosaurus'                       'X-Allosaurus'                       'Volcano_Allo_Character_BP_C'                  'Volcano_Allo'       @('ArkSE', 'ArkSA') @('Genesis', 'CrystalIsles', 'LostIsland')                                              'Genesis'        'X'             'Natural' $true  $true  $true 
    & $AddDino 'X-Ankylosaurus'                     'X-Ankylosaurus'                     'Volcano_Ankylo_Character_BP_C'                'Volcano_Ankylo'     @('ArkSE', 'ArkSA') @('Genesis', 'CrystalIsles', 'LostIsland')                                              'Genesis'        'X'             'Natural' $true  $true  $true 
    & $AddDino 'X-Argentavis'                       'X-Argentavis'                       'Snow_Argent_Character_BP_C'                   'Snow_Argent'        @('ArkSE', 'ArkSA') @('Genesis', 'CrystalIsles', 'LostIsland')                                              'Genesis'        'X'             'Natural' $true  $true  $true 
    & $AddDino 'X-Basilosaurus'                     'X-Basilosaurus'                     'Ocean_Basilosaurus_Character_BP_C'            'Ocean_Basilosaurus' @('ArkSE', 'ArkSA') @('Genesis', 'CrystalIsles', 'LostIsland')                                              'Genesis'        'X'             'Natural' $true  $true  $true 
    & $AddDino 'X-Dragon'                           'X-Dragon'                           'Volcanic_Dragon_Character_BP_C'               'Volcanic_Dragon'    @('ArkSE', 'ArkSA') @('Genesis', 'CrystalIsles', 'LostIsland')                                              'Genesis'        'X'             'Natural' $true  $true  $true 
    & $AddDino 'X-Dunkleosteus'                     'X-Dunkleosteus'                     'Ocean_Dunkle_Character_BP_C'                  'Ocean_Dunkle'       @('ArkSE', 'ArkSA') @('Genesis', 'CrystalIsles', 'LostIsland')                                              'Genesis'        'X'             'Natural' $true  $true  $true 
    & $AddDino 'X-Ichthyosaurus'                    'X-Ichthyosaurus'                    'Ocean_Dolphin_Character_BP_C'                 'Ocean_Dolphin'      @('ArkSE', 'ArkSA') @('Genesis', 'CrystalIsles', 'LostIsland')                                              'Genesis'        'X'             'Natural' $true  $true  $true 
    & $AddDino 'X-Megalodon'                        'X-Megalodon'                        'Ocean_Megalodon_Character_BP_C'               'Ocean_Megalodon'    @('ArkSE', 'ArkSA') @('Genesis', 'CrystalIsles', 'LostIsland')                                              'Genesis'        'X'             'Natural' $true  $true  $true 
    & $AddDino 'X-Mosasaurus'                       'X-Mosasaurus'                       'Ocean_Mosa_Character_BP_C'                    'Ocean_Mosa'         @('ArkSE', 'ArkSA') @('Genesis', 'CrystalIsles', 'LostIsland')                                              'Genesis'        'X'             'Natural' $true  $true  $true 
    & $AddDino 'X-Otter'                            'X-Otter'                            'Snow_Otter_Character_BP_C'                    'Snow_Otter'         @('ArkSE', 'ArkSA') @('Genesis', 'CrystalIsles', 'LostIsland')                                              'Genesis'        'X'             'Natural' $true  $true  $true 
    & $AddDino 'X-Paraceratherium'                  'X-Paraceratherium'                  'Bog_Paracer_Character_BP_C'                   'Bog_Paracer'        @('ArkSE', 'ArkSA') @('Genesis', 'CrystalIsles', 'LostIsland')                                              'Genesis'        'X'             'Natural' $true  $true  $true 
    & $AddDino 'X-Parasaur'                         'X-Parasaur'                         'Bog_Para_Character_BP_C'                      'Bog_Para'           @('ArkSE', 'ArkSA') @('Genesis', 'CrystalIsles', 'LostIsland')                                              'Genesis'        'X'             'Natural' $true  $true  $true 
    & $AddDino 'X-Raptor'                           'X-Raptor'                           'Bog_Raptor_Character_BP_C'                    'Bog_Raptor'         @('ArkSE', 'ArkSA') @('Genesis', 'CrystalIsles', 'LostIsland')                                              'Genesis'        'X'             'Natural' $true  $true  $true 
    & $AddDino 'X-Rex'                              'X-Rex'                              'Volcano_Rex_Character_BP_C'                   'Volcano_Rex'        @('ArkSE', 'ArkSA') @('Genesis', 'CrystalIsles', 'LostIsland')                                              'Genesis'        'X'             'Natural' $true  $true  $true 
    & $AddDino 'X-Rock Elemental'                   'X-Rock Elemental'                   'Volcano_Golem_Character_BP_C'                 'RockGolem'          @('ArkSE', 'ArkSA') @('Genesis', 'CrystalIsles', 'LostIsland')                                              'Genesis'        'X'             'Natural' $true  $true  $true 
    & $AddDino 'X-Sabertooth'                       'X-Sabertooth'                       'Snow_Saber_Character_BP_C'                    'Snow_Saber'         @('ArkSE', 'ArkSA') @('Genesis', 'CrystalIsles', 'LostIsland')                                              'Genesis'        'X'             'Natural' $true  $true  $true 
    & $AddDino 'X-Sabertooth Salmon'                'X-Sabertooth Salmon'                'Lunar_Salmon_Character_BP_C'                  'Salmon'             @('ArkSE', 'ArkSA') @('Genesis', 'CrystalIsles', 'LostIsland')                                              'Genesis'        'X'             'Natural' $true  $true  $true 
    & $AddDino 'X-Sabertooth Salmon (Rare)'         'X-Sabertooth Salmon (Rare)'         'Rare_Lunar_Salmon_Character_BP_C'             'Salmon'             @('ArkSE', 'ArkSA') @('Genesis', 'CrystalIsles', 'LostIsland')                                              'Genesis'        'X'             'Natural' $true  $true  $true 
    & $AddDino 'X-Spino'                            'X-Spino'                            'Bog_Spino_Character_BP_C'                     'Bog_Spino'          @('ArkSE', 'ArkSA') @('Genesis', 'CrystalIsles', 'LostIsland')                                              'Genesis'        'X'             'Natural' $true  $true  $true 

    $result = $catalog.ToArray()

    if (-not [string]::IsNullOrWhiteSpace($GameId)) {
        $result = $result | Where-Object { $_.Games -contains $GameId }
    }

    if (-not [string]::IsNullOrWhiteSpace($MapName)) {
        $result = $result | Where-Object { ($_.Maps -contains '*') -or ($_.Maps -contains $MapName) }
    }

    return $result
}

function Get-UGSMArkDinosForGame {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$GameId
    )

    Get-UGSMArkDinoCatalog -GameId $GameId
}

function Get-UGSMArkDinosForGameAndMap {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$GameId,
        [Parameter(Mandatory)]
        [string]$MapName
    )

    Get-UGSMArkDinoCatalog -GameId $GameId -MapName $MapName
}
