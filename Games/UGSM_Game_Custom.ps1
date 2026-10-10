# UGSM Custom / Unsupported Game Module
#
# Purpose
# -------
# This module is a generic fallback for games that are not fully supported yet.
# It is intentionally manual-first:
# - the user can supply a Steam app id or custom install path
# - the user can point UGSM at the dedicated server executable
# - startup arguments are stored per instance/profile
# - a generic Mods tab stores workshop ids / custom mod arguments
#
# This is not intended to replace full game modules. It is a bridge so a game can
# still be launched and managed inside UGSM before dedicated support exists.

function Get-UGSMGameCUSTOMAppDataRoot {
    [CmdletBinding()]
    param()

    if (Get-Command -Name Get-UGSMAppDataRoot -ErrorAction SilentlyContinue) {
        try { return [string](Get-UGSMAppDataRoot) } catch {}
    }

    return (Join-Path $env:LOCALAPPDATA 'UGSM')
}

function Get-UGSMGameCUSTOMProfileBaseRoot {
    [CmdletBinding()]
    param()

    $settings = $null
    if (Get-Command -Name Get-UGSMGlobalSettings -ErrorAction SilentlyContinue) {
        try { $settings = Get-UGSMGlobalSettings -CreateIfMissing } catch { $settings = $null }
    }

    if ($settings -and $settings.PSObject.Properties['ProfileBaseRoot'] -and -not [string]::IsNullOrWhiteSpace([string]$settings.ProfileBaseRoot)) {
        return [string]$settings.ProfileBaseRoot
    }

    if (Get-Command -Name Get-UGSMDefaultInstanceProfilePath -ErrorAction SilentlyContinue) {
        try {
            $probe = Get-UGSMDefaultInstanceProfilePath -GameId 'CUSTOM' -Name '_probe_'
            if (-not [string]::IsNullOrWhiteSpace([string]$probe)) {
                return (Split-Path -Parent (Split-Path -Parent $probe))
            }
        }
        catch {}
    }

    return (Join-Path (Get-UGSMGameCUSTOMAppDataRoot) 'Profiles')
}

function ConvertTo-UGSMGameCUSTOMSafeKey {
    [CmdletBinding()]
    param([AllowNull()][string]$Value, [string]$DefaultValue = 'CUSTOM')

    $safe = ([string]$Value -replace '[^A-Za-z0-9_.-]', '').Trim()
    if ([string]::IsNullOrWhiteSpace($safe)) { $safe = $DefaultValue }
    return $safe
}

function Get-UGSMGameCUSTOMTargetGameKey {
    [CmdletBinding()]
    param([AllowNull()][object]$Instance, [string]$DefaultValue = 'CUSTOM')

    if ($Instance -and $Instance.PSObject.Properties['TargetGameKey'] -and -not [string]::IsNullOrWhiteSpace([string]$Instance.TargetGameKey)) {
        return (ConvertTo-UGSMGameCUSTOMSafeKey -Value ([string]$Instance.TargetGameKey) -DefaultValue $DefaultValue)
    }

    # Older Custom profiles did not have a target key, so keep them under CUSTOM until the user chooses one.
    return (ConvertTo-UGSMGameCUSTOMSafeKey -Value $DefaultValue -DefaultValue 'CUSTOM')
}

function Get-UGSMGameCUSTOMProfileRoot {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$ProfileName,
        [string]$TargetGameKey = 'CUSTOM'
    )

    $safeName = ($ProfileName -replace '[\/:*?"<>|]', '_').Trim()
    if ([string]::IsNullOrWhiteSpace($safeName)) { $safeName = 'CustomServer' }
    $safeKey = ConvertTo-UGSMGameCUSTOMSafeKey -Value $TargetGameKey -DefaultValue 'CUSTOM'
    return (Join-Path (Join-Path (Get-UGSMGameCUSTOMProfileBaseRoot) $safeKey) $safeName)
}

function Get-UGSMGameCUSTOMManifestPath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$Instance
    )

    $profileRoot = Get-UGSMGameCUSTOMResolvedProfileRoot -Instance $Instance
    return (Join-Path $profileRoot 'custom.instance.json')
}

function Get-UGSMGameCUSTOMRuntimeStatePath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$Instance
    )

    $profileRoot = Get-UGSMGameCUSTOMResolvedProfileRoot -Instance $Instance
    return (Join-Path $profileRoot 'custom.runtime.json')
}

function Get-UGSMGameCUSTOMResolvedProfileRoot {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$Instance
    )

    if ($Instance.PSObject.Properties['ProfilePath'] -and -not [string]::IsNullOrWhiteSpace([string]$Instance.ProfilePath)) {
        return [string]$Instance.ProfilePath
    }

    $name = ''
    if ($Instance.PSObject.Properties['Name']) {
        $name = [string]$Instance.Name
    }
    if ([string]::IsNullOrWhiteSpace($name)) {
        $name = 'CustomServer'
    }

    $targetKey = Get-UGSMGameCUSTOMTargetGameKey -Instance $Instance
    return (Get-UGSMGameCUSTOMProfileRoot -ProfileName $name -TargetGameKey $targetKey)
}


function Get-UGSMGameCUSTOMCandidateProfileRoots {
    [CmdletBinding()]
    param(
        [AllowNull()][object]$Instance,
        [AllowNull()][string]$ProfileName,
        [AllowNull()][string]$TargetGameKey,
        [AllowNull()][string]$ExplicitProfilePath
    )

    $roots = New-Object System.Collections.Generic.List[string]
    $seen = @{}

    function Add-CustomCandidateRoot {
        param([AllowNull()][string]$PathValue)
        if ([string]::IsNullOrWhiteSpace($PathValue)) { return }
        try { $resolved = [System.IO.Path]::GetFullPath([string]$PathValue) } catch { $resolved = [string]$PathValue }
        $key = $resolved.ToLowerInvariant()
        if (-not $seen.ContainsKey($key)) {
            $seen[$key] = $true
            [void]$roots.Add($resolved)
        }
    }

    $safeName = [string]$ProfileName
    if ([string]::IsNullOrWhiteSpace($safeName) -and $Instance -and $Instance.PSObject.Properties['Name']) {
        $safeName = [string]$Instance.Name
    }
    if ([string]::IsNullOrWhiteSpace($safeName)) { $safeName = 'CustomServer' }

    $safeTarget = ConvertTo-UGSMGameCUSTOMSafeKey -Value $TargetGameKey -DefaultValue 'CUSTOM'
    if ($Instance -and $Instance.PSObject.Properties['TargetGameKey'] -and -not [string]::IsNullOrWhiteSpace([string]$Instance.TargetGameKey)) {
        $safeTarget = ConvertTo-UGSMGameCUSTOMSafeKey -Value ([string]$Instance.TargetGameKey) -DefaultValue $safeTarget
    }

    # Prefer the future/native game folder first.
    Add-CustomCandidateRoot (Get-UGSMGameCUSTOMProfileRoot -ProfileName $safeName -TargetGameKey $safeTarget)
    Add-CustomCandidateRoot $ExplicitProfilePath

    if ($Instance) {
        if ($Instance.PSObject.Properties['ProfilePath']) {
            Add-CustomCandidateRoot ([string]$Instance.ProfilePath)
        }
        if ($Instance.PSObject.Properties['Name'] -and -not [string]::IsNullOrWhiteSpace([string]$Instance.Name)) {
            Add-CustomCandidateRoot (Get-UGSMGameCUSTOMProfileRoot -ProfileName ([string]$Instance.Name) -TargetGameKey $safeTarget)
            Add-CustomCandidateRoot (Get-UGSMGameCUSTOMProfileRoot -ProfileName ([string]$Instance.Name) -TargetGameKey 'CUSTOM')
        }
        if ($Instance.PSObject.Properties['InstanceId'] -and -not [string]::IsNullOrWhiteSpace([string]$Instance.InstanceId)) {
            Add-CustomCandidateRoot (Get-UGSMGameCUSTOMProfileRoot -ProfileName ([string]$Instance.InstanceId) -TargetGameKey $safeTarget)
            Add-CustomCandidateRoot (Get-UGSMGameCUSTOMProfileRoot -ProfileName ([string]$Instance.InstanceId) -TargetGameKey 'CUSTOM')
        }
    }

    # Keep a mirror under CUSTOM so the existing Custom instance can reload the edited bridge values
    # until the global instance cache learns the native target path.
    Add-CustomCandidateRoot (Get-UGSMGameCUSTOMProfileRoot -ProfileName $safeName -TargetGameKey 'CUSTOM')

    return @($roots)
}

function Get-UGSMGameCUSTOMMetadata {
    [CmdletBinding()]
    param()

    return [pscustomobject]@{
        Id                       = 'CUSTOM'
        Name                     = 'Custom Game'
        Category                 = 'Custom'
        Description              = 'Generic fallback for unsupported or partially supported dedicated servers. User supplies install details, mod info, and launch arguments.'
        IsCustom                 = $true
        SupportTier              = 'Custom'
        SortOrder                = 9000
        IsVisible                = $true

        SupportedTabs            = @('Home', 'Games', 'Instances', 'Analytics', 'Tasks', 'About', 'Settings')
        UseSteamArt              = $false

        SupportsInstall          = $false
        SupportsUpdate           = $false
        SupportsVerify           = $false
        SupportsRepair           = $false
        SupportsStart            = $true
        SupportsStop             = $true
        SupportsMods             = $true
        SupportsWorkshop         = $true
        SupportsRcon             = $false
        SupportsBootstrap        = $false
        SupportsProfiles         = $true
        SupportsInstanceUi       = $true

        InstallProvider          = 'Manual'
        RequiresSteamLogin       = $false
        SteamLoginMode           = 'Anonymous'
        SteamAppId               = ''
        SteamStoreAppId          = ''
        ServerExecutable         = ''
        ServerExecutableRelative = ''
        UsesSharedBinaries       = $true
        InstanceType             = 'DedicatedServer'

        ConfigRootRelative       = 'Config'
        SaveRootRelative         = 'Saved'
        LogRootRelative          = 'Logs'

        RequiredFiles            = @()
        InstallMarkers           = @()
        PortSchema               = @(
            @{ Name = 'GamePort'; Protocol = 'UDP'; PreferredStart = 27015 }
            @{ Name = 'QueryPort'; Protocol = 'UDP'; PreferredStart = 27016 }
        )

        GameTraits               = [pscustomobject]@{
            UsesIniFiles          = $true
            UsesJsonFiles         = $true
            UsesXmlFiles          = $true
            UsesSqlite            = $false
            UsesProfileSync       = $false
            UsesPluginFramework   = $false
            UsesZipMods           = $true
            UsesFolderCopyMods    = $true
            UsesFileMergeWorkflow = $false
            UsesMissionFiles      = $false
            UsesWorkshopItems     = $true
        }

        SpecialRequirements      = [pscustomobject]@{
            Notes = @(
                'Custom Game is a fallback module, not a full integration.',
                'Set Steam App ID if the game can be downloaded with SteamCMD.',
                'Set either a full executable path or Install Path + relative executable path.',
                'Startup and mod fields are saved per instance profile.',
                'This module is intended to get unsupported servers running inside UGSM quickly.',
                'Use Target Game Key to store the profile under Profiles\<GameKey> so a future native game module can import it.'
            )
        }
    }
}

function Get-UGSMGameCUSTOMInstanceSetting {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$Instance,
        [Parameter(Mandatory)][string]$Name,
        [string]$DefaultValue = ''
    )

    # Prefer saved bridge manifests over the stale instance cache. Search both the
    # future/native profile folder and the original CUSTOM mirror folder so edits
    # survive while UGSM still lists the profile under Custom.
    $candidateRoots = Get-UGSMGameCUSTOMCandidateProfileRoots -Instance $Instance -ProfileName $null -TargetGameKey $null -ExplicitProfilePath $null
    foreach ($root in $candidateRoots) {
        foreach ($manifestFile in @('custom.instance.json','UGSM_CustomProfile.json')) {
            $manifestPath = Join-Path $root $manifestFile
            if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) { continue }
            try {
                $data = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
                if ($data.PSObject.Properties[$Name]) {
                    $value = $data.$Name
                    if ($null -ne $value -and -not [string]::IsNullOrWhiteSpace([string]$value)) {
                        return [string]$value
                    }
                }
            }
            catch {}
        }
    }

    if ($Instance -and $Instance.PSObject.Properties[$Name]) {
        $value = $Instance.$Name
        if ($null -ne $value -and -not [string]::IsNullOrWhiteSpace([string]$value)) {
            return [string]$value
        }
    }

    return [string]$DefaultValue
}

function Set-UGSMGameCUSTOMInstanceProperty {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$Instance,
        [Parameter(Mandatory)][string]$Name,
        [AllowNull()][object]$Value
    )

    if ($Instance.PSObject.Properties[$Name]) {
        $Instance.$Name = $Value
    }
    else {
        Add-Member -InputObject $Instance -MemberType NoteProperty -Name $Name -Value $Value -Force
    }
}



function Get-UGSMGameCUSTOMControlTextValue {
    [CmdletBinding()]
    param([AllowNull()][object]$Control)

    if ($null -eq $Control) { return '' }

    # WinForms controls expose Text as a .NET property, not always as a
    # PSObject note property. Access it directly and catch non-control values.
    try {
        $value = $Control.Text
        if ($null -ne $value) { return [string]$value }
    }
    catch {}

    try { return [string]$Control } catch { return '' }
}

function Set-UGSMGameCUSTOMControlTextValue {
    [CmdletBinding()]
    param(
        [AllowNull()][object]$Control,
        [AllowNull()][string]$Text
    )

    if ($null -eq $Control) { return }
    try { $Control.Text = [string]$Text }
    catch {
        try { Write-UGSMLog -Category 'Custom' -Level 'WARN' -Message ('Custom UI status update skipped: ' + $_.Exception.Message) } catch {}
    }
}


function Import-UGSMGameCUSTOMManifestIntoInstance {
    [CmdletBinding()]
    param([Parameter(Mandatory)][object]$Instance)

    $paths = New-Object System.Collections.Generic.List[string]
    try {
        $root = Get-UGSMGameCUSTOMResolvedProfileRoot -Instance $Instance
        if (-not [string]::IsNullOrWhiteSpace($root)) {
            $paths.Add((Join-Path $root 'custom.instance.json'))
            $paths.Add((Join-Path $root 'UGSM_CustomProfile.json'))
        }
    } catch {}

    foreach ($path in $paths) {
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { continue }
        try {
            $data = Get-Content -LiteralPath $path -Raw | ConvertFrom-Json
            foreach ($name in @(
                'Name','TargetGameKey','ProfilePath','SteamAppId','InstallPath','ServerExecutablePath','ExecutableRelativePath',
                'DownloadArguments','WorkshopItemIds','ModInstallArguments','WorkingDirectory','StartupArguments','StopProcessName'
            )) {
                if ($data.PSObject.Properties[$name]) {
                    Set-UGSMGameCUSTOMInstanceProperty -Instance $Instance -Name $name -Value ([string]$data.$name)
                }
            }
            return $true
        }
        catch {}
    }

    return $false
}

function Save-UGSMGameCUSTOMManifest {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$Instance
    )

    $profileRoot = Get-UGSMGameCUSTOMResolvedProfileRoot -Instance $Instance
    if (-not (Test-Path -LiteralPath $profileRoot -PathType Container)) {
        New-Item -ItemType Directory -Path $profileRoot -Force | Out-Null
    }

    $targetKey = Get-UGSMGameCUSTOMTargetGameKey -Instance $Instance

    $manifest = [ordered]@{
        GameId                 = 'CUSTOM'
        CreatedBy              = 'CUSTOM'
        TargetGameKey          = $targetKey
        NativeImportReady      = $true
        MigrationStatus        = 'CustomBridge'
        Name                   = [string](Get-UGSMGameCUSTOMInstanceSetting -Instance $Instance -Name 'Name' -DefaultValue 'CustomServer')
        ProfilePath            = $profileRoot
        InstallPath            = [string](Get-UGSMGameCUSTOMInstanceSetting -Instance $Instance -Name 'InstallPath')
        SteamAppId             = [string](Get-UGSMGameCUSTOMInstanceSetting -Instance $Instance -Name 'SteamAppId')
        ServerExecutablePath   = [string](Get-UGSMGameCUSTOMInstanceSetting -Instance $Instance -Name 'ServerExecutablePath')
        ExecutableRelativePath = [string](Get-UGSMGameCUSTOMInstanceSetting -Instance $Instance -Name 'ExecutableRelativePath')
        WorkingDirectory       = [string](Get-UGSMGameCUSTOMInstanceSetting -Instance $Instance -Name 'WorkingDirectory')
        StartupArguments       = [string](Get-UGSMGameCUSTOMInstanceSetting -Instance $Instance -Name 'StartupArguments')
        DownloadArguments      = [string](Get-UGSMGameCUSTOMInstanceSetting -Instance $Instance -Name 'DownloadArguments')
        WorkshopItemIds        = [string](Get-UGSMGameCUSTOMInstanceSetting -Instance $Instance -Name 'WorkshopItemIds')
        ModInstallArguments    = [string](Get-UGSMGameCUSTOMInstanceSetting -Instance $Instance -Name 'ModInstallArguments')
        StopProcessName        = [string](Get-UGSMGameCUSTOMInstanceSetting -Instance $Instance -Name 'StopProcessName')
        UpdatedAtUtc           = [DateTime]::UtcNow.ToString('o')
    }

    ($manifest | ConvertTo-Json -Depth 6) | Set-Content -LiteralPath (Get-UGSMGameCUSTOMManifestPath -Instance $Instance) -Encoding UTF8

    # Future native modules can look for this marker in Profiles\<TargetGameKey>\<ProfileName>.
    $bridgePath = Join-Path $profileRoot 'UGSM_CustomProfile.json'
    ($manifest | ConvertTo-Json -Depth 6) | Set-Content -LiteralPath $bridgePath -Encoding UTF8

    return [pscustomobject]$manifest
}

function Initialize-UGSMGameCUSTOMProfile {
    [CmdletBinding(DefaultParameterSetName='ByInstance')]
    param(
        [Parameter(Mandatory, ParameterSetName='ByInstance')][object]$Instance,
        [Parameter(Mandatory, ParameterSetName='ByName')][string]$ProfileName,
        [Parameter(ParameterSetName='ByName')][string]$InstallPath,
        [Parameter(ParameterSetName='ByName')][string]$TargetGameKey = 'CUSTOM',
        [switch]$Force,
        [int]$BootstrapSeconds = 0
    )

    if ($PSCmdlet.ParameterSetName -eq 'ByByName') {}

    if ($PSCmdlet.ParameterSetName -eq 'ByInstance') {
        $profileRoot = Get-UGSMGameCUSTOMResolvedProfileRoot -Instance $Instance
    }
    else {
        $profileRoot = Get-UGSMGameCUSTOMProfileRoot -ProfileName $ProfileName -TargetGameKey $TargetGameKey
        $Instance = [pscustomobject]@{
            Name        = $ProfileName
            InstallPath = $InstallPath
            ProfilePath = $profileRoot
            TargetGameKey = $TargetGameKey
        }
    }

    if ((Test-Path -LiteralPath $profileRoot -PathType Container) -and $Force) {
        Get-ChildItem -LiteralPath $profileRoot -Force -ErrorAction SilentlyContinue | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
    }

    foreach ($path in @(
        $profileRoot,
        (Join-Path $profileRoot 'Mods'),
        (Join-Path $profileRoot 'Config'),
        (Join-Path $profileRoot 'Logs')
    )) {
        if (-not (Test-Path -LiteralPath $path -PathType Container)) {
            New-Item -ItemType Directory -Path $path -Force | Out-Null
        }
    }

    Set-UGSMGameCUSTOMInstanceProperty -Instance $Instance -Name 'ProfilePath' -Value $profileRoot
    $manifest = Save-UGSMGameCUSTOMManifest -Instance $Instance

    return [pscustomobject]@{
        GameId      = 'CUSTOM'
        ProfileRoot = $profileRoot
        ConfigRoot  = (Join-Path $profileRoot 'Config')
        ModsRoot    = (Join-Path $profileRoot 'Mods')
        LogsRoot    = (Join-Path $profileRoot 'Logs')
        Manifest    = $manifest
        Initialized = $true
    }
}

function Ensure-UGSMGameCUSTOMTemplate {
    [CmdletBinding()]
    param(
        [string]$GameId = 'CUSTOM',
        [string]$InstallPath,
        [switch]$ForceRefresh,
        [int]$BootstrapSeconds = 0
    )

    return [pscustomobject]@{
        GameId             = 'CUSTOM'
        InstallPath        = $InstallPath
        BootstrapPerformed = $false
        Notes              = 'Custom Game does not use a generated template. Profile data is stored directly per instance.'
    }
}


function Split-UGSMGameCUSTOMCommandLine {
    [CmdletBinding()]
    param(
        [string]$Text
    )

    $items = New-Object System.Collections.Generic.List[string]
    if ([string]::IsNullOrWhiteSpace($Text)) {
        return @()
    }

    $pattern = '"([^"\\]*(?:\\.[^"\\]*)*)"|(\S+)'
    foreach ($match in [regex]::Matches($Text, $pattern)) {
        if ($match.Groups[1].Success) {
            $items.Add($match.Groups[1].Value)
        }
        elseif ($match.Groups[2].Success) {
            $items.Add($match.Groups[2].Value)
        }
    }

    return @($items)
}

function Invoke-UGSMGameCUSTOMSteamCmdAction {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$Instance,
        [ValidateSet('Install','Update','Verify')][string]$Action = 'Install'
    )

    $steamAppId = (Get-UGSMGameCUSTOMInstanceSetting -Instance $Instance -Name 'SteamAppId').Trim()
    if ([string]::IsNullOrWhiteSpace($steamAppId)) {
        throw 'Steam App ID is required before running a SteamCMD action.'
    }

    $installPath = (Get-UGSMGameCUSTOMInstanceSetting -Instance $Instance -Name 'InstallPath').Trim()
    if ([string]::IsNullOrWhiteSpace($installPath)) {
        throw 'Install Path is required before running a SteamCMD action.'
    }

    if (-not (Get-Command -Name Ensure-UGSMSteamCMDInstalled -ErrorAction SilentlyContinue)) {
        throw 'SteamCMD helper is not available in this build.'
    }
    if (-not (Get-Command -Name Invoke-UGSMProcess -ErrorAction SilentlyContinue)) {
        throw 'Process helper is not available in this build.'
    }

    $steam = Ensure-UGSMSteamCMDInstalled
    if (-not $steam -or -not $steam.Success -or -not $steam.IsInstalled) {
        throw 'SteamCMD is not available.'
    }

    if (-not (Test-Path -LiteralPath $installPath -PathType Container)) {
        New-Item -Path $installPath -ItemType Directory -Force | Out-Null
    }

    $extraArgs = Split-UGSMGameCUSTOMCommandLine -Text (Get-UGSMGameCUSTOMInstanceSetting -Instance $Instance -Name 'DownloadArguments')
    $args = @('+force_install_dir', $installPath, '+login', 'anonymous', '+app_update', $steamAppId)
    if ($Action -eq 'Verify') {
        $args += 'validate'
    }
    if (@($extraArgs).Count -gt 0) {
        $args += @($extraArgs)
    }
    $args += '+quit'

    $proc = Invoke-UGSMProcess -FilePath $steam.ExePath -ArgumentList $args -WorkingDirectory $steam.InstallPath -ShowWindow -TimeoutSeconds 7200
    if ([int]$proc.ExitCode -eq 8) {
        Start-Sleep -Seconds 2
        $proc = Invoke-UGSMProcess -FilePath $steam.ExePath -ArgumentList $args -WorkingDirectory $steam.InstallPath -ShowWindow -TimeoutSeconds 7200
    }

    $validation = Test-UGSMGameCUSTOMInstall -Instance $Instance
    $message = if ($validation.ServerExecutableExists) {
        'Download finished and the configured executable was found.'
    }
    elseif ($validation.InstallPathExists) {
        'Download finished. Server files were found, but the configured executable path still needs review.'
    }
    else {
        'SteamCMD finished, but the install path did not validate yet.'
    }

    Save-UGSMGameCUSTOMManifest -Instance $Instance | Out-Null

    return [pscustomobject]@{
        Success    = ([bool]$proc.Success -and [int]$proc.ExitCode -eq 0)
        Action     = $Action
        ExitCode   = [int]$proc.ExitCode
        InstallPath = $installPath
        SteamAppId = $steamAppId
        Validation = $validation
        Message    = $message
    }
}

function Resolve-UGSMGameCUSTOMExecutablePath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$Instance
    )

    $installPath = [string](Get-UGSMGameCUSTOMInstanceSetting -Instance $Instance -Name 'InstallPath')
    $fullPath = [string](Get-UGSMGameCUSTOMInstanceSetting -Instance $Instance -Name 'ServerExecutablePath')
    $relativePath = [string](Get-UGSMGameCUSTOMInstanceSetting -Instance $Instance -Name 'ExecutableRelativePath')

    if (-not [string]::IsNullOrWhiteSpace($fullPath)) {
        $fullPath = $fullPath.Trim().Trim('"')
    }
    if (-not [string]::IsNullOrWhiteSpace($installPath)) {
        $installPath = $installPath.Trim().Trim('"')
    }
    if (-not [string]::IsNullOrWhiteSpace($relativePath)) {
        $relativePath = $relativePath.Trim().Trim('"')
    }

    $useFullPath = (-not [string]::IsNullOrWhiteSpace($fullPath))
    if ($useFullPath -and -not [string]::IsNullOrWhiteSpace($installPath)) {
        if ($fullPath -ieq $installPath) {
            $useFullPath = $false
        }
        elseif (Test-Path -LiteralPath $fullPath -PathType Container) {
            $useFullPath = $false
        }
    }

    if ($useFullPath) {
        return $fullPath
    }

    if (-not [string]::IsNullOrWhiteSpace($installPath) -and -not [string]::IsNullOrWhiteSpace($relativePath)) {
        return (Join-Path $installPath $relativePath)
    }

    return ''
}


function Get-UGSMGameCUSTOMLaunchPlan {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$Instance
    )

    $resolvedPath = Resolve-UGSMGameCUSTOMExecutablePath -Instance $Instance
    if ([string]::IsNullOrWhiteSpace($resolvedPath)) {
        throw 'CUSTOM start failed: no server executable path was configured.'
    }
    if (-not (Test-Path -LiteralPath $resolvedPath -PathType Leaf)) {
        throw "CUSTOM start failed: server executable was not found: $resolvedPath"
    }

    $startupArguments = Get-UGSMGameCUSTOMInstanceSetting -Instance $Instance -Name 'StartupArguments'
    $workingDirectory = Get-UGSMGameCUSTOMInstanceSetting -Instance $Instance -Name 'WorkingDirectory'
    if ([string]::IsNullOrWhiteSpace($workingDirectory)) {
        $workingDirectory = Split-Path -Parent $resolvedPath
    }
    if (-not (Test-Path -LiteralPath $workingDirectory -PathType Container)) {
        throw "CUSTOM start failed: working directory was not found: $workingDirectory"
    }

    $extension = [System.IO.Path]::GetExtension($resolvedPath)
    $launchFilePath = $resolvedPath
    $launchArguments = $startupArguments
    $displayCommand = $resolvedPath

    if (-not [string]::IsNullOrWhiteSpace($startupArguments)) {
        $displayCommand += ' ' + $startupArguments
    }

    if ($extension -match '^(?i)\.(bat|cmd)$') {
        $cmdExe = Join-Path $env:SystemRoot 'System32\cmd.exe'
        if (-not (Test-Path -LiteralPath $cmdExe -PathType Leaf)) {
            $cmdExe = 'cmd.exe'
        }

        $quotedScript = '"' + $resolvedPath.Replace('"', '""') + '"'
        if (-not [string]::IsNullOrWhiteSpace($startupArguments)) {
            $launchArguments = '/c ' + $quotedScript + ' ' + $startupArguments
            $displayCommand = $cmdExe + ' /c ' + $quotedScript + ' ' + $startupArguments
        }
        else {
            $launchArguments = '/c ' + $quotedScript
            $displayCommand = $cmdExe + ' /c ' + $quotedScript
        }

        $launchFilePath = $cmdExe
    }

    return [pscustomobject]@{
        ResolvedExecutablePath = $resolvedPath
        LaunchFilePath         = $launchFilePath
        LaunchArguments        = $launchArguments
        WorkingDirectory       = $workingDirectory
        DisplayCommand         = $displayCommand
        UsesCommandShell       = ($launchFilePath -ne $resolvedPath)
    }
}

function Test-UGSMGameCUSTOMInstall {
    [CmdletBinding()]
    param(
        [string]$InstallPath,
        [object]$Instance
    )

    if (-not $Instance) {
        $Instance = [pscustomobject]@{ InstallPath = $InstallPath }
    }
    elseif (-not [string]::IsNullOrWhiteSpace($InstallPath)) {
        Set-UGSMGameCUSTOMInstanceProperty -Instance $Instance -Name 'InstallPath' -Value $InstallPath
    }

    $resolvedInstallPath = Get-UGSMGameCUSTOMInstanceSetting -Instance $Instance -Name 'InstallPath'
    $exePath = Resolve-UGSMGameCUSTOMExecutablePath -Instance $Instance
    $installExists = $false
    if (-not [string]::IsNullOrWhiteSpace($resolvedInstallPath)) {
        $installExists = Test-Path -LiteralPath $resolvedInstallPath -PathType Container
    }
    $exeExists = $false
    if (-not [string]::IsNullOrWhiteSpace($exePath)) {
        $exeExists = Test-Path -LiteralPath $exePath -PathType Leaf
    }

    $missing = @()
    if (-not $installExists -and -not [string]::IsNullOrWhiteSpace($resolvedInstallPath)) { $missing += $resolvedInstallPath }
    if (-not $exeExists -and -not [string]::IsNullOrWhiteSpace($exePath)) { $missing += $exePath }

    return [pscustomobject]@{
        GameId               = 'CUSTOM'
        InstallPath          = $resolvedInstallPath
        InstallPathExists    = $installExists
        ServerExecutablePath = $exePath
        ServerExecutableExists = $exeExists
        MissingItems         = @($missing)
        IsInstalled          = ($installExists -or $exeExists)
        IsValid              = ($exeExists)
        NeedsRepair          = $false
    }
}

function Test-UGSMGameCUSTOMInstance {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$Instance
    )

    $profileRoot = Get-UGSMGameCUSTOMResolvedProfileRoot -Instance $Instance
    $install = Test-UGSMGameCUSTOMInstall -Instance $Instance

    return [pscustomobject]@{
        GameId              = 'CUSTOM'
        ProfileRoot         = $profileRoot
        ProfileExists       = (Test-Path -LiteralPath $profileRoot -PathType Container)
        ManifestPath        = (Get-UGSMGameCUSTOMManifestPath -Instance $Instance)
        ManifestExists      = (Test-Path -LiteralPath (Get-UGSMGameCUSTOMManifestPath -Instance $Instance) -PathType Leaf)
        InstallValidation   = $install
        IsValid             = ($install.ServerExecutableExists)
    }
}

function Start-UGSMGameCUSTOMInstance {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$Instance
    )

    $null = Initialize-UGSMGameCUSTOMProfile -Instance $Instance
    $launchPlan = Get-UGSMGameCUSTOMLaunchPlan -Instance $Instance

    $proc = Start-Process -FilePath $launchPlan.LaunchFilePath -ArgumentList $launchPlan.LaunchArguments -WorkingDirectory $launchPlan.WorkingDirectory -PassThru
    if (-not $proc -or -not $proc.Id) {
        throw 'CUSTOM start failed: Start-Process did not return a valid process.'
    }

    Set-UGSMGameCUSTOMInstanceProperty -Instance $Instance -Name 'Pid' -Value ([int]$proc.Id)
    Set-UGSMGameCUSTOMInstanceProperty -Instance $Instance -Name 'Status' -Value 'Running'
    Save-UGSMGameCUSTOMManifest -Instance $Instance | Out-Null

    $runtimeState = [ordered]@{
        GameId               = 'CUSTOM'
        TargetGameKey        = (Get-UGSMGameCUSTOMTargetGameKey -Instance $Instance)
        InstanceId           = [string]$(if ($Instance.PSObject.Properties['Id']) { $Instance.Id } else { '' })
        Name                 = [string](Get-UGSMGameCUSTOMInstanceSetting -Instance $Instance -Name 'Name' -DefaultValue 'CustomServer')
        ProfilePath          = Get-UGSMGameCUSTOMResolvedProfileRoot -Instance $Instance
        ServerExecutablePath = $launchPlan.ResolvedExecutablePath
        LaunchFilePath       = $launchPlan.LaunchFilePath
        WorkingDirectory     = $launchPlan.WorkingDirectory
        StartupArguments     = [string](Get-UGSMGameCUSTOMInstanceSetting -Instance $Instance -Name 'StartupArguments')
        LaunchArguments      = $launchPlan.LaunchArguments
        DisplayCommand       = $launchPlan.DisplayCommand
        Pid                  = [int]$proc.Id
        StartedAtUtc         = [DateTime]::UtcNow.ToString('o')
    }
    ($runtimeState | ConvertTo-Json -Depth 6) | Set-Content -LiteralPath (Get-UGSMGameCUSTOMRuntimeStatePath -Instance $Instance) -Encoding UTF8

    return [pscustomobject]@{
        Instance = $Instance
        Pid      = [int]$proc.Id
        Status   = 'Running'
        Runtime  = [pscustomobject]$runtimeState
    }
}

function Stop-UGSMGameCUSTOMInstance {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$Instance
    )

    $targetPid = $null
    if ($Instance.PSObject.Properties['Pid'] -and $Instance.Pid) {
        $targetPid = [int]$Instance.Pid
    }

    if (-not $targetPid) {
        $runtimePath = Get-UGSMGameCUSTOMRuntimeStatePath -Instance $Instance
        if (Test-Path -LiteralPath $runtimePath -PathType Leaf) {
            try {
                $runtime = Get-Content -LiteralPath $runtimePath -Raw | ConvertFrom-Json
                if ($runtime.Pid) { $targetPid = [int]$runtime.Pid }
            }
            catch {}
        }
    }

    $stopped = $false
    if ($targetPid) {
        if (Get-Command -Name Stop-UGSMProcessTree -ErrorAction SilentlyContinue) {
            try {
                $result = Stop-UGSMProcessTree -ProcessId $targetPid -TimeoutSeconds 20
                $stopped = $true
            }
            catch {}
        }

        if (-not $stopped) {
            try {
                Stop-Process -Id $targetPid -Force -ErrorAction Stop
                $stopped = $true
            }
            catch {}
        }
    }
    else {
        $stopName = Get-UGSMGameCUSTOMInstanceSetting -Instance $Instance -Name 'StopProcessName'
        if (-not [string]::IsNullOrWhiteSpace($stopName)) {
            try {
                Get-Process -Name $stopName -ErrorAction Stop | Stop-Process -Force -ErrorAction Stop
                $stopped = $true
            }
            catch {}
        }
    }

    Set-UGSMGameCUSTOMInstanceProperty -Instance $Instance -Name 'Pid' -Value $null
    Set-UGSMGameCUSTOMInstanceProperty -Instance $Instance -Name 'Status' -Value 'Stopped'

    $runtimePath = Get-UGSMGameCUSTOMRuntimeStatePath -Instance $Instance
    if (Test-Path -LiteralPath $runtimePath -PathType Leaf) {
        try { Remove-Item -LiteralPath $runtimePath -Force -ErrorAction Stop } catch {}
    }

    return [pscustomobject]@{
        Instance = $Instance
        Status   = 'Stopped'
        Stopped  = $stopped
    }
}

function New-UGSMGameCUSTOMLabel {
    param(
        [string]$Text,
        [int]$Width = 190,
        [int]$Height = 20
    )
    $label = New-Object System.Windows.Forms.Label
    $label.Text = $Text
    $label.Width = $Width
    $label.Height = $Height
    $label.AutoSize = $false
    $label.ForeColor = (Get-UGSMGameCUSTOMUIColor -Name 'Text' -Fallback ([System.Drawing.Color]::White))
    $label.BackColor = [System.Drawing.Color]::Transparent
    return $label
}

function New-UGSMGameCUSTOMTextBox {
    param(
        [string]$Text = '',
        [int]$Width = 560,
        [switch]$Multiline,
        [int]$Height = 24
    )
    $tb = New-Object System.Windows.Forms.TextBox
    $tb.Width = $Width
    $tb.Text = $Text
    $tb.BorderStyle = 'FixedSingle'
    $tb.BackColor = (Get-UGSMGameCUSTOMUIColor -Name 'InputBackground' -Fallback ([System.Drawing.ColorTranslator]::FromHtml('#0A1320')) )
    $tb.ForeColor = (Get-UGSMGameCUSTOMUIColor -Name 'Text' -Fallback ([System.Drawing.Color]::White))
    $tb.Multiline = [bool]$Multiline
    $tb.ScrollBars = $(if ($Multiline) { 'Vertical' } else { 'None' })
    $tb.Height = $(if ($Multiline) { $Height } else { 24 })
    return $tb
}


function Get-UGSMGameCUSTOMUIColor {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][System.Drawing.Color]$Fallback
    )

    $varName = "UGSM_Color$Name"
    try {
        $value = Get-Variable -Name $varName -Scope Global -ErrorAction SilentlyContinue
        if ($value -and $value.Value -is [System.Drawing.Color]) { return $value.Value }
    }
    catch {}

    return $Fallback
}

function Set-UGSMGameCUSTOMControlTheme {
    [CmdletBinding()]
    param([Parameter(Mandatory)][System.Windows.Forms.Control]$Control)

    $bg      = Get-UGSMGameCUSTOMUIColor -Name 'Background' -Fallback ([System.Drawing.ColorTranslator]::FromHtml('#071120'))
    $surface = Get-UGSMGameCUSTOMUIColor -Name 'PanelBackground' -Fallback ([System.Drawing.ColorTranslator]::FromHtml('#0B1728'))
    $inputBg = Get-UGSMGameCUSTOMUIColor -Name 'InputBackground' -Fallback ([System.Drawing.ColorTranslator]::FromHtml('#0A1320'))
    $text    = Get-UGSMGameCUSTOMUIColor -Name 'Text' -Fallback ([System.Drawing.Color]::White)
    $muted   = Get-UGSMGameCUSTOMUIColor -Name 'MutedText' -Fallback ([System.Drawing.Color]::Silver)
    $button  = Get-UGSMGameCUSTOMUIColor -Name 'Neutral' -Fallback ([System.Drawing.ColorTranslator]::FromHtml('#334155'))
    $accent  = Get-UGSMGameCUSTOMUIColor -Name 'Primary' -Fallback ([System.Drawing.ColorTranslator]::FromHtml('#3B82F6'))

    if ($Control -is [System.Windows.Forms.TextBox]) {
        $Control.BackColor = $inputBg
        $Control.ForeColor = $text
    }
    elseif ($Control -is [System.Windows.Forms.Button]) {
        $Control.FlatStyle = 'Flat'
        $Control.BackColor = $button
        $Control.ForeColor = $text
        try { $Control.FlatAppearance.BorderColor = $accent } catch {}
    }
    elseif ($Control -is [System.Windows.Forms.TabControl]) {
        $Control.BackColor = $surface
        $Control.ForeColor = $text
    }
    elseif ($Control -is [System.Windows.Forms.TabPage]) {
        $Control.BackColor = $surface
        $Control.ForeColor = $text
    }
    elseif ($Control -is [System.Windows.Forms.FlowLayoutPanel] -or $Control -is [System.Windows.Forms.Panel]) {
        $Control.BackColor = $surface
        $Control.ForeColor = $text
    }
    elseif ($Control -is [System.Windows.Forms.Label]) {
        $Control.BackColor = [System.Drawing.Color]::Transparent
        if ($Control.Text -match '^(Enter |Use |Per-|Optional|Friendly|Folder|Steam|Target|UGSM|Set |If )' -or $Control.Height -gt 24) {
            $Control.ForeColor = $muted
        }
        else {
            $Control.ForeColor = $text
        }
    }
    elseif ($Control -is [System.Windows.Forms.CheckBox]) {
        $Control.BackColor = $surface
        $Control.ForeColor = $text
    }
    else {
        try { $Control.BackColor = $surface } catch {}
        try { $Control.ForeColor = $text } catch {}
    }

    foreach ($child in $Control.Controls) {
        Set-UGSMGameCUSTOMControlTheme -Control $child
    }
}

function New-UGSMGameCUSTOMFieldRow {
    param(
        [Parameter(Mandatory)][System.Windows.Forms.Control]$Parent,
        [Parameter(Mandatory)][string]$Label,
        [Parameter(Mandatory)][System.Windows.Forms.Control]$Control,
        [string]$HelpText = ''
    )

    $row = New-Object System.Windows.Forms.FlowLayoutPanel
    $row.FlowDirection = 'TopDown'
    $row.WrapContents = $false
    $row.AutoSize = $true
    $row.AutoSizeMode = 'GrowAndShrink'
    $row.Dock = 'Top'
    $row.Margin = New-Object System.Windows.Forms.Padding(0,0,0,10)

    [void]$row.Controls.Add((New-UGSMGameCUSTOMLabel -Text $Label))
    [void]$row.Controls.Add($Control)

    if (-not [string]::IsNullOrWhiteSpace($HelpText)) {
        $help = New-Object System.Windows.Forms.Label
        $help.AutoSize = $false
        $help.Width = [Math]::Max(560, $Control.Width)
        $help.Height = 34
        $help.ForeColor = [System.Drawing.Color]::Silver
        $help.Text = $HelpText
        [void]$row.Controls.Add($help)
    }

    [void]$Parent.Controls.Add($row)
}

function New-UGSMGameCUSTOMInstanceEditor {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$Instance,
        [Parameter(Mandatory)][hashtable]$Theme,
        [Parameter(Mandatory)][System.Windows.Forms.Panel]$HostPanel,
        [AllowNull()][System.Windows.Forms.Label]$StatusLabel
    )

    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing

    # Do not call Initialize here. It writes custom.instance.json and can
    # overwrite saved bridge values with stale cache values before the user
    # even clicks Save. Load any existing marker first, then only make sure the
    # folder exists.
    try { [void](Import-UGSMGameCUSTOMManifestIntoInstance -Instance $Instance) } catch {}
    try {
        $initialRoot = Get-UGSMGameCUSTOMResolvedProfileRoot -Instance $Instance
        foreach ($path in @($initialRoot, (Join-Path $initialRoot 'Mods'), (Join-Path $initialRoot 'Config'), (Join-Path $initialRoot 'Logs'))) {
            if (-not (Test-Path -LiteralPath $path -PathType Container)) { New-Item -ItemType Directory -Path $path -Force | Out-Null }
        }
    } catch {}

    $HostPanel.Controls.Clear()

    $customBg = Get-UGSMGameCUSTOMUIColor -Name 'Background' -Fallback ([System.Drawing.ColorTranslator]::FromHtml('#071120'))
    $customSurface = Get-UGSMGameCUSTOMUIColor -Name 'PanelBackground' -Fallback ([System.Drawing.ColorTranslator]::FromHtml('#0B1728'))
    $customText = Get-UGSMGameCUSTOMUIColor -Name 'Text' -Fallback ([System.Drawing.Color]::White)
    $customMuted = Get-UGSMGameCUSTOMUIColor -Name 'MutedText' -Fallback ([System.Drawing.Color]::Silver)

    $root = New-Object System.Windows.Forms.Panel
    $root.Dock = 'Fill'
    $root.BackColor = $customBg
    $root.ForeColor = $customText
    $root.AutoScroll = $true
    $HostPanel.Controls.Add($root)

    $header = New-Object System.Windows.Forms.Label
    $header.Dock = 'Top'
    $header.Height = 44
    $header.Text = 'Custom Game Editor - Generic unsupported server setup'
    $header.BackColor = $customBg
    $header.ForeColor = $customText
    $header.Font = New-Object System.Drawing.Font('Segoe UI', 11, [System.Drawing.FontStyle]::Bold)
    $root.Controls.Add($header)

    $tabs = New-Object System.Windows.Forms.TabControl
    $tabs.Dock = 'Fill'
    $tabs.BackColor = $customSurface
    $tabs.ForeColor = $customText
    $root.Controls.Add($tabs)
    $root.Controls.SetChildIndex($tabs, 0)

    $tabGeneral = New-Object System.Windows.Forms.TabPage
    $tabGeneral.BackColor = $customSurface
    $tabGeneral.ForeColor = $customText
    $tabGeneral.Text = 'General'
    $generalPanel = New-Object System.Windows.Forms.FlowLayoutPanel
    $generalPanel.Dock = 'Fill'
    $generalPanel.BackColor = $customSurface
    $generalPanel.ForeColor = $customText
    $generalPanel.FlowDirection = 'TopDown'
    $generalPanel.WrapContents = $false
    $generalPanel.AutoScroll = $true
    $generalPanel.Padding = New-Object System.Windows.Forms.Padding(12)
    $tabGeneral.Controls.Add($generalPanel)

    $tabInstall = New-Object System.Windows.Forms.TabPage
    $tabInstall.BackColor = $customSurface
    $tabInstall.ForeColor = $customText
    $tabInstall.Text = 'Install'
    $installPanel = New-Object System.Windows.Forms.FlowLayoutPanel
    $installPanel.Dock = 'Fill'
    $installPanel.BackColor = $customSurface
    $installPanel.ForeColor = $customText
    $installPanel.FlowDirection = 'TopDown'
    $installPanel.WrapContents = $false
    $installPanel.AutoScroll = $true
    $installPanel.Padding = New-Object System.Windows.Forms.Padding(12)
    $tabInstall.Controls.Add($installPanel)

    $tabMods = New-Object System.Windows.Forms.TabPage
    $tabMods.BackColor = $customSurface
    $tabMods.ForeColor = $customText
    $tabMods.Text = 'Mods'
    $modsPanel = New-Object System.Windows.Forms.FlowLayoutPanel
    $modsPanel.Dock = 'Fill'
    $modsPanel.BackColor = $customSurface
    $modsPanel.ForeColor = $customText
    $modsPanel.FlowDirection = 'TopDown'
    $modsPanel.WrapContents = $false
    $modsPanel.AutoScroll = $true
    $modsPanel.Padding = New-Object System.Windows.Forms.Padding(12)
    $tabMods.Controls.Add($modsPanel)

    $tabStartup = New-Object System.Windows.Forms.TabPage
    $tabStartup.BackColor = $customSurface
    $tabStartup.ForeColor = $customText
    $tabStartup.Text = 'Startup'
    $startupPanel = New-Object System.Windows.Forms.FlowLayoutPanel
    $startupPanel.Dock = 'Fill'
    $startupPanel.BackColor = $customSurface
    $startupPanel.ForeColor = $customText
    $startupPanel.FlowDirection = 'TopDown'
    $startupPanel.WrapContents = $false
    $startupPanel.AutoScroll = $true
    $startupPanel.Padding = New-Object System.Windows.Forms.Padding(12)
    $tabStartup.Controls.Add($startupPanel)

    [void]$tabs.TabPages.Add($tabGeneral)
    [void]$tabs.TabPages.Add($tabInstall)
    [void]$tabs.TabPages.Add($tabMods)
    [void]$tabs.TabPages.Add($tabStartup)

    $txtDisplayName = New-UGSMGameCUSTOMTextBox -Text (Get-UGSMGameCUSTOMInstanceSetting -Instance $Instance -Name 'Name' -DefaultValue ([string]$(if ($Instance.PSObject.Properties['Name']) { $Instance.Name } else { 'CustomServer' })))
    $txtDisplayName.Name = 'Custom_DisplayName'
    $txtTargetGameKey = New-UGSMGameCUSTOMTextBox -Text (Get-UGSMGameCUSTOMInstanceSetting -Instance $Instance -Name 'TargetGameKey' -DefaultValue (Get-UGSMGameCUSTOMTargetGameKey -Instance $Instance))
    $txtTargetGameKey.Name = 'Custom_TargetGameKey'
    $txtProfilePath = New-UGSMGameCUSTOMTextBox -Text (Get-UGSMGameCUSTOMResolvedProfileRoot -Instance $Instance)
    $txtProfilePath.Name = 'Custom_ProfilePath'
    $txtProfilePath.ReadOnly = $true
    $lblIntro = New-Object System.Windows.Forms.Label
    $lblIntro.AutoSize = $false
    $lblIntro.Width = 760
    $lblIntro.Height = 54
    $lblIntro.BackColor = [System.Drawing.Color]::Transparent
    $lblIntro.ForeColor = $customMuted
    $lblIntro.Text = 'Use Custom Game for unsupported servers. Set Target Game Key to the future/native game id, for example Enshrouded. UGSM stores this profile under Profiles\<TargetGameKey> so a later native module can offer to import it.'
    $lblIntro.Margin = New-Object System.Windows.Forms.Padding(0,0,0,10)
    [void]$generalPanel.Controls.Add($lblIntro)

    New-UGSMGameCUSTOMFieldRow -Parent $generalPanel -Label 'Server Name / Profile Name' -Control $txtDisplayName -HelpText 'Friendly name shown in UGSM for this instance.'
    New-UGSMGameCUSTOMFieldRow -Parent $generalPanel -Label 'Target Game Key' -Control $txtTargetGameKey -HelpText 'Use a stable key for the real game this profile belongs to. Example: Enshrouded. If UGSM supports this game later, the native module can find this profile.'
    New-UGSMGameCUSTOMFieldRow -Parent $generalPanel -Label 'Profile Path' -Control $txtProfilePath -HelpText 'Per-instance profile folder. Custom bridge profiles are stored under the target game key, not under Custom, when a target is provided.'

    $updateCustomProfilePathPreview = {
        $safeTarget = ConvertTo-UGSMGameCUSTOMSafeKey -Value $txtTargetGameKey.Text -DefaultValue 'CUSTOM'
        $safeName = $txtDisplayName.Text
        if ([string]::IsNullOrWhiteSpace($safeName)) { $safeName = 'CustomServer' }
        $txtProfilePath.Text = Get-UGSMGameCUSTOMProfileRoot -ProfileName $safeName -TargetGameKey $safeTarget
    }.GetNewClosure()
    $txtDisplayName.Add_TextChanged({ & $updateCustomProfilePathPreview }.GetNewClosure())
    $txtTargetGameKey.Add_TextChanged({ & $updateCustomProfilePathPreview }.GetNewClosure())

    $txtSteamAppId = New-UGSMGameCUSTOMTextBox -Text (Get-UGSMGameCUSTOMInstanceSetting -Instance $Instance -Name 'SteamAppId')
    $txtSteamAppId.Name = 'Custom_SteamAppId'
    $txtInstallPath = New-UGSMGameCUSTOMTextBox -Text (Get-UGSMGameCUSTOMInstanceSetting -Instance $Instance -Name 'InstallPath')
    $txtInstallPath.Name = 'Custom_InstallPath'
    $txtServerExe = New-UGSMGameCUSTOMTextBox -Text (Get-UGSMGameCUSTOMInstanceSetting -Instance $Instance -Name 'ServerExecutablePath')
    $txtServerExe.Name = 'Custom_ServerExecutablePath'
    $txtExeRelative = New-UGSMGameCUSTOMTextBox -Text (Get-UGSMGameCUSTOMInstanceSetting -Instance $Instance -Name 'ExecutableRelativePath')
    $txtExeRelative.Name = 'Custom_ExecutableRelativePath'
    $txtDownloadArgs = New-UGSMGameCUSTOMTextBox -Text (Get-UGSMGameCUSTOMInstanceSetting -Instance $Instance -Name 'DownloadArguments') -Multiline -Height 90
    $txtDownloadArgs.Name = 'Custom_DownloadArguments'

    New-UGSMGameCUSTOMFieldRow -Parent $installPanel -Label 'Steam App ID (optional)' -Control $txtSteamAppId -HelpText 'Enter the dedicated server app id only if this game can be downloaded with SteamCMD. Leave blank for manual installs.'
    New-UGSMGameCUSTOMFieldRow -Parent $installPanel -Label 'Install Path' -Control $txtInstallPath -HelpText 'Folder where the dedicated server files already exist or should be downloaded to.'
    New-UGSMGameCUSTOMFieldRow -Parent $installPanel -Label 'Full Server Executable Path (preferred)' -Control $txtServerExe -HelpText 'Full path to the server executable. Example: D:\Servers\Game\Server.exe'
    New-UGSMGameCUSTOMFieldRow -Parent $installPanel -Label 'Executable Relative Path (used with Install Path)' -Control $txtExeRelative -HelpText 'Optional relative path under Install Path. Example: ShooterGame\Binaries\Win64\ArkAscendedServer.exe'
    New-UGSMGameCUSTOMFieldRow -Parent $installPanel -Label 'Extra Download / SteamCMD Arguments' -Control $txtDownloadArgs -HelpText 'Optional extra SteamCMD arguments. Leave blank unless the game documentation says otherwise.'


    $installActionsPanel = New-Object System.Windows.Forms.FlowLayoutPanel
    $installActionsPanel.AutoSize = $true
    $installActionsPanel.WrapContents = $false
    $installActionsPanel.FlowDirection = 'LeftToRight'
    $installActionsPanel.Margin = New-Object System.Windows.Forms.Padding(0,6,0,6)
    $btnInstallFiles = New-Object System.Windows.Forms.Button
    $btnInstallFiles.Text = 'Install Files'
    $btnInstallFiles.Width = 110
    $btnUpdateFiles = New-Object System.Windows.Forms.Button
    $btnUpdateFiles.Text = 'Update Files'
    $btnUpdateFiles.Width = 110
    $btnVerifyFiles = New-Object System.Windows.Forms.Button
    $btnVerifyFiles.Text = 'Verify Files'
    $btnVerifyFiles.Width = 110
    $lblInstallStatus = New-Object System.Windows.Forms.Label
    $lblInstallStatus.AutoSize = $false
    $lblInstallStatus.Width = 420
    $lblInstallStatus.Height = 40
    $lblInstallStatus.Text = 'Enter Steam App ID and Install Path, then use Install Files to download with SteamCMD.'
    [void]$installActionsPanel.Controls.Add($btnInstallFiles)
    [void]$installActionsPanel.Controls.Add($btnUpdateFiles)
    [void]$installActionsPanel.Controls.Add($btnVerifyFiles)
    [void]$installActionsPanel.Controls.Add($lblInstallStatus)
    [void]$installPanel.Controls.Add($installActionsPanel)

    $txtWorkshopIds = New-UGSMGameCUSTOMTextBox -Text (Get-UGSMGameCUSTOMInstanceSetting -Instance $Instance -Name 'WorkshopItemIds') -Multiline -Height 120
    $txtWorkshopIds.Name = 'Custom_WorkshopItemIds'
    $txtModArgs = New-UGSMGameCUSTOMTextBox -Text (Get-UGSMGameCUSTOMInstanceSetting -Instance $Instance -Name 'ModInstallArguments') -Multiline -Height 120
    $txtModArgs.Name = 'Custom_ModInstallArguments'
    New-UGSMGameCUSTOMFieldRow -Parent $modsPanel -Label 'Workshop Item IDs (one per line or comma separated)' -Control $txtWorkshopIds -HelpText 'Paste Steam Workshop ids here if the game supports workshop mods. This module only stores the values.'
    New-UGSMGameCUSTOMFieldRow -Parent $modsPanel -Label 'Generic Mod Install Arguments / Notes' -Control $txtModArgs -HelpText 'Optional mod-related launch or install notes. Custom Game does not validate these values.'

    $txtWorkingDir = New-UGSMGameCUSTOMTextBox -Text (Get-UGSMGameCUSTOMInstanceSetting -Instance $Instance -Name 'WorkingDirectory')
    $txtWorkingDir.Name = 'Custom_WorkingDirectory'
    $txtStartupArgs = New-UGSMGameCUSTOMTextBox -Text (Get-UGSMGameCUSTOMInstanceSetting -Instance $Instance -Name 'StartupArguments') -Multiline -Height 140
    $txtStartupArgs.Name = 'Custom_StartupArguments'
    $txtStopProcessName = New-UGSMGameCUSTOMTextBox -Text (Get-UGSMGameCUSTOMInstanceSetting -Instance $Instance -Name 'StopProcessName')
    $txtStopProcessName.Name = 'Custom_StopProcessName'
    $lblCommandPreview = New-Object System.Windows.Forms.Label
    $lblCommandPreview.AutoSize = $false
    $lblCommandPreview.Width = 760
    $lblCommandPreview.Height = 72
    $lblCommandPreview.BorderStyle = 'FixedSingle'
    $lblCommandPreview.Padding = New-Object System.Windows.Forms.Padding(6)
    $lblCommandPreview.Text = 'Command Preview\r\nConfigure the executable path and any optional startup arguments.'
    New-UGSMGameCUSTOMFieldRow -Parent $startupPanel -Label 'Working Directory (blank = executable folder)' -Control $txtWorkingDir -HelpText 'Optional. Leave blank to use the executable folder.'
    New-UGSMGameCUSTOMFieldRow -Parent $startupPanel -Label 'Startup Arguments' -Control $txtStartupArgs -HelpText 'Enter everything after the executable. Leave blank to start the server with the executable only. Example: TheIsland_WP?listen?SessionName=MyServer -port=7777 -queryport=27015 -log'
    New-UGSMGameCUSTOMFieldRow -Parent $startupPanel -Label 'Fallback Stop Process Name (optional)' -Control $txtStopProcessName -HelpText 'Optional process name used only if the tracked pid is unavailable. Example: ArkAscendedServer.exe'
    New-UGSMGameCUSTOMFieldRow -Parent $startupPanel -Label 'Command Preview' -Control $lblCommandPreview -HelpText 'UGSM will launch the executable with the arguments exactly as shown below.'

    $updateCommandPreview = {
        $exePath = $txtServerExe.Text.Trim()
        if ([string]::IsNullOrWhiteSpace($exePath)) {
            $installPathValue = $txtInstallPath.Text.Trim()
            $relativeValue = $txtExeRelative.Text.Trim()
            if ((-not [string]::IsNullOrWhiteSpace($installPathValue)) -and (-not [string]::IsNullOrWhiteSpace($relativeValue))) {
                try { $exePath = [System.IO.Path]::GetFullPath((Join-Path $installPathValue $relativeValue)) } catch { $exePath = (Join-Path $installPathValue $relativeValue) }
            }
        }

        $argValue = $txtStartupArgs.Text.Trim()
        if ([string]::IsNullOrWhiteSpace($exePath) -and [string]::IsNullOrWhiteSpace($argValue)) {
            $lblCommandPreview.Text = "Command Preview`r`nConfigure the executable path and any optional startup arguments."
            return
        }

        $resolved = $exePath
        if (-not [string]::IsNullOrWhiteSpace($resolved)) {
            $ext = [System.IO.Path]::GetExtension($resolved)
            if ($ext -match '^(?i)\.(bat|cmd)$') {
                $cmdExe = Join-Path $env:SystemRoot 'System32\cmd.exe'
                if (-not (Test-Path -LiteralPath $cmdExe -PathType Leaf)) { $cmdExe = 'cmd.exe' }
                $quoted = '"' + $resolved.Replace('"', '""') + '"'
                $resolved = $cmdExe + ' /c ' + $quoted
            }
        }
        if (-not [string]::IsNullOrWhiteSpace($argValue)) {
            if (-not [string]::IsNullOrWhiteSpace($resolved)) {
                $resolved = $resolved + ' ' + $argValue
            }
            else {
                $resolved = $argValue
            }
        }

        $lblCommandPreview.Text = "Command Preview`r`n" + $resolved
    }.GetNewClosure()

    foreach ($tb in @($txtInstallPath, $txtServerExe, $txtExeRelative, $txtStartupArgs)) {
        $tb.Add_TextChanged({ & $updateCommandPreview }.GetNewClosure())
    }
    & $updateCommandPreview


    # Status updates are written directly with Set-UGSMGameCUSTOMControlTextValue.
    # Avoid an indirection scriptblock here because WinForms event closures can
    # occasionally capture a non-scriptblock object and make '& $setStatusText' throw.


    $getEditorTextByName = {
        param([Parameter(Mandatory)][string]$ControlName, [AllowNull()][object]$FallbackControl)
        try {
            $matches = $root.Controls.Find($ControlName, $true)
            if ($matches -and $matches.Count -gt 0) {
                return [string]$matches[0].Text
            }
        }
        catch {}
        return (Get-UGSMGameCUSTOMControlTextValue -Control $FallbackControl)
    }.GetNewClosure()

    $saveEditorValues = {
        # Save directly from the live editor controls. Do not depend on the
        # current Instance object or an older custom.instance.json, because those
        # can contain stale values until the instance cache refreshes.
        $values = [ordered]@{
            Name                   = & $getEditorTextByName 'Custom_DisplayName' $txtDisplayName
            TargetGameKey          = & $getEditorTextByName 'Custom_TargetGameKey' $txtTargetGameKey
            ProfilePath            = & $getEditorTextByName 'Custom_ProfilePath' $txtProfilePath
            SteamAppId             = & $getEditorTextByName 'Custom_SteamAppId' $txtSteamAppId
            InstallPath            = & $getEditorTextByName 'Custom_InstallPath' $txtInstallPath
            ServerExecutablePath   = & $getEditorTextByName 'Custom_ServerExecutablePath' $txtServerExe
            ExecutableRelativePath = & $getEditorTextByName 'Custom_ExecutableRelativePath' $txtExeRelative
            DownloadArguments      = & $getEditorTextByName 'Custom_DownloadArguments' $txtDownloadArgs
            WorkshopItemIds        = & $getEditorTextByName 'Custom_WorkshopItemIds' $txtWorkshopIds
            ModInstallArguments    = & $getEditorTextByName 'Custom_ModInstallArguments' $txtModArgs
            WorkingDirectory       = & $getEditorTextByName 'Custom_WorkingDirectory' $txtWorkingDir
            StartupArguments       = & $getEditorTextByName 'Custom_StartupArguments' $txtStartupArgs
            StopProcessName        = & $getEditorTextByName 'Custom_StopProcessName' $txtStopProcessName
        }

        if ([string]::IsNullOrWhiteSpace([string]$values.Name)) { $values.Name = 'CustomServer' }
        if ([string]::IsNullOrWhiteSpace([string]$values.TargetGameKey)) { $values.TargetGameKey = 'CUSTOM' }

        $values.TargetGameKey = ConvertTo-UGSMGameCUSTOMSafeKey -Value ([string]$values.TargetGameKey) -DefaultValue 'CUSTOM'
        # Always derive the bridge profile path from the current editor values.
        # The visible ProfilePath box is read-only and can be stale if the user
        # renamed the Custom profile during this editor session.
        $values.ProfilePath = Get-UGSMGameCUSTOMProfileRoot -ProfileName ([string]$values.Name) -TargetGameKey ([string]$values.TargetGameKey)
        Set-UGSMGameCUSTOMControlTextValue -Control $txtProfilePath -Text ([string]$values.ProfilePath)

        foreach ($key in $values.Keys) {
            Set-UGSMGameCUSTOMInstanceProperty -Instance $Instance -Name $key -Value $values[$key]
        }

        $profileRoot = [string]$values.ProfilePath
        if (-not (Test-Path -LiteralPath $profileRoot -PathType Container)) {
            New-Item -ItemType Directory -Path $profileRoot -Force | Out-Null
        }

        # Keep the per-profile bridge files in the future native game folder.
        $manifest = [ordered]@{
            GameId                 = 'CUSTOM'
            CreatedBy              = 'CUSTOM'
            TargetGameKey          = [string]$values.TargetGameKey
            NativeImportReady      = $true
            MigrationStatus        = 'CustomBridge'
            Name                   = [string]$values.Name
            ProfilePath            = $profileRoot
            InstallPath            = [string]$values.InstallPath
            SteamAppId             = [string]$values.SteamAppId
            ServerExecutablePath   = [string]$values.ServerExecutablePath
            ExecutableRelativePath = [string]$values.ExecutableRelativePath
            WorkingDirectory       = [string]$values.WorkingDirectory
            StartupArguments       = [string]$values.StartupArguments
            DownloadArguments      = [string]$values.DownloadArguments
            WorkshopItemIds        = [string]$values.WorkshopItemIds
            ModInstallArguments    = [string]$values.ModInstallArguments
            StopProcessName        = [string]$values.StopProcessName
            UpdatedAtUtc           = [DateTime]::UtcNow.ToString('o')
        }

        $json = ($manifest | ConvertTo-Json -Depth 8)

        # Save the bridge manifest to the future/native profile path AND mirror it
        # under the original CUSTOM profile path. Without the CUSTOM mirror, the
        # current instance cache can reopen the old folder and appear to "forget"
        # the edited values until a full migration/import happens.
        $writeRoots = Get-UGSMGameCUSTOMCandidateProfileRoots -Instance $Instance -ProfileName ([string]$values.Name) -TargetGameKey ([string]$values.TargetGameKey) -ExplicitProfilePath $profileRoot
        foreach ($writeRoot in $writeRoots) {
            if (-not (Test-Path -LiteralPath $writeRoot -PathType Container)) {
                New-Item -ItemType Directory -Path $writeRoot -Force | Out-Null
            }
            $json | Set-Content -LiteralPath (Join-Path $writeRoot 'custom.instance.json') -Encoding UTF8
            $json | Set-Content -LiteralPath (Join-Path $writeRoot 'UGSM_CustomProfile.json') -Encoding UTF8
        }

        # Do not call the generic initializer here: it can re-save stale cache values.
        # Save Settings has already created the profile folders and bridge manifests.

        try {
            Write-UGSMLog -Category 'Custom' -Level 'INFO' -Message ('Custom bridge settings saved. Name={0}; TargetGameKey={1}; ProfilePath={2}; InstallPath={3}' -f ([string]$values.Name), ([string]$values.TargetGameKey), $profileRoot, ([string]$values.InstallPath))
        } catch {}

        return [pscustomobject]$manifest
    }.GetNewClosure()

    $syncEditorToProbeInstance = {
        $probe = $Instance.PSObject.Copy()
        foreach ($pair in @(
            @{ Name = 'Name'; Control = $txtDisplayName },
            @{ Name = 'TargetGameKey'; Control = $txtTargetGameKey },
            @{ Name = 'ProfilePath'; Control = $txtProfilePath },
            @{ Name = 'SteamAppId'; Control = $txtSteamAppId },
            @{ Name = 'InstallPath'; Control = $txtInstallPath },
            @{ Name = 'ServerExecutablePath'; Control = $txtServerExe },
            @{ Name = 'ExecutableRelativePath'; Control = $txtExeRelative },
            @{ Name = 'DownloadArguments'; Control = $txtDownloadArgs },
            @{ Name = 'WorkshopItemIds'; Control = $txtWorkshopIds },
            @{ Name = 'ModInstallArguments'; Control = $txtModArgs },
            @{ Name = 'WorkingDirectory'; Control = $txtWorkingDir },
            @{ Name = 'StartupArguments'; Control = $txtStartupArgs },
            @{ Name = 'StopProcessName'; Control = $txtStopProcessName }
        )) {
            $controlRef = $pair['Control']
            $propName = [string]$pair['Name']
            Set-UGSMGameCUSTOMInstanceProperty -Instance $probe -Name $propName -Value (Get-UGSMGameCUSTOMControlTextValue -Control $controlRef)
        }
        return $probe
    }.GetNewClosure()

    $runSteamCmdAction = {
        param([string]$ActionName)
        try {
            & $saveEditorValues | Out-Null
            $probe = & $syncEditorToProbeInstance
            $null = Initialize-UGSMGameCUSTOMProfile -Instance $probe
            Save-UGSMGameCUSTOMManifest -Instance $probe | Out-Null
            $result = Invoke-UGSMGameCUSTOMSteamCmdAction -Instance $probe -Action $ActionName
            Set-UGSMGameCUSTOMControlTextValue -Control $lblInstallStatus -Text $result.Message
            try { if ($lblValidation) { Set-UGSMGameCUSTOMControlTextValue -Control $lblValidation -Text $result.Message } } catch {}
            Set-UGSMGameCUSTOMControlTextValue -Control $StatusLabel -Text ('Custom Game ' + $ActionName + ' finished. ' + $result.Message)
        }
        catch {
            Set-UGSMGameCUSTOMControlTextValue -Control $lblInstallStatus -Text ('SteamCMD ' + $ActionName + ' failed: ' + $_.Exception.Message)
            Set-UGSMGameCUSTOMControlTextValue -Control $StatusLabel -Text (Get-UGSMGameCUSTOMControlTextValue -Control $lblInstallStatus)
        }
    }.GetNewClosure()

    $btnInstallFiles.Add_Click({ & $runSteamCmdAction 'Install' }.GetNewClosure())
    $btnUpdateFiles.Add_Click({ & $runSteamCmdAction 'Update' }.GetNewClosure())
    $btnVerifyFiles.Add_Click({ & $runSteamCmdAction 'Verify' }.GetNewClosure())

    $validationPanel = New-Object System.Windows.Forms.FlowLayoutPanel
    $validationPanel.Dock = 'Top'
    $validationPanel.AutoSize = $true
    $validationPanel.WrapContents = $false
    $validationPanel.FlowDirection = 'LeftToRight'
    $validationPanel.Padding = New-Object System.Windows.Forms.Padding(12,0,12,8)

    $btnSaveSettings = New-Object System.Windows.Forms.Button
    $btnSaveSettings.Text = 'Save Settings'
    $btnSaveSettings.Width = 120
    $btnValidate = New-Object System.Windows.Forms.Button
    $btnValidate.Text = 'Validate Paths'
    $btnValidate.Width = 120
    $btnStartServer = New-Object System.Windows.Forms.Button
    $btnStartServer.Text = 'Start Server'
    $btnStartServer.Width = 120
    $btnStopServer = New-Object System.Windows.Forms.Button
    $btnStopServer.Text = 'Stop Server'
    $btnStopServer.Width = 120
    $lblValidation = New-Object System.Windows.Forms.Label
    $lblValidation.Width = 900
    $lblValidation.Height = 28
    $lblValidation.Text = 'Fill in install and startup values, click Save Settings, then validate or start the instance.'
    [void]$validationPanel.Controls.Add($btnSaveSettings)
    [void]$validationPanel.Controls.Add($btnValidate)
    [void]$validationPanel.Controls.Add($btnStartServer)
    [void]$validationPanel.Controls.Add($btnStopServer)
    [void]$validationPanel.Controls.Add($lblValidation)
    $root.Controls.Add($validationPanel)
    $root.Controls.SetChildIndex($validationPanel, 1)


    $btnSaveSettings.Tag = [pscustomobject]@{
        TxtDisplayName         = $txtDisplayName
        TxtTargetGameKey       = $txtTargetGameKey
        TxtProfilePath         = $txtProfilePath
        TxtSteamAppId          = $txtSteamAppId
        TxtInstallPath         = $txtInstallPath
        TxtServerExe           = $txtServerExe
        TxtExeRelative         = $txtExeRelative
        TxtDownloadArgs        = $txtDownloadArgs
        TxtWorkshopIds         = $txtWorkshopIds
        TxtModArgs             = $txtModArgs
        TxtWorkingDir          = $txtWorkingDir
        TxtStartupArgs         = $txtStartupArgs
        TxtStopProcessName     = $txtStopProcessName
        LblValidation          = $lblValidation
        StatusLabel            = $StatusLabel
        Instance               = $Instance
    }

    $btnSaveSettings.Add_Click({
        param($sender, $eventArgs)
        try {
            Write-UGSMLog -Category 'Custom' -Level 'INFO' -Message 'Custom bridge internal Save Settings button clicked.'

            $tag = $sender.Tag
            if ($null -eq $tag) { throw 'Save failed: button tag state was missing.' }

            $readText = {
                param([object]$Control)
                if ($null -eq $Control) { return '' }
                try { return [string]$Control.Text } catch { return '' }
            }

            $name = (& $readText $tag.TxtDisplayName).Trim()
            if ([string]::IsNullOrWhiteSpace($name)) { $name = 'CustomServer' }

            $target = (& $readText $tag.TxtTargetGameKey).Trim()
            if ([string]::IsNullOrWhiteSpace($target)) { $target = 'CUSTOM' }
            $target = ConvertTo-UGSMGameCUSTOMSafeKey -Value $target -DefaultValue 'CUSTOM'

            $profileRoot = Get-UGSMGameCUSTOMProfileRoot -ProfileName $name -TargetGameKey $target
            try { $tag.TxtProfilePath.Text = $profileRoot } catch {}

            $manifest = [ordered]@{
                GameId                 = 'CUSTOM'
                CreatedBy              = 'CUSTOM'
                TargetGameKey          = $target
                NativeImportReady      = $true
                MigrationStatus        = 'CustomBridge'
                Name                   = $name
                ProfilePath            = $profileRoot
                InstallPath            = (& $readText $tag.TxtInstallPath)
                SteamAppId             = (& $readText $tag.TxtSteamAppId)
                ServerExecutablePath   = (& $readText $tag.TxtServerExe)
                ExecutableRelativePath = (& $readText $tag.TxtExeRelative)
                WorkingDirectory       = (& $readText $tag.TxtWorkingDir)
                StartupArguments       = (& $readText $tag.TxtStartupArgs)
                DownloadArguments      = (& $readText $tag.TxtDownloadArgs)
                WorkshopItemIds        = (& $readText $tag.TxtWorkshopIds)
                ModInstallArguments    = (& $readText $tag.TxtModArgs)
                StopProcessName        = (& $readText $tag.TxtStopProcessName)
                UpdatedAtUtc           = [DateTime]::UtcNow.ToString('o')
            }

            foreach ($key in @('Name','TargetGameKey','ProfilePath','SteamAppId','InstallPath','ServerExecutablePath','ExecutableRelativePath','DownloadArguments','WorkshopItemIds','ModInstallArguments','WorkingDirectory','StartupArguments','StopProcessName')) {
                try { Set-UGSMGameCUSTOMInstanceProperty -Instance $tag.Instance -Name $key -Value $manifest[$key] } catch {}
            }

            $customMirror = Join-Path (Get-UGSMGameCUSTOMProfileBaseRoot) (Join-Path 'CUSTOM' $name)
            $writeRoots = New-Object System.Collections.Generic.List[string]
            foreach ($candidate in @([string]$profileRoot, [string]$customMirror)) {
                if (-not [string]::IsNullOrWhiteSpace($candidate) -and -not $writeRoots.Contains($candidate)) {
                    [void]$writeRoots.Add($candidate)
                }
            }

            $json = ($manifest | ConvertTo-Json -Depth 8)
            foreach ($writeRoot in $writeRoots) {
                foreach ($path in @($writeRoot, (Join-Path $writeRoot 'Mods'), (Join-Path $writeRoot 'Config'), (Join-Path $writeRoot 'Logs'))) {
                    if (-not (Test-Path -LiteralPath $path -PathType Container)) {
                        New-Item -ItemType Directory -Path $path -Force | Out-Null
                    }
                }
                $json | Set-Content -LiteralPath (Join-Path $writeRoot 'custom.instance.json') -Encoding UTF8
                $json | Set-Content -LiteralPath (Join-Path $writeRoot 'UGSM_CustomProfile.json') -Encoding UTF8
            }

            $probe = [pscustomobject]$manifest
            $validation = Test-UGSMGameCUSTOMInstall -Instance $probe
            if ($validation.ServerExecutableExists) {
                Set-UGSMGameCUSTOMControlTextValue -Control $tag.LblValidation -Text ('Saved Custom Game settings. Target={0}; Profile={1}. Executable found and ready to start.' -f $target, $profileRoot)
            }
            elseif (-not [string]::IsNullOrWhiteSpace([string]$validation.ServerExecutablePath)) {
                Set-UGSMGameCUSTOMControlTextValue -Control $tag.LblValidation -Text ('Saved Custom Game settings. Target={0}; Profile={1}. Executable not found yet: {2}' -f $target, $profileRoot, [string]$validation.ServerExecutablePath)
            }
            else {
                Set-UGSMGameCUSTOMControlTextValue -Control $tag.LblValidation -Text ('Saved Custom Game settings. Target={0}; Profile={1}. Configure the executable path before starting the instance.' -f $target, $profileRoot)
            }
            Set-UGSMGameCUSTOMControlTextValue -Control $tag.StatusLabel -Text (Get-UGSMGameCUSTOMControlTextValue -Control $tag.LblValidation)

            Write-UGSMLog -Category 'Custom' -Level 'INFO' -Message ('Custom bridge direct save completed. Name={0}; TargetGameKey={1}; ProfilePath={2}; MirrorPath={3}' -f $name, $target, $profileRoot, $customMirror)
        }
        catch {
            try { Write-UGSMLog -Category 'Custom' -Level 'ERROR' -Message ('Custom bridge direct save failed: ' + $_.Exception.Message) -Exception $_.Exception } catch {}
            try { Set-UGSMGameCUSTOMControlTextValue -Control $sender.Tag.LblValidation -Text ('Save failed: ' + $_.Exception.Message) } catch {}
            try { Set-UGSMGameCUSTOMControlTextValue -Control $sender.Tag.StatusLabel -Text ('Save failed: ' + $_.Exception.Message) } catch {}
        }
    })

    $btnValidate.Add_Click({
        try {
            $probe = [pscustomobject]@{
                Name                   = $txtDisplayName.Text
                TargetGameKey          = $txtTargetGameKey.Text
                ProfilePath            = $txtProfilePath.Text
                InstallPath            = $txtInstallPath.Text
                SteamAppId             = $txtSteamAppId.Text
                ServerExecutablePath   = $txtServerExe.Text
                ExecutableRelativePath = $txtExeRelative.Text
                WorkingDirectory       = $txtWorkingDir.Text
                StartupArguments       = $txtStartupArgs.Text
                StopProcessName        = $txtStopProcessName.Text
            }
            $result = Test-UGSMGameCUSTOMInstall -Instance $probe
            if ($result.ServerExecutableExists) {
                Set-UGSMGameCUSTOMControlTextValue -Control $lblValidation -Text 'Executable found. Custom Game should be ready to start after save.'
            }
            elseif (-not [string]::IsNullOrWhiteSpace([string]$result.ServerExecutablePath)) {
                Set-UGSMGameCUSTOMControlTextValue -Control $lblValidation -Text ('Executable not found: ' + [string]$result.ServerExecutablePath)
            }
            else {
                Set-UGSMGameCUSTOMControlTextValue -Control $lblValidation -Text 'No executable path is configured yet.'
            }
        }
        catch {
            Set-UGSMGameCUSTOMControlTextValue -Control $lblValidation -Text ('Validation failed: ' + $_.Exception.Message)
        }
    })

    $btnStartServer.Add_Click({
        try {
            & $saveEditorValues | Out-Null
            $result = Start-UGSMGameCUSTOMInstance -Instance $Instance
            Set-UGSMGameCUSTOMControlTextValue -Control $lblValidation -Text ('Started Custom Game server. PID: ' + [string]$result.Pid)
            Set-UGSMGameCUSTOMControlTextValue -Control $StatusLabel -Text (Get-UGSMGameCUSTOMControlTextValue -Control $lblValidation)
        }
        catch {
            Set-UGSMGameCUSTOMControlTextValue -Control $lblValidation -Text ('Start failed: ' + $_.Exception.Message)
            Set-UGSMGameCUSTOMControlTextValue -Control $StatusLabel -Text (Get-UGSMGameCUSTOMControlTextValue -Control $lblValidation)
        }
    })

    $btnStopServer.Add_Click({
        try {
            $result = Stop-UGSMGameCUSTOMInstance -Instance $Instance
            Set-UGSMGameCUSTOMControlTextValue -Control $lblValidation -Text 'Stopped Custom Game server.'
            Set-UGSMGameCUSTOMControlTextValue -Control $StatusLabel -Text (Get-UGSMGameCUSTOMControlTextValue -Control $lblValidation)
        }
        catch {
            Set-UGSMGameCUSTOMControlTextValue -Control $lblValidation -Text ('Stop failed: ' + $_.Exception.Message)
            Set-UGSMGameCUSTOMControlTextValue -Control $StatusLabel -Text (Get-UGSMGameCUSTOMControlTextValue -Control $lblValidation)
        }
    })

    Set-UGSMGameCUSTOMControlTheme -Control $root

    Set-UGSMGameCUSTOMControlTextValue -Control $StatusLabel -Text 'Custom Game editor loaded. Use Save Settings after changing install, mods, or startup values.'

    return [pscustomobject]@{
        Root = $root
        Controls = [ordered]@{
            Name                   = $txtDisplayName
            TargetGameKey          = $txtTargetGameKey
            ProfilePath            = $txtProfilePath
            SteamAppId             = $txtSteamAppId
            InstallPath            = $txtInstallPath
            ServerExecutablePath   = $txtServerExe
            ExecutableRelativePath = $txtExeRelative
            DownloadArguments      = $txtDownloadArgs
            WorkshopItemIds        = $txtWorkshopIds
            ModInstallArguments    = $txtModArgs
            WorkingDirectory       = $txtWorkingDir
            StartupArguments       = $txtStartupArgs
            StopProcessName        = $txtStopProcessName
        }
    }
}


function Save-UGSMGameCUSTOMInstanceEditor {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$Instance,
        [Parameter(Mandatory)][hashtable]$EditorState
    )

    try { Write-UGSMLog -Category 'Custom' -Level 'INFO' -Message 'Custom bridge SaveEditor invoked from host Save Settings.' } catch {}

    if (-not $EditorState.ContainsKey('Controls')) {
        throw 'CUSTOM save failed: editor controls were not supplied.'
    }

    $controls = $EditorState.Controls

    $readControl = {
        param([string]$Name, [string]$DefaultValue = '')
        try {
            $ctrl = $null
            if ($controls -is [System.Collections.IDictionary]) {
                if ($controls.Contains($Name)) { $ctrl = $controls[$Name] }
            }
            else {
                try { $ctrl = $controls.$Name } catch {}
            }
            if ($null -ne $ctrl -and $ctrl.PSObject.Properties['Text']) {
                return [string]$ctrl.Text
            }
            if ($null -ne $ctrl -and $ctrl.GetType().GetProperty('Text')) {
                return [string]$ctrl.Text
            }
        } catch {}
        return $DefaultValue
    }

    $name = (& $readControl 'Name' ([string](Get-UGSMGameCUSTOMInstanceSetting -Instance $Instance -Name 'Name' -DefaultValue 'CustomServer'))).Trim()
    if ([string]::IsNullOrWhiteSpace($name)) { $name = 'CustomServer' }

    $target = (& $readControl 'TargetGameKey' ([string](Get-UGSMGameCUSTOMInstanceSetting -Instance $Instance -Name 'TargetGameKey' -DefaultValue 'CUSTOM'))).Trim()
    if ([string]::IsNullOrWhiteSpace($target)) { $target = 'CUSTOM' }
    $target = ConvertTo-UGSMGameCUSTOMSafeKey -Value $target -DefaultValue 'CUSTOM'

    $values = [ordered]@{
        Name                   = $name
        TargetGameKey          = $target
        SteamAppId             = (& $readControl 'SteamAppId' '')
        InstallPath            = (& $readControl 'InstallPath' '')
        ServerExecutablePath   = (& $readControl 'ServerExecutablePath' '')
        ExecutableRelativePath = (& $readControl 'ExecutableRelativePath' '')
        DownloadArguments      = (& $readControl 'DownloadArguments' '')
        WorkshopItemIds        = (& $readControl 'WorkshopItemIds' '')
        ModInstallArguments    = (& $readControl 'ModInstallArguments' '')
        WorkingDirectory       = (& $readControl 'WorkingDirectory' '')
        StartupArguments       = (& $readControl 'StartupArguments' '')
        StopProcessName        = (& $readControl 'StopProcessName' '')
    }

    $profileRoot = Get-UGSMGameCUSTOMProfileRoot -ProfileName $name -TargetGameKey $target
    $values['ProfilePath'] = $profileRoot

    foreach ($key in $values.Keys) {
        Set-UGSMGameCUSTOMInstanceProperty -Instance $Instance -Name $key -Value $values[$key]
    }

    foreach ($path in @($profileRoot, (Join-Path $profileRoot 'Mods'), (Join-Path $profileRoot 'Config'), (Join-Path $profileRoot 'Logs'))) {
        if (-not (Test-Path -LiteralPath $path -PathType Container)) {
            New-Item -ItemType Directory -Path $path -Force | Out-Null
        }
    }

    $manifest = [ordered]@{
        GameId                 = 'CUSTOM'
        CreatedBy              = 'CUSTOM'
        TargetGameKey          = [string]$values.TargetGameKey
        NativeImportReady      = $true
        MigrationStatus        = 'CustomBridge'
        Name                   = [string]$values.Name
        ProfilePath            = [string]$values.ProfilePath
        InstallPath            = [string]$values.InstallPath
        SteamAppId             = [string]$values.SteamAppId
        ServerExecutablePath   = [string]$values.ServerExecutablePath
        ExecutableRelativePath = [string]$values.ExecutableRelativePath
        WorkingDirectory       = [string]$values.WorkingDirectory
        StartupArguments       = [string]$values.StartupArguments
        DownloadArguments      = [string]$values.DownloadArguments
        WorkshopItemIds        = [string]$values.WorkshopItemIds
        ModInstallArguments    = [string]$values.ModInstallArguments
        StopProcessName        = [string]$values.StopProcessName
        UpdatedAtUtc           = [DateTime]::UtcNow.ToString('o')
    }

    $json = ($manifest | ConvertTo-Json -Depth 8)

    $customMirror = Join-Path (Get-UGSMGameCUSTOMProfileBaseRoot) (Join-Path 'CUSTOM' $name)
    $writeRoots = New-Object System.Collections.Generic.List[string]
    foreach ($candidate in @([string]$profileRoot, [string]$customMirror)) {
        if (-not [string]::IsNullOrWhiteSpace($candidate) -and -not $writeRoots.Contains($candidate)) {
            [void]$writeRoots.Add($candidate)
        }
    }

    foreach ($writeRoot in $writeRoots) {
        if (-not (Test-Path -LiteralPath $writeRoot -PathType Container)) {
            New-Item -ItemType Directory -Path $writeRoot -Force | Out-Null
        }
        $json | Set-Content -LiteralPath (Join-Path $writeRoot 'custom.instance.json') -Encoding UTF8
        $json | Set-Content -LiteralPath (Join-Path $writeRoot 'UGSM_CustomProfile.json') -Encoding UTF8
    }

    try {
        Write-UGSMLog -Category 'Custom' -Level 'INFO' -Message ('Custom bridge settings saved by SaveEditor. Name={0}; TargetGameKey={1}; ProfilePath={2}; MirrorPath={3}' -f $name, $target, $profileRoot, $customMirror)
    } catch {}

    return [pscustomobject]@{
        Success    = $true
        Message    = ('Saved Custom bridge settings. Target={0}; Profile={1}' -f $target, $profileRoot)
        Manifest   = [pscustomobject]$manifest
        Validation = (Test-UGSMGameCUSTOMInstall -Instance ([pscustomobject]$manifest))
    }
}


function Register-UGSMGameCUSTOMModule {
    [CmdletBinding()]
    param()

    $metadata = Get-UGSMGameCUSTOMMetadata

    return [pscustomobject]@{
        Id       = [string]$metadata.Id
        Metadata = $metadata
        Handlers = [pscustomobject]@{
            GetMetadata       = 'Get-UGSMGameCUSTOMMetadata'
            TestInstall       = 'Test-UGSMGameCUSTOMInstall'
            TestInstance      = 'Test-UGSMGameCUSTOMInstance'
            EnsureTemplate    = 'Ensure-UGSMGameCUSTOMTemplate'
            InitializeProfile = 'Initialize-UGSMGameCUSTOMProfile'
            Start             = 'Start-UGSMGameCUSTOMInstance'
            Stop              = 'Stop-UGSMGameCUSTOMInstance'
            BuildEditor       = 'New-UGSMGameCUSTOMInstanceEditor'
            SaveEditor        = 'Save-UGSMGameCUSTOMInstanceEditor'
        }
    }
}
