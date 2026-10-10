# DayZ

function Write-UGSMGameDayZPathLog {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Message,
        [ValidateSet('Debug', 'Info', 'Warn', 'Error')][string]$Level = 'Info'
    )

    try {
        Write-UGSMLogEntry -Category 'DayZ' -Message $Message -Level $Level
    }
    catch {
    }
}

function Test-UGSMGameDayZTraderPlusEnabled {
    param([Parameter(Mandatory)][object]$Instance)
    foreach ($mod in @(Get-UGSMGameDayZStoredMods -Instance $Instance)) {
        if ($mod.Id -eq '2458896948' -or $mod.Name -like '*TraderPlus*') { return $true }
    }
    return $false
}

function Test-UGSMGameDayZExpansionMarketEnabled {
    param([Parameter(Mandatory)][object]$Instance)
    foreach ($mod in @(Get-UGSMGameDayZStoredMods -Instance $Instance)) {
        if ($mod.Id -eq '2116151622' -or $mod.Name -like '*Expansion-Market*') { return $true }
    }
    return $false
}

function Get-UGSMGameDayZNominalMap {
    param([Parameter(Mandatory)][string]$TypesPath)
    $map = @{}
    if (-not (Test-Path -LiteralPath $TypesPath -PathType Leaf)) { return $map }
    try {
        [xml]$xml = Get-Content -LiteralPath $TypesPath -Raw
        foreach ($node in @($xml.SelectNodes("//type"))) {
            $name = $node.GetAttribute("name")
            $nominalNode = $node.SelectSingleNode("nominal")
            if ($name -and $nominalNode) {
                $map[$name.ToLowerInvariant()] = [int]$nominalNode.InnerText
            }
        }
    }
    catch { Write-UGSMGameDayZPathLog -Message "Failed to build nominal map: $($_.Exception.Message)" -Level 'Warn' }
    return $map
}

function Get-UGSMGameDayZItemTraderBalance {
    param([int]$Nominal)
    $safeNom = [Math]::Max(1, $Nominal)
    return [pscustomobject]@{
        BuyPrice  = [int](150000 / ($safeNom + 10)) # Rarer = much more expensive
        SellPrice = [int](75000 / ($safeNom + 10))
        MaxStock  = [Math]::Max(1, [int](150 / ($safeNom / 5 + 1))) # Rarer = Trader holds more
    }
}

function Resolve-UGSMGameDayZTypesXmlPath {
    [CmdletBinding()]
    param([Parameter(Mandatory)][object]$Instance)

    if (Get-Command -Name Get-UGSMDayZTypesXmlPath -ErrorAction SilentlyContinue) {
        $resolved = Get-UGSMDayZTypesXmlPath -Instance $Instance
        if (-not [string]::IsNullOrWhiteSpace([string]$resolved) -and (Test-Path -LiteralPath $resolved -PathType Leaf)) { return [string]$resolved }
    }

    try {
        $paths = Get-UGSMGameDayZProfilePaths -Instance $Instance
        foreach ($candidate in @(
                (Join-Path ([string]$paths.RuntimeMissionPath) 'db\types.xml'),
                (Join-Path ([string]$paths.ProfileRoot) 'mpmissions\dayzOffline.chernarusplus\db\types.xml'),
                (Join-Path ([string]$paths.ProfileRoot) 'mpmissions\dayzOffline.enoch\db\types.xml'),
                (Join-Path ([string]$paths.ProfileRoot) 'mpmissions\dayzOffline.sakhal\db\types.xml')
            )) {
            if (-not [string]::IsNullOrWhiteSpace([string]$candidate) -and (Test-Path -LiteralPath $candidate -PathType Leaf)) { return [string]$candidate }
        }
    }
    catch { }

    return ''
}


function Resolve-UGSMGameDayZTraderPlusDefaultConfigSourceRoot {
    [CmdletBinding()]
    param([Parameter(Mandatory)][object]$Instance)

    $modMatch = $null
    foreach ($mod in @(Get-UGSMGameDayZStoredMods -Instance $Instance)) {
        $modId = [string]$(if ($mod.PSObject.Properties.Name -contains 'Id') { $mod.Id } else { '' })
        $modName = [string]$(if ($mod.PSObject.Properties.Name -contains 'Name') { $mod.Name } else { '' })
        if ($modId -eq '2458896948' -or $modName -like '*TraderPlus*') {
            $modMatch = $mod
            break
        }
    }
    if ($null -eq $modMatch) { return '' }

    try {
        $sourcePath = Resolve-UGSMGameDayZWorkshopModSourcePath -Instance $Instance -Mod $modMatch
        if ([string]::IsNullOrWhiteSpace([string]$sourcePath)) { return '' }

        $configRoot = Join-Path ([string]$sourcePath) 'ServerProfile\TraderPlus\TraderPlusConfig'
        if (Test-Path -LiteralPath $configRoot -PathType Container) {
            return [string]$configRoot
        }
    }
    catch {
    }

    return ''
}

function Ensure-UGSMGameDayZTraderPlusDefaultConfigFiles {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$Instance,
        [AllowNull()][object]$Runtime
    )

    $result = [pscustomobject]@{
        Enabled      = $false
        SourceRoot   = ''
        TargetRoots  = @()
        Copied       = @()
        Missing      = @()
        Errors       = @()
    }

    if (-not (Test-UGSMGameDayZTraderPlusEnabled -Instance $Instance)) {
        return $result
    }

    $result.Enabled = $true

    if (-not $Runtime) {
        try {
            $installDefinition = Get-UGSMGameDayZInstallDefinition -InstallPath $Instance.InstallPath -Instance $Instance
            $Runtime = Ensure-UGSMGameDayZRuntimeLayout -Instance $Instance -InstallDefinition $installDefinition
        }
        catch {
        }
    }

    $sourceRoot = Resolve-UGSMGameDayZTraderPlusDefaultConfigSourceRoot -Instance $Instance
    $result.SourceRoot = [string]$sourceRoot
    if ([string]::IsNullOrWhiteSpace([string]$sourceRoot) -or -not (Test-Path -LiteralPath $sourceRoot -PathType Container)) {
        $result.Errors += 'TraderPlus default config source root could not be resolved.'
        return $result
    }

    $paths = $null
    try { $paths = Get-UGSMGameDayZProfilePaths -Instance $Instance } catch { $paths = $null }

    $targetRoots = New-Object System.Collections.Generic.List[string]
    if ($Runtime -and $Runtime.PSObject.Properties.Name -contains 'RuntimeProfilesRoot' -and -not [string]::IsNullOrWhiteSpace([string]$Runtime.RuntimeProfilesRoot)) {
        $targetRoots.Add((Join-Path ([string]$Runtime.RuntimeProfilesRoot) 'TraderPlus\TraderPlusConfig'))
    }
    if ($paths -and $paths.PSObject.Properties.Name -contains 'ProfileRoot' -and -not [string]::IsNullOrWhiteSpace([string]$paths.ProfileRoot)) {
        $targetRoots.Add((Join-Path ([string]$paths.ProfileRoot) 'profiles\TraderPlus\TraderPlusConfig'))
    }

    $uniqueTargetRoots = @($targetRoots | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) } | Select-Object -Unique)
    $result.TargetRoots = $uniqueTargetRoots

    $fileNames = @('TraderPlusIDsConfig.json', 'TraderPlusPriceConfig.json')

    foreach ($targetRoot in $uniqueTargetRoots) {
        try {
            if (-not (Test-Path -LiteralPath $targetRoot -PathType Container)) {
                New-Item -ItemType Directory -Path $targetRoot -Force | Out-Null
            }

            foreach ($fileName in $fileNames) {
                $sourcePath = Join-Path ([string]$sourceRoot) $fileName
                $targetPath = Join-Path ([string]$targetRoot) $fileName

                if (-not (Test-Path -LiteralPath $sourcePath -PathType Leaf)) {
                    $result.Missing += $sourcePath
                    continue
                }

                if (Test-Path -LiteralPath $targetPath -PathType Leaf) {
                    continue
                }

                Copy-Item -LiteralPath $sourcePath -Destination $targetPath -Force
                $result.Copied += $targetPath
            }
        }
        catch {
            $result.Errors += $_.Exception.Message
        }
    }

    return $result
}


function Resolve-UGSMGameDayZTraderPlusPriceConfigPath {
    [CmdletBinding()]
    param([Parameter(Mandatory)][object]$Instance)

    if (Get-Command -Name Get-UGSMGameDayZTraderPlusJsonFiles -ErrorAction SilentlyContinue) {
        $file = @(Get-UGSMGameDayZTraderPlusJsonFiles -Instance $Instance | Where-Object { $_.Name -eq 'TraderPlusPriceConfig.json' } | Select-Object -First 1)
        if ($file.Count -gt 0 -and -not [string]::IsNullOrWhiteSpace([string]$file[0].FullName)) { return [string]$file[0].FullName }
    }

    return ''
}

function Invoke-UGSMGameDayZEconomySync {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory)][object]$Instance,
        [string]$TypesPath,
        [string]$TraderPlusPriceConfigPath,
        [switch]$SyncTraderPlus,
        [switch]$SyncExpansionMarket,
        [switch]$AddMissingItems,
        [switch]$UpdateStockFromNominal,
        [string]$DefaultTraderPlusCategoryName = 'AUTO_IMPORTED_ITEMS',
        [string]$TraderPlusSkipNamePattern = 'Default|Base|BanditAI_',
        [string]$ExpansionTargetFileName = 'UGSM_Generated.json'
    )

    if ([string]::IsNullOrWhiteSpace($TypesPath)) {
        $TypesPath = Resolve-UGSMGameDayZTypesXmlPath -Instance $Instance
    }
    if ([string]::IsNullOrWhiteSpace($TypesPath) -or -not (Test-Path -LiteralPath $TypesPath -PathType Leaf)) {
        throw 'Economy sync failed: types.xml could not be resolved.'
    }

    $reports = New-Object System.Collections.ArrayList

    if ($SyncTraderPlus) {
        if ([string]::IsNullOrWhiteSpace($TraderPlusPriceConfigPath)) {
            $TraderPlusPriceConfigPath = Resolve-UGSMGameDayZTraderPlusPriceConfigPath -Instance $Instance
        }
        if ([string]::IsNullOrWhiteSpace($TraderPlusPriceConfigPath) -or -not (Test-Path -LiteralPath $TraderPlusPriceConfigPath -PathType Leaf)) {
            throw 'Economy sync failed: TraderPlusPriceConfig.json could not be resolved.'
        }
        if (-not (Get-Command -Name Sync-UGSMGameDayZTraderPlusPriceConfigWithTypes -ErrorAction SilentlyContinue)) {
            throw 'Economy sync failed: TraderPlus sync function is not loaded.'
        }

        $tpReport = Sync-UGSMGameDayZTraderPlusPriceConfigWithTypes `
            -PriceConfigPath $TraderPlusPriceConfigPath `
            -TypesPath $TypesPath `
            -DefaultCategoryName $DefaultTraderPlusCategoryName `
            -SkipNamePattern $TraderPlusSkipNamePattern `
            -AddMissingItems:$AddMissingItems `
            -UpdateStockFromNominal:$UpdateStockFromNominal
        [void]$reports.Add($tpReport)
    }

    if ($SyncExpansionMarket) {
        if (-not (Get-Command -Name Add-UGSMGameDayZMissingTypesToExpansionMarket -ErrorAction SilentlyContinue)) {
            throw 'Economy sync failed: Expansion Market sync function is not loaded.'
        }

        $expReport = Add-UGSMGameDayZMissingTypesToExpansionMarket `
            -Instance $Instance `
            -TypesPath $TypesPath `
            -TargetFileName $ExpansionTargetFileName `
            -UpdateStockFromNominal:$UpdateStockFromNominal
        [void]$reports.Add($expReport)
    }

    return [pscustomobject]@{
        InstanceName           = [string]$Instance.Name
        TypesPath              = [string]$TypesPath
        SyncTraderPlus         = [bool]$SyncTraderPlus
        SyncExpansionMarket    = [bool]$SyncExpansionMarket
        AddMissingItems        = [bool]$AddMissingItems
        UpdateStockFromNominal = [bool]$UpdateStockFromNominal
        Reports                = @($reports)
    }
}

function Write-UGSMGameDayZDebug {
    param(
        [string]$Message
    )

    try {
        Write-UGSMGameDayZPathLog -Message $Message -Level 'Debug'
    }
    catch {
    }
}

function Get-UGSMGameDayZMetadata {
    [CmdletBinding()]
    param()

    return [pscustomobject]@{
        Id                       = 'DayZ'
        Name                     = 'DayZ'
        Category                 = 'Survival'
        Description              = 'DayZ module.'
        IsCustom                 = $false
        SupportTier              = 'Full'
        SortOrder                = 9999
        IsVisible                = $true

        SupportedTabs            = @('Home', 'Games', 'Instances', 'Analytics', 'Tasks', 'Files', 'About', 'Settings', 'Mods')
        UseSteamArt              = $true

        SupportsInstall          = $true
        SupportsVerify           = $true
        SupportsRepair           = $true
        SupportsStart            = $true
        SupportsStop             = $true
        SupportsMods             = $true
        SupportsWorkshop         = $true
        SupportsRcon             = $false
        SupportsBootstrap        = $true
        SupportsProfiles         = $true
        SupportsInstanceUi       = $true

        InstallProvider          = 'SteamCMD'
        RequiresSteamLogin       = $true
        SteamAppId               = '223350'
        SteamToolAppId           = '223350'
        SteamStoreAppId          = '221100'
        ServerExecutable         = 'DayZServer_x64.exe'
        ServerExecutableRelative = 'DayZServer_x64.exe'
        UsesSharedBinaries       = $true
        InstanceType             = 'DedicatedServer'

        ConfigRootRelative       = 'profiles'
        SaveRootRelative         = 'mpmissions'
        LogRootRelative          = 'profiles'

        RequiredFiles            = @(
            'DayZServer_x64.exe'
        )

        InstallMarkers           = @(
            'DayZServer_x64.exe'
            'addons'
            'mpmissions'
        )

        PortSchema               = @(
            @{ Name = 'GamePort'; Protocol = 'UDP'; PreferredStart = 2302 }
            @{ Name = 'SteamQuery'; Protocol = 'UDP'; PreferredStart = 27016 }
            @{ Name = 'RconPort'; Protocol = 'TCP'; PreferredStart = 2305 }
        )

        GameTraits               = [pscustomobject]@{
            UsesIniFiles          = $false
            UsesJsonFiles         = $true
            UsesXmlFiles          = $true
            UsesCfgFiles          = $true
            UsesSqlite            = $false
            UsesProfileSync       = $false
            UsesPluginFramework   = $false
            UsesZipMods           = $false
            UsesFolderCopyMods    = $true
            UsesFileMergeWorkflow = $true
            UsesMissionFiles      = $true
            UsesWorkshopItems     = $true
        }

        SpecialRequirements      = [pscustomobject]@{
            Notes = @(
                'DayZ is a work in progress.'
            )
        }
    }
}


function Get-UGSMGameDayZInstallDefinition {
    [CmdletBinding()]
    param(
        [string]$InstallPath,
        [object]$Instance
    )

    $settings = $null
    if (Get-Command -Name Get-UGSMGlobalSettings -ErrorAction SilentlyContinue) {
        try { $settings = Get-UGSMGlobalSettings -CreateIfMissing } catch { $settings = $null }
    }

    $steamRoot = $null
    if ($settings) {
        foreach ($propName in @('SteamCmdPath', 'SteamCmdRoot', 'SteamRoot')) {
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
        throw 'DayZ install definition failed: Steam root could not be resolved.'
    }

    $meta = Get-UGSMGameDayZMetadata
    $canonicalInstallPath = Join-Path $steamRoot 'steamapps\common\DayZServer'

    if ([string]::IsNullOrWhiteSpace($InstallPath)) {
        $InstallPath = $canonicalInstallPath
    }
    else {
        $leaf = Split-Path -Leaf $InstallPath
        if ($leaf -ne 'DayZServer') {
            $InstallPath = $canonicalInstallPath
        }
    }

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
        MainConfigPath       = Join-Path $InstallPath 'serverDZ.cfg'
    }
}


function Get-UGSMGameDayZAppDataRoot {
    [CmdletBinding()]
    param()

    if (Get-Command -Name Get-UGSMAppDataRoot -ErrorAction SilentlyContinue) {
        return [string](Get-UGSMAppDataRoot)
    }

    return (Join-Path $env:LOCALAPPDATA 'UGSM')
}

function Get-UGSMGameDayZProfileBaseRoot {
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
        $probe = Get-UGSMDefaultInstanceProfilePath -GameId 'DayZ' -Name '_probe_'
        if (-not [string]::IsNullOrWhiteSpace([string]$probe)) {
            return (Split-Path -Parent (Split-Path -Parent $probe))
        }
    }

    return (Join-Path (Get-UGSMGameDayZAppDataRoot) 'Profiles')
}

function Get-UGSMGameDayZDayZRoot {
    [CmdletBinding()]
    param()

    if (Get-Command -Name Get-UGSMAppDataRoot -ErrorAction SilentlyContinue) {
        return [string](Get-UGSMAppDataRoot)
    }

    return (Join-Path $env:LOCALAPPDATA 'UGSM')
}

function Get-UGSMGameDayZProfileRoot {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ProfileName
    )

    return (Join-Path (Join-Path (Get-UGSMGameDayZProfileBaseRoot) 'DayZ') $ProfileName)
}


function Get-UGSMGameDayZRuntimeRoot {
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
            $profileRoot = Get-UGSMGameDayZProfileRoot -ProfileName $candidate
        }
    }

    if ([string]::IsNullOrWhiteSpace([string]$profileRoot)) {
        throw 'DayZ runtime root could not be resolved for the selected instance.'
    }

    return $profileRoot
}

function Remove-UGSMGameDayZPath {
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

function New-UGSMGameDayZDirectoryJunction {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$LinkPath,

        [Parameter(Mandatory)]
        [string]$TargetPath
    )

    if (-not (Test-Path -LiteralPath $TargetPath -PathType Container)) {
        throw "DayZ junction target was not found: $TargetPath"
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
                    if ([string]::Equals($targetFull, $resolvedFull, [System.StringComparison]::OrdinalIgnoreCase)) {
                        return
                    }
                }
                catch {}
            }
        }

        Remove-UGSMGameDayZPath -Path $LinkPath
    }

    try {
        New-Item -ItemType Junction -Path $LinkPath -Target $TargetPath -Force -ErrorAction Stop | Out-Null
    }
    catch {
        $null = & cmd.exe /c ('mklink /J "{0}" "{1}"' -f $LinkPath, $TargetPath)
        if ($LASTEXITCODE -ne 0 -and -not (Test-Path -LiteralPath $LinkPath -PathType Container)) {
            throw "DayZ junction creation failed for '$LinkPath' -> '$TargetPath'."
        }
    }
}

function Copy-UGSMGameDayZFilesToRuntime {
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

    Copy-UGSMGameDayZDirectoryContent -Source $Source -Destination $Destination -ClearDestination:$ClearDestination
}

function Get-UGSMGameDayZRuntimeDefinition {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Instance,

        [Parameter(Mandatory)]
        [object]$InstallDefinition
    )

    $runtimeRoot = Get-UGSMGameDayZRuntimeRoot -Instance $Instance
    $runtimeInstallRoot = $runtimeRoot
    $runtimeProfilesRoot = Join-Path $runtimeInstallRoot 'profiles'
    $runtimeMissionsRoot = Join-Path $runtimeInstallRoot 'mpmissions'
    $runtimeKeysRoot = Join-Path $runtimeInstallRoot 'keys'
    $runtimeAddonsRoot = Join-Path $runtimeInstallRoot 'addons'

    return [pscustomobject]@{
        RuntimeRoot           = $runtimeRoot
        RuntimeInstallRoot    = $runtimeInstallRoot
        RuntimeProfilesRoot   = $runtimeProfilesRoot
        RuntimeMissionsRoot   = $runtimeMissionsRoot
        RuntimeKeysRoot       = $runtimeKeysRoot
        RuntimeAddonsRoot     = $runtimeAddonsRoot

        RuntimeConfigRootPath = $runtimeProfilesRoot
        RuntimeSaveRootPath   = $runtimeMissionsRoot
        RuntimeLogRootPath    = $runtimeProfilesRoot

        RuntimeServerExePath  = Join-Path $runtimeInstallRoot 'DayZServer_x64.exe'
        RuntimeMainConfigPath = Join-Path $runtimeInstallRoot 'serverDZ.cfg'
        SharedInstallPath     = [string]$InstallDefinition.InstallPath
    }
}


function Ensure-UGSMGameDayZRuntimeLayout {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Instance,

        [Parameter(Mandatory)]
        [object]$InstallDefinition
    )

    $runtime = Get-UGSMGameDayZRuntimeDefinition -Instance $Instance -InstallDefinition $InstallDefinition

    foreach ($path in @(
            $runtime.RuntimeRoot,
            $runtime.RuntimeInstallRoot,
            $runtime.RuntimeProfilesRoot,
            $runtime.RuntimeMissionsRoot,
            $runtime.RuntimeKeysRoot,
            $runtime.RuntimeAddonsRoot
        )) {
        if (-not (Test-Path -LiteralPath $path -PathType Container)) {
            New-Item -ItemType Directory -Path $path -Force | Out-Null
        }
    }

    # Runtime profile should be minimal:
    # - serverDZ.cfg
    # - profiles\
    # - mpmissions\
    # - keys\
    # - addons\   (only for intentional server-side/root copied mod payloads)
    # Do NOT mirror the shared DayZ install into the profile runtime.

    if (-not (Test-Path -LiteralPath $runtime.RuntimeMainConfigPath -PathType Leaf) -and
        (Test-Path -LiteralPath $InstallDefinition.MainConfigPath -PathType Leaf)) {
        Copy-Item -LiteralPath $InstallDefinition.MainConfigPath -Destination $runtime.RuntimeMainConfigPath -Force
    }

    if (Test-Path -LiteralPath $InstallDefinition.ConfigRootPath -PathType Container) {
        foreach ($file in @(Get-ChildItem -LiteralPath $InstallDefinition.ConfigRootPath -File -Recurse -Force -ErrorAction SilentlyContinue)) {
            $relative = $file.FullName.Substring(([string]$InstallDefinition.ConfigRootPath).Length).TrimStart('\')
            if ([string]::IsNullOrWhiteSpace($relative)) { continue }

            $targetPath = Join-Path $runtime.RuntimeProfilesRoot $relative
            $targetParent = Split-Path -Parent $targetPath
            if (-not (Test-Path -LiteralPath $targetParent -PathType Container)) {
                New-Item -ItemType Directory -Path $targetParent -Force | Out-Null
            }

            if (-not (Test-Path -LiteralPath $targetPath -PathType Leaf)) {
                Copy-Item -LiteralPath $file.FullName -Destination $targetPath -Force
            }
        }
    }

    if (Test-Path -LiteralPath $InstallDefinition.SaveRootPath -PathType Container) {
        foreach ($item in @(Get-ChildItem -LiteralPath $InstallDefinition.SaveRootPath -Force -ErrorAction SilentlyContinue)) {
            $targetPath = Join-Path $runtime.RuntimeMissionsRoot $item.Name
            if (Test-Path -LiteralPath $targetPath) { continue }

            if ($item.PSIsContainer) {
                Copy-Item -LiteralPath $item.FullName -Destination $targetPath -Recurse -Force -ErrorAction SilentlyContinue
            }
            else {
                Copy-Item -LiteralPath $item.FullName -Destination $targetPath -Force -ErrorAction SilentlyContinue
            }
        }
    }

    return $runtime
}


function Initialize-UGSMGameDayZRuntimeData {
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
        Copy-UGSMGameDayZFilesToRuntime -Source $ProfileConfigRoot -Destination $RuntimeConfigRoot
    }

    if ((Get-ChildItem -LiteralPath $RuntimeSaveRoot -Force -ErrorAction SilentlyContinue | Measure-Object).Count -eq 0) {
        Copy-UGSMGameDayZFilesToRuntime -Source $ProfileSaveRoot -Destination $RuntimeSaveRoot
    }
}

function Copy-UGSMGameDayZDirectoryContent {
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

function Get-UGSMGameDayZRunningBootstrapProcesses {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ServerExecutablePath,

        [Parameter(Mandatory)]
        [datetime]$StartedAfter
    )

    $matches = @()
    try {
        $matches = @(Get-CimInstance Win32_Process -Filter "Name = 'DayZServer.exe'" -ErrorAction Stop)
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

        if (-not [string]::Equals($exePath, $normalizedExe, [System.StringComparison]::OrdinalIgnoreCase)) {
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

function Start-UGSMGameDayZBootstrapProcess {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ServerExecutablePath,

        [Parameter(Mandatory)]
        [string]$WorkingDirectory,

        [int]$BootstrapSeconds = 15
    )

    if (-not (Test-Path -LiteralPath $ServerExecutablePath -PathType Leaf)) {
        throw "DayZ server executable was not found: $ServerExecutablePath"
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

    $remaining = @(Get-Process -Name 'DayZServer' -ErrorAction SilentlyContinue)

    if ($remaining.Count -gt 0) {

        & taskkill.exe /IM DayZServer.exe /T /F
        $fallbackExit = $LASTEXITCODE

        Start-Sleep -Seconds 2

        $remaining = @(Get-Process -Name 'DayZServer' -ErrorAction SilentlyContinue)
        foreach ($p in $remaining) {
            try {
                Stop-Process -Id $p.Id -Force -ErrorAction Stop
            }
            catch {
            }
        }
    }

    Start-Sleep -Seconds 2

    $remainingFinal = @(Get-Process -Name 'DayZServer' -ErrorAction SilentlyContinue)

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

function Ensure-UGSMGameDayZDayZ {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$InstallPath,

        [switch]$ForceRefresh,

        [int]$BootstrapSeconds = 15
    )

    $definition = Get-UGSMGameDayZInstallDefinition -InstallPath $InstallPath
    $validation = Test-UGSMGameDayZInstall -InstallPath $InstallPath
    if (-not $validation.IsValid) {
        throw "DayZ install is not valid at '$InstallPath'."
    }

    $DayZRoot = Get-UGSMGameDayZDayZRoot

    # DayZ install/update calls the optional EnsureTemplate handler after SteamCMD finishes.
    # Keep this bootstrap defensive: install/update should never warn just because DayZ has
    # not generated a profiles folder yet. These template folders are only a cache target.
    $DayZTemplateRoot = Join-Path $DayZRoot 'Templates\DayZ'
    $DayZConfigRoot = Join-Path $DayZTemplateRoot 'Config'
    $DayZSaveRoot = Join-Path $DayZTemplateRoot 'SaveFiles'

    $sourceConfigRoot = [string]$definition.ConfigRootPath
    $sourceSaveRoot = [string]$definition.SaveRootPath

    New-Item -ItemType Directory -Path $DayZRoot -Force | Out-Null
    New-Item -ItemType Directory -Path $DayZTemplateRoot -Force | Out-Null
    New-Item -ItemType Directory -Path $DayZConfigRoot -Force | Out-Null
    New-Item -ItemType Directory -Path $DayZSaveRoot -Force | Out-Null

    $existingTemplateFiles = @(
        Get-ChildItem -LiteralPath $DayZConfigRoot -File -Force -ErrorAction SilentlyContinue
    )

    $sourceConfigFiles = @()
    if (Test-Path -LiteralPath $sourceConfigRoot -PathType Container) {
        $sourceConfigFiles = @(
            Get-ChildItem -LiteralPath $sourceConfigRoot -File -Force -ErrorAction SilentlyContinue
        )
    }

    $copiedConfigFiles = @()
    $bootstrapWarning = $null
    $copiedFromInstall = $false
    $shouldRefreshTemplates = $ForceRefresh.IsPresent -or ($existingTemplateFiles.Count -eq 0)

    if ($shouldRefreshTemplates -and $sourceConfigFiles.Count -gt 0) {
        Copy-UGSMGameDayZDirectoryContent -Source $sourceConfigRoot -Destination $DayZConfigRoot -ClearDestination -IncludeExtensions @('.ini', '.json', '.xml', '.cfg')
        $copiedConfigFiles = @(
            Get-ChildItem -LiteralPath $DayZConfigRoot -File -Force -ErrorAction SilentlyContinue |
            Select-Object -ExpandProperty Name
        )
        $copiedFromInstall = $true
    }
    elseif ($sourceConfigFiles.Count -eq 0) {
        $bootstrapWarning = "DayZ install does not contain generated profile config files yet. Skipping optional template refresh for install/verify/update."
        Write-UGSMGameDayZPathLog -Message $bootstrapWarning -Level 'Debug'
    }
    else {
        $copiedConfigFiles = @($existingTemplateFiles | Select-Object -ExpandProperty Name)
    }

    return [pscustomobject]@{
        GameId               = 'DayZ'
        InstallPath          = $InstallPath
        DayZRoot             = $DayZRoot
        DayZConfigRoot       = $DayZConfigRoot
        DayZSaveRoot         = $DayZSaveRoot
        SourceConfigRoot     = $sourceConfigRoot
        SourceSaveRoot       = $sourceSaveRoot
        BootstrapPerformed   = $false
        BootstrapSkipped     = $true
        BootstrapResult      = $null
        BootstrapWarning     = $bootstrapWarning
        CopiedFromInstall    = $copiedFromInstall
        GeneratedConfigFiles = @($copiedConfigFiles)
    }
}

function Initialize-UGSMGameDayZProfile {
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
    }

    if ([string]::IsNullOrWhiteSpace($effectiveProfileName)) {
        throw 'ProfileName could not be resolved for DayZ profile initialization.'
    }

    if ([string]::IsNullOrWhiteSpace($effectiveInstallPath)) {
        throw 'InstallPath is required to initialize a DayZ profile.'
    }

    $installDef = Get-UGSMGameDayZInstallDefinition -InstallPath $effectiveInstallPath
    if (-not (Test-Path -LiteralPath $installDef.InstallPath -PathType Container)) {
        throw "DayZ install path was not found: $($installDef.InstallPath)"
    }

    $profileRoot = Get-UGSMGameDayZProfileRoot -ProfileName $effectiveProfileName
    if ((Test-Path -LiteralPath $profileRoot -PathType Container) -and $Force) {
        Get-ChildItem -LiteralPath $profileRoot -Force -ErrorAction SilentlyContinue |
        Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
    }

    New-Item -ItemType Directory -Path $profileRoot -Force | Out-Null

    $runtimeInstallRoot = $profileRoot
    $runtimeProfilesRoot = Join-Path $runtimeInstallRoot 'profiles'
    $runtimeMissionsRoot = Join-Path $runtimeInstallRoot 'mpmissions'

    foreach ($path in @($runtimeInstallRoot, $runtimeProfilesRoot, $runtimeMissionsRoot)) {
        if (-not (Test-Path -LiteralPath $path -PathType Container)) {
            New-Item -ItemType Directory -Path $path -Force | Out-Null
        }
    }

    $mainConfigPath = Join-Path $runtimeInstallRoot 'serverDZ.cfg'
    if (-not (Test-Path -LiteralPath $mainConfigPath -PathType Leaf) -and (Test-Path -LiteralPath $installDef.MainConfigPath -PathType Leaf)) {
        Copy-Item -LiteralPath $installDef.MainConfigPath -Destination $mainConfigPath -Force
    }

    if (Test-Path -LiteralPath $installDef.ConfigRootPath -PathType Container) {
        foreach ($file in @(Get-ChildItem -LiteralPath $installDef.ConfigRootPath -File -Recurse -Force -ErrorAction SilentlyContinue)) {
            $relative = $file.FullName.Substring(([string]$installDef.ConfigRootPath).Length).TrimStart('\')
            if ([string]::IsNullOrWhiteSpace($relative)) { continue }
            $targetPath = Join-Path $runtimeProfilesRoot $relative
            $targetParent = Split-Path -Parent $targetPath
            if (-not (Test-Path -LiteralPath $targetParent -PathType Container)) {
                New-Item -ItemType Directory -Path $targetParent -Force | Out-Null
            }
            if (-not (Test-Path -LiteralPath $targetPath -PathType Leaf)) {
                Copy-Item -LiteralPath $file.FullName -Destination $targetPath -Force
            }
        }
    }

    if (Test-Path -LiteralPath $installDef.SaveRootPath -PathType Container) {
        foreach ($item in @(Get-ChildItem -LiteralPath $installDef.SaveRootPath -Force -ErrorAction SilentlyContinue)) {
            $targetPath = Join-Path $runtimeMissionsRoot $item.Name
            if (Test-Path -LiteralPath $targetPath) { continue }
            if ($item.PSIsContainer) {
                Copy-Item -LiteralPath $item.FullName -Destination $targetPath -Recurse -Force -ErrorAction SilentlyContinue
            }
            else {
                Copy-Item -LiteralPath $item.FullName -Destination $targetPath -Force -ErrorAction SilentlyContinue
            }
        }
    }

    if ($PSCmdlet.ParameterSetName -eq 'ByInstance' -and $Instance) {
        if ($Instance.PSObject.Properties.Name -contains 'ProfilePath') { $Instance.ProfilePath = $profileRoot }
        if ($Instance.PSObject.Properties.Name -contains 'Status') { $Instance.Status = 'Stopped' }
        if ($Instance.PSObject.Properties.Name -contains 'Pid') { $Instance.Pid = $null }
    }

    return [pscustomobject]@{
        Success          = $true
        GameId           = 'DayZ'
        InstanceId       = $instanceId
        ProfileName      = $effectiveProfileName
        ProfileRoot      = $profileRoot
        RuntimeInstall   = $runtimeInstallRoot
        RuntimeProfiles  = $runtimeProfilesRoot
        RuntimeMissions  = $runtimeMissionsRoot
        MainConfigPath   = $mainConfigPath
        BootstrapSeconds = $BootstrapSeconds
        Message          = 'DayZ profile initialized with runtime-only seed files.'
        Instance         = $Instance
        Status           = 'Stopped'
    }
}


function Test-UGSMGameDayZInstall {
    [CmdletBinding()]
    param(
        [string]$InstallPath
    )

    $definition = Get-UGSMGameDayZInstallDefinition -InstallPath $InstallPath
    if (-not $definition -or [string]::IsNullOrWhiteSpace([string]$definition.InstallPath)) {
        throw 'DayZ validation failed: InstallPath could not be resolved.'
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
        GameId                 = 'DayZ'
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




function Convert-UGSMGameDayZWorkshopInputToId {
    [CmdletBinding()]
    param(
        [AllowEmptyString()][AllowNull()][string]$InputText
    )

    $text = [string]$InputText
    if ([string]::IsNullOrWhiteSpace($text)) { return '' }

    $trimmed = $text.Trim()
    $patterns = @(
        'id=(\d+)',
        '(?:filedetails|sharedfiles/filedetails)/\?id=(\d+)',
        '(\d{5,})'
    )

    foreach ($pattern in $patterns) {
        $match = [regex]::Match($trimmed, $pattern, [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
        if ($match.Success -and $match.Groups.Count -gt 1) {
            $value = [string]$match.Groups[1].Value
            if ($value -match '^\d+$') { return $value }
        }
    }

    if ($trimmed -match '^\d+$') { return $trimmed }
    return ''
}

function Get-UGSMGameDayZLegacyModManifestPath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$Instance
    )

    $paths = Get-UGSMGameDayZProfilePaths -Instance $Instance
    return (Join-Path ([string]$paths.ProfileRoot) 'DayZModManifest.json')
}

function Initialize-UGSMGameDayZInstanceModCollections {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$Instance
    )

    if (-not ($Instance.PSObject.Properties.Name -contains 'Mods')) {
        $Instance | Add-Member -NotePropertyName 'Mods' -NotePropertyValue @() -Force
    }
    elseif ($null -eq $Instance.Mods) {
        $Instance.Mods = @()
    }

    if (-not ($Instance.PSObject.Properties.Name -contains 'ModStates')) {
        $Instance | Add-Member -NotePropertyName 'ModStates' -NotePropertyValue @() -Force
    }
    elseif ($null -eq $Instance.ModStates) {
        $Instance.ModStates = @()
    }
}

function Normalize-UGSMGameDayZModEntries {
    [CmdletBinding()]
    param(
        [AllowNull()][object[]]$Mods
    )

    $normalized = @()
    $index = 0
    foreach ($mod in @($Mods)) {
        if ($null -eq $mod) { continue }

        $rawId = if ($mod -is [string]) { [string]$mod } elseif ($mod.PSObject.Properties.Name -contains 'Id') { [string]$mod.Id } else { '' }
        $modId = Convert-UGSMGameDayZWorkshopInputToId -InputText $rawId
        if ([string]::IsNullOrWhiteSpace($modId)) { continue }

        $modName = if ($mod -is [string]) { $modId } elseif ($mod.PSObject.Properties.Name -contains 'Name') { [string]$mod.Name } else { '' }
        if ([string]::IsNullOrWhiteSpace($modName)) { $modName = $modId }

        $normalized += [pscustomobject]@{
            Id                  = $modId
            Name                = $modName
            FolderName          = [string]$(if ($mod -isnot [string] -and $mod.PSObject.Properties.Name -contains 'FolderName') { $mod.FolderName } else { '' })
            SourcePath          = [string]$(if ($mod -isnot [string] -and $mod.PSObject.Properties.Name -contains 'SourcePath') { $mod.SourcePath } else { '' })
            LoadOrder           = $index
            Enabled             = [bool]$(if ($mod -isnot [string] -and $mod.PSObject.Properties.Name -contains 'Enabled') { $mod.Enabled } else { $true })
            IsServerMod         = [bool]$(if ($mod -isnot [string] -and $mod.PSObject.Properties.Name -contains 'IsServerMod') { $mod.IsServerMod } else { $false })
            MergeTypes          = [bool]$(if ($mod -isnot [string] -and $mod.PSObject.Properties.Name -contains 'MergeTypes') { $mod.MergeTypes } else { $true })
            MergeEvents         = [bool]$(if ($mod -isnot [string] -and $mod.PSObject.Properties.Name -contains 'MergeEvents') { $mod.MergeEvents } else { $true })
            MergeSpawnableTypes = [bool]$(if ($mod -isnot [string] -and $mod.PSObject.Properties.Name -contains 'MergeSpawnableTypes') { $mod.MergeSpawnableTypes } else { $true })
        }
        $index++
    }

    return @($normalized)
}

function Get-UGSMGameDayZLegacyManifestMods {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$Instance
    )

    $manifestPath = Get-UGSMGameDayZLegacyModManifestPath -Instance $Instance
    if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) { return @() }

    try {
        $raw = Get-Content -LiteralPath $manifestPath -Raw -ErrorAction Stop
        if ([string]::IsNullOrWhiteSpace([string]$raw)) { return @() }

        $parsed = $raw | ConvertFrom-Json -ErrorAction Stop
        $mods = @()
        if ($parsed -and $parsed.PSObject.Properties.Name -contains 'Mods') {
            $mods = @($parsed.Mods)
        }
        elseif ($parsed -is [System.Collections.IEnumerable]) {
            $mods = @($parsed)
        }

        return @(Normalize-UGSMGameDayZModEntries -Mods $mods)
    }
    catch {
        return @()
    }
}

function Get-UGSMGameDayZInstanceDefinitionPath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$Instance
    )

    if (Get-Command -Name Get-UGSMDayZInstanceDefinitionPath -ErrorAction SilentlyContinue) {
        try {
            $dayZDefinitionPath = [string](Get-UGSMDayZInstanceDefinitionPath -Instance $Instance -Create)
            if (-not [string]::IsNullOrWhiteSpace($dayZDefinitionPath)) {
                return $dayZDefinitionPath
            }
        }
        catch { }
    }

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

function Save-UGSMGameDayZInstanceDefinition {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$Instance
    )

    # Prefer the DayZ folder-based instance storage when DayZFiles service is loaded.
    # This prevents falling back to the old flat AppData instance JSON path.
    if (Get-Command -Name Save-UGSMDayZInstanceJson -ErrorAction SilentlyContinue) {
        try {
            [void](Save-UGSMDayZInstanceJson -Instance $Instance)

            $hasLegacyPathCommand = [bool](Get-Command -Name Get-UGSMDayZLegacyInstanceJsonPath -ErrorAction SilentlyContinue)
            $hasFolderPathCommand = [bool](Get-Command -Name Get-UGSMDayZInstanceJsonPath -ErrorAction SilentlyContinue)

            if ($hasLegacyPathCommand -and $hasFolderPathCommand) {
                $legacyPath = [string](Get-UGSMDayZLegacyInstanceJsonPath -Instance $Instance)
                $folderJsonPath = [string](Get-UGSMDayZInstanceJsonPath -Instance $Instance)

                if (
                    -not [string]::IsNullOrWhiteSpace($legacyPath) -and
                    -not [string]::IsNullOrWhiteSpace($folderJsonPath) -and
                    (Test-Path -LiteralPath $legacyPath -PathType Leaf) -and
                    ($legacyPath.ToLowerInvariant() -ne $folderJsonPath.ToLowerInvariant())
                ) {
                    $migratedPath = $legacyPath + '.migrated.bak'
                    Move-Item -LiteralPath $legacyPath -Destination $migratedPath -Force -ErrorAction SilentlyContinue
                }
            }

            return $true
        }
        catch {
            # Fall through to the generic save path if the DayZ service save fails.
        }
    }

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

    $definitionPath = Get-UGSMGameDayZInstanceDefinitionPath -Instance $Instance
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

function Get-UGSMGameDayZStoredMods {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$Instance
    )

    Initialize-UGSMGameDayZInstanceModCollections -Instance $Instance

    $mods = @(Normalize-UGSMGameDayZModEntries -Mods @($Instance.Mods))
    if ($mods.Count -gt 0) {
        $Instance.Mods = @($mods)
        return @($mods)
    }

    # $legacyMods = @(Get-UGSMGameDayZLegacyManifestMods -Instance $Instance)
    # if ($legacyMods.Count -gt 0) {
    #      $Instance.Mods = @($legacyMods)
    #      [void](Save-UGSMGameDayZInstanceDefinition -Instance $Instance)
    #     return @($legacyMods)
    # }

    $Instance.Mods = @()
    return @()
}

function Save-UGSMGameDayZStoredMods {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$Instance,
        [AllowEmptyCollection()][AllowNull()][object[]]$Mods
    )

    Initialize-UGSMGameDayZInstanceModCollections -Instance $Instance

    $normalized = @(Normalize-UGSMGameDayZModEntries -Mods $Mods)
    $Instance.Mods = @($normalized)

    $states = @()
    foreach ($mod in @($normalized)) {
        $states += [pscustomobject]@{
            Id          = [string]$mod.Id
            Enabled     = [bool]$mod.Enabled
            IsServerMod = [bool]$mod.IsServerMod
        }
    }
    $Instance.ModStates = @($states)

    [void](Save-UGSMGameDayZInstanceDefinition -Instance $Instance)
    return @($normalized)
}

function Get-UGSMGameDayZModManifest {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$Instance
    )

    return [pscustomobject]@{
        Path = (Get-UGSMGameDayZInstanceDefinitionPath -Instance $Instance)
        Mods = @(Get-UGSMGameDayZStoredMods -Instance $Instance)
    }
}

function Save-UGSMGameDayZModManifest {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$Instance,
        [AllowEmptyCollection()][AllowNull()][object[]]$Mods
    )

    $savedMods = @(Save-UGSMGameDayZStoredMods -Instance $Instance -Mods $Mods)
    return [pscustomobject]@{
        Path = (Get-UGSMGameDayZInstanceDefinitionPath -Instance $Instance)
        Mods = @($savedMods)
    }
}

function Get-UGSMGameDayZProfileMods {
    [CmdletBinding()]
    param([Parameter(Mandatory)][object]$Instance)

    $resolved = @()
    $index = 0
    foreach ($entry in @(Get-UGSMGameDayZStoredMods -Instance $Instance)) {
        if ($null -eq $entry) { continue }

        $workshopId = Convert-UGSMGameDayZWorkshopInputToId -InputText ([string]$entry.Id)
        if ([string]::IsNullOrWhiteSpace($workshopId)) { continue }

        $sourcePath = Resolve-UGSMGameDayZWorkshopModSourcePath -Instance $Instance -Mod $entry

        $resolvedName = [string]$entry.Name
        if ((-not [string]::IsNullOrWhiteSpace([string]$sourcePath)) -and (Test-Path -LiteralPath $sourcePath -PathType Container)) {
            $resolvedName = Get-UGSMGameDayZModNameFromSource -SourcePath $sourcePath -FallbackId $workshopId
        }
        if ([string]::IsNullOrWhiteSpace($resolvedName)) { $resolvedName = $workshopId }

        $resolved += [pscustomobject]@{
            Id                  = $workshopId
            Name                = $resolvedName
            FolderName          = (Get-UGSMGameDayZSafeModFolderName -Name $resolvedName -Id $workshopId)
            SourcePath          = [string]$sourcePath
            RuntimePath         = [string]$sourcePath
            LoadOrder           = $index
            Enabled             = [bool]$entry.Enabled
            IsServerMod         = [bool]$entry.IsServerMod
            MergeTypes          = [bool]$entry.MergeTypes
            MergeEvents         = [bool]$entry.MergeEvents
            MergeSpawnableTypes = [bool]$entry.MergeSpawnableTypes
        }
        $index++
    }

    return @($resolved)
}

function Get-UGSMGameDayZSteamCmdExecutablePath {
    [CmdletBinding()]
    param([AllowNull()][object]$Instance)

    $candidates = @()
    if ($Instance) {
        foreach ($propertyName in @('SteamCMDPath', 'SteamCmdPath', 'SteamCmdExePath')) {
            if ($Instance.PSObject.Properties.Name -contains $propertyName) {
                $value = [string]$Instance.$propertyName
                if (-not [string]::IsNullOrWhiteSpace([string]$value)) { $candidates += $value }
            }
        }
    }

    $settings = $null
    if (Get-Command -Name Get-UGSMGlobalSettings -ErrorAction SilentlyContinue) {
        try { $settings = Get-UGSMGlobalSettings -CreateIfMissing } catch { $settings = $null }
    }
    if ($settings) {
        foreach ($propertyName in @('SteamCMDPath', 'SteamCmdPath', 'SteamCmdExePath')) {
            if ($settings.PSObject.Properties.Name -contains $propertyName) {
                $value = [string]$settings.$propertyName
                if (-not [string]::IsNullOrWhiteSpace([string]$value)) { $candidates += $value }
            }
        }
        foreach ($propertyName in @('SteamCmdRoot', 'SteamRoot', 'InstallRoot', 'SteamLibraryRoot')) {
            if ($settings.PSObject.Properties.Name -contains $propertyName) {
                $value = [string]$settings.$propertyName
                if (-not [string]::IsNullOrWhiteSpace([string]$value)) {
                    $candidates += (Join-Path $value 'steamcmd.exe')
                    $candidates += (Join-Path $value 'SteamCMD\steamcmd.exe')
                    $candidates += (Join-Path $value 'tools\steamcmd\steamcmd.exe')
                }
            }
        }
    }
    foreach ($candidate in @($candidates | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) } | Select-Object -Unique)) {
        if (Test-Path -LiteralPath $candidate -PathType Leaf) { return [string]$candidate }
    }
    throw 'DayZ mod download failed: SteamCMD executable could not be resolved from the current settings.'
}

function Get-UGSMGameDayZSteamLoginArguments {
    [CmdletBinding()]
    param()

    $settings = $null
    if (Get-Command -Name Get-UGSMGlobalSettings -ErrorAction SilentlyContinue) {
        try { $settings = Get-UGSMGlobalSettings -CreateIfMissing } catch { $settings = $null }
    }

    $steamUser = ''
    $steamPass = ''
    if ($settings) {
        foreach ($propertyName in @('SteamUser', 'SteamUsername', 'SteamCmdUser')) {
            if ($settings.PSObject.Properties.Name -contains $propertyName -and -not [string]::IsNullOrWhiteSpace([string]$settings.$propertyName)) {
                $steamUser = [string]$settings.$propertyName
                break
            }
        }
        foreach ($propertyName in @('SteamPass', 'SteamPassword', 'SteamCmdPassword')) {
            if ($settings.PSObject.Properties.Name -contains $propertyName -and -not [string]::IsNullOrWhiteSpace([string]$settings.$propertyName)) {
                $steamPass = [string]$settings.$propertyName
                break
            }
        }
    }

    if ([string]::IsNullOrWhiteSpace($steamUser)) {
        throw 'DayZ mod download requires Steam credentials. Set your Steam username in settings.'
    }

    if ([string]::IsNullOrWhiteSpace($steamPass)) {
        return @('+login', $steamUser)
    }

    return @('+login', $steamUser, $steamPass)
}

function Invoke-UGSMGameDayZWorkshopDownload {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$Instance,
        [Parameter(Mandatory)][string[]]$WorkshopItemIds
    )

    $itemIds = @()
    foreach ($rawId in @($WorkshopItemIds)) {
        $itemId = Convert-UGSMGameDayZWorkshopInputToId -InputText ([string]$rawId)
        if (-not [string]::IsNullOrWhiteSpace($itemId) -and $itemIds -notcontains $itemId) {
            $itemIds += $itemId
        }
    }
    if ($itemIds.Count -eq 0) { throw 'No valid DayZ workshop ids were provided.' }

    $steamCmdPath = Get-UGSMGameDayZSteamCmdExecutablePath -Instance $Instance
    $steamCmdRoot = Split-Path -Parent $steamCmdPath
    $argumentParts = @()
    $argumentParts += @(Get-UGSMGameDayZSteamLoginArguments)
    foreach ($itemId in $itemIds) {
        $argumentParts += @('+workshop_download_item', '221100', [string]$itemId)
    }
    $argumentParts += '+quit'

    $argumentString = ($argumentParts | ForEach-Object {
            $part = [string]$_
            if ($part -match '\s') { '"{0}"' -f $part.Replace('"', '"') } else { $part }
        }) -join ' '

    $process = Start-Process -FilePath $steamCmdPath -WorkingDirectory $steamCmdRoot -ArgumentList $argumentString -PassThru -Wait
    if ($null -eq $process) { throw 'DayZ mod download failed: SteamCMD process did not start.' }
    if ([int]$process.ExitCode -ne 0) { throw ('DayZ mod download failed: SteamCMD exited with code {0}.' -f [int]$process.ExitCode) }

    $missingItems = @()
    $contentRoots = @(Get-UGSMGameDayZWorkshopContentRoots -InstallPath ([string]$Instance.InstallPath))
    foreach ($itemId in $itemIds) {
        $found = $false
        foreach ($root in $contentRoots) {
            $candidate = Join-Path $root $itemId
            if (Test-Path -LiteralPath $candidate -PathType Container) {
                $found = $true
                break
            }
        }
        if (-not $found) { $missingItems += $itemId }
    }

    return [pscustomobject]@{
        SteamCmdPath = $steamCmdPath
        SteamCmdRoot = $steamCmdRoot
        ItemIds      = @($itemIds)
        ExitCode     = [int]$process.ExitCode
        MissingItems = @($missingItems)
    }
}

function Get-UGSMGameDayZWorkshopContentRoots {
    [CmdletBinding()]
    param([AllowNull()][string]$InstallPath)

    $roots = @()
    if (-not [string]::IsNullOrWhiteSpace([string]$InstallPath)) {
        $installPathText = [string]$InstallPath
        $marker = '\steamapps\common\'
        $markerIndex = $installPathText.IndexOf($marker, [System.StringComparison]::OrdinalIgnoreCase)
        if ($markerIndex -ge 0) {
            $libraryRoot = $installPathText.Substring(0, $markerIndex)
            if (-not [string]::IsNullOrWhiteSpace([string]$libraryRoot)) {
                $roots += (Join-Path $libraryRoot 'steamapps\workshop\content\221100')
            }
        }
        $installParent = Split-Path -Parent $installPathText
        if (-not [string]::IsNullOrWhiteSpace([string]$installParent)) { $roots += (Join-Path $installParent 'steamapps\workshop\content\221100') }
        $roots += (Join-Path $installPathText 'steamapps\workshop\content\221100')
    }

    $steamCmdPath = $null
    try { $steamCmdPath = Get-UGSMGameDayZSteamCmdExecutablePath -Instance $null } catch { $steamCmdPath = $null }
    if (-not [string]::IsNullOrWhiteSpace([string]$steamCmdPath)) {
        $steamCmdRoot = Split-Path -Parent $steamCmdPath
        if (-not [string]::IsNullOrWhiteSpace([string]$steamCmdRoot)) {
            $roots += (Join-Path $steamCmdRoot 'steamapps\workshop\content\221100')
            $steamCmdParent = Split-Path -Parent $steamCmdRoot
            if (-not [string]::IsNullOrWhiteSpace([string]$steamCmdParent)) { $roots += (Join-Path $steamCmdParent 'steamapps\workshop\content\221100') }
        }
    }

    if (Get-Command -Name Get-UGSMGlobalSettings -ErrorAction SilentlyContinue) {
        try {
            $settings = Get-UGSMGlobalSettings -CreateIfMissing
            foreach ($propertyName in @('SteamCmdRoot', 'SteamRoot', 'InstallRoot', 'SteamLibraryRoot')) {
                if ($settings -and $settings.PSObject.Properties.Name -contains $propertyName) {
                    $candidateRoot = [string]$settings.$propertyName
                    if (-not [string]::IsNullOrWhiteSpace([string]$candidateRoot)) {
                        $roots += (Join-Path $candidateRoot 'steamapps\workshop\content\221100')
                        $roots += (Join-Path $candidateRoot 'servers\steamapps\workshop\content\221100')
                        $roots += (Join-Path $candidateRoot 'SteamCMD\steamapps\workshop\content\221100')
                    }
                }
            }
        }
        catch {}
    }

    $uniqueRoots = @()
    foreach ($root in @($roots)) {
        if ([string]::IsNullOrWhiteSpace([string]$root)) { continue }
        $exists = $false
        foreach ($existing in @($uniqueRoots)) {
            if ([string]::Equals([string]$existing, [string]$root, [System.StringComparison]::OrdinalIgnoreCase)) { $exists = $true; break }
        }
        if (-not $exists) { $uniqueRoots += [string]$root }
    }
    return @($uniqueRoots)
}
function Get-UGSMGameDayZSafeModFolderName {
    [CmdletBinding()]
    param([AllowEmptyString()][AllowNull()][string]$Name, [AllowEmptyString()][AllowNull()][string]$Id)

    $candidateName = [string]$Name
    if ([string]::IsNullOrWhiteSpace([string]$candidateName)) { $candidateName = [string]$Id }
    if ([string]::IsNullOrWhiteSpace([string]$candidateName)) { $candidateName = 'Mod' }
    $safeName = [regex]::Replace($candidateName, '[\/:*?"<>|]+', '')
    $safeName = [regex]::Replace($safeName, '\s+', '_')
    $safeName = [regex]::Replace($safeName, '[^A-Za-z0-9@\._-]', '')
    if ([string]::IsNullOrWhiteSpace([string]$safeName)) { $safeName = 'Mod' }
    if (-not $safeName.StartsWith('@')) { $safeName = '@' + $safeName }
    return $safeName
}

function Resolve-UGSMGameDayZWorkshopModSourcePath {
    [CmdletBinding()]
    param([Parameter(Mandatory)][object]$Instance, [Parameter(Mandatory)]$Mod)

    $modId = Convert-UGSMGameDayZWorkshopInputToId -InputText ([string]$(if ($Mod.PSObject.Properties.Name -contains 'Id') { $Mod.Id } else { '' }))
    if ([string]::IsNullOrWhiteSpace([string]$modId)) { return $null }
    foreach ($root in @(Get-UGSMGameDayZWorkshopContentRoots -InstallPath ([string]$Instance.InstallPath))) {
        if ([string]::IsNullOrWhiteSpace([string]$root)) { continue }
        $candidatePath = Join-Path $root $modId
        if (Test-Path -LiteralPath $candidatePath -PathType Container) { return [string]$candidatePath }
    }
    return $null
}

function Get-UGSMGameDayZResolvedActiveMods {
    [CmdletBinding()]
    param([Parameter(Mandatory)][object]$Instance)

    $resolvedMods = @()
    $index = 0
    foreach ($entry in @(Get-UGSMGameDayZProfileMods -Instance $Instance)) {
        if ($null -eq $entry -or -not [bool]$entry.Enabled) { continue }
        $sourcePath = Resolve-UGSMGameDayZWorkshopModSourcePath -Instance $Instance -Mod $entry
        $resolvedName = [string]$entry.Name
        if ((-not [string]::IsNullOrWhiteSpace([string]$sourcePath)) -and (Test-Path -LiteralPath $sourcePath -PathType Container)) {
            $resolvedName = Get-UGSMGameDayZModNameFromSource -SourcePath $sourcePath -FallbackId ([string]$entry.Id)
        }
        if ([string]::IsNullOrWhiteSpace([string]$resolvedName)) { $resolvedName = [string]$entry.Id }
        $resolvedMods += [pscustomobject]@{
            Id                  = [string]$entry.Id
            Name                = $resolvedName
            FolderName          = (Get-UGSMGameDayZSafeModFolderName -Name $resolvedName -Id ([string]$entry.Id))
            SourcePath          = [string]$sourcePath
            RuntimePath         = $null
            LoadOrder           = [int]$index
            Enabled             = $true
            IsServerMod         = [bool]$entry.IsServerMod
            MergeTypes          = [bool]$entry.MergeTypes
            MergeEvents         = [bool]$entry.MergeEvents
            MergeSpawnableTypes = [bool]$entry.MergeSpawnableTypes
        }
        $index++
    }
    return @($resolvedMods)
}

function Copy-UGSMGameDayZModKeys {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$ModRoot, [Parameter(Mandatory)][string]$RuntimeKeysRoot)

    if (-not (Test-Path -LiteralPath $RuntimeKeysRoot -PathType Container)) { New-Item -ItemType Directory -Path $RuntimeKeysRoot -Force | Out-Null }
    $keysRoot = Join-Path $ModRoot 'keys'
    if (-not (Test-Path -LiteralPath $keysRoot -PathType Container)) { return 0 }
    $copiedCount = 0
    foreach ($keyFile in @(Get-ChildItem -LiteralPath $keysRoot -Filter '*.bikey' -File -ErrorAction SilentlyContinue)) {
        Copy-Item -LiteralPath $keyFile.FullName -Destination (Join-Path $RuntimeKeysRoot $keyFile.Name) -Force
        $copiedCount++
    }
    return $copiedCount
}

function Copy-UGSMGameDayZServerModPbos {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$ModRoot, [Parameter(Mandatory)][string]$RuntimeAddonsRoot)

    $addonsRoot = Join-Path $ModRoot 'addons'
    if (-not (Test-Path -LiteralPath $addonsRoot -PathType Container)) { return 0 }
    if (-not (Test-Path -LiteralPath $RuntimeAddonsRoot -PathType Container)) { New-Item -ItemType Directory -Path $RuntimeAddonsRoot -Force | Out-Null }
    $copiedCount = 0
    foreach ($pattern in @('*.pbo', '*.bisign')) {
        foreach ($addonFile in @(Get-ChildItem -LiteralPath $addonsRoot -Filter $pattern -File -ErrorAction SilentlyContinue)) {
            Copy-Item -LiteralPath $addonFile.FullName -Destination (Join-Path $RuntimeAddonsRoot $addonFile.Name) -Force
            $copiedCount++
        }
    }
    return $copiedCount
}

function Copy-UGSMGameDayZSelectedServerModPbos {
    [CmdletBinding()]
    param([Parameter(Mandatory)][object]$Instance, [Parameter(Mandatory)]$Mod, [AllowNull()][object]$Runtime)

    if (-not $Runtime) {
        $installDefinition = Get-UGSMGameDayZInstallDefinition -InstallPath $Instance.InstallPath -Instance $Instance
        $Runtime = Ensure-UGSMGameDayZRuntimeLayout -Instance $Instance -InstallDefinition $installDefinition
    }
    $paths = Get-UGSMGameDayZProfilePaths -Instance $Instance
    if (-not (Test-Path -LiteralPath $paths.RuntimeAddonsRoot -PathType Container)) { New-Item -ItemType Directory -Path $paths.RuntimeAddonsRoot -Force | Out-Null }
    $sourcePath = Resolve-UGSMGameDayZWorkshopModSourcePath -Instance $Instance -Mod $Mod
    if ([string]::IsNullOrWhiteSpace([string]$sourcePath) -or -not (Test-Path -LiteralPath $sourcePath -PathType Container)) {
        $modLabel = [string]$(if ($Mod.PSObject.Properties.Name -contains 'Name' -and -not [string]::IsNullOrWhiteSpace([string]$Mod.Name)) { $Mod.Name } else { $Mod.Id })
        throw ('DayZ mod source could not be resolved for {0}.' -f $modLabel)
    }
    return [int](Copy-UGSMGameDayZServerModPbos -ModRoot $sourcePath -RuntimeAddonsRoot $paths.RuntimeAddonsRoot)
}

function Sync-UGSMGameDayZModFilesToRuntime {
    [CmdletBinding()]
    param([Parameter(Mandatory)][object]$Instance, [AllowNull()][object]$Runtime)

    if (-not $Runtime) {
        $installDefinition = Get-UGSMGameDayZInstallDefinition -InstallPath $Instance.InstallPath -Instance $Instance
        $Runtime = Ensure-UGSMGameDayZRuntimeLayout -Instance $Instance -InstallDefinition $installDefinition
    }

    $paths = Get-UGSMGameDayZProfilePaths -Instance $Instance
    $activeMods = @(Get-UGSMGameDayZResolvedActiveMods -Instance $Instance)

    foreach ($requiredRoot in @($paths.RuntimeKeysRoot, $paths.RuntimeAddonsRoot)) {
        if (-not (Test-Path -LiteralPath $requiredRoot -PathType Container)) {
            New-Item -ItemType Directory -Path $requiredRoot -Force | Out-Null
        }
    }

    foreach ($runtimeFolder in @(Get-ChildItem -LiteralPath $paths.RuntimeModsRoot -Directory -Force -ErrorAction SilentlyContinue)) {
        if ($runtimeFolder.Name -like '@*') {
            Remove-Item -LiteralPath $runtimeFolder.FullName -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    $missingMods = New-Object System.Collections.Generic.List[string]
    $keysCopied = 0
    $pbosCopied = 0
    $enabledMods = @()

    foreach ($mod in $activeMods) {
        $sourcePath = [string]$mod.SourcePath
        if ([string]::IsNullOrWhiteSpace([string]$sourcePath) -or -not (Test-Path -LiteralPath $sourcePath -PathType Container)) {
            $label = [string]$(if ([string]::IsNullOrWhiteSpace([string]$mod.Name)) { $mod.Id } else { $mod.Name })
            [void]$missingMods.Add($label)
            continue
        }

        $folderName = [string]$mod.FolderName
        if ([string]::IsNullOrWhiteSpace($folderName)) {
            $resolvedName = Get-UGSMGameDayZModNameFromSource -SourcePath $sourcePath -FallbackId ([string]$mod.Id)
            $folderName = Get-UGSMGameDayZSafeModFolderName -Name $resolvedName -Id ([string]$mod.Id)
        }

        $keysCopied += [int](Copy-UGSMGameDayZModKeys -ModRoot $sourcePath -RuntimeKeysRoot $paths.RuntimeKeysRoot)
        if ([bool]$mod.IsServerMod) {
            $pbosCopied += [int](Copy-UGSMGameDayZServerModPbos -ModRoot $sourcePath -RuntimeAddonsRoot $paths.RuntimeAddonsRoot)
        }

        $enabledMods += [pscustomobject]@{
            Id          = [string]$mod.Id
            Name        = [string]$mod.Name
            FolderName  = $folderName
            SourcePath  = $sourcePath
            RuntimePath = $sourcePath
            LoadOrder   = $mod.LoadOrder
            IsServerMod = [bool]$mod.IsServerMod
        }
    }

    return [pscustomobject]@{
        EnabledMods       = @($enabledMods)
        RuntimeModFolders = @()
        MissingMods       = @($missingMods)
        KeysCopied        = $keysCopied
        PbosCopied        = $pbosCopied
        ModsCopied        = @()
        ModsSkipped       = @()
    }
}

function ConvertTo-UGSMGameDayZSanitizedXmlText {
    [CmdletBinding()]
    param([Parameter(Mandatory)][AllowEmptyString()][string]$Text)

    if ([string]::IsNullOrEmpty($Text)) { return $Text }

    $result = $Text

    if ($result.Length -gt 0 -and [int][char]$result[0] -eq 0xFEFF) {
        $result = $result.Substring(1)
    }

    $result = $result.TrimStart()

    $result = [System.Text.RegularExpressions.Regex]::Replace($result, '<\?xml[^>]*\?>', '')

    $builder = New-Object System.Text.StringBuilder
    $cursor = 0
    while ($cursor -lt $result.Length) {
        $openIndex = $result.IndexOf('<!--', $cursor)
        if ($openIndex -lt 0) {
            [void]$builder.Append($result.Substring($cursor))
            break
        }

        [void]$builder.Append($result.Substring($cursor, $openIndex - $cursor))

        $closeIndex = $result.IndexOf('-->', $openIndex + 4)
        if ($closeIndex -lt 0) {
            break
        }

        $body = $result.Substring($openIndex + 4, $closeIndex - ($openIndex + 4))
        while ($body.IndexOf('--') -ge 0) {
            $body = $body.Replace('--', '- -')
        }
        if ($body.EndsWith('-')) {
            $body = $body.TrimEnd('-') + ' '
        }

        [void]$builder.Append('<!--')
        [void]$builder.Append($body)
        [void]$builder.Append('-->')

        $cursor = $closeIndex + 3
    }

    return $builder.ToString().TrimStart()
}

function Read-UGSMGameDayZXmlDocumentSafe {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Path,
        [switch]$AllowFragmentWrap,
        [string]$FragmentRootName = 'root'
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "XML file was not found: $Path"
    }

    $rawXml = Get-Content -LiteralPath $Path -Raw -ErrorAction Stop
    if ([string]::IsNullOrWhiteSpace([string]$rawXml)) {
        throw "XML file was empty: $Path"
    }

    $xmlDocument = New-Object System.Xml.XmlDocument
    $xmlDocument.PreserveWhitespace = $true

    try {
        $xmlDocument.LoadXml($rawXml)
        return $xmlDocument
    }
    catch {
        $lastError = $_.Exception.Message
    }

    $sanitizedXml = ConvertTo-UGSMGameDayZSanitizedXmlText -Text $rawXml

    try {
        $xmlDocument.LoadXml($sanitizedXml)
        return $xmlDocument
    }
    catch {
        $lastError = $_.Exception.Message
    }

    if ($AllowFragmentWrap) {
        $wrappedDocument = New-Object System.Xml.XmlDocument
        $wrappedDocument.PreserveWhitespace = $true
        $wrappedXml = ('<{0}>{1}</{0}>' -f $FragmentRootName, $sanitizedXml)
        try {
            $wrappedDocument.LoadXml($wrappedXml)
            return $wrappedDocument
        }
        catch {
            $lastError = $_.Exception.Message
        }
    }

    throw "Failed to parse XML: $Path :: $lastError"
}

function Get-UGSMGameDayZBackupRoot {
    [CmdletBinding()]
    param(
        [AllowNull()][object]$Instance,
        [string]$TargetPath
    )

    $globalRoot = ''
    $settingsCandidates = @()

    if (Get-Command -Name Get-UGSMGlobalSettings -ErrorAction SilentlyContinue) {
        try { $settingsCandidates += ,(Get-UGSMGlobalSettings -CreateIfMissing) } catch { }
    }

    if (Get-Command -Name Get-UGSMGlobalSettingsModel -ErrorAction SilentlyContinue) {
        try { $settingsCandidates += ,(Get-UGSMGlobalSettingsModel) } catch { }
    }

    foreach ($settings in @($settingsCandidates)) {
        if ($null -eq $settings) { continue }
        if ($settings.PSObject.Properties.Name -contains 'BackupRoot') {
            $candidate = ([string]$settings.BackupRoot).Trim()
            if (-not [string]::IsNullOrWhiteSpace($candidate)) {
                $globalRoot = $candidate
                break
            }
        }
    }

    $instanceName = ''
    if ($null -ne $Instance) {
        foreach ($prop in @('InstanceId','Name','Id')) {
            if ($Instance.PSObject.Properties.Name -contains $prop) {
                $value = ([string]$Instance.$prop).Trim()
                if (-not [string]::IsNullOrWhiteSpace($value)) {
                    $instanceName = $value
                    break
                }
            }
        }
    }

    if ([string]::IsNullOrWhiteSpace($instanceName) -and -not [string]::IsNullOrWhiteSpace($TargetPath)) {
        try {
            $segments = @(([System.IO.Path]::GetFullPath($TargetPath)) -split '[\/]')
            for ($i = 0; $i -lt ($segments.Count - 1); $i++) {
                if ($segments[$i] -ieq 'DayZ' -and ($i + 1) -lt $segments.Count) {
                    $instanceName = ([string]$segments[$i + 1]).Trim()
                    if (-not [string]::IsNullOrWhiteSpace($instanceName)) { break }
                }
            }
        } catch { }
    }

    if (-not [string]::IsNullOrWhiteSpace($globalRoot)) {
        if (-not [string]::IsNullOrWhiteSpace($instanceName)) {
            return (Join-Path (Join-Path $globalRoot 'DayZ') $instanceName)
        }

        return (Join-Path $globalRoot 'DayZ')
    }

    if ($null -ne $Instance -and (Get-Command -Name Get-UGSMDayZInstanceStoragePaths -ErrorAction SilentlyContinue)) {
        try {
            $paths = Get-UGSMDayZInstanceStoragePaths -Instance $Instance -Create
            if ($paths -and $paths.PSObject.Properties.Name -contains 'BackupsFolder' -and -not [string]::IsNullOrWhiteSpace([string]$paths.BackupsFolder)) {
                return [string]$paths.BackupsFolder
            }
        } catch { }
    }

    return ''
}

function Get-UGSMGameDayZBackupDestinationPath {
    [CmdletBinding()]
    param(
        [AllowNull()][object]$Instance,
        [Parameter(Mandatory)][string]$TargetPath,
        [string]$BackupExtension = '.bak'
    )

    if ([string]::IsNullOrWhiteSpace($TargetPath)) { return '' }

    $targetFullPath = ''
    try { $targetFullPath = [System.IO.Path]::GetFullPath($TargetPath) } catch { $targetFullPath = $TargetPath }

    $backupRoot = Get-UGSMGameDayZBackupRoot -Instance $Instance -TargetPath $TargetPath

    $profileBaseRoot = ''
    $globalBackupRoot = ''
    if (Get-Command -Name Get-UGSMGlobalSettings -ErrorAction SilentlyContinue) {
        try {
            $globalSettings = Get-UGSMGlobalSettings -CreateIfMissing
            if ($globalSettings) {
                if ($globalSettings.PSObject.Properties.Name -contains 'ProfileBaseRoot') {
                    $profileBaseRoot = ([string]$globalSettings.ProfileBaseRoot).Trim()
                }
                if ($globalSettings.PSObject.Properties.Name -contains 'BackupRoot') {
                    $globalBackupRoot = ([string]$globalSettings.BackupRoot).Trim()
                }
            }
        } catch { }
    }

    if ([string]::IsNullOrWhiteSpace($backupRoot) -and -not [string]::IsNullOrWhiteSpace($globalBackupRoot)) {
        $instanceName = ''
        if (-not [string]::IsNullOrWhiteSpace($profileBaseRoot)) {
            try {
                $normalizedProfileBase = [System.IO.Path]::GetFullPath($profileBaseRoot).TrimEnd('\','/')
                if ($targetFullPath.StartsWith($normalizedProfileBase, [System.StringComparison]::OrdinalIgnoreCase)) {
                    $relativeToBase = $targetFullPath.Substring($normalizedProfileBase.Length).TrimStart('\','/')
                    $segments = @($relativeToBase -split '[\/]')
                    if ($segments.Count -ge 2 -and $segments[0] -ieq 'DayZ') {
                        $instanceName = $segments[1]
                    }
                }
            } catch { }
        }

        if ([string]::IsNullOrWhiteSpace($instanceName)) {
            $segments = @($targetFullPath -split '[\/]')
            for ($i = 0; $i -lt ($segments.Count - 1); $i++) {
                if ($segments[$i] -ieq 'DayZ' -and ($i + 1) -lt $segments.Count) {
                    $instanceName = $segments[$i + 1]
                    break
                }
            }
        }

        if (-not [string]::IsNullOrWhiteSpace($instanceName)) {
            $backupRoot = Join-Path (Join-Path $globalBackupRoot 'DayZ') $instanceName
        }
    }

    if ([string]::IsNullOrWhiteSpace($backupRoot)) { return '' }

    $relativeFolder = 'misc'
    $leafName = [System.IO.Path]::GetFileName($TargetPath)

    try {
        $candidateRoots = New-Object System.Collections.Generic.List[string]

        if ($null -ne $Instance) {
            try {
                $profilePaths = Get-UGSMGameDayZProfilePaths -Instance $Instance
                if ($profilePaths) {
                    foreach ($prop in @('ProfileRoot','RuntimeRoot','InstallRoot','InstallPath')) {
                        if ($profilePaths.PSObject.Properties.Name -contains $prop) {
                            $value = [string]$profilePaths.$prop
                            if (-not [string]::IsNullOrWhiteSpace($value)) { [void]$candidateRoots.Add($value) }
                        }
                    }
                }
            } catch { }

            foreach ($prop in @('ProfilePath','RuntimePath','RuntimeProfilePath','InstallPath')) {
                if ($Instance.PSObject.Properties.Name -contains $prop) {
                    $value = [string]$Instance.$prop
                    if (-not [string]::IsNullOrWhiteSpace($value)) { [void]$candidateRoots.Add($value) }
                }
            }
        }

        if (-not [string]::IsNullOrWhiteSpace($profileBaseRoot)) {
            [void]$candidateRoots.Add($profileBaseRoot)
        }

        foreach ($root in @($candidateRoots | Select-Object -Unique)) {
            if ([string]::IsNullOrWhiteSpace($root)) { continue }

            $normalizedRoot = [System.IO.Path]::GetFullPath($root).TrimEnd('\','/')
            $normalizedTarget = $targetFullPath

            if ($normalizedTarget.StartsWith($normalizedRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
                $relative = $normalizedTarget.Substring($normalizedRoot.Length).TrimStart('\','/')
                $relativeParent = Split-Path -Parent $relative

                if (-not [string]::IsNullOrWhiteSpace($relativeParent)) {
                    $relativeFolder = $relativeParent
                }
                else {
                    $relativeFolder = ''
                }

                if ($null -ne $Instance -and $Instance.PSObject.Properties.Name -contains 'InstallPath' -and $root -eq [string]$Instance.InstallPath) {
                    $relativeFolder = Join-Path 'install' $relativeFolder
                }
                elseif (-not [string]::IsNullOrWhiteSpace($profileBaseRoot) -and $root -eq $profileBaseRoot) {
                    $relativeFolder = $relativeFolder
                }
                else {
                    $relativeFolder = Join-Path 'profile' $relativeFolder
                }

                break
            }
        }
    } catch { }

    $destinationFolder = if ([string]::IsNullOrWhiteSpace($relativeFolder)) { $backupRoot } else { Join-Path $backupRoot $relativeFolder }
    if (-not (Test-Path -LiteralPath $destinationFolder -PathType Container)) {
        New-Item -ItemType Directory -Path $destinationFolder -Force | Out-Null
    }

    return (Join-Path $destinationFolder ($leafName + $BackupExtension))
}

function Backup-UGSMGameDayZXmlFile {
    [CmdletBinding()]
    param(
        [AllowNull()][object]$Instance,
        [Parameter(Mandatory)][string]$TargetPath
    )

    if (-not (Test-Path -LiteralPath $TargetPath -PathType Leaf)) {
        return $null
    }

    $backupPath = Get-UGSMGameDayZBackupDestinationPath -Instance $Instance -TargetPath $TargetPath -BackupExtension '.bak'
    if ([string]::IsNullOrWhiteSpace($backupPath)) {
        $backupPath = '{0}.ugsm.bak' -f $TargetPath
    }

    Copy-Item -LiteralPath $TargetPath -Destination $backupPath -Force
    return $backupPath
}

function Resolve-UGSMGameDayZRuntimeSpawnableTypesTargetPath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$Instance
    )

    $paths = Get-UGSMGameDayZProfilePaths -Instance $Instance
    if (Test-Path -LiteralPath $paths.RuntimeSpawnableTypesPath -PathType Leaf) {
        return [string]$paths.RuntimeSpawnableTypesPath
    }

    return [string]$paths.RuntimeSpawnableTypesDbPath
}

function Merge-UGSMGameDayZNamedXmlNodes {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$TargetPath,
        [Parameter(Mandatory)][string]$SourcePath,
        [Parameter(Mandatory)][string]$RootXPath,
        [Parameter(Mandatory)][string]$NodeXPath,
        [Parameter(Mandatory)][string]$NameAttribute,
        [switch]$AllowSourceFragmentWrap,
        [string]$SourceFragmentRootName = 'root'
    )

    $targetDocument = Read-UGSMGameDayZXmlDocumentSafe -Path $TargetPath
    $sourceDocument = Read-UGSMGameDayZXmlDocumentSafe -Path $SourcePath -AllowFragmentWrap:$AllowSourceFragmentWrap -FragmentRootName $SourceFragmentRootName

    $targetRootNode = $targetDocument.SelectSingleNode($RootXPath)
    if ($null -eq $targetRootNode) {
        throw "XML merge failed: target root node was not found at '$RootXPath' in '$TargetPath'."
    }

    $sourceNodes = $sourceDocument.SelectNodes($NodeXPath)
    if ($null -eq $sourceNodes) {
        return 0
    }

    $existingNames = @{}
    foreach ($existingNode in @($targetDocument.SelectNodes($NodeXPath))) {
        if ($null -eq $existingNode) { continue }
        $attributeNode = $existingNode.Attributes[$NameAttribute]
        if ($null -eq $attributeNode) { continue }
        $nameValue = [string]$attributeNode.Value
        if ([string]::IsNullOrWhiteSpace([string]$nameValue)) { continue }
        $existingNames[$nameValue.ToLowerInvariant()] = $true
    }

    $addedCount = 0
    foreach ($sourceNode in @($sourceNodes)) {
        if ($null -eq $sourceNode) { continue }
        $attributeNode = $sourceNode.Attributes[$NameAttribute]
        if ($null -eq $attributeNode) { continue }
        $nameValue = [string]$attributeNode.Value
        if ([string]::IsNullOrWhiteSpace([string]$nameValue)) { continue }

        $nameKey = $nameValue.ToLowerInvariant()
        if ($existingNames.ContainsKey($nameKey)) { continue }

        $importedNode = $targetDocument.ImportNode($sourceNode, $true)
        [void]$targetRootNode.AppendChild($importedNode)
        $existingNames[$nameKey] = $true
        $addedCount++
    }

    if ($addedCount -gt 0) {
        $targetDocument.Save($TargetPath)
    }

    return $addedCount
}

function Merge-UGSMGameDayZTypesXml {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$TargetPath,
        [Parameter(Mandatory)][string]$SourcePath
    )

    return (Merge-UGSMGameDayZNamedXmlNodes `
            -TargetPath $TargetPath `
            -SourcePath $SourcePath `
            -RootXPath '/types' `
            -NodeXPath '/types/type|/type' `
            -NameAttribute 'name' `
            -AllowSourceFragmentWrap `
            -SourceFragmentRootName 'types')
}

function Merge-UGSMGameDayZEventsXml {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$TargetPath,
        [Parameter(Mandatory)][string]$SourcePath
    )

    return (Merge-UGSMGameDayZNamedXmlNodes `
            -TargetPath $TargetPath `
            -SourcePath $SourcePath `
            -RootXPath '/events' `
            -NodeXPath '/events/event|/event' `
            -NameAttribute 'name' `
            -AllowSourceFragmentWrap `
            -SourceFragmentRootName 'events')
}

function Merge-UGSMGameDayZSpawnableTypesXml {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$TargetPath,
        [Parameter(Mandatory)][string]$SourcePath
    )

    return (Merge-UGSMGameDayZNamedXmlNodes -TargetPath $TargetPath -SourcePath $SourcePath -RootXPath '/spawnabletypes' -NodeXPath '/spawnabletypes/type|/type' -NameAttribute 'name' -AllowSourceFragmentWrap -SourceFragmentRootName 'spawnabletypes')
}

function Get-UGSMGameDayZCandidateModXmlPath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$ModRoot,
        [Parameter(Mandatory)][string[]]$RelativeCandidates
    )

    foreach ($relativePath in $RelativeCandidates) {
        $candidatePath = Join-Path $ModRoot $relativePath
        if (Test-Path -LiteralPath $candidatePath -PathType Leaf) {
            return $candidatePath
        }
    }

    foreach ($fileName in @($RelativeCandidates | ForEach-Object { Split-Path -Leaf $_ } | Select-Object -Unique)) {
        $match = Get-ChildItem -LiteralPath $ModRoot -Recurse -File -Filter $fileName -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($match) {
            return [string]$match.FullName
        }
    }

    return $null
}

function Find-UGSMGameDayZModXmlCandidates {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$ModSourcePath,
        [Parameter(Mandatory)][ValidateSet('Types', 'Events', 'SpawnableTypes')][string]$Kind
    )

    $results = New-Object System.Collections.Generic.List[object]

    if ([string]::IsNullOrWhiteSpace([string]$ModSourcePath)) { return @() }
    if (-not (Test-Path -LiteralPath $ModSourcePath -PathType Container)) { return @() }

    $expectedRoot = switch ($Kind) {
        'Types' { 'types' }
        'Events' { 'events' }
        'SpawnableTypes' { 'spawnabletypes' }
    }

    $entryName = switch ($Kind) {
        'Types' { 'type' }
        'Events' { 'event' }
        'SpawnableTypes' { 'type' }
    }

    # Explicit char[] avoids .NET overload binding errors like:
    # "Argument types do not match"
    $pathTrimChars = [char[]]@('\', '/')
    $rootPath = ([string]$ModSourcePath).TrimEnd($pathTrimChars)
    $rootLength = $rootPath.Length

    $xmlFiles = @(
        Get-ChildItem `
            -LiteralPath $ModSourcePath `
            -Filter '*.xml' `
            -Recurse `
            -File `
            -ErrorAction SilentlyContinue
    )

    foreach ($file in $xmlFiles) {
        $doc = $null

        try {
            $doc = Read-UGSMGameDayZXmlDocumentSafe `
                -Path $file.FullName `
                -AllowFragmentWrap `
                -FragmentRootName $expectedRoot
        }
        catch {
            continue
        }

        if (-not $doc -or -not $doc.DocumentElement) { continue }

        $docRootName = ([string]$doc.DocumentElement.Name).ToLowerInvariant()
        $entryNodes = $null

        if ($docRootName -eq $expectedRoot) {
            $entryNodes = $doc.SelectNodes(('/{0}/{1}' -f $expectedRoot, $entryName))
        }
        elseif ($docRootName -eq $entryName) {
            $entryNodes = $doc.SelectNodes(('/{0}' -f $entryName))
        }
        else {
            continue
        }

        $entryCount = 0
        if ($entryNodes) { $entryCount = [int]$entryNodes.Count }
        if ($entryCount -le 0) { continue }

        $relative = [string]$file.FullName
        if ($relative.Length -gt $rootLength) {
            $relative = $relative.Substring($rootLength).TrimStart($pathTrimChars)
        }

        [void]$results.Add([pscustomobject]@{
            RelativePath = [string]$relative
            FullPath     = [string]$file.FullName
            RootElement  = [string]$doc.DocumentElement.Name
            EntryCount   = [int]$entryCount
        })
    }

    return @($results | Sort-Object EntryCount -Descending)
}

function Merge-UGSMGameDayZActiveModXmlFiles {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$Instance,
        [AllowNull()][object]$Runtime,
        [ValidateSet('All', 'Types', 'Events', 'SpawnableTypes')]
        [string]$Kind = 'All'
    )

    $mergeStage = 'enter'
    $currentModName = ''
    $currentKind = ''
    $currentFile = ''

    $typesAdded = 0
    $eventsAdded = 0
    $spawnableTypesAdded = 0
    $resolvedMods = 0
    $candidateFiles = New-Object System.Collections.Generic.List[object]
    $skippedFiles = New-Object System.Collections.Generic.List[object]

    try {
        if (-not $Runtime) {
            $mergeStage = 'resolve-runtime-definition'
            $installDefinition = Get-UGSMGameDayZInstallDefinition -InstallPath $Instance.InstallPath -Instance $Instance
            $Runtime = Get-UGSMGameDayZRuntimeDefinition -Instance $Instance -InstallDefinition $installDefinition
        }

        $mergeStage = 'resolve-profile-paths'
        $paths = Get-UGSMGameDayZProfilePaths -Instance $Instance

        $mergeStage = 'resolve-active-mods'
        $activeMods = @(Get-UGSMGameDayZResolvedActiveMods -Instance $Instance)

        $doTypes = ($Kind -eq 'All' -or $Kind -eq 'Types')
        $doEvents = ($Kind -eq 'All' -or $Kind -eq 'Events')
        $doSpawnableTypes = ($Kind -eq 'All' -or $Kind -eq 'SpawnableTypes')

        if ($doTypes -and (Test-Path -LiteralPath $paths.RuntimeTypesPath -PathType Leaf)) {
            $mergeStage = 'backup-types-xml'
            Backup-UGSMGameDayZXmlFile -TargetPath $paths.RuntimeTypesPath | Out-Null
        }

        if ($doEvents -and (Test-Path -LiteralPath $paths.RuntimeEventsPath -PathType Leaf)) {
            $mergeStage = 'backup-events-xml'
            Backup-UGSMGameDayZXmlFile -TargetPath $paths.RuntimeEventsPath | Out-Null
        }

        $mergeStage = 'resolve-spawnable-target'
        $spawnableTargetPath = Resolve-UGSMGameDayZRuntimeSpawnableTypesTargetPath -Instance $Instance

        if ($doSpawnableTypes -and -not [string]::IsNullOrWhiteSpace([string]$spawnableTargetPath) -and (Test-Path -LiteralPath $spawnableTargetPath -PathType Leaf)) {
            $mergeStage = 'backup-spawnable-xml'
            Backup-UGSMGameDayZXmlFile -TargetPath $spawnableTargetPath | Out-Null
        }

        foreach ($mod in $activeMods) {
            $currentModName = [string]$mod.Name
            $modRoot = [string]$mod.SourcePath

            if ([string]::IsNullOrWhiteSpace($modRoot) -or -not (Test-Path -LiteralPath $modRoot -PathType Container)) {
                continue
            }

            $resolvedMods++

            if ($doTypes -and [bool]$mod.MergeTypes -and (Test-Path -LiteralPath $paths.RuntimeTypesPath -PathType Leaf)) {
                $currentKind = 'types'
                $mergeStage = 'find-types-candidates'

                $typeCandidates = @()
                try {
                    $typeCandidates = @(Find-UGSMGameDayZModXmlCandidates -ModSourcePath $modRoot -Kind 'Types')
                }
                catch {
                    [void]$skippedFiles.Add([pscustomobject]@{
                        ModName = [string]$mod.Name
                        ModId   = [string]$mod.Id
                        Kind    = 'types'
                        File    = [string]$modRoot
                        Error   = 'Candidate scan failed: ' + $_.Exception.Message
                    })
                    continue
                }

                foreach ($candidate in $typeCandidates) {
                    $currentFile = [string]$candidate.FullPath
                    [void]$candidateFiles.Add($candidate)
                    $mergeStage = 'merge-types-xml'

                    try {
                        $typesAdded += [int](Merge-UGSMGameDayZTypesXml -TargetPath $paths.RuntimeTypesPath -SourcePath $currentFile)
                    }
                    catch {
                        [void]$skippedFiles.Add([pscustomobject]@{
                            ModName = [string]$mod.Name
                            ModId   = [string]$mod.Id
                            Kind    = 'types'
                            File    = $currentFile
                            Error   = $_.Exception.Message
                        })
                    }
                }
            }

            if ($doEvents -and [bool]$mod.MergeEvents -and (Test-Path -LiteralPath $paths.RuntimeEventsPath -PathType Leaf)) {
                $currentKind = 'events'
                $mergeStage = 'find-events-candidates'

                $eventCandidates = @()
                try {
                    $eventCandidates = @(Find-UGSMGameDayZModXmlCandidates -ModSourcePath $modRoot -Kind 'Events')
                }
                catch {
                    [void]$skippedFiles.Add([pscustomobject]@{
                        ModName = [string]$mod.Name
                        ModId   = [string]$mod.Id
                        Kind    = 'events'
                        File    = [string]$modRoot
                        Error   = 'Candidate scan failed: ' + $_.Exception.Message
                    })
                    continue
                }

                foreach ($candidate in $eventCandidates) {
                    $currentFile = [string]$candidate.FullPath
                    [void]$candidateFiles.Add($candidate)
                    $mergeStage = 'merge-events-xml'

                    try {
                        $eventsAdded += [int](Merge-UGSMGameDayZEventsXml -TargetPath $paths.RuntimeEventsPath -SourcePath $currentFile)
                    }
                    catch {
                        [void]$skippedFiles.Add([pscustomobject]@{
                            ModName = [string]$mod.Name
                            ModId   = [string]$mod.Id
                            Kind    = 'events'
                            File    = $currentFile
                            Error   = $_.Exception.Message
                        })
                    }
                }
            }

            if ($doSpawnableTypes -and [bool]$mod.MergeSpawnableTypes -and -not [string]::IsNullOrWhiteSpace([string]$spawnableTargetPath) -and (Test-Path -LiteralPath $spawnableTargetPath -PathType Leaf)) {
                $currentKind = 'cfgspawnabletypes'
                $mergeStage = 'find-spawnable-candidates'

                $spawnableCandidates = @()
                try {
                    $spawnableCandidates = @(Find-UGSMGameDayZModXmlCandidates -ModSourcePath $modRoot -Kind 'SpawnableTypes')
                }
                catch {
                    [void]$skippedFiles.Add([pscustomobject]@{
                        ModName = [string]$mod.Name
                        ModId   = [string]$mod.Id
                        Kind    = 'cfgspawnabletypes'
                        File    = [string]$modRoot
                        Error   = 'Candidate scan failed: ' + $_.Exception.Message
                    })
                    continue
                }

                foreach ($candidate in $spawnableCandidates) {
                    $currentFile = [string]$candidate.FullPath
                    [void]$candidateFiles.Add($candidate)
                    $mergeStage = 'merge-cfgspawnabletypes-xml'

                    try {
                        $spawnableTypesAdded += [int](Merge-UGSMGameDayZSpawnableTypesXml -TargetPath $spawnableTargetPath -SourcePath $currentFile)
                    }
                    catch {
                        [void]$skippedFiles.Add([pscustomobject]@{
                            ModName = [string]$mod.Name
                            ModId   = [string]$mod.Id
                            Kind    = 'cfgspawnabletypes'
                            File    = $currentFile
                            Error   = $_.Exception.Message
                        })
                    }
                }
            }
        }

        $candidateFileList = @()
        foreach ($candidateFile in $candidateFiles) {
            if ($null -ne $candidateFile) { $candidateFileList += $candidateFile }
        }

        $skippedFileList = @()
        foreach ($skippedFile in $skippedFiles) {
            if ($null -ne $skippedFile) { $skippedFileList += $skippedFile }
        }

        return [pscustomobject]@{
            Kind                = [string]$Kind

            ActiveModsCount     = [int]@($activeMods).Count
            ResolvedModsCount   = [int]$resolvedMods
            CandidateFilesCount = [int]@($candidateFileList).Count
            MergedFilesCount    = [int]@($candidateFileList).Count
            SkippedFilesCount   = [int]@($skippedFileList).Count

            ActiveMods          = [int]@($activeMods).Count
            ResolvedMods        = [int]$resolvedMods
            CandidateFiles      = @($candidateFileList)
            FilesMerged         = [int]@($candidateFileList).Count
            SkippedFiles        = @($skippedFileList)

            TypesAdded          = [int]$typesAdded
            EventsAdded         = [int]$eventsAdded
            SpawnableTypesAdded = [int]$spawnableTypesAdded
        }
    }
    catch {
        if (Get-Command Write-UGSMLogEntry -ErrorAction SilentlyContinue) {
            Write-UGSMLogEntry -Category 'DayZ' -Level Error -Message ("Merge diagnostic: stage=$mergeStage ; mod='$currentModName' ; kind='$currentKind' ; file='$currentFile' ; error=$($_.Exception.Message)")
        }
        throw
    }
}
function Get-UGSMGameDayZLaunchModString {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$Instance,
        [AllowNull()][object]$Runtime
    )

    if (-not $Runtime) {
        $installDefinition = Get-UGSMGameDayZInstallDefinition -InstallPath $Instance.InstallPath -Instance $Instance
        $Runtime = Get-UGSMGameDayZRuntimeDefinition -Instance $Instance -InstallDefinition $installDefinition
    }

    $modPaths = New-Object System.Collections.Generic.List[string]
    foreach ($mod in @(Get-UGSMGameDayZResolvedActiveMods -Instance $Instance)) {
        if ([bool]$mod.IsServerMod) { continue }

        $sourcePath = [string]$mod.SourcePath
        if ([string]::IsNullOrWhiteSpace($sourcePath)) { continue }

        if (Test-Path -LiteralPath $sourcePath -PathType Container) {
            [void]$modPaths.Add($sourcePath)
        }
    }

    if ($modPaths.Count -eq 0) {
        return ''
    }

    return ('-mod={0}' -f ([string]::Join(';', @($modPaths))))
}

function Write-UGSMGameDayZStartDiagnostic {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Stage,
        [Parameter(Mandatory)][object]$ErrorRecord
    )

    if (-not (Get-Command Write-UGSMLogEntry -ErrorAction SilentlyContinue)) { return }

    $exception = $ErrorRecord.Exception
    $parts = New-Object System.Collections.Generic.List[string]
    [void]$parts.Add(('stage={0}' -f $Stage))
    if ($exception) {
        [void]$parts.Add(('type={0}' -f $exception.GetType().FullName))
        [void]$parts.Add(('message={0}' -f $exception.Message))
        $inner = $exception.InnerException
        while ($inner) {
            [void]$parts.Add(('inner={0}: {1}' -f $inner.GetType().FullName, $inner.Message))
            $inner = $inner.InnerException
        }
    }
    $invocation = $ErrorRecord.InvocationInfo
    if ($invocation) {
        [void]$parts.Add(('at={0}:{1}' -f [string]$invocation.ScriptName, [int]$invocation.ScriptLineNumber))
        [void]$parts.Add(('line={0}' -f ([string]$invocation.Line).Trim()))
    }
    if ($ErrorRecord.ScriptStackTrace) {
        [void]$parts.Add(('stack={0}' -f ([string]$ErrorRecord.ScriptStackTrace -replace "`r?`n", ' | ')))
    }

    Write-UGSMLogEntry -Category 'DayZ' -Level Error -Message ('Start diagnostic: ' + [string]::Join(' ; ', $parts))
}

function Start-UGSMGameDayZInstance {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Instance
    )

    $diagStage = 'enter'
    try {

        if (-not $Instance) {
            throw 'DayZ start failed: Instance was null.'
        }

        $diagStage = 'validate-install'
        $validation = Test-UGSMGameDayZInstall -InstallPath $Instance.InstallPath
        if (-not $validation -or -not $validation.IsInstalled -or -not $validation.ServerExecutableExists) {
            throw 'DayZ start failed: DayZ is not installed or the server executable is missing.'
        }

        $diagStage = 'resolve-install-definition'
        $installDef = Get-UGSMGameDayZInstallDefinition -InstallPath $Instance.InstallPath -Instance $Instance
        if (-not $installDef) {
            throw 'DayZ start failed: Install definition could not be resolved.'
        }

        $diagStage = 'resolve-profile-path'
        $profilePath = $null
        if ($Instance.PSObject.Properties.Name -contains 'ProfilePath' -and -not [string]::IsNullOrWhiteSpace([string]$Instance.ProfilePath)) {
            $profilePath = [string]$Instance.ProfilePath
        }
        else {
            $profilePath = Get-UGSMGameDayZProfileRoot -ProfileName ([string]$Instance.Name)
        }

        if ([string]::IsNullOrWhiteSpace($profilePath) -or -not (Test-Path -LiteralPath $profilePath -PathType Container)) {
            throw "DayZ start failed: Profile path was not found: $profilePath"
        }

        $diagStage = 'ensure-runtime-layout'
        $runtime = Ensure-UGSMGameDayZRuntimeLayout -Instance $Instance -InstallDefinition $installDef
        $paths = Get-UGSMGameDayZProfilePaths -Instance $Instance

        $serverExe = [string]$installDef.ServerExecutablePath
        $mainConfigPath = [string]$runtime.RuntimeMainConfigPath
        $profilesPath = [string]$runtime.RuntimeProfilesRoot
        $missionPath = [string]$paths.RuntimeMissionPath

        $diagStage = 'sync-mod-files'
        $modSyncResult = Sync-UGSMGameDayZModFilesToRuntime -Instance $Instance -Runtime $runtime
        $diagStage = 'ensure-traderplus-defaults'
        $traderPlusSeedResult = Ensure-UGSMGameDayZTraderPlusDefaultConfigFiles -Instance $Instance -Runtime $runtime
        $diagStage = 'merge-xml'
        $xmlMergeResult = Merge-UGSMGameDayZActiveModXmlFiles -Instance $Instance -Runtime $runtime
        $diagStage = 'build-mod-argument'
        $modArgument = Get-UGSMGameDayZLaunchModString -Instance $Instance -Runtime $runtime

        $diagStage = 'verify-runtime-paths'
        if (-not (Test-Path -LiteralPath $serverExe -PathType Leaf)) {
            throw "DayZ start failed: shared install server executable was not found: $serverExe"
        }

        if (-not (Test-Path -LiteralPath $mainConfigPath -PathType Leaf)) {
            throw "DayZ start failed: runtime serverDZ.cfg was not found: $mainConfigPath"
        }

        if (-not (Test-Path -LiteralPath $profilesPath -PathType Container)) {
            throw "DayZ start failed: runtime profiles path was not found: $profilesPath"
        }

        if (-not (Test-Path -LiteralPath $missionPath -PathType Container)) {
            throw "DayZ start failed: runtime mission path was not found: $missionPath"
        }

        $diagStage = 'resolve-game-port'
        $gamePort = '2302'
        if ($Instance.PSObject.Properties.Name -contains 'GamePort' -and -not [string]::IsNullOrWhiteSpace([string]$Instance.GamePort)) {
            $gamePort = [string]$Instance.GamePort
        }

        $diagStage = 'build-launch-args'
        $launchArgs = @(
            ('-config={0}' -f $mainConfigPath)
            ('-profiles={0}' -f $profilesPath)
            ('-mission={0}' -f $missionPath)
            ('-port={0}' -f $gamePort)
            '-dologs'
            '-adminlog'
            '-netlog'
            '-freezecheck'
        )

        if (-not [string]::IsNullOrWhiteSpace([string]$modArgument)) {
            $launchArgs += $modArgument
        }

        $diagStage = 'start-process'
        $proc = Start-Process -FilePath $serverExe -ArgumentList $launchArgs -PassThru
        if (-not $proc -or -not $proc.Id) {
            throw 'DayZ start failed: Start-Process did not return a valid process.'
        }

        $gamePid = [int]$proc.Id

        $diagStage = 'update-instance-state'
        if ($Instance.PSObject.Properties.Name -contains 'Pid') { $Instance.Pid = $gamePid }
        if ($Instance.PSObject.Properties.Name -contains 'Status') { $Instance.Status = 'Running' }
        if ($Instance.PSObject.Properties.Name -contains 'ProfilePath' -and [string]::IsNullOrWhiteSpace([string]$Instance.ProfilePath)) {
            $Instance.ProfilePath = $profilePath
        }

        $diagStage = 'write-runtime-marker'
        try {
            $runtimeMarker = Join-Path $runtime.RuntimeConfigRootPath 'UGSM.Runtime.json'
            $runtimeData = [pscustomobject]@{
                InstanceId      = [string]$Instance.Id
                GameId          = 'DayZ'
                ProfilePath     = $profilePath
                RuntimeRoot     = [string]$runtime.RuntimeRoot
                RuntimeInstall  = [string]$runtime.RuntimeInstallRoot
                RuntimeProfiles = [string]$runtime.RuntimeConfigRootPath
                RuntimeMissions = [string]$runtime.RuntimeSaveRootPath
                MainConfigPath  = $mainConfigPath
                Pid             = $gamePid
                StartedAtUtc    = [DateTime]::UtcNow.ToString('o')
                Mods            = $modSyncResult
                TraderPlusSeed  = $traderPlusSeedResult
                XmlMerge        = $xmlMergeResult
            }
            $runtimeData | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $runtimeMarker -Encoding UTF8
        }
        catch {}

        $diagStage = 'return-result'
        return [pscustomobject]@{
            Instance = $Instance
            Pid      = $gamePid
            Status   = 'Running'
            Runtime  = $runtime
            Mods            = $modSyncResult
            TraderPlusSeed  = $traderPlusSeedResult
            XmlMerge        = $xmlMergeResult
        }

    }
    catch {
        Write-UGSMGameDayZStartDiagnostic -Stage $diagStage -ErrorRecord $_
        throw
    }
}


function Stop-UGSMGameDayZInstance {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Instance
    )

    if (-not $Instance) {
        throw 'DayZ stop failed: Instance was null.'
    }

    $installDef = Get-UGSMGameDayZInstallDefinition -InstallPath $Instance.InstallPath -Instance $Instance
    if (-not $installDef) {
        throw 'DayZ stop failed: Install definition could not be resolved.'
    }

    $runtime = Get-UGSMGameDayZRuntimeDefinition -Instance $Instance -InstallDefinition $installDef

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
        throw ("DayZ stop failed: Process {0} is still running." -f $targetProcessId)
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

function Register-UGSMGameDayZModule {
    [CmdletBinding()]
    param()

    $metadata = Get-UGSMGameDayZMetadata

    return [pscustomobject]@{
        Id       = [string]$metadata.Id
        Metadata = $metadata
        Handlers = [pscustomobject]@{
            GetMetadata          = 'Get-UGSMGameDayZMetadata'
            GetInstallDefinition = 'Get-UGSMGameDayZInstallDefinition'
            TestInstall          = 'Test-UGSMGameDayZInstall'
            TestInstance         = 'Test-UGSMGameDayZInstance'
            EnsureTemplate       = 'Ensure-UGSMGameDayZDayZ'
            InitializeProfile    = 'Initialize-UGSMGameDayZProfile'
            Start                = 'Start-UGSMGameDayZInstance'
            Stop                 = 'Stop-UGSMGameDayZInstance'
            BuildEditor          = 'New-UGSMGameDayZInstanceEditor'
            SaveEditor           = 'Save-UGSMGameDayZInstanceEditor'
            BuildModsUi          = 'New-UGSMGameDayZModsEditor'
        }
    }
}


function Get-UGSMGameDayZProfilePaths {
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
        $profileRoot = Get-UGSMGameDayZProfileRoot -ProfileName ([string]$Instance.Name)
    }
    elseif (Get-Command -Name Get-UGSMDefaultInstanceProfilePath -ErrorAction SilentlyContinue) {
        $profileRoot = Get-UGSMDefaultInstanceProfilePath -GameId 'DayZ' -Name ([string]$Instance.Name)
    }

    if ([string]::IsNullOrWhiteSpace([string]$profileRoot)) {
        throw 'DayZ profile paths could not be resolved for the selected instance.'
    }

    $runtimeRoot = Get-UGSMGameDayZRuntimeRoot -Instance $Instance
    $runtimeInstallRoot = $runtimeRoot
    $runtimeMissionRoot = Join-Path $runtimeInstallRoot 'mpmissions'
    $runtimeMissionName = 'dayzOffline.chernarusplus'
    $runtimeMissionPath = Join-Path $runtimeMissionRoot $runtimeMissionName
    $runtimeDbPath = Join-Path $runtimeMissionPath 'db'
    $runtimeEnvPath = Join-Path $runtimeMissionPath 'env'

    [pscustomobject]@{
        Instance                    = $Instance

        ProfileRoot                 = $profileRoot
        RuntimeRoot                 = $runtimeRoot
        RuntimeInstallRoot          = $runtimeInstallRoot
        RuntimeMissionRoot          = $runtimeMissionRoot
        RuntimeMissionName          = $runtimeMissionName
        RuntimeMissionPath          = $runtimeMissionPath
        RuntimeDbPath               = $runtimeDbPath
        RuntimeEnvPath              = $runtimeEnvPath
        RuntimeInstallPath          = $runtimeInstallPath

        ConfigRoot                  = $runtimeInstallRoot
        SaveRoot                    = $runtimeMissionRoot
        LogRoot                     = $runtimeInstallRoot

        RuntimeModsRoot             = $runtimeInstallRoot
        RuntimeKeysRoot             = (Join-Path $runtimeInstallRoot 'keys')
        RuntimeAddonsRoot           = (Join-Path $runtimeInstallRoot 'addons')

        ServerSettingsPath          = (Join-Path $runtimeInstallRoot 'serverDZ.cfg')
        InitPath                    = (Join-Path $runtimeMissionPath 'init.c')
        MissionFolderPath           = $runtimeMissionPath
        DbFolderPath                = $runtimeDbPath
        EnvFolderPath               = $runtimeEnvPath

        RuntimeTypesPath            = (Join-Path $runtimeDbPath 'types.xml')
        RuntimeEventsPath           = (Join-Path $runtimeDbPath 'events.xml')
        RuntimeSpawnableTypesPath   = (Join-Path $runtimeMissionPath 'cfgspawnabletypes.xml')
        RuntimeSpawnableTypesDbPath = (Join-Path $runtimeDbPath 'cfgspawnabletypes.xml')

        RuntimeGlobalsPath          = (Join-Path $runtimeDbPath 'globals.xml')
        RuntimeEconomyPath          = (Join-Path $runtimeDbPath 'economy.xml')
        RuntimeMessagesPath         = (Join-Path $runtimeDbPath 'messages.xml')
        RuntimeCfgGameplayPath      = Join-Path $runtimeMissionPath 'cfggameplay.json'
    }
}

function Read-UGSMGameDayZIniFile {
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

function Get-UGSMGameDayZIniValue {
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

function Set-UGSMGameDayZIniValue {
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

function Read-UGSMGameDayZStringListFile {
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

function Write-UGSMGameDayZStringListFile {
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

function Set-UGSMGameDayZCfgValue {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Key,
        [Parameter(Mandatory)][string]$Value
    )

    if ([string]::IsNullOrWhiteSpace($Path)) {
        throw 'DayZ cfg save failed: target path was blank.'
    }

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw ("DayZ cfg save failed: target file does not exist: {0}" -f $Path)
    }

    $lines = @(Get-Content -LiteralPath $Path -ErrorAction Stop)
    $escapedKey = [Regex]::Escape($Key)
    $pattern = '^\s*' + $escapedKey + '\s*=\s*.*?;\s*(//.*)?$'
    $updated = $false

    for ($i = 0; $i -lt $lines.Count; $i++) {
        $line = [string]$lines[$i]

        if ($line -match $pattern) {
            $comment = ''
            if ($line -match ';\s*(//.*)$') {
                $comment = ' ' + [string]$Matches[1]
            }

            $lines[$i] = ('{0}={1};{2}' -f $Key, $Value, $comment)
            $updated = $true
            break
        }
    }

    if (-not $updated) {
        $lines += ('{0}={1};' -f $Key, $Value)
    }

    Set-Content -LiteralPath $Path -Value $lines -Encoding UTF8
}

function Get-UGSMGameDayZCfgValue {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Key,
        $DefaultValue = $null
    )

    if ([string]::IsNullOrWhiteSpace($Path) -or -not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        return $DefaultValue
    }

    $content = Get-Content -LiteralPath $Path -Raw -ErrorAction SilentlyContinue
    if ([string]::IsNullOrWhiteSpace($content)) {
        return $DefaultValue
    }

    $escapedKey = [Regex]::Escape($Key)
    $pattern = '(?im)^\s*' + $escapedKey + '\s*=\s*([^;]*?)\s*;'

    $match = [Regex]::Match($content, $pattern)
    if (-not $match.Success) {
        return $DefaultValue
    }

    $value = [string]$match.Groups[1].Value.Trim()

    if ($value.Length -ge 2 -and $value.StartsWith('"') -and $value.EndsWith('"')) {
        $value = $value.Substring(1, $value.Length - 2)
    }

    return $value
}

function Get-DayZSafeFieldValue {
    param([hashtable]$Field)

    try {
        return Get-UGSMGameDayZEditorFieldCurrentValue -Field $Field -Paths $paths
    }
    catch {
        if ($StatusLabel) {
            $StatusLabel.Text = 'DayZ field load failed for ' + [string]$Field.Id + ': ' + $_.Exception.Message
        }

        return $(if ($Field.ContainsKey('DefaultValue')) { $Field.DefaultValue } else { $null })
    }
}

function Resolve-UGSMGameDayZEditorFilePath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Paths,
        [Parameter(Mandatory)][hashtable]$Field
    )

    switch ([string]$Field.File) {
        'serverDZ.cfg' { return [string]$Paths.ServerSettingsPath }
        'init.c' { return [string]$Paths.InitPath }
        default {
            throw ("DayZ file resolver failed: unsupported file target '{0}'." -f [string]$Field.File)
        }
    }
}

function Resolve-UGSMGameDayZEditorFieldPath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][hashtable]$Field,
        [Parameter(Mandatory)]$Paths,
        [ValidateSet('Active', 'Profile', 'Runtime')]
        [string]$TargetSet = 'Active'
    )

    if ($Field.ContainsKey('Path') -and -not [string]::IsNullOrWhiteSpace([string]$Field.Path)) {
        $rawPath = [string]$Field.Path

        if ([System.IO.Path]::IsPathRooted($rawPath)) {
            return $rawPath
        }

        switch ($TargetSet) {
            'Profile' { $baseRoot = [string]$Paths.ProfileRoot }
            'Runtime' { $baseRoot = [string]$Paths.RuntimeRoot }
            default {
                $baseRoot = [string]$Paths.RuntimeRoot
                if ([string]::IsNullOrWhiteSpace($baseRoot)) {
                    $baseRoot = [string]$Paths.ProfileRoot
                }
            }
        }

        if (-not [string]::IsNullOrWhiteSpace($baseRoot)) {
            return [string](Join-Path $baseRoot $rawPath)
        }
    }

    if ($Field.ContainsKey('File') -and -not [string]::IsNullOrWhiteSpace([string]$Field.File)) {
        return Resolve-UGSMGameDayZEditorFilePath -Paths $Paths -Field $Field
    }

    return $null
}

function Get-UGSMGameDayZFieldDecimalPlaces {
    [CmdletBinding()]
    param([Parameter(Mandatory)][hashtable]$Field)

    if ($Field.ContainsKey('Decimals')) { return [int]$Field.Decimals }
    if ($Field.ContainsKey('Increment')) {
        $incrementText = ([string]$Field.Increment).Trim()
        $dotIndex = $incrementText.IndexOf('.')
        if ($dotIndex -ge 0) { return ($incrementText.Length - $dotIndex - 1) }
    }
    if ([string]$Field.Type -eq 'Decimal') { return 2 }
    return 0
}

function ConvertTo-UGSMGameDayZEditorFieldValue {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][hashtable]$Field,
        [Parameter(Mandatory)]$Control
    )

    switch ([string]$Field.Type) {
        'Boolean' {
            return [string]$(if ($Control.Checked) { '1' } else { '0' })
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
        'Decimal' {
            $raw = [decimal]$Control.Value
            $decimals = Get-UGSMGameDayZFieldDecimalPlaces -Field $Field
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

function Save-UGSMGameDayZInstanceEditor {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$Instance,
        [Parameter(Mandatory)][hashtable]$EditorState
    )

    $paths = Get-UGSMGameDayZProfilePaths -Instance $Instance

    foreach ($dirPath in @($paths.ConfigRoot, $paths.SaveRoot, $paths.LogRoot)) {
        if (-not [string]::IsNullOrWhiteSpace([string]$dirPath) -and -not (Test-Path -LiteralPath $dirPath -PathType Container)) {
            New-Item -ItemType Directory -Path $dirPath -Force | Out-Null
        }
    }

    $saveSummary = [ordered]@{
        IniKeysWritten       = 0
        StringListsWritten   = 0
        RuntimeCopiesUpdated = 0
    }

    $updatedInstance = $Instance
    $discordInput = [ordered]@{}
    $hasDiscordChanges = $false

    foreach ($entry in $EditorState.GetEnumerator()) {
        $item = $entry.Value
        if (-not $item) { continue }

        $field = $item.Field
        $control = $item.Control
        if (-not $field -or -not $control) { continue }

        switch ([string]$field.Type) {
            'StringList' {
                $targetPath = Resolve-UGSMGameDayZEditorFieldPath -Field $field -Paths $paths -TargetSet Runtime
                if ([string]::IsNullOrWhiteSpace([string]$targetPath)) {
                    $targetPath = Resolve-UGSMGameDayZEditorFieldPath -Field $field -Paths $paths
                }

                if ([string]::IsNullOrWhiteSpace([string]$targetPath)) {
                    throw ("DayZ save failed: no runtime path could be resolved for string list field '{0}'." -f [string]$field.Id)
                }

                $values = @($control.Lines | ForEach-Object { [string]$_ })
                Write-UGSMGameDayZStringListFile -Path $targetPath -Values $values
                $saveSummary.StringListsWritten++
                $saveSummary.RuntimeCopiesUpdated++
            }

            'Boolean' {
                $value = ConvertTo-UGSMGameDayZEditorFieldValue -Field $field -Control $control
                if ([string]$field.Format -eq 'Cfg') {
                    $targetPath = Resolve-UGSMGameDayZEditorFilePath -Paths $paths -Field $field
                    Set-UGSMGameDayZCfgValue -Path $targetPath -Key ([string]$field.Key) -Value $value
                    $saveSummary.IniKeysWritten++
                    $saveSummary.RuntimeCopiesUpdated++
                }
            }

            'Number' {
                $value = ConvertTo-UGSMGameDayZEditorFieldValue -Field $field -Control $control
                if ([string]$field.Format -eq 'Cfg') {
                    $targetPath = Resolve-UGSMGameDayZEditorFilePath -Paths $paths -Field $field
                    Set-UGSMGameDayZCfgValue -Path $targetPath -Key ([string]$field.Key) -Value $value
                    $saveSummary.IniKeysWritten++
                    $saveSummary.RuntimeCopiesUpdated++
                }
            }

            'Decimal' {
                $value = ConvertTo-UGSMGameDayZEditorFieldValue -Field $field -Control $control
                if ([string]$field.Format -eq 'Cfg') {
                    $targetPath = Resolve-UGSMGameDayZEditorFilePath -Paths $paths -Field $field
                    Set-UGSMGameDayZCfgValue -Path $targetPath -Key ([string]$field.Key) -Value $value
                    $saveSummary.IniKeysWritten++
                    $saveSummary.RuntimeCopiesUpdated++
                }
            }

            'Text' {
                $value = [string](ConvertTo-UGSMGameDayZEditorFieldValue -Field $field -Control $control)

                if ([string]$field.Format -eq 'Cfg') {
                    $targetPath = Resolve-UGSMGameDayZEditorFilePath -Paths $paths -Field $field

                    # DayZ cfg strings should just be quoted normally.
                    $quotedValue = '"' + $value + '"'

                    Set-UGSMGameDayZCfgValue -Path $targetPath -Key ([string]$field.Key) -Value $quotedValue
                    $saveSummary.IniKeysWritten++
                    $saveSummary.RuntimeCopiesUpdated++
                }
            }

            'InstanceText' {
                $value = [string](ConvertTo-UGSMGameDayZEditorFieldValue -Field $field -Control $control)
                if ([string]$field.Model -eq 'Discord') {
                    $discordInput[[string]$field.Property] = $value
                    $hasDiscordChanges = $true
                }
            }

            'InstanceBoolean' {
                $value = [bool](ConvertTo-UGSMGameDayZEditorFieldValue -Field $field -Control $control)
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
            [void](Save-UGSMGameDayZInstanceDefinition -Instance $PersistedInstance)
        }

        $discordResult = Save-UGSMInstanceDiscordSettingsModel -Instance $updatedInstance -InputObject ([pscustomobject]$discordInput) -PersistInstance $persistScript
        if ($discordResult -and $discordResult.PSObject.Properties['Instance']) {
            $updatedInstance = $discordResult.Instance
        }
    }

    return [pscustomobject]@{
        Success  = $true
        Message  = ("Saved DayZ runtime settings. INI keys: {0}. User lists: {1}." -f $saveSummary.IniKeysWritten, $saveSummary.StringListsWritten)
        Summary  = [pscustomobject]$saveSummary
        Instance = $updatedInstance
    }
}

function Convert-UGSMGameDayZEditorFieldValue {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][hashtable]$Field,
        [Parameter(Mandatory)]$Control
    )

    switch ([string]$Field.Type) {
        'Boolean' {
            return (if ([bool]$Control.Checked) { '1' } else { '0' })
        }
        'Number' {
            if ($Control.PSObject.Properties.Name -contains 'Value') {
                return ([string]$Control.Value)
            }
            return ([string]$Control.Text)
        }
        default {
            return [string]$Control.Text
        }
    }
}

function Get-UGSMGameDayZXmlEditorTargetPath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$Instance,
        [Parameter(Mandatory)][string]$Kind
    )

    $paths = Get-UGSMGameDayZProfilePaths -Instance $Instance
    $mission = [string]$paths.RuntimeMissionPath

    switch ($Kind) {
        'Types' { return [string]$paths.RuntimeTypesPath }
        'SpawnableTypes' { return [string](Resolve-UGSMGameDayZRuntimeSpawnableTypesTargetPath -Instance $Instance) }
        'Events' { return [string]$paths.RuntimeEventsPath }
        'EventSpawns' { return (Join-Path $mission 'cfgeventspawns.xml') }

        'Globals' { return [string]$paths.RuntimeGlobalsPath }
        'Economy' { return [string]$paths.RuntimeEconomyPath }
        'Messages' { return [string]$paths.RuntimeMessagesPath }
        'CfgGameplay' { return [string]$paths.RuntimeCfgGameplayPath }

        'CfgEconomyCore' { return (Join-Path $mission 'cfgeconomycore.xml') }
        'CfgEffectArea' { return (Join-Path $mission 'cfgeffectarea.json') }
        'CfgEnvironment' { return (Join-Path $mission 'cfgenvironment.xml') }
        'TerritoryZones' { return (Join-Path (Join-Path $mission 'env') 'bear_territories.xml') }
        'CfgEventGroups' { return (Join-Path $mission 'cfgeventgroups.xml') }
        'CfgIgnoreList' { return (Join-Path $mission 'cfgignorelist.xml') }
        'CfgPlayerSpawnPoints' { return (Join-Path $mission 'cfgplayerspawnpoints.xml') }
        'CfgRandomPresets' { return (Join-Path $mission 'cfgrandompresets.xml') }
        'CfgWeather' { return (Join-Path $mission 'cfgweather.xml') }
        'MapGroupPos' { return (Join-Path $mission 'mapgrouppos.xml') }
        'MapGroupProto' { return (Join-Path $mission 'mapgroupproto.xml') }
        'MapGroupCluster' { return (Join-Path $mission 'mapgroupcluster.xml') }
        'MapGroupDirt' { return (Join-Path $mission 'mapgroupdirt.xml') }
        'MapClusterProto' { return (Join-Path $mission 'mapclusterproto.xml') }

        default { return '' }
    }
}

function Read-UGSMGameDayZTextFileSafe {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return '' }
    return [string](Get-Content -LiteralPath $Path -Raw -ErrorAction Stop)
}


function Get-UGSMGameDayZPreferredNewLineChars {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Path)

    $lfFiles = @(
        'cfgeconomycore.xml',
        'cfgeffectarea.json',
        'cfgenvironment.xml',
        'cfgeventgroups.xml',
        'cfgeventspawns.xml',
        'cfggameplay.json',
        'cfgignorelist.xml',
        'cfglimitsdefinition.xml',
        'cfgplayerspawnpoints.xml',
        'cfgrandompresets.xml',
        'cfgspawnabletypes.xml',
        'mapgroupcluster.xml',
        'mapgroupcluster01.xml',
        'mapgroupcluster02.xml',
        'mapgroupcluster03.xml',
        'mapgroupcluster04.xml',
        'mapgrouppos.xml',
        'types.xml',
        'economy.xml',
        'events.xml',
        'globals.xml'
    )

    $leaf = [string]([System.IO.Path]::GetFileName([string]$Path))
    if ($lfFiles -contains $leaf.ToLowerInvariant()) {
        return "`n"
    }

    return "`r`n"
}

function Write-UGSMGameDayZTextFileSafe {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Path,
        [AllowNull()][string]$Content
    )

    $parent = Split-Path -Parent $Path
    if (-not [string]::IsNullOrWhiteSpace([string]$parent) -and -not (Test-Path -LiteralPath $parent -PathType Container)) {
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
    }

    if ($null -eq $Content) {
        $Content = ''
    }

    $normalized = [string]$Content
    $normalized = $normalized -replace "`r`n", "`n"
    $normalized = $normalized -replace "`r", "`n"
    $newlineChars = Get-UGSMGameDayZPreferredNewLineChars -Path $Path
    if ($newlineChars -eq "`r`n") {
        $normalized = $normalized -replace "`n", "`r`n"
    }

    [System.IO.File]::WriteAllText(
        $Path,
        $normalized,
        (New-Object System.Text.UTF8Encoding($false))
    )

    return $Path
}

function Backup-UGSMGameDayZFile {
    [CmdletBinding()]
    param(
        [AllowNull()][object]$Instance,
        [Parameter(Mandatory)][string]$TargetPath
    )

    if ([string]::IsNullOrWhiteSpace($TargetPath) -or -not (Test-Path -LiteralPath $TargetPath -PathType Leaf)) {
        return ''
    }

    $backupPath = Get-UGSMGameDayZBackupDestinationPath -Instance $Instance -TargetPath $TargetPath -BackupExtension '.bak'
    if ([string]::IsNullOrWhiteSpace($backupPath)) {
        $folder = Split-Path -Parent $TargetPath
        $name = [System.IO.Path]::GetFileNameWithoutExtension($TargetPath)
        $ext = [System.IO.Path]::GetExtension($TargetPath)
        $backupPath = Join-Path $folder ("{0}.bak{1}" -f $name, $ext)
    }

    Copy-Item -LiteralPath $TargetPath -Destination $backupPath -Force

    return $backupPath
}

function Remove-UGSMGameDayZOldBackups {
    [CmdletBinding()]
    param(
        [AllowNull()][object]$Instance,
        [Parameter(Mandatory)][string]$TargetPath,
        [int]$Keep = 1
    )

    if ([string]::IsNullOrWhiteSpace($TargetPath)) { return }
    if ($Keep -lt 1) { $Keep = 1 }

    $backupRoot = Get-UGSMGameDayZBackupRoot -Instance $Instance -TargetPath $TargetPath
    if (-not [string]::IsNullOrWhiteSpace($backupRoot) -and (Test-Path -LiteralPath $backupRoot -PathType Container)) {
        $backupLeaf = [System.IO.Path]::GetFileName($TargetPath)
        $pattern = $backupLeaf + '.bak'
        $backups = @(
            Get-ChildItem -LiteralPath $backupRoot -Filter $pattern -File -Recurse -ErrorAction SilentlyContinue |
            Sort-Object LastWriteTime -Descending
        )

        if ($backups.Count -le $Keep) { return }

        foreach ($oldBackup in @($backups | Select-Object -Skip $Keep)) {
            Remove-Item -LiteralPath $oldBackup.FullName -Force -ErrorAction SilentlyContinue
        }
        return
    }

    $folder = Split-Path -Parent $TargetPath
    if ([string]::IsNullOrWhiteSpace($folder) -or -not (Test-Path -LiteralPath $folder -PathType Container)) {
        return
    }

    $name = [System.IO.Path]::GetFileNameWithoutExtension($TargetPath)
    $ext = [System.IO.Path]::GetExtension($TargetPath)
    $pattern = "{0}.*.bak{1}" -f $name, $ext

    $backups = @(
        Get-ChildItem -LiteralPath $folder -Filter $pattern -File -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending
    )

    if ($backups.Count -le $Keep) { return }

    foreach ($oldBackup in @($backups | Select-Object -Skip $Keep)) {
        Remove-Item -LiteralPath $oldBackup.FullName -Force -ErrorAction SilentlyContinue
    }
}

function Read-UGSMGameDayZJsonDataSafe {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Path
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        return [ordered]@{}
    }

    $raw = Get-Content -LiteralPath $Path -Raw -ErrorAction Stop
    if ([string]::IsNullOrWhiteSpace($raw)) {
        return [ordered]@{}
    }

    return ($raw | ConvertFrom-Json -ErrorAction Stop)
}

function Write-UGSMGameDayZJsonDataSafe {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)]$Data
    )

    $parent = Split-Path -Parent $Path
    if (-not [string]::IsNullOrWhiteSpace([string]$parent) -and -not (Test-Path -LiteralPath $parent -PathType Container)) {
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
    }

    $json = ($Data | ConvertTo-Json -Depth 100) -replace "`r`n", "`n"
    $newlineChars = Get-UGSMGameDayZPreferredNewLineChars -Path $Path
    if ($newlineChars -eq "`r`n") {
        $json = $json -replace "`n", "`r`n"
    }
    [System.IO.File]::WriteAllText($Path, $json, (New-Object System.Text.UTF8Encoding($false)))
    return $Path
}

function Test-UGSMGameDayZJsonObjectLike {
    [CmdletBinding()]
    param($Value)

    if ($null -eq $Value) { return $false }
    if ($Value -is [System.Collections.IDictionary]) { return $true }
    if ($Value -is [pscustomobject]) { return $true }
    return $false
}

function Get-UGSMGameDayZJsonObjectPropertyNames {
    [CmdletBinding()]
    param($Value)

    if ($null -eq $Value) { return @() }
    if ($Value -is [System.Collections.IDictionary]) { return @($Value.Keys) }
    return @($Value.PSObject.Properties | ForEach-Object { $_.Name })
}

function Get-UGSMGameDayZJsonObjectPropertyValue {
    [CmdletBinding()]
    param(
        $Value,
        [Parameter(Mandatory)][string]$Name
    )

    if ($null -eq $Value) { return $null }
    if ($Value -is [System.Collections.IDictionary]) {
        if ($Value.Contains($Name)) { return $Value[$Name] }
        return $null
    }

    $property = $Value.PSObject.Properties[$Name]
    if ($property) { return $property.Value }
    return $null
}

function Set-UGSMGameDayZJsonObjectPropertyValue {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][System.Collections.IDictionary]$Target,
        [Parameter(Mandatory)][string]$Name,
        $Value
    )

    $Target[$Name] = $Value
}

function Copy-UGSMGameDayZJsonValue {
    [CmdletBinding()]
    param($Value)

    if ($null -eq $Value) { return $null }

    if (Test-UGSMGameDayZJsonObjectLike -Value $Value) {
        $copy = [ordered]@{}
        foreach ($name in @(Get-UGSMGameDayZJsonObjectPropertyNames -Value $Value)) {
            Set-UGSMGameDayZJsonObjectPropertyValue -Target $copy -Name ([string]$name) -Value (Copy-UGSMGameDayZJsonValue -Value (Get-UGSMGameDayZJsonObjectPropertyValue -Value $Value -Name ([string]$name)))
        }
        return $copy
    }

    if ($Value -is [System.Collections.IEnumerable] -and $Value -isnot [string]) {
        $list = New-Object System.Collections.ArrayList
        foreach ($item in @($Value)) {
            [void]$list.Add((Copy-UGSMGameDayZJsonValue -Value $item))
        }
        return @($list)
    }

    return $Value
}

function Get-UGSMGameDayZJsonMergeArrayKeyName {
    [CmdletBinding()]
    param([Parameter(Mandatory)][object[]]$Items)

    $candidateNames = @('ClassName', 'Classname', 'Name', 'name', 'Id', 'ID', 'TraderId', 'TraderID', 'CategoryId', 'CategoryID')

    foreach ($candidate in $candidateNames) {
        $found = $false
        $allHave = $true
        foreach ($item in @($Items)) {
            if (-not (Test-UGSMGameDayZJsonObjectLike -Value $item)) {
                $allHave = $false
                break
            }

            $value = Get-UGSMGameDayZJsonObjectPropertyValue -Value $item -Name $candidate
            if ($null -eq $value -or [string]::IsNullOrWhiteSpace([string]$value)) {
                $allHave = $false
                break
            }
            $found = $true
        }

        if ($found -and $allHave) {
            return $candidate
        }
    }

    return ''
}

function Merge-UGSMGameDayZJsonValues {
    [CmdletBinding()]
    param(
        $TargetValue,
        $SourceValue
    )

    if ($null -eq $SourceValue) {
        return (Copy-UGSMGameDayZJsonValue -Value $TargetValue)
    }

    if ($null -eq $TargetValue) {
        return (Copy-UGSMGameDayZJsonValue -Value $SourceValue)
    }

    $targetIsObject = Test-UGSMGameDayZJsonObjectLike -Value $TargetValue
    $sourceIsObject = Test-UGSMGameDayZJsonObjectLike -Value $SourceValue
    if ($targetIsObject -and $sourceIsObject) {
        $merged = [ordered]@{}

        foreach ($name in @(Get-UGSMGameDayZJsonObjectPropertyNames -Value $TargetValue)) {
            Set-UGSMGameDayZJsonObjectPropertyValue -Target $merged -Name ([string]$name) -Value (Copy-UGSMGameDayZJsonValue -Value (Get-UGSMGameDayZJsonObjectPropertyValue -Value $TargetValue -Name ([string]$name)))
        }

        foreach ($name in @(Get-UGSMGameDayZJsonObjectPropertyNames -Value $SourceValue)) {
            $key = [string]$name
            $existingValue = Get-UGSMGameDayZJsonObjectPropertyValue -Value $merged -Name $key
            $sourceChild = Get-UGSMGameDayZJsonObjectPropertyValue -Value $SourceValue -Name $key
            if ($null -eq $existingValue) {
                Set-UGSMGameDayZJsonObjectPropertyValue -Target $merged -Name $key -Value (Copy-UGSMGameDayZJsonValue -Value $sourceChild)
            }
            else {
                Set-UGSMGameDayZJsonObjectPropertyValue -Target $merged -Name $key -Value (Merge-UGSMGameDayZJsonValues -TargetValue $existingValue -SourceValue $sourceChild)
            }
        }

        return $merged
    }

    $targetIsArray = ($TargetValue -is [System.Collections.IEnumerable] -and $TargetValue -isnot [string])
    $sourceIsArray = ($SourceValue -is [System.Collections.IEnumerable] -and $SourceValue -isnot [string])
    if ($targetIsArray -and $sourceIsArray) {
        $targetItems = @($TargetValue)
        $sourceItems = @($SourceValue)
        $keyName = Get-UGSMGameDayZJsonMergeArrayKeyName -Items @($targetItems + $sourceItems)

        if (-not [string]::IsNullOrWhiteSpace($keyName)) {
            $mergedList = New-Object System.Collections.ArrayList
            $index = @{}

            foreach ($item in $targetItems) {
                $copied = Copy-UGSMGameDayZJsonValue -Value $item
                [void]$mergedList.Add($copied)
                $itemKey = [string](Get-UGSMGameDayZJsonObjectPropertyValue -Value $copied -Name $keyName)
                if (-not [string]::IsNullOrWhiteSpace($itemKey)) { $index[$itemKey] = $mergedList.Count - 1 }
            }

            foreach ($item in $sourceItems) {
                $itemKey = [string](Get-UGSMGameDayZJsonObjectPropertyValue -Value $item -Name $keyName)
                if (-not [string]::IsNullOrWhiteSpace($itemKey) -and $index.ContainsKey($itemKey)) {
                    $position = [int]$index[$itemKey]
                    $mergedList[$position] = Merge-UGSMGameDayZJsonValues -TargetValue $mergedList[$position] -SourceValue $item
                }
                else {
                    $copied = Copy-UGSMGameDayZJsonValue -Value $item
                    [void]$mergedList.Add($copied)
                    if (-not [string]::IsNullOrWhiteSpace($itemKey)) { $index[$itemKey] = $mergedList.Count - 1 }
                }
            }

            return @($mergedList)
        }

        return (Copy-UGSMGameDayZJsonValue -Value $SourceValue)
    }

    return (Copy-UGSMGameDayZJsonValue -Value $SourceValue)
}

function Merge-UGSMGameDayZJsonFiles {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$TargetPath,
        [Parameter(Mandatory)][string]$SourcePath
    )

    $targetData = Read-UGSMGameDayZJsonDataSafe -Path $TargetPath
    $sourceData = Read-UGSMGameDayZJsonDataSafe -Path $SourcePath

    $isTraderPlusMerge = ([System.IO.Path]::GetFileName($TargetPath) -eq 'TraderPlusPriceConfig.json')

    if ($isTraderPlusMerge) {
        $merged = Merge-UGSMGameDayZTraderPlusPriceData -TargetData $targetData -SourceData $sourceData
    }
    else {
        $merged = Merge-UGSMGameDayZJsonValues -TargetValue $targetData -SourceValue $sourceData
    }

    [void](Write-UGSMGameDayZJsonDataSafe -Path $TargetPath -Data $merged)
    return $TargetPath
}



function Read-UGSMGameDayZTypesXmlRows {

    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Path
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        return @()
    }

    [xml]$xml = Get-Content -LiteralPath $Path -Raw -ErrorAction Stop
    $rows = @()

    $typeNodes = @()
    if ($xml -and $xml.DocumentElement -and $xml.DocumentElement.Name -eq 'types') {
        $typeNodes = $xml.DocumentElement.SelectNodes('./type')
    }

    foreach ($typeNode in $typeNodes) {
        if ($null -eq $typeNode) { continue }

        $usageValues = @()
        foreach ($usageNode in @($typeNode.SelectNodes('./usage'))) {
            if ($usageNode -and $usageNode.Attributes['name']) {
                $usageValues += [string]$usageNode.Attributes['name'].Value
            }
        }

        $valueValues = @()
        foreach ($valueNode in @($typeNode.SelectNodes('./value'))) {
            if ($valueNode -and $valueNode.Attributes['name']) {
                $valueValues += [string]$valueNode.Attributes['name'].Value
            }
        }

        $categoryValue = ''
        $categoryNode = $typeNode.SelectSingleNode('./category')
        if ($categoryNode -and $categoryNode.Attributes['name']) {
            $categoryValue = [string]$categoryNode.Attributes['name'].Value
        }

        $flagsNode = $typeNode.SelectSingleNode('./flags')
        $getFlagValue = {
            param(
                [object]$Node,
                [string]$Name,
                [string]$Default
            )

            if ($Node -and $Node.Attributes[$Name]) {
                return [string]$Node.Attributes[$Name].Value
            }

            return [string]$Default
        }

        $flagCargo = & $getFlagValue $flagsNode 'count_in_cargo' '0'
        $flagHoarder = & $getFlagValue $flagsNode 'count_in_hoarder' '0'
        $flagMap = & $getFlagValue $flagsNode 'count_in_map' '1'
        $flagPlayer = & $getFlagValue $flagsNode 'count_in_player' '0'
        $flagCrafted = & $getFlagValue $flagsNode 'crafted' '0'
        $flagDeloot = & $getFlagValue $flagsNode 'deloot' '0'
        $delootDisplay = if ($flagDeloot -eq '1' -or $flagDeloot.ToLowerInvariant() -eq 'true' -or $flagDeloot.ToLowerInvariant() -eq 'yes') { 'Yes' } else { 'No' }

        $rows += [pscustomobject]@{
            Name           = [string]$(if ($typeNode.Attributes['name']) { $typeNode.Attributes['name'].Value } else { '' })
            Nominal        = [string]($typeNode.SelectSingleNode('./nominal').'#text')
            Lifetime       = [string]($typeNode.SelectSingleNode('./lifetime').'#text')
            Restock        = [string]($typeNode.SelectSingleNode('./restock').'#text')
            Min            = [string]($typeNode.SelectSingleNode('./min').'#text')
            Max            = if ($typeNode.SelectSingleNode('./max') -and -not [string]::IsNullOrWhiteSpace([string]($typeNode.SelectSingleNode('./max').'#text'))) { [string]($typeNode.SelectSingleNode('./max').'#text') } else { '0' }
            QuantMin       = [string]($typeNode.SelectSingleNode('./quantmin').'#text')
            QuantMax       = [string]($typeNode.SelectSingleNode('./quantmax').'#text')
            Cost           = [string]($typeNode.SelectSingleNode('./cost').'#text')
            Category       = $categoryValue
            Usage          = [string]($usageValues -join ',')
            Value          = [string]($valueValues -join ',')
            Deloot         = $delootDisplay
            CountInCargo   = $flagCargo
            CountInHoarder = $flagHoarder
            CountInMap     = $flagMap
            CountInPlayer  = $flagPlayer
            Crafted        = $flagCrafted
        }
    }

    return @($rows)
}

function Write-UGSMGameDayZTypesXmlRows {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][object[]]$Rows
    )

    $settings = New-Object System.Xml.XmlWriterSettings
    $settings.Indent = $true
    $settings.IndentChars = '    '
    $settings.NewLineChars = [Environment]::NewLine
    $settings.NewLineHandling = [System.Xml.NewLineHandling]::Replace
    $settings.Encoding = New-Object System.Text.UTF8Encoding($false)

    $parent = Split-Path -Parent $Path
    if (-not [string]::IsNullOrWhiteSpace([string]$parent) -and -not (Test-Path -LiteralPath $parent -PathType Container)) {
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
    }

    $writer = [System.Xml.XmlWriter]::Create($Path, $settings)
    try {
        $writer.WriteStartDocument()
        $writer.WriteStartElement('types')

        foreach ($row in @($Rows)) {
            if ($null -eq $row) { continue }

            $name = [string]$row.Name
            if ([string]::IsNullOrWhiteSpace($name)) { continue }

            $writer.WriteStartElement('type')
            $writer.WriteAttributeString('name', $name)

            $normalizeTypeValue = {
                param(
                    [object]$Value,
                    [string]$Default = ''
                )

                $text = [string]$Value
                if ([string]::IsNullOrWhiteSpace($text)) { return $Default }
                return $text.Trim()
            }

            foreach ($field in @(
                    @{ Name = 'nominal'; Value = (& $normalizeTypeValue $row.Nominal '0') }
                    @{ Name = 'lifetime'; Value = (& $normalizeTypeValue $row.Lifetime '0') }
                    @{ Name = 'restock'; Value = (& $normalizeTypeValue $row.Restock '0') }
                    @{ Name = 'min'; Value = (& $normalizeTypeValue $row.Min '0') }
                    @{ Name = 'max'; Value = if ($row.PSObject.Properties.Name -contains 'Max') { (& $normalizeTypeValue $row.Max '0') } else { '0' } }
                    @{ Name = 'quantmin'; Value = (& $normalizeTypeValue $row.QuantMin '-1') }
                    @{ Name = 'quantmax'; Value = (& $normalizeTypeValue $row.QuantMax '-1') }
                    @{ Name = 'cost'; Value = (& $normalizeTypeValue $row.Cost '100') }
                )) {
                $writer.WriteElementString($field.Name, [string]$field.Value)
            }

            $normalizeFlag = {
                param(
                    [string]$Value,
                    [string]$Default = '0'
                )

                if ([string]::IsNullOrWhiteSpace($Value)) { return $Default }

                $clean = $Value.Trim()
                if ($clean -eq '1' -or $clean.ToLowerInvariant() -eq 'true' -or $clean.ToLowerInvariant() -eq 'yes') { return '1' }
                if ($clean -eq '0' -or $clean.ToLowerInvariant() -eq 'false' -or $clean.ToLowerInvariant() -eq 'no') { return '0' }

                return $clean
            }

            $writer.WriteStartElement('flags')
            $writer.WriteAttributeString('count_in_cargo', (& $normalizeFlag ([string]$row.CountInCargo) '0'))
            $writer.WriteAttributeString('count_in_hoarder', (& $normalizeFlag ([string]$row.CountInHoarder) '0'))
            $writer.WriteAttributeString('count_in_map', (& $normalizeFlag ([string]$row.CountInMap) '1'))
            $writer.WriteAttributeString('count_in_player', (& $normalizeFlag ([string]$row.CountInPlayer) '0'))
            $writer.WriteAttributeString('crafted', (& $normalizeFlag ([string]$row.Crafted) '0'))
            $writer.WriteAttributeString('deloot', (& $normalizeFlag ([string]$row.Deloot) '0'))
            $writer.WriteEndElement()

            $category = [string]$row.Category
            if (-not [string]::IsNullOrWhiteSpace($category)) {
                $writer.WriteStartElement('category')
                $writer.WriteAttributeString('name', $category.Trim())
                $writer.WriteEndElement()
            }

            foreach ($usage in @(([string]$row.Usage -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ }))) {
                $writer.WriteStartElement('usage')
                $writer.WriteAttributeString('name', $usage)
                $writer.WriteEndElement()
            }

            foreach ($value in @(([string]$row.Value -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ }))) {
                $writer.WriteStartElement('value')
                $writer.WriteAttributeString('name', $value)
                $writer.WriteEndElement()
            }

            $writer.WriteEndElement()
        }

        $writer.WriteEndElement()
        $writer.WriteEndDocument()
    }
    finally {
        if ($writer) { $writer.Dispose() }
    }

    return $Path
}

function Get-UGSMGameDayZTypesGridRows {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][System.Windows.Forms.DataGridView]$Grid
    )

    $rows = @()

    foreach ($gridRow in @($Grid.Rows)) {
        if ($null -eq $gridRow -or $gridRow.IsNewRow) { continue }

        $name = [string]$gridRow.Cells['Name'].Value
        if ([string]::IsNullOrWhiteSpace($name)) { continue }

        $rows += [pscustomobject]@{
            Name     = $name.Trim()
            Nominal  = [string]$gridRow.Cells['Nominal'].Value
            Lifetime = [string]$gridRow.Cells['Lifetime'].Value
            Restock  = [string]$gridRow.Cells['Restock'].Value
            Min      = [string]$gridRow.Cells['Min'].Value
            Max      = if ($Grid.Columns.Contains('Max') -and -not [string]::IsNullOrWhiteSpace([string]$gridRow.Cells['Max'].Value)) { [string]$gridRow.Cells['Max'].Value } else { '0' }
            QuantMin = [string]$gridRow.Cells['QuantMin'].Value
            QuantMax = [string]$gridRow.Cells['QuantMax'].Value
            Cost     = [string]$gridRow.Cells['Cost'].Value
            Category       = [string]$gridRow.Cells['Category'].Value
            Usage          = [string]$gridRow.Cells['Usage'].Value
            Value          = [string]$gridRow.Cells['Value'].Value
            Deloot         = [string]$gridRow.Cells['Deloot'].Value
            CountInCargo   = [string]$gridRow.Cells['CountInCargo'].Value
            CountInHoarder = [string]$gridRow.Cells['CountInHoarder'].Value
            CountInMap     = [string]$gridRow.Cells['CountInMap'].Value
            CountInPlayer  = [string]$gridRow.Cells['CountInPlayer'].Value
            Crafted        = [string]$gridRow.Cells['Crafted'].Value
        }
    }

    return @($rows)
}


function Convert-UGSMGameDayZXmlNodeToPrettyString {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][System.Xml.XmlNode]$Node
    )

    $settings = New-Object System.Xml.XmlWriterSettings
    $settings.Indent = $true
    $settings.IndentChars = '    '
    $settings.OmitXmlDeclaration = $true
    $settings.NewLineChars = [Environment]::NewLine
    $settings.NewLineHandling = [System.Xml.NewLineHandling]::Replace

    $builder = New-Object System.Text.StringBuilder
    $writer = [System.Xml.XmlWriter]::Create($builder, $settings)
    try {
        $Node.WriteTo($writer)
    }
    finally {
        if ($writer) {
            $writer.Flush()
            $writer.Dispose()
        }
    }

    return [string]$builder.ToString()
}

function Read-UGSMGameDayZSpawnableTypesXmlRows {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Path
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        return @()
    }

    $xml = Read-UGSMGameDayZXmlDocumentSafe -Path $Path
    if ($null -eq $xml -or $null -eq $xml.DocumentElement) {
        return @()
    }

    $rows = @()
    $typeNodes = $xml.DocumentElement.SelectNodes('./type')

    foreach ($typeNode in @($typeNodes)) {
        if ($null -eq $typeNode) { continue }

        $attachmentsNode = $typeNode.SelectSingleNode('./attachments')
        $cargoNode = $typeNode.SelectSingleNode('./cargo')
        $damageNode = $typeNode.SelectSingleNode('./damage')

        $rows += [pscustomobject]@{
            Name             = [string]$typeNode.GetAttribute('name')
            AttachmentsCount = @($typeNode.SelectNodes('./attachments/attachment')).Count
            CargoCount       = @($typeNode.SelectNodes('./cargo/item')).Count
            HasAttachments   = if ($attachmentsNode) { 'Yes' } else { 'No' }
            HasCargo         = if ($cargoNode) { 'Yes' } else { 'No' }
            DamageMin        = if ($damageNode) { [string]$damageNode.GetAttribute('min') } else { '' }
            DamageMax        = if ($damageNode) { [string]$damageNode.GetAttribute('max') } else { '' }
            OuterXml         = [string](Convert-UGSMGameDayZXmlNodeToPrettyString -Node $typeNode)
        }
    }

    return @($rows)
}

function Get-UGSMGameDayZSpawnableTypesGridRows {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][System.Windows.Forms.DataGridView]$Grid
    )

    $rows = @()

    foreach ($gridRow in @($Grid.Rows)) {
        if ($null -eq $gridRow -or $gridRow.IsNewRow) { continue }

        $name = [string]$gridRow.Cells['Name'].Value
        if ([string]::IsNullOrWhiteSpace($name)) { continue }

        $tag = $gridRow.Tag
        $rows += [pscustomobject]@{
            Name             = $name.Trim()
            AttachmentsCount = [string]$gridRow.Cells['AttachmentsCount'].Value
            CargoCount       = [string]$gridRow.Cells['CargoCount'].Value
            HasAttachments   = [string]$gridRow.Cells['HasAttachments'].Value
            HasCargo         = [string]$gridRow.Cells['HasCargo'].Value
            DamageMin        = [string]$gridRow.Cells['DamageMin'].Value
            DamageMax        = [string]$gridRow.Cells['DamageMax'].Value
            OuterXml         = if ($tag) { [string]$tag.OuterXml } else { '' }
        }
    }

    return @($rows)
}

function Write-UGSMGameDayZSpawnableTypesXmlRows {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][object[]]$Rows
    )

    $settings = New-Object System.Xml.XmlWriterSettings
    $settings.Indent = $true
    $settings.IndentChars = '    '
    $settings.NewLineChars = [Environment]::NewLine
    $settings.NewLineHandling = [System.Xml.NewLineHandling]::Replace
    $settings.Encoding = New-Object System.Text.UTF8Encoding($false)

    $parent = Split-Path -Parent $Path
    if (-not [string]::IsNullOrWhiteSpace([string]$parent) -and -not (Test-Path -LiteralPath $parent -PathType Container)) {
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
    }

    $writer = [System.Xml.XmlWriter]::Create($Path, $settings)
    try {
        $writer.WriteStartDocument()
        $writer.WriteStartElement('spawnabletypes')

        foreach ($row in @($Rows)) {
            if ($null -eq $row) { continue }

            $outerXml = [string]$row.OuterXml
            $name = [string]$row.Name
            if ([string]::IsNullOrWhiteSpace($outerXml) -and [string]::IsNullOrWhiteSpace($name)) { continue }

            if (-not [string]::IsNullOrWhiteSpace($outerXml)) {
                $fragmentDoc = New-Object System.Xml.XmlDocument
                try {
                    $fragmentDoc.LoadXml("<spawnabletypes>$outerXml</spawnabletypes>")
                }
                catch {
                    throw "Spawnable type '$name' contains invalid XML: $($_.Exception.Message)"
                }

                foreach ($typeNode in @($fragmentDoc.DocumentElement.SelectNodes('./type'))) {
                    if ($typeNode) {
                        $writer.WriteRaw([string](Convert-UGSMGameDayZXmlNodeToPrettyString -Node $typeNode))
                    }
                }
            }
        }

        $writer.WriteEndElement()
        $writer.WriteEndDocument()
    }
    finally {
        if ($writer) { $writer.Dispose() }
    }

    return $Path
}

function New-UGSMGameDayZInstanceEditor {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$Instance,
        [Parameter(Mandatory)][hashtable]$Theme,
        [Parameter(Mandatory)][System.Windows.Forms.Panel]$HostPanel,
        [AllowNull()][System.Windows.Forms.Label]$StatusLabel
    )

    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing

    if (Get-Command -Name Save-UGSMGameDayZInstanceDefinition -ErrorAction SilentlyContinue) {
        [void](Save-UGSMGameDayZInstanceDefinition -Instance $Instance)
    }

    $paths = Get-UGSMGameDayZProfilePaths -Instance $Instance
    $editorInstance = $Instance
    $editorPaths = $paths
    $editorStatusLabel = $StatusLabel
    $schema = Get-UGSMGameDayZEditorSchema
    #$iniData = Read-UGSMGameDayZIniFile -Path $paths.ServerSettingsPath
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

    function Get-DayZSafeFieldValue {
        param([hashtable]$Field)

        try {
            return Get-UGSMGameDayZEditorFieldCurrentValue -Field $Field -Paths $paths
        }
        catch {
            if ($StatusLabel) {
                $StatusLabel.Text = 'DayZ field load failed for ' + [string]$Field.Id + ': ' + $_.Exception.Message
            }

            if ($Field.ContainsKey('DefaultValue')) {
                return $Field.DefaultValue
            }

            return $null
        }
    }

    function New-DayZTextBox {
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

    function New-DayZStretchTextBox {
        param(
            [switch]$Multiline,
            [int]$Height = 24
        )

        $tb = New-DayZTextBox -Width $layout.ControlWidth -Multiline:$Multiline -Height $Height
        $tb.Width = $layout.ControlWidth
        $tb.Anchor = 'Left,Right,Top'
        return $tb
    }

    function New-DayZNarrowHost {
        $panel = New-Object System.Windows.Forms.Panel
        $panel.Dock = 'Top'
        $panel.Height = 26
        $panel.Margin = New-Object System.Windows.Forms.Padding(0)
        $panel.Padding = New-Object System.Windows.Forms.Padding(0)
        return $panel
    }

    function Add-DayZFieldRow {
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
                    $fieldHost = New-DayZNarrowHost
                    $control = New-Object System.Windows.Forms.CheckBox
                    $control.AutoSize = $true
                    $control.Anchor = 'Left'
                    $control.Margin = New-Object System.Windows.Forms.Padding(0)
                    $control.BackColor = [System.Drawing.Color]::Transparent
                    $control.ForeColor = New-UGSMColor $Theme.Text
                    $control.Checked = ([string](Get-DayZSafeFieldValue -Field $Field) -match '^(?i:true|1|yes)$')
                    [void]$fieldHost.Controls.Add($control)
                    [void]$row.Controls.Add($fieldHost, 1, 0)
                    $controlMap[$Field.Id] = @{ Field = $Field; Control = $control }
                }
                'InstanceBoolean' {
                    $fieldHost = New-DayZNarrowHost
                    $control = New-Object System.Windows.Forms.CheckBox
                    $control.AutoSize = $true
                    $control.Anchor = 'Left'
                    $control.Margin = New-Object System.Windows.Forms.Padding(0)
                    $control.BackColor = [System.Drawing.Color]::Transparent
                    $control.ForeColor = New-UGSMColor $Theme.Text
                    $control.Checked = [bool](Get-DayZSafeFieldValue -Field $Field)
                    [void]$fieldHost.Controls.Add($control)
                    [void]$row.Controls.Add($fieldHost, 1, 0)
                    $controlMap[$Field.Id] = @{ Field = $Field; Control = $control }
                }
                'Number' {
                    $numberHost = New-DayZNarrowHost
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
                    $rawValue = Get-DayZSafeFieldValue -Field $Field
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
                'Decimal' {
                    $numberHost = New-DayZNarrowHost
                    $control = New-Object System.Windows.Forms.NumericUpDown
                    $control.Margin = New-Object System.Windows.Forms.Padding(0)
                    $control.Width = $layout.NarrowControlWidth
                    $control.Anchor = 'Left'
                    $min = if ($Field.ContainsKey('Min')) { [decimal]$Field.Min } else { [decimal]0 }
                    $max = if ($Field.ContainsKey('Max')) { [decimal]$Field.Max } else { [decimal]2147483647 }
                    $decimals = Get-UGSMGameDayZFieldDecimalPlaces -Field $Field
                    $control.Minimum = $min
                    $control.Maximum = $max
                    $control.DecimalPlaces = $decimals
                    $control.Increment = if ($Field.ContainsKey('Increment')) { [decimal]::Parse([string]$Field.Increment, [System.Globalization.CultureInfo]::InvariantCulture) } else { [decimal]0.1 }
                    $rawValue = Get-DayZSafeFieldValue -Field $Field
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
                    $control = New-DayZStretchTextBox -Multiline -Height $layout.MultilineHeight
                    $control.Text = [string](Get-DayZSafeFieldValue -Field $Field)
                    [void]$row.Controls.Add($control, 1, 0)
                    $controlMap[$Field.Id] = @{ Field = $Field; Control = $control }
                }
                'InstanceText' {
                    $control = New-DayZStretchTextBox
                    $control.Text = [string](Get-DayZSafeFieldValue -Field $Field)
                    [void]$row.Controls.Add($control, 1, 0)
                    $controlMap[$Field.Id] = @{ Field = $Field; Control = $control }
                }
                'StringList' {
                    $control = New-DayZTextBox -Width $layout.WideControlWidth -Multiline -Height $layout.StringListHeight
                    $resolvedListPath = Resolve-UGSMGameDayZEditorFieldPath -Field $Field -Paths $paths
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
                    $buttonHost = New-DayZNarrowHost
                    $control = New-UGSMButton -Text ([string]$Field.ButtonText) -X 0 -Y 0 -Width 220 -Height 30 -BackColor '#253341'
                    $action = $Field.Action
                    $control.Add_Click({
                            try { & $action $Instance $paths $StatusLabel }
                            catch { if ($StatusLabel) { $StatusLabel.Text = 'DayZ action failed: ' + $_.Exception.Message } }
                        }.GetNewClosure())
                    [void]$buttonHost.Controls.Add($control)
                    [void]$row.Controls.Add($buttonHost, 1, 0)
                }
                default {
                    $control = New-DayZStretchTextBox
                    $control.Text = [string](Get-DayZSafeFieldValue -Field $Field)
                    [void]$row.Controls.Add($control, 1, 0)
                    $controlMap[$Field.Id] = @{ Field = $Field; Control = $control }
                }
            }

            if (-not [string]::IsNullOrWhiteSpace([string]$Field.Hint)) {
                $hint = New-UGSMLabel -Text ([string]$Field.Hint) -X 0 -Y 0 -Width 700 -Height 18 -FontSize 8.5 -Color $Theme.Muted
                $hint.Margin = New-Object System.Windows.Forms.Padding(0, 2, 0, 0)
                [void]$row.Controls.Add($hint, 1, 1)
            }
        }
        catch {
            $errorLabel = New-UGSMLabel -Text ('DayZ field row failed: ' + $_.Exception.Message) -X 0 -Y 0 -Width 700 -Height 18 -FontSize 8.5 -Color '#FF7B72'
            $errorLabel.Margin = New-Object System.Windows.Forms.Padding(0, 4, 0, 0)
            [void]$row.Controls.Add($errorLabel, 1, 0)
        }

        [void]$Parent.Controls.Add($row)
    }

    

    function New-DayZEditorContent {
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
            Add-DayZFieldRow -Parent $content -Field $field -Instance $Instance -StatusLabel $StatusLabel
        }

        & $refreshScrollLayout
    }

    $editorInstance = $Instance
    $editorPaths = $paths
    $editorStatusLabel = $StatusLabel

    $invokeModsXmlAction = {
        param(
            [Parameter(Mandatory)][scriptblock]$Action
        )

        try {
            & $Action $editorInstance $editorPaths $editorStatusLabel | Out-Null
        }
        catch {
            if ($editorStatusLabel) {
                $editorStatusLabel.Text = 'DayZ Mods/XML action failed: ' + $_.Exception.Message
            }
        }
    }.GetNewClosure()

    function New-DayZModsContent {
        param(
            [Parameter(Mandatory)][System.Windows.Forms.Control]$Parent
        )

        $modsInstance = $editorInstance
        $modsPaths = $editorPaths
        $modsStatusLabel = $editorStatusLabel

        $scroll = New-Object System.Windows.Forms.Panel
        $scroll.Dock = 'Fill'
        $scroll.AutoScroll = $true
        $scroll.BackColor = New-UGSMColor '#0B121D'
        [void]$Parent.Controls.Add($scroll)

        $content = New-Object System.Windows.Forms.Panel
        $content.Dock = 'Top'
        $content.Height = 700
        $content.Padding = New-Object System.Windows.Forms.Padding(12, 10, 12, 10)
        $content.BackColor = New-UGSMColor '#0B121D'
        [void]$scroll.Controls.Add($content)

        $desc = New-UGSMLabel -Text 'Manage DayZ instance mods for this profile. Mods are stored on the instance and synced into the runtime install when needed.' -X 0 -Y 0 -Width 1200 -Height 22 -FontSize 8.5 -Color $Theme.Muted
        [void]$content.Controls.Add($desc)

        $subTitle = New-UGSMLabel -Text ('Source: Steam Workshop Cache    Runtime: ' + [string]$modsPaths.RuntimeInstallRoot) -X 0 -Y 22 -Width 1400 -Height 18 -FontSize 8 -Color $Theme.Muted
        [void]$content.Controls.Add($subTitle)

        $main = New-Object System.Windows.Forms.TableLayoutPanel
        $main.Location = New-Object System.Drawing.Point(0, 48)
        $main.Size = New-Object System.Drawing.Size(1280, 610)
        $main.ColumnCount = 2
        $main.RowCount = 1
        $main.BackColor = [System.Drawing.Color]::Transparent
        [void]$main.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Absolute, 470)))
        [void]$main.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent, 100)))
        [void]$content.Controls.Add($main)

        $leftCard = New-Object System.Windows.Forms.Panel
        $leftCard.Dock = 'Fill'
        $leftCard.BackColor = New-UGSMColor '#0E1620'
        $leftCard.Padding = New-Object System.Windows.Forms.Padding(12)
        [void]$main.Controls.Add($leftCard, 0, 0)

        $leftTitle = New-UGSMLabel -Text 'Active Mods [Load Order]' -X 0 -Y 0 -Width 300 -Height 18 -FontSize 9 -Style Bold -Color $Theme.Text
        [void]$leftCard.Controls.Add($leftTitle)

        $modsList = New-Object System.Windows.Forms.ListBox
        $modsList.Location = New-Object System.Drawing.Point(0, 26)
        $modsList.Size = New-Object System.Drawing.Size(320, 470)
        $modsList.BackColor = [System.Drawing.Color]::White
        $modsList.ForeColor = [System.Drawing.Color]::Black
        $modsList.BorderStyle = 'FixedSingle'
        [void]$leftCard.Controls.Add($modsList)

        $btnMoveUp = New-UGSMButton -Text 'Move Up' -X 340 -Y 26 -Width 100 -Height 30 -BackColor '#253341'
        $btnMoveDown = New-UGSMButton -Text 'Move Down' -X 340 -Y 64 -Width 100 -Height 30 -BackColor '#253341'
        [void]$leftCard.Controls.Add($btnMoveUp)
        [void]$leftCard.Controls.Add($btnMoveDown)
        
        $btnRemove = New-Object System.Windows.Forms.Button
        $btnRemove.Text = 'Remove'
        $btnRemove.Location = New-Object System.Drawing.Point(340, 112)
        $btnRemove.Size = New-Object System.Drawing.Size(100, 30)
        $btnRemove.BackColor = [System.Drawing.ColorTranslator]::FromHtml('#A63A2D')
        $btnRemove.ForeColor = [System.Drawing.Color]::White
        $btnRemove.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
        $btnRemove.Cursor = [System.Windows.Forms.Cursors]::Hand
        $btnRemove.UseVisualStyleBackColor = $false
        $btnRemove.TabStop = $true
        $btnRemove.Enabled = $true
        [void]$leftCard.Controls.Add($btnRemove)
        $btnRemove.BringToFront()

        $rightHost = New-Object System.Windows.Forms.FlowLayoutPanel
        $rightHost.Dock = 'Fill'
        $rightHost.FlowDirection = 'TopDown'
        $rightHost.WrapContents = $false
        $rightHost.AutoScroll = $true
        $rightHost.BackColor = [System.Drawing.Color]::Transparent
        $rightHost.Margin = New-Object System.Windows.Forms.Padding(12, 0, 0, 0)
        [void]$main.Controls.Add($rightHost, 1, 0)

        $addCard = New-Object System.Windows.Forms.Panel
        $addCard.Width = 720
        $addCard.Height = 120
        $addCard.BackColor = New-UGSMColor '#0E1620'
        $addCard.Padding = New-Object System.Windows.Forms.Padding(12)
        $addCard.Margin = New-Object System.Windows.Forms.Padding(0, 0, 0, 12)
        [void]$rightHost.Controls.Add($addCard)

        $addTitle = New-UGSMLabel -Text 'Add New Mod' -X 0 -Y 0 -Width 220 -Height 18 -FontSize 9 -Style Bold -Color $Theme.Text
        [void]$addCard.Controls.Add($addTitle)

        $lblWorkshop = New-UGSMLabel -Text 'Workshop ID / URL:' -X 0 -Y 28 -Width 180 -Height 18 -FontSize 8.5 -Color $Theme.Text
        [void]$addCard.Controls.Add($lblWorkshop)

        $txtWorkshop = New-DayZTextBox -Width 320
        $txtWorkshop.Location = New-Object System.Drawing.Point(0, 50)
        [void]$addCard.Controls.Add($txtWorkshop)

        $btnAdd = New-UGSMButton -Text 'Add' -X 340 -Y 48 -Width 100 -Height 30 -BackColor $Theme.AccentBlue
        [void]$addCard.Controls.Add($btnAdd)

        $chkServerMod = New-Object System.Windows.Forms.CheckBox
        $chkServerMod.Location = New-Object System.Drawing.Point(0, 84)
        $chkServerMod.AutoSize = $true
        $chkServerMod.BackColor = [System.Drawing.Color]::Transparent
        $chkServerMod.ForeColor = New-UGSMColor $Theme.Text
        $chkServerMod.Text = 'Server-Side Mod (Copy PBOs to Root)'
        [void]$addCard.Controls.Add($chkServerMod)

        $utilityCard = New-Object System.Windows.Forms.Panel
        $utilityCard.Width = 720
        $utilityCard.Height = 260
        $utilityCard.BackColor = New-UGSMColor '#0E1620'
        $utilityCard.Padding = New-Object System.Windows.Forms.Padding(12)
        $utilityCard.Margin = New-Object System.Windows.Forms.Padding(0, 0, 0, 12)
        [void]$rightHost.Controls.Add($utilityCard)

        $utilityTitle = New-UGSMLabel -Text 'Utility Actions' -X 0 -Y 0 -Width 220 -Height 18 -FontSize 9 -Style Bold -Color $Theme.Text
        [void]$utilityCard.Controls.Add($utilityTitle)

        $btnDownloadAll = New-UGSMButton -Text 'Download / Update All Mods' -X 0 -Y 32 -Width 360 -Height 34 -BackColor '#9FCFE2'
        $btnCopyAllKeys = New-UGSMButton -Text 'Copy Keys from ALL Mods' -X 0 -Y 76 -Width 360 -Height 34 -BackColor '#87D988'
        $btnCopySelectedPbos = New-UGSMButton -Text 'Copy PBOs (Selected Mod)' -X 0 -Y 120 -Width 360 -Height 34 -BackColor '#F4A300'
        $btnSyncRuntime = New-UGSMButton -Text 'Sync Mods to Runtime' -X 0 -Y 164 -Width 360 -Height 34 -BackColor $Theme.AccentBlue
        $btnBuildIndex = New-UGSMButton -Text 'Build DayZ Index Cache' -X 380 -Y 32 -Width 300 -Height 34 -BackColor $Theme.Accent

        [void]$utilityCard.Controls.Add($btnDownloadAll)
        [void]$utilityCard.Controls.Add($btnCopyAllKeys)
        [void]$utilityCard.Controls.Add($btnCopySelectedPbos)
        [void]$utilityCard.Controls.Add($btnSyncRuntime)
        [void]$utilityCard.Controls.Add($btnBuildIndex)

        $utilityHint = New-UGSMLabel -Text 'Builds the AppData index cache used by the XML tab. Apply and cleanup actions for live XML files are handled on the XML tab.' -X 380 -Y 76 -Width 300 -Height 120 -FontSize 8.5 -Color $Theme.Muted
        [void]$utilityCard.Controls.Add($utilityHint)

        $currentMods = @()

        $getProfileMods = {
            return @(Get-UGSMGameDayZProfileMods -Instance $modsInstance)
        }.GetNewClosure()

        $refreshModsList = {
            try {
                $currentMods = @(& $getProfileMods)

                $modsList.Items.Clear()
                foreach ($mod in $currentMods) {
                    $displayName = [string]$(if ($null -ne $mod.Name -and -not [string]::IsNullOrWhiteSpace([string]$mod.Name)) { $mod.Name } else { $mod.Id })
                    $displayId = [string]$(if ($null -ne $mod.Id) { $mod.Id } else { '' })
                    [void]$modsList.Items.Add(('{0} ({1})' -f $displayName, $displayId))
                }

                if ($currentMods.Count -eq 0) {
                    if ($modsStatusLabel) { $modsStatusLabel.Text = 'No mods are configured for this profile.' }
                }
                else {
                    $modsList.SelectedIndex = 0
                    if ($modsStatusLabel) { $modsStatusLabel.Text = ('Loaded {0} DayZ mod(s) for this profile.' -f $currentMods.Count) }
                }
            }
            catch {
                if ($modsStatusLabel) { $modsStatusLabel.Text = 'Failed to load DayZ profile mods: ' + $_.Exception.Message }
            }
        }.GetNewClosure()

       

        $extractWorkshopId = {
            param([string]$InputText)

            $text = [string]$InputText
            if ([string]::IsNullOrWhiteSpace($text)) { return '' }

            $trimmed = $text.Trim()

            if ($trimmed -match '(\d{6,})') {
                return [string]$Matches[1]
            }

            return ''
        }.GetNewClosure()

        $getNewLoadOrder = {
            if ($currentMods.Count -eq 0) { return 0 }
            return [int]((@($currentMods | Measure-Object -Property LoadOrder -Maximum).Maximum) + 1)
        }.GetNewClosure()

        $getSelectedModForUtilityAction = {
            $selectedIndex = [int]$modsList.SelectedIndex
            if ($selectedIndex -lt 0) {
                throw 'Select a mod first.'
            }

            $freshMods = @(& $getProfileMods)
            if ($selectedIndex -ge 0 -and $selectedIndex -lt $freshMods.Count) {
                return $freshMods[$selectedIndex]
            }

            # Fallback: parse the selected list text "Name (123456789)".
            $selectedText = [string]$modsList.SelectedItem
            if ($selectedText -match '\((\d{6,})\)\s*$') {
                $selectedId = [string]$Matches[1]
                foreach ($mod in $freshMods) {
                    $modId = [string]$(if ($mod.PSObject.Properties.Name -contains 'Id') { $mod.Id } else { '' })
                    if ($modId -eq $selectedId) { return $mod }
                }

                return [pscustomobject]@{
                    Id = $selectedId
                    Name = $selectedId
                }
            }

            throw 'Select a mod first.'
        }.GetNewClosure()

        $getSelectedModIdForUtilityAction = {
            $selectedMod = & $getSelectedModForUtilityAction
            $selectedModId = [string]$(if ($selectedMod.PSObject.Properties.Name -contains 'Id') { $selectedMod.Id } else { '' })
            if ([string]::IsNullOrWhiteSpace($selectedModId)) {
                throw 'Selected mod does not have a workshop id.'
            }
            return $selectedModId
        }.GetNewClosure()


        $btnAdd.Add_Click({
                try {
                    $rawInput = [string]$txtWorkshop.Text
                    $normalizedId = Convert-UGSMGameDayZWorkshopInputToId -InputText $rawInput
                    if ([string]::IsNullOrWhiteSpace($normalizedId)) {
                        throw 'Enter a valid DayZ workshop URL or numeric workshop id.'
                    }

                    $existingMods = @(Get-UGSMGameDayZStoredMods -Instance $modsInstance)
                    foreach ($existing in @($existingMods)) {
                        $existingId = Convert-UGSMGameDayZWorkshopInputToId -InputText ([string]$existing.Id)
                        if ($existingId -eq $normalizedId) {
                            throw 'That mod is already added for this profile.'
                        }
                    }

                    $updatedMods = @($existingMods)
                    $updatedMods += [pscustomobject]@{
                        Id                  = $normalizedId
                        Name                = $normalizedId
                        FolderName          = ''
                        SourcePath          = ''
                        LoadOrder           = @($existingMods).Count
                        Enabled             = $true
                        IsServerMod         = [bool]$chkServerMod.Checked
                        MergeTypes          = $true
                        MergeEvents         = $true
                        MergeSpawnableTypes = $true
                    }

                    Save-UGSMGameDayZStoredMods -Instance $modsInstance -Mods @($updatedMods) | Out-Null
                    $txtWorkshop.Clear()
                    $chkServerMod.Checked = $false
                    & $refreshModsList
                    if ($modsList.Items.Count -gt 0) { $modsList.SelectedIndex = $modsList.Items.Count - 1 }
                    if ($modsStatusLabel) { $modsStatusLabel.Text = ('Added DayZ workshop mod {0}.' -f $normalizedId) }
                }
                catch {
                    if ($modsStatusLabel) { $modsStatusLabel.Text = $_.Exception.Message }
                }
            }.GetNewClosure())

        $btnRemove.Add_Click({
                try {
                    $index = $modsList.SelectedIndex
                    if ($index -lt 0) {
                        if ($modsStatusLabel) { $modsStatusLabel.Text = 'Select a mod to remove.' }
                        return
                    }

                    $storedMods = @(Get-UGSMGameDayZStoredMods -Instance $modsInstance)
                    if (@($storedMods).Count -le 0) {
                        if ($modsStatusLabel) { $modsStatusLabel.Text = 'No stored mods were found for this profile.' }
                        return
                    }

                    if ($index -ge @($storedMods).Count) {
                        if ($modsStatusLabel) { $modsStatusLabel.Text = 'Selected mod index does not match the stored mods list.' }
                        return
                    }

                    $updated = @()
                    for ($i = 0; $i -lt @($storedMods).Count; $i++) {
                        if ($i -ne $index) {
                            $updated += $storedMods[$i]
                        }
                    }

                    Save-UGSMGameDayZStoredMods -Instance $modsInstance -Mods @($updated) | Out-Null

                    if ($refreshModsList -is [scriptblock]) {
                        & $refreshModsList
                    }

                    if ($modsStatusLabel) { $modsStatusLabel.Text = 'Removed selected DayZ mod from this profile.' }
                }
                catch {
                    if ($modsStatusLabel) { $modsStatusLabel.Text = 'Removing DayZ mod failed: ' + $_.Exception.Message }
                }
            }.GetNewClosure())

        $btnMoveUp.Add_Click({
                try {
                    $index = $modsList.SelectedIndex
                    $mods = @(Get-UGSMGameDayZProfileMods -Instance $modsInstance)

                    if ($index -le 0 -or $index -ge $mods.Count) { return }

                    $temp = $mods[$index - 1]
                    $mods[$index - 1] = $mods[$index]
                    $mods[$index] = $temp

                    Save-UGSMGameDayZStoredMods -Instance $modsInstance -Mods @($mods) | Out-Null

                    & $refreshModsList
                    if ($modsList.Items.Count -gt 0) {
                        $modsList.SelectedIndex = [Math]::Max(0, $index - 1)
                    }

                    if ($modsStatusLabel) { $modsStatusLabel.Text = 'Moved DayZ mod up.' }
                }
                catch {
                    if ($modsStatusLabel) { $modsStatusLabel.Text = 'Moving DayZ mod failed: ' + $_.Exception.Message }
                }
            }.GetNewClosure())

        $btnMoveDown.Add_Click({
                try {
                    $index = $modsList.SelectedIndex
                    $mods = @(Get-UGSMGameDayZProfileMods -Instance $modsInstance)

                    if ($index -lt 0 -or $index -ge ($mods.Count - 1)) { return }

                    $temp = $mods[$index + 1]
                    $mods[$index + 1] = $mods[$index]
                    $mods[$index] = $temp

                    Save-UGSMGameDayZStoredMods -Instance $modsInstance -Mods @($mods) | Out-Null

                    & $refreshModsList
                    if ($modsList.Items.Count -gt 0) {
                        $modsList.SelectedIndex = [Math]::Min($modsList.Items.Count - 1, $index + 1)
                    }

                    if ($modsStatusLabel) { $modsStatusLabel.Text = 'Moved DayZ mod down.' }
                }
                catch {
                    if ($modsStatusLabel) { $modsStatusLabel.Text = 'Moving DayZ mod failed: ' + $_.Exception.Message }
                }
            }.GetNewClosure())

        $btnDownloadAll.Add_Click({
                try {
                    $modsToDownload = @(Get-UGSMGameDayZStoredMods -Instance $modsInstance | Where-Object {
                            $_ -and -not [string]::IsNullOrWhiteSpace([string]$_.Id)
                        })

                    if ($modsToDownload.Count -eq 0) {
                        throw 'No DayZ workshop mods are configured for this profile.'
                    }

                    $ids = @()
                    foreach ($mod in $modsToDownload) {
                        $id = Convert-UGSMGameDayZWorkshopInputToId -InputText ([string]$mod.Id)
                        if (-not [string]::IsNullOrWhiteSpace($id) -and $ids -notcontains $id) {
                            $ids += $id
                        }
                    }

                    if ($ids.Count -eq 0) {
                        throw 'No valid DayZ workshop IDs were found in the instance mod list.'
                    }

                    $downloadResult = Invoke-UGSMGameDayZWorkshopDownload -Instance $modsInstance -WorkshopItemIds $ids

                    & $refreshModsList

                    if ($modsStatusLabel) {
                        $statusText = ('Downloaded or updated {0} DayZ workshop mod(s) from SteamCMD.' -f @($downloadResult.ItemIds).Count)
                        if ($downloadResult -and $downloadResult.PSObject.Properties.Name -contains 'MissingItems' -and @($downloadResult.MissingItems).Count -gt 0) {
                            $statusText += ' Missing after download: ' + ((@($downloadResult.MissingItems)) -join ', ')
                        }
                        $modsStatusLabel.Text = $statusText
                    }
                }
                catch {
                    if ($modsStatusLabel) { $modsStatusLabel.Text = 'DayZ workshop download failed: ' + $_.Exception.Message }
                }
            }.GetNewClosure())

        $btnCopyAllKeys.Add_Click({
                try {
                    $runtime = Ensure-UGSMGameDayZRuntimeLayout -Instance $modsInstance -InstallDefinition (Get-UGSMGameDayZInstallDefinition -InstallPath $modsInstance.InstallPath -Instance $modsInstance)
                    $result = Sync-UGSMGameDayZModFilesToRuntime -Instance $modsInstance -Runtime $runtime
                    if ($modsStatusLabel) { $modsStatusLabel.Text = ('Copied keys from all enabled DayZ mods. Keys={0}' -f [int]$result.KeysCopied) }
                    & $refreshModsList
                }
                catch {
                    if ($modsStatusLabel) { $modsStatusLabel.Text = 'Copying DayZ mod keys failed: ' + $_.Exception.Message }
                }
            }.GetNewClosure())

        $btnCopySelectedPbos.Add_Click({
                try {
                    $index = $modsList.SelectedIndex
                    $mods = @(Get-UGSMGameDayZProfileMods -Instance $modsInstance)

                    if ($index -lt 0 -or $index -ge $mods.Count) {
                        if ($modsStatusLabel) { $modsStatusLabel.Text = 'Select a DayZ mod first.' }
                        return
                    }

                    $mod = $mods[$index]
                    $runtime = Ensure-UGSMGameDayZRuntimeLayout -Instance $modsInstance -InstallDefinition (Get-UGSMGameDayZInstallDefinition -InstallPath $modsInstance.InstallPath -Instance $modsInstance)
                    $copiedCount = Copy-UGSMGameDayZSelectedServerModPbos -Instance $modsInstance -Mod $mod -Runtime $runtime

                    if ($modsStatusLabel) {
                        $modsStatusLabel.Text = ('Copied selected DayZ mod server-side PBOs={0}' -f [int]$copiedCount)
                    }

                    & $refreshModsList
                    if ($modsList.Items.Count -gt 0 -and $index -ge 0 -and $index -lt $modsList.Items.Count) {
                        $modsList.SelectedIndex = $index
                    }
                }
                catch {
                    if ($modsStatusLabel) { $modsStatusLabel.Text = 'Copying selected DayZ mod PBOs failed: ' + $_.Exception.Message }
                }
            }.GetNewClosure())

        $btnSyncRuntime.Add_Click({
                try {
                    $runtime = Ensure-UGSMGameDayZRuntimeLayout -Instance $modsInstance -InstallDefinition (Get-UGSMGameDayZInstallDefinition -InstallPath $modsInstance.InstallPath -Instance $modsInstance)
                    $result = Sync-UGSMGameDayZModFilesToRuntime -Instance $modsInstance -Runtime $runtime

                    if ($modsStatusLabel) {
                        $missingText = ''
                        if ($result -and $result.PSObject.Properties.Name -contains 'MissingMods' -and @($result.MissingMods).Count -gt 0) {
                            $missingText = ' Missing: ' + ((@($result.MissingMods) -join ', '))
                        }

                        $modsStatusLabel.Text = ('DayZ mods synced to runtime. RuntimeFolders={0} Keys={1} PBOs={2}.{3}' -f @($result.RuntimeModFolders).Count, [int]$result.KeysCopied, [int]$result.PbosCopied, $missingText)
                    }

                    & $refreshModsList
                }
                catch {
                    if ($modsStatusLabel) { $modsStatusLabel.Text = 'Syncing DayZ mods to runtime failed: ' + $_.Exception.Message }
                }
            }.GetNewClosure())


        $btnBuildIndex.Add_Click({
                try {
                    if (-not (Get-Command -Name Invoke-UGSMDayZInstanceIndexScan -ErrorAction SilentlyContinue)) {
                        throw 'DayZFiles service scanner was not loaded. Check that UGSM_Service_DayZFiles.ps1 is in the source folder and loaded before the DayZ UI.'
                    }

                    if ($modsStatusLabel) { $modsStatusLabel.Text = 'Scanning enabled DayZ mod folders and building instance cache...' }
                    [System.Windows.Forms.Application]::DoEvents()

                    $report = Invoke-UGSMDayZInstanceIndexScan -Instance $modsInstance

                    $warningText = ''
                    if ($report -and $report.PSObject.Properties.Name -contains 'WarningCount' -and [int]$report.WarningCount -gt 0) {
                        $warningText = (' Warnings={0}.' -f [int]$report.WarningCount)
                    }

                    if ($modsStatusLabel) {
                        $modsStatusLabel.Text = ('DayZ index cache built. ActiveMods={0} Files={1} ClassNames={2}.{3}' -f [int]$report.ActiveModCount, [int]$report.FileCount, [int]$report.ClassNameCount, $warningText)
                    }
                }
                catch {
                    if ($modsStatusLabel) { $modsStatusLabel.Text = 'Building DayZ index cache failed: ' + $_.Exception.Message }
                }
            }.GetNewClosure())

        & $refreshModsList
        #& $refreshScrollLayout
    }

    

function Get-UGSMGameDayZRuntimeEnvFolderPath {
    [CmdletBinding()]
    param([Parameter(Mandatory)][object]$Instance)

    $paths = Get-UGSMGameDayZProfilePaths -Instance $Instance
    $mission = [string]$paths.RuntimeMissionPath
    if ([string]::IsNullOrWhiteSpace($mission)) { return '' }

    return (Join-Path $mission 'env')
}

function Read-UGSMGameDayZCfgEnvironmentFileRows {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return @() }

    $xml = Read-UGSMGameDayZXmlDocumentSafe -Path $Path
    if ($null -eq $xml -or $null -eq $xml.DocumentElement) { return @() }

    $rows = @()
    $fileNodes = @($xml.SelectNodes('/env/territories/file[@path]'))
    $index = 0

    foreach ($node in $fileNodes) {
        if ($null -eq $node) { continue }
        $index++

        $pathValue = [string]$node.GetAttribute('path')
        $rows += [pscustomobject]@{
            Index = $index
            Path  = $pathValue
        }
    }

    return @($rows)
}

function Read-UGSMGameDayZCfgEnvironmentTerritoryRows {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return @() }

    $xml = Read-UGSMGameDayZXmlDocumentSafe -Path $Path
    if ($null -eq $xml -or $null -eq $xml.DocumentElement) { return @() }

    $rows = @()
    $territoryNodes = @($xml.SelectNodes('/env/territories/territory'))
    $index = 0

    foreach ($territoryNode in $territoryNodes) {
        if ($null -eq $territoryNode) { continue }
        $index++

        $fileUsableValues = @()
        foreach ($fileNode in @($territoryNode.SelectNodes('./file[@usable]'))) {
            $fileUsableValues += [string]$fileNode.GetAttribute('usable')
        }

        $rows += [pscustomobject]@{
            Index      = $index
            Name       = [string]$territoryNode.GetAttribute('name')
            Type       = [string]$territoryNode.GetAttribute('type')
            Behavior   = [string]$territoryNode.GetAttribute('behavior')
            FileUsable = [string]($fileUsableValues -join ',')
            Agents     = @($territoryNode.SelectNodes('./agent')).Count
            Spawns     = @($territoryNode.SelectNodes('.//spawn')).Count
            Items      = @($territoryNode.SelectNodes('./item')).Count
            OuterXml   = [string](Convert-UGSMGameDayZXmlNodeToPrettyString -Node $territoryNode)
        }
    }

    return @($rows)
}

function Write-UGSMGameDayZCfgEnvironmentRows {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][object[]]$FileRows,
        [Parameter(Mandatory)][object[]]$TerritoryRows
    )

    $settings = New-Object System.Xml.XmlWriterSettings
    $settings.Indent = $true
    $settings.IndentChars = '    '
    $settings.NewLineChars = [Environment]::NewLine
    $settings.NewLineHandling = [System.Xml.NewLineHandling]::Replace
    $settings.Encoding = New-Object System.Text.UTF8Encoding($false)

    $parent = Split-Path -Parent $Path
    if (-not [string]::IsNullOrWhiteSpace([string]$parent) -and -not (Test-Path -LiteralPath $parent -PathType Container)) {
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
    }

    $writer = [System.Xml.XmlWriter]::Create($Path, $settings)
    try {
        $writer.WriteStartDocument()
        $writer.WriteStartElement('env')
        $writer.WriteStartElement('territories')

        foreach ($fileRow in @($FileRows)) {
            if ($null -eq $fileRow) { continue }
            $pathValue = [string]$fileRow.Path
            if ([string]::IsNullOrWhiteSpace($pathValue)) { continue }

            $writer.WriteStartElement('file')
            $writer.WriteAttributeString('path', $pathValue.Trim())
            $writer.WriteEndElement()
        }

        foreach ($territoryRow in @($TerritoryRows)) {
            if ($null -eq $territoryRow) { continue }

            $name = [string]$territoryRow.Name
            if ([string]::IsNullOrWhiteSpace($name)) { continue }

            $outerXml = [string]$territoryRow.OuterXml
            $fragmentDoc = New-Object System.Xml.XmlDocument
            $territoryNode = $null

            if (-not [string]::IsNullOrWhiteSpace($outerXml)) {
                try {
                    $fragmentDoc.LoadXml("<root>$outerXml</root>")
                    $territoryNode = $fragmentDoc.DocumentElement.SelectSingleNode('./territory')
                }
                catch {
                    $territoryNode = $null
                }
            }

            if ($null -eq $territoryNode) {
                $territoryNode = $fragmentDoc.CreateElement('territory')
                [void]$territoryNode.SetAttribute('name', $name.Trim())
            }

            [void]$territoryNode.SetAttribute('name', $name.Trim())
            [void]$territoryNode.SetAttribute('type', ([string]$territoryRow.Type).Trim())
            [void]$territoryNode.SetAttribute('behavior', ([string]$territoryRow.Behavior).Trim())

            foreach ($oldFile in @($territoryNode.SelectNodes('./file'))) {
                [void]$territoryNode.RemoveChild($oldFile)
            }

            $firstChild = $territoryNode.FirstChild
            foreach ($usable in @(([string]$territoryRow.FileUsable -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ }))) {
                $fileNode = $fragmentDoc.CreateElement('file')
                [void]$fileNode.SetAttribute('usable', $usable)
                if ($firstChild) {
                    [void]$territoryNode.InsertBefore($fileNode, $firstChild)
                }
                else {
                    [void]$territoryNode.AppendChild($fileNode)
                }
            }

            $writer.WriteRaw([string](Convert-UGSMGameDayZXmlNodeToPrettyString -Node $territoryNode))
        }

        $writer.WriteEndElement()
        $writer.WriteEndElement()
        $writer.WriteEndDocument()
    }
    finally {
        if ($writer) { $writer.Dispose() }
    }

    return $Path
}

function Get-UGSMGameDayZCfgEnvironmentGridFileRows {
    [CmdletBinding()]
    param([Parameter(Mandatory)][System.Windows.Forms.DataGridView]$Grid)

    $rows = @()
    foreach ($gridRow in @($Grid.Rows)) {
        if ($null -eq $gridRow -or $gridRow.IsNewRow) { continue }

        $pathValue = [string]$gridRow.Cells['Path'].Value
        if ([string]::IsNullOrWhiteSpace($pathValue)) { continue }

        $rows += [pscustomobject]@{
            Index = [string]$gridRow.Cells['Index'].Value
            Path  = $pathValue.Trim()
        }
    }

    return @($rows)
}

function Get-UGSMGameDayZCfgEnvironmentGridTerritoryRows {
    [CmdletBinding()]
    param([Parameter(Mandatory)][System.Windows.Forms.DataGridView]$Grid)

    $rows = @()
    foreach ($gridRow in @($Grid.Rows)) {
        if ($null -eq $gridRow -or $gridRow.IsNewRow) { continue }

        $name = [string]$gridRow.Cells['Name'].Value
        if ([string]::IsNullOrWhiteSpace($name)) { continue }

        $tag = $gridRow.Tag
        $rows += [pscustomobject]@{
            Index      = [string]$gridRow.Cells['Index'].Value
            Name       = $name.Trim()
            Type       = [string]$gridRow.Cells['Type'].Value
            Behavior   = [string]$gridRow.Cells['Behavior'].Value
            FileUsable = [string]$gridRow.Cells['FileUsable'].Value
            Agents     = [string]$gridRow.Cells['Agents'].Value
            Spawns     = [string]$gridRow.Cells['Spawns'].Value
            Items      = [string]$gridRow.Cells['Items'].Value
            OuterXml   = if ($tag -and $tag.PSObject.Properties.Name -contains 'OuterXml') { [string]$tag.OuterXml } else { '' }
        }
    }

    return @($rows)
}

function Read-UGSMGameDayZTerritoryZoneRows {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return @() }

    $xml = Read-UGSMGameDayZXmlDocumentSafe -Path $Path
    if ($null -eq $xml -or $null -eq $xml.DocumentElement) { return @() }

    $rows = @()
    $territoryIndex = 0

    foreach ($territoryNode in @($xml.SelectNodes('/territory-type/territory'))) {
        if ($null -eq $territoryNode) { continue }

        $territoryIndex++
        $color = [string]$territoryNode.GetAttribute('color')
        $zoneIndex = 0

        foreach ($zoneNode in @($territoryNode.SelectNodes('./zone'))) {
            if ($null -eq $zoneNode) { continue }
            $zoneIndex++

            $rows += [pscustomobject]@{
                Territory = $territoryIndex
                Color     = $color
                Zone      = $zoneIndex
                Name      = [string]$zoneNode.GetAttribute('name')
                SMin      = [string]$zoneNode.GetAttribute('smin')
                SMax      = [string]$zoneNode.GetAttribute('smax')
                DMin      = [string]$zoneNode.GetAttribute('dmin')
                DMax      = [string]$zoneNode.GetAttribute('dmax')
                X         = [string]$zoneNode.GetAttribute('x')
                Z         = [string]$zoneNode.GetAttribute('z')
                R         = [string]$zoneNode.GetAttribute('r')
            }
        }
    }

    return @($rows)
}

function Get-UGSMGameDayZTerritoryZoneGridRows {
    [CmdletBinding()]
    param([Parameter(Mandatory)][System.Windows.Forms.DataGridView]$Grid)

    $rows = @()
    foreach ($gridRow in @($Grid.Rows)) {
        if ($null -eq $gridRow -or $gridRow.IsNewRow) { continue }

        $territory = [string]$gridRow.Cells['Territory'].Value
        $x = [string]$gridRow.Cells['X'].Value
        $z = [string]$gridRow.Cells['Z'].Value
        $r = [string]$gridRow.Cells['R'].Value

        if ([string]::IsNullOrWhiteSpace($territory) -or [string]::IsNullOrWhiteSpace($x) -or [string]::IsNullOrWhiteSpace($z) -or [string]::IsNullOrWhiteSpace($r)) {
            continue
        }

        $rows += [pscustomobject]@{
            Territory = $territory
            Color     = [string]$gridRow.Cells['Color'].Value
            Zone      = [string]$gridRow.Cells['Zone'].Value
            Name      = [string]$gridRow.Cells['Name'].Value
            SMin      = [string]$gridRow.Cells['SMin'].Value
            SMax      = [string]$gridRow.Cells['SMax'].Value
            DMin      = [string]$gridRow.Cells['DMin'].Value
            DMax      = [string]$gridRow.Cells['DMax'].Value
            X         = $x
            Z         = $z
            R         = $r
        }
    }

    return @($rows)
}

function Write-UGSMGameDayZTerritoryZoneRows {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][object[]]$Rows
    )

    $settings = New-Object System.Xml.XmlWriterSettings
    $settings.Indent = $true
    $settings.IndentChars = '    '
    $settings.NewLineChars = [Environment]::NewLine
    $settings.NewLineHandling = [System.Xml.NewLineHandling]::Replace
    $settings.Encoding = New-Object System.Text.UTF8Encoding($false)

    $parent = Split-Path -Parent $Path
    if (-not [string]::IsNullOrWhiteSpace([string]$parent) -and -not (Test-Path -LiteralPath $parent -PathType Container)) {
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
    }

    $writer = [System.Xml.XmlWriter]::Create($Path, $settings)
    try {
        $writer.WriteStartDocument()
        $writer.WriteStartElement('territory-type')

        $grouped = @($Rows | Sort-Object {[int]$_.Territory}, {[int]$_.Zone} | Group-Object -Property Territory)
        foreach ($group in $grouped) {
            $groupRows = @($group.Group)
            if (@($groupRows).Count -le 0) { continue }

            $color = [string]$groupRows[0].Color
            if ([string]::IsNullOrWhiteSpace($color)) { $color = '4294923520' }

            $writer.WriteStartElement('territory')
            $writer.WriteAttributeString('color', $color)

            foreach ($row in $groupRows) {
                $writer.WriteStartElement('zone')
                $writer.WriteAttributeString('name', ([string]$row.Name))
                $writer.WriteAttributeString('smin', ([string]$row.SMin))
                $writer.WriteAttributeString('smax', ([string]$row.SMax))
                $writer.WriteAttributeString('dmin', ([string]$row.DMin))
                $writer.WriteAttributeString('dmax', ([string]$row.DMax))
                $writer.WriteAttributeString('x', ([string]$row.X))
                $writer.WriteAttributeString('z', ([string]$row.Z))
                $writer.WriteAttributeString('r', ([string]$row.R))
                $writer.WriteEndElement()
            }

            $writer.WriteEndElement()
        }

        $writer.WriteEndElement()
        $writer.WriteEndDocument()
    }
    finally {
        if ($writer) { $writer.Dispose() }
    }

    return $Path
}




function Read-UGSMGameDayZEventSpawnsXmlRows {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return @() }

    $xml = Read-UGSMGameDayZXmlDocumentSafe -Path $Path
    if ($null -eq $xml -or $null -eq $xml.DocumentElement) { return @() }

    $rows = @()
    $eventIndex = 0

    foreach ($eventNode in @($xml.DocumentElement.SelectNodes('./event[@name]'))) {
        if ($null -eq $eventNode) { continue }

        $eventIndex++
        $eventName = [string]$eventNode.GetAttribute('name')
        $nodeIndex = 0

        foreach ($childNode in @($eventNode.ChildNodes)) {
            if ($null -eq $childNode -or $childNode.NodeType -ne [System.Xml.XmlNodeType]::Element) { continue }
            if ($childNode.Name -ne 'pos' -and $childNode.Name -ne 'zone') { continue }

            $nodeIndex++
            $rows += [pscustomobject]@{
                EventIndex = $eventIndex
                PosIndex   = $nodeIndex
                NodeType   = [string]$childNode.Name
                EventName  = $eventName
                X          = [string]$childNode.GetAttribute('x')
                Y          = [string]$childNode.GetAttribute('y')
                Z          = [string]$childNode.GetAttribute('z')
                A          = [string]$childNode.GetAttribute('a')
                SMin       = [string]$childNode.GetAttribute('smin')
                SMax       = [string]$childNode.GetAttribute('smax')
                DMin       = [string]$childNode.GetAttribute('dmin')
                DMax       = [string]$childNode.GetAttribute('dmax')
                R          = [string]$childNode.GetAttribute('r')
            }
        }

        if ($nodeIndex -eq 0) {
            $rows += [pscustomobject]@{
                EventIndex = $eventIndex
                PosIndex   = 0
                NodeType   = 'event'
                EventName  = $eventName
                X          = ''
                Y          = ''
                Z          = ''
                A          = ''
                SMin       = ''
                SMax       = ''
                DMin       = ''
                DMax       = ''
                R          = ''
            }
        }
    }

    return @($rows)
}

function Get-UGSMGameDayZEventSpawnsGridRows {
    [CmdletBinding()]
    param([Parameter(Mandatory)][System.Windows.Forms.DataGridView]$Grid)

    $rows = @()
    foreach ($gridRow in @($Grid.Rows)) {
        if ($null -eq $gridRow -or $gridRow.IsNewRow) { continue }

        $eventName = [string]$gridRow.Cells['EventName'].Value
        if ([string]::IsNullOrWhiteSpace($eventName)) { continue }

        $nodeType = [string]$gridRow.Cells['NodeType'].Value
        if ([string]::IsNullOrWhiteSpace($nodeType)) {
            if (-not [string]::IsNullOrWhiteSpace([string]$gridRow.Cells['SMin'].Value) -or -not [string]::IsNullOrWhiteSpace([string]$gridRow.Cells['R'].Value)) {
                $nodeType = 'zone'
            }
            elseif (-not [string]::IsNullOrWhiteSpace([string]$gridRow.Cells['X'].Value) -or -not [string]::IsNullOrWhiteSpace([string]$gridRow.Cells['Z'].Value)) {
                $nodeType = 'pos'
            }
            else {
                $nodeType = 'event'
            }
        }

        $rows += [pscustomobject]@{
            EventIndex = [string]$gridRow.Cells['EventIndex'].Value
            PosIndex   = [string]$gridRow.Cells['PosIndex'].Value
            NodeType   = $nodeType.Trim().ToLowerInvariant()
            EventName  = $eventName.Trim()
            X          = [string]$gridRow.Cells['X'].Value
            Y          = [string]$gridRow.Cells['Y'].Value
            Z          = [string]$gridRow.Cells['Z'].Value
            A          = [string]$gridRow.Cells['A'].Value
            SMin       = [string]$gridRow.Cells['SMin'].Value
            SMax       = [string]$gridRow.Cells['SMax'].Value
            DMin       = [string]$gridRow.Cells['DMin'].Value
            DMax       = [string]$gridRow.Cells['DMax'].Value
            R          = [string]$gridRow.Cells['R'].Value
        }
    }

    return @($rows)
}

function Write-UGSMGameDayZEventSpawnsXmlRows {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][object[]]$Rows
    )

    $settings = New-Object System.Xml.XmlWriterSettings
    $settings.Indent = $true
    $settings.IndentChars = "`t"
    $settings.NewLineChars = [Environment]::NewLine
    $settings.NewLineHandling = [System.Xml.NewLineHandling]::Replace
    $settings.Encoding = New-Object System.Text.UTF8Encoding($false)

    $parent = Split-Path -Parent $Path
    if (-not [string]::IsNullOrWhiteSpace([string]$parent) -and -not (Test-Path -LiteralPath $parent -PathType Container)) {
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
    }

    $writer = [System.Xml.XmlWriter]::Create($Path, $settings)
    try {
        $writer.WriteStartDocument($true)
        $writer.WriteStartElement('eventposdef')

        $eventRows = @($Rows | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_.EventName) } | Sort-Object @{ Expression = { try { [int]$_.EventIndex } catch { 999999 } } }, @{ Expression = { [string]$_.EventName } }, @{ Expression = { try { [int]$_.PosIndex } catch { 999999 } } })
        $grouped = @($eventRows | Group-Object -Property EventName)
        $grouped = @($grouped | Sort-Object @{ Expression = { try { [int]($_.Group | Select-Object -First 1).EventIndex } catch { 999999 } } }, Name)

        foreach ($group in $grouped) {
            $eventName = [string]$group.Name
            if ([string]::IsNullOrWhiteSpace($eventName)) { continue }

            $writer.WriteStartElement('event')
            $writer.WriteAttributeString('name', $eventName)

            foreach ($row in @($group.Group | Sort-Object @{ Expression = { try { [int]$_.PosIndex } catch { 999999 } } })) {
                $nodeType = [string]$row.NodeType
                if ([string]::IsNullOrWhiteSpace($nodeType)) { $nodeType = 'pos' }
                $nodeType = $nodeType.Trim().ToLowerInvariant()

                if ($nodeType -eq 'event') { continue }

                if ($nodeType -eq 'zone') {
                    $writer.WriteStartElement('zone')
                    foreach ($attr in @(
                            @{ Name = 'smin'; Value = [string]$row.SMin },
                            @{ Name = 'smax'; Value = [string]$row.SMax },
                            @{ Name = 'dmin'; Value = [string]$row.DMin },
                            @{ Name = 'dmax'; Value = [string]$row.DMax },
                            @{ Name = 'r';    Value = [string]$row.R }
                        )) {
                        if (-not [string]::IsNullOrWhiteSpace($attr.Value)) {
                            $writer.WriteAttributeString($attr.Name, $attr.Value)
                        }
                    }
                    $writer.WriteEndElement()
                    continue
                }

                $x = [string]$row.X
                $z = [string]$row.Z
                if ([string]::IsNullOrWhiteSpace($x) -or [string]::IsNullOrWhiteSpace($z)) { continue }

                $writer.WriteStartElement('pos')
                $writer.WriteAttributeString('x', $x)
                $writer.WriteAttributeString('z', $z)
                if (-not [string]::IsNullOrWhiteSpace([string]$row.A)) {
                    $writer.WriteAttributeString('a', [string]$row.A)
                }
                if (-not [string]::IsNullOrWhiteSpace([string]$row.Y)) {
                    $writer.WriteAttributeString('y', [string]$row.Y)
                }
                $writer.WriteEndElement()
            }

            $writer.WriteEndElement()
        }

        $writer.WriteEndElement()
        $writer.WriteEndDocument()
    }
    finally {
        if ($writer) { $writer.Dispose() }
    }

    return $Path
}




function Read-UGSMGameDayZCfgEconomyCoreRootClassRows {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return @() }

    $xml = Read-UGSMGameDayZXmlDocumentSafe -Path $Path
    if ($null -eq $xml -or $null -eq $xml.DocumentElement) { return @() }

    $rows = @()
    $index = 0
    foreach ($node in @($xml.SelectNodes('/economycore/classes/rootclass[@name]'))) {
        if ($null -eq $node) { continue }
        $index++
        $rows += [pscustomobject]@{
            Index            = $index
            Name             = [string]$node.GetAttribute('name')
            Act              = [string]$node.GetAttribute('act')
            ReportMemoryLOD  = [string]$node.GetAttribute('reportMemoryLOD')
        }
    }

    return @($rows)
}

function Read-UGSMGameDayZCfgEconomyCoreDefaultRows {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return @() }

    $xml = Read-UGSMGameDayZXmlDocumentSafe -Path $Path
    if ($null -eq $xml -or $null -eq $xml.DocumentElement) { return @() }

    $rows = @()
    $index = 0
    foreach ($node in @($xml.SelectNodes('/economycore/defaults/default[@name]'))) {
        if ($null -eq $node) { continue }
        $index++
        $rows += [pscustomobject]@{
            Index = $index
            Name  = [string]$node.GetAttribute('name')
            Value = [string]$node.GetAttribute('value')
        }
    }

    return @($rows)
}

function Get-UGSMGameDayZCfgEconomyCoreRootClassGridRows {
    [CmdletBinding()]
    param([Parameter(Mandatory)][System.Windows.Forms.DataGridView]$Grid)

    $rows = @()
    foreach ($gridRow in @($Grid.Rows)) {
        if ($null -eq $gridRow -or $gridRow.IsNewRow) { continue }

        $name = [string]$gridRow.Cells['Name'].Value
        if ([string]::IsNullOrWhiteSpace($name)) { continue }

        $rows += [pscustomobject]@{
            Index           = [string]$gridRow.Cells['Index'].Value
            Name            = $name.Trim()
            Act             = [string]$gridRow.Cells['Act'].Value
            ReportMemoryLOD = [string]$gridRow.Cells['ReportMemoryLOD'].Value
        }
    }

    return @($rows)
}

function Get-UGSMGameDayZCfgEconomyCoreDefaultGridRows {
    [CmdletBinding()]
    param([Parameter(Mandatory)][System.Windows.Forms.DataGridView]$Grid)

    $rows = @()
    foreach ($gridRow in @($Grid.Rows)) {
        if ($null -eq $gridRow -or $gridRow.IsNewRow) { continue }

        $name = [string]$gridRow.Cells['Name'].Value
        if ([string]::IsNullOrWhiteSpace($name)) { continue }

        $rows += [pscustomobject]@{
            Index = [string]$gridRow.Cells['Index'].Value
            Name  = $name.Trim()
            Value = [string]$gridRow.Cells['Value'].Value
        }
    }

    return @($rows)
}

function Write-UGSMGameDayZCfgEconomyCoreRows {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][object[]]$RootClassRows,
        [Parameter(Mandatory)][object[]]$DefaultRows
    )

    $settings = New-Object System.Xml.XmlWriterSettings
    $settings.Indent = $true
    $settings.IndentChars = "`t"
    $settings.NewLineChars = [Environment]::NewLine
    $settings.NewLineHandling = [System.Xml.NewLineHandling]::Replace
    $settings.Encoding = New-Object System.Text.UTF8Encoding($false)

    $parent = Split-Path -Parent $Path
    if (-not [string]::IsNullOrWhiteSpace([string]$parent) -and -not (Test-Path -LiteralPath $parent -PathType Container)) {
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
    }

    $writer = [System.Xml.XmlWriter]::Create($Path, $settings)
    try {
        $writer.WriteStartDocument($true)
        $writer.WriteStartElement('economycore')

        $writer.WriteStartElement('classes')
        foreach ($row in @($RootClassRows)) {
            if ($null -eq $row) { continue }

            $name = [string]$row.Name
            if ([string]::IsNullOrWhiteSpace($name)) { continue }

            $writer.WriteStartElement('rootclass')
            $writer.WriteAttributeString('name', $name.Trim())

            $act = [string]$row.Act
            if (-not [string]::IsNullOrWhiteSpace($act)) {
                $writer.WriteAttributeString('act', $act.Trim())
            }

            $reportMemoryLOD = [string]$row.ReportMemoryLOD
            if (-not [string]::IsNullOrWhiteSpace($reportMemoryLOD)) {
                $writer.WriteAttributeString('reportMemoryLOD', $reportMemoryLOD.Trim())
            }

            $writer.WriteEndElement()
        }
        $writer.WriteEndElement()

        $writer.WriteStartElement('defaults')
        foreach ($row in @($DefaultRows)) {
            if ($null -eq $row) { continue }

            $name = [string]$row.Name
            if ([string]::IsNullOrWhiteSpace($name)) { continue }

            $writer.WriteStartElement('default')
            $writer.WriteAttributeString('name', $name.Trim())
            $writer.WriteAttributeString('value', [string]$row.Value)
            $writer.WriteEndElement()
        }
        $writer.WriteEndElement()

        $writer.WriteEndElement()
        $writer.WriteEndDocument()
    }
    finally {
        if ($writer) { $writer.Dispose() }
    }

    return $Path
}




function Read-UGSMGameDayZCfgEventGroupsRows {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return @() }

    $xml = Read-UGSMGameDayZXmlDocumentSafe -Path $Path
    if ($null -eq $xml -or $null -eq $xml.DocumentElement) { return @() }

    $rows = @()
    $groupIndex = 0
    foreach ($groupNode in @($xml.SelectNodes('/eventgroupdef/group[@name]'))) {
        if ($null -eq $groupNode) { continue }

        $groupIndex++
        $groupName = [string]$groupNode.GetAttribute('name')
        $childIndex = 0

        foreach ($childNode in @($groupNode.SelectNodes('./child[@type]'))) {
            if ($null -eq $childNode) { continue }

            $childIndex++
            $rows += [pscustomobject]@{
                GroupIndex = $groupIndex
                ChildIndex = $childIndex
                GroupName  = $groupName
                Type       = [string]$childNode.GetAttribute('type')
                Deloot     = [string]$childNode.GetAttribute('deloot')
                LootMax    = [string]$childNode.GetAttribute('lootmax')
                LootMin    = [string]$childNode.GetAttribute('lootmin')
                X          = [string]$childNode.GetAttribute('x')
                Z          = [string]$childNode.GetAttribute('z')
                A          = [string]$childNode.GetAttribute('a')
                Y          = [string]$childNode.GetAttribute('y')
            }
        }

        if ($childIndex -eq 0) {
            $rows += [pscustomobject]@{
                GroupIndex = $groupIndex
                ChildIndex = 0
                GroupName  = $groupName
                Type       = ''
                Deloot     = ''
                LootMax    = ''
                LootMin    = ''
                X          = ''
                Z          = ''
                A          = ''
                Y          = ''
            }
        }
    }

    return @($rows)
}

function Get-UGSMGameDayZCfgEventGroupsGridRows {
    [CmdletBinding()]
    param([Parameter(Mandatory)][System.Windows.Forms.DataGridView]$Grid)

    $rows = @()
    foreach ($gridRow in @($Grid.Rows)) {
        if ($null -eq $gridRow -or $gridRow.IsNewRow) { continue }

        $groupName = [string]$gridRow.Cells['GroupName'].Value
        if ([string]::IsNullOrWhiteSpace($groupName)) { continue }

        $rows += [pscustomobject]@{
            GroupIndex = [string]$gridRow.Cells['GroupIndex'].Value
            ChildIndex = [string]$gridRow.Cells['ChildIndex'].Value
            GroupName  = $groupName.Trim()
            Type       = [string]$gridRow.Cells['Type'].Value
            Deloot     = [string]$gridRow.Cells['Deloot'].Value
            LootMax    = [string]$gridRow.Cells['LootMax'].Value
            LootMin    = [string]$gridRow.Cells['LootMin'].Value
            X          = [string]$gridRow.Cells['X'].Value
            Z          = [string]$gridRow.Cells['Z'].Value
            A          = [string]$gridRow.Cells['A'].Value
            Y          = [string]$gridRow.Cells['Y'].Value
        }
    }

    return @($rows)
}

function Write-UGSMGameDayZCfgEventGroupsRows {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][object[]]$Rows
    )

    $settings = New-Object System.Xml.XmlWriterSettings
    $settings.Indent = $true
    $settings.IndentChars = "    "
    $settings.NewLineChars = [Environment]::NewLine
    $settings.NewLineHandling = [System.Xml.NewLineHandling]::Replace
    $settings.Encoding = New-Object System.Text.UTF8Encoding($false)

    $parent = Split-Path -Parent $Path
    if (-not [string]::IsNullOrWhiteSpace([string]$parent) -and -not (Test-Path -LiteralPath $parent -PathType Container)) {
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
    }

    $writer = [System.Xml.XmlWriter]::Create($Path, $settings)
    try {
        $writer.WriteStartDocument($true)
        $writer.WriteStartElement('eventgroupdef')

        $grouped = @($Rows | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_.GroupName) } | Sort-Object @{ Expression = { try { [int]$_.GroupIndex } catch { 999999 } } }, @{ Expression = { [string]$_.GroupName } }, @{ Expression = { try { [int]$_.ChildIndex } catch { 999999 } } } | Group-Object -Property GroupName)
        $grouped = @($grouped | Sort-Object @{ Expression = { try { [int]($_.Group | Select-Object -First 1).GroupIndex } catch { 999999 } } }, Name)

        foreach ($group in $grouped) {
            $groupName = [string]$group.Name
            if ([string]::IsNullOrWhiteSpace($groupName)) { continue }

            $writer.WriteStartElement('group')
            $writer.WriteAttributeString('name', $groupName)

            foreach ($row in @($group.Group | Sort-Object @{ Expression = { try { [int]$_.ChildIndex } catch { 999999 } } })) {
                $type = [string]$row.Type
                if ([string]::IsNullOrWhiteSpace($type)) { continue }

                $writer.WriteStartElement('child')
                $writer.WriteAttributeString('type', $type)

                foreach ($attr in @(
                        @{ Name = 'deloot'; Value = [string]$row.Deloot },
                        @{ Name = 'lootmax'; Value = [string]$row.LootMax },
                        @{ Name = 'lootmin'; Value = [string]$row.LootMin },
                        @{ Name = 'x'; Value = [string]$row.X },
                        @{ Name = 'z'; Value = [string]$row.Z },
                        @{ Name = 'a'; Value = [string]$row.A },
                        @{ Name = 'y'; Value = [string]$row.Y }
                    )) {
                    if (-not [string]::IsNullOrWhiteSpace($attr.Value)) {
                        $writer.WriteAttributeString($attr.Name, $attr.Value)
                    }
                }

                $writer.WriteEndElement()
            }

            $writer.WriteEndElement()
        }

        $writer.WriteEndElement()
        $writer.WriteEndDocument()
    }
    finally {
        if ($writer) { $writer.Dispose() }
    }

    return $Path
}




function Read-UGSMGameDayZCfgIgnoreListRows {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return @() }

    $xml = Read-UGSMGameDayZXmlDocumentSafe -Path $Path
    if ($null -eq $xml -or $null -eq $xml.DocumentElement) { return @() }

    $rows = @()
    $index = 0
    foreach ($node in @($xml.SelectNodes('/ignore/type[@name]'))) {
        if ($null -eq $node) { continue }
        $index++
        $rows += [pscustomobject]@{
            Index = $index
            Name  = [string]$node.GetAttribute('name')
        }
    }

    return @($rows)
}

function Get-UGSMGameDayZCfgIgnoreListGridRows {
    [CmdletBinding()]
    param([Parameter(Mandatory)][System.Windows.Forms.DataGridView]$Grid)

    $rows = @()
    foreach ($gridRow in @($Grid.Rows)) {
        if ($null -eq $gridRow -or $gridRow.IsNewRow) { continue }

        $name = [string]$gridRow.Cells['Name'].Value
        if ([string]::IsNullOrWhiteSpace($name)) { continue }

        $rows += [pscustomobject]@{
            Index = [string]$gridRow.Cells['Index'].Value
            Name  = $name.Trim()
        }
    }

    return @($rows)
}

function Write-UGSMGameDayZCfgIgnoreListRows {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][object[]]$Rows
    )

    $settings = New-Object System.Xml.XmlWriterSettings
    $settings.Indent = $true
    $settings.IndentChars = "`t"
    $settings.NewLineChars = [Environment]::NewLine
    $settings.NewLineHandling = [System.Xml.NewLineHandling]::Replace
    $settings.Encoding = New-Object System.Text.UTF8Encoding($false)

    $parent = Split-Path -Parent $Path
    if (-not [string]::IsNullOrWhiteSpace([string]$parent) -and -not (Test-Path -LiteralPath $parent -PathType Container)) {
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
    }

    $writer = [System.Xml.XmlWriter]::Create($Path, $settings)
    try {
        $writer.WriteStartDocument($true)
        $writer.WriteStartElement('ignore')

        foreach ($row in @($Rows)) {
            if ($null -eq $row) { continue }
            $name = [string]$row.Name
            if ([string]::IsNullOrWhiteSpace($name)) { continue }

            $writer.WriteStartElement('type')
            $writer.WriteAttributeString('name', $name.Trim())
            $writer.WriteEndElement()
        }

        $writer.WriteEndElement()
        $writer.WriteEndDocument()
    }
    finally {
        if ($writer) { $writer.Dispose() }
    }

    return $Path
}


function New-DayZXmlContent {
        param(
            [Parameter(Mandatory)][System.Windows.Forms.Control]$Parent
        )

        $xmlInstance = $editorInstance
        $xmlStatusLabel = $editorStatusLabel
        $xmlKinds = @('Types', 'SpawnableTypes', 'Events', 'EventSpawns', 'Globals', 'Economy', 'Messages', 'CfgGameplay', 'CfgEconomyCore', 'CfgEffectArea', 'CfgEnvironment', 'TerritoryZones', 'CfgEventGroups', 'CfgIgnoreList', 'CfgPlayerSpawnPoints', 'CfgRandomPresets', 'CfgWeather', 'MapGroupPos', 'MapGroupProto', 'MapGroupCluster', 'MapGroupDirt', 'MapClusterProto')

        $usageOptions = @(
            'Town', 'Village', 'School', 'Industrial', 'Farm',
            'Firefighter', 'Medic', 'Coast', 'Office', 'Police',
            'Hunting', 'Military', 'Prison', 'Lunapark',
            'SeasonalEvent', 'ContaminatedArea', 'Historical'
        )

        $valueOptions = @('Tier1', 'Tier2', 'Tier3', 'Tier4', 'Unique')

        $bulkFields = @('nominal', 'lifetime', 'restock', 'min', 'max', 'quantmin', 'quantmax', 'cost', 'deloot')

        $rootPanel = New-Object System.Windows.Forms.Panel
        $rootPanel.Dock = 'Fill'
        $rootPanel.Padding = New-Object System.Windows.Forms.Padding(10, 8, 10, 10)
        $rootPanel.BackColor = New-UGSMColor '#0B121D'
        [void]$Parent.Controls.Add($rootPanel)

        $desc = New-UGSMLabel -Text 'Edit runtime XML files and merge XML content from active DayZ mods.' -X 0 -Y 0 -Width 1200 -Height 18 -FontSize 8.5 -Color $Theme.Muted
        [void]$rootPanel.Controls.Add($desc)

        $topBar = New-Object System.Windows.Forms.Panel
        $topBar.Location = New-Object System.Drawing.Point(0, 26)
        $topBar.Height = 58
        $topBar.Anchor = 'Top,Left,Right'
        $topBar.Width = [Math]::Max(900, $rootPanel.ClientSize.Width)
        $topBar.BackColor = New-UGSMColor '#0B121D'
        [void]$rootPanel.Controls.Add($topBar)

        $lblKind = New-UGSMLabel -Text 'XML File:' -X 0 -Y 0 -Width 80 -Height 18 -FontSize 8.5 -Color $Theme.Text
        [void]$topBar.Controls.Add($lblKind)

        $cmbKind = New-Object System.Windows.Forms.ComboBox
        $cmbKind.Location = New-Object System.Drawing.Point(0, 22)
        $cmbKind.Size = New-Object System.Drawing.Size(220, 24)
        $cmbKind.DropDownStyle = 'DropDownList'
        $cmbKind.FlatStyle = 'Flat'
        $cmbKind.BackColor = [System.Drawing.Color]::White
        $cmbKind.ForeColor = [System.Drawing.Color]::Black
        foreach ($kind in $xmlKinds) { [void]$cmbKind.Items.Add($kind) }
        $cmbKind.SelectedIndex = 0
        [void]$topBar.Controls.Add($cmbKind)

        $btnLoadXml = New-UGSMButton -Text 'Load XML' -X 240 -Y 20 -Width 95 -Height 28 -BackColor '#253341'
        $btnSaveXml = New-UGSMButton -Text 'Save XML' -X 345 -Y 20 -Width 95 -Height 28 -BackColor $Theme.Accent

        $lblXmlMod = New-UGSMLabel -Text 'Mod:' -X 455 -Y 4 -Width 40 -Height 18 -FontSize 8.5 -Color $Theme.Text
        [void]$topBar.Controls.Add($lblXmlMod)

        $cmbXmlMod = New-Object System.Windows.Forms.ComboBox
        $cmbXmlMod.Location = New-Object System.Drawing.Point(455, 22)
        $cmbXmlMod.Size = New-Object System.Drawing.Size(250, 24)
        $cmbXmlMod.DropDownStyle = 'DropDownList'
        $cmbXmlMod.FlatStyle = 'Flat'
        $cmbXmlMod.BackColor = [System.Drawing.Color]::White
        $cmbXmlMod.ForeColor = [System.Drawing.Color]::Black
        [void]$topBar.Controls.Add($cmbXmlMod)

        # Reuse the existing button variable names so the rest of the file stays stable.
        $btnBackupXml = New-UGSMButton -Text 'Preview Selected types.xml' -X 725 -Y 20 -Width 170 -Height 28 -BackColor '#9FCFE2'
        $btnMergeXml = New-UGSMButton -Text 'Apply Selected types.xml' -X 905 -Y 20 -Width 160 -Height 28 -BackColor '#F4A300'
        $btnXmlPreviewRemoved = New-UGSMButton -Text 'Preview Removed types.xml Cleanup' -X 1075 -Y 20 -Width 220 -Height 28 -BackColor '#9FCFE2'
        $btnXmlApplyRemoved = New-UGSMButton -Text 'Apply Removed types.xml Cleanup' -X 1305 -Y 20 -Width 220 -Height 28 -BackColor $global:UGSM_ColorDanger

        [void]$topBar.Controls.Add($btnLoadXml)
        [void]$topBar.Controls.Add($btnSaveXml)
        [void]$topBar.Controls.Add($btnBackupXml)
        [void]$topBar.Controls.Add($btnMergeXml)
        [void]$topBar.Controls.Add($btnXmlPreviewRemoved)
        [void]$topBar.Controls.Add($btnXmlApplyRemoved)

        $topTools = New-Object System.Windows.Forms.Panel
        $topTools.Location = New-Object System.Drawing.Point(0, 90)
        $topTools.Height = 58
        $topTools.Anchor = 'Top,Left,Right'
        $topTools.Width = [Math]::Max(900, $rootPanel.ClientSize.Width)
        $topTools.BackColor = New-UGSMColor '#0B121D'
        [void]$rootPanel.Controls.Add($topTools)

        $lblSearch = New-UGSMLabel -Text 'Search:' -X 0 -Y 4 -Width 52 -Height 18 -FontSize 8.5 -Color $Theme.Text
        [void]$topTools.Controls.Add($lblSearch)

        $txtSearch = New-DayZStretchTextBox
        $txtSearch.Location = New-Object System.Drawing.Point(58, 2)
        $txtSearch.Size = New-Object System.Drawing.Size(338, 24)
        [void]$topTools.Controls.Add($txtSearch)

        $btnSearch = New-UGSMButton -Text 'Search' -X 392 -Y 0 -Width 80 -Height 28 -BackColor '#253341'
        $btnShowAll = New-UGSMButton -Text 'Show All' -X 482 -Y 0 -Width 90 -Height 28 -BackColor '#253341'
        [void]$topTools.Controls.Add($btnSearch)
        [void]$topTools.Controls.Add($btnShowAll)

        $lblCategory = New-UGSMLabel -Text 'Category:' -X 594 -Y 4 -Width 70 -Height 18 -FontSize 8.5 -Color $Theme.Text
        [void]$topTools.Controls.Add($lblCategory)

        $cmbCategory = New-Object System.Windows.Forms.ComboBox
        $cmbCategory.Location = New-Object System.Drawing.Point(662, 2)
        $cmbCategory.Size = New-Object System.Drawing.Size(120, 24)
        $cmbCategory.DropDownStyle = 'DropDownList'
        $cmbCategory.FlatStyle = 'Flat'
        $cmbCategory.BackColor = [System.Drawing.Color]::White
        $cmbCategory.ForeColor = [System.Drawing.Color]::Black
        [void]$cmbCategory.Items.Add('All')
        $cmbCategory.SelectedIndex = 0
        [void]$topTools.Controls.Add($cmbCategory)

        $lblBulk = New-UGSMLabel -Text 'Bulk Edit Selected' -X 0 -Y 32 -Width 140 -Height 18 -FontSize 8.5 -Style Bold -Color $Theme.Text
        [void]$topTools.Controls.Add($lblBulk)

        $cmbBulkField = New-Object System.Windows.Forms.ComboBox
        $cmbBulkField.Location = New-Object System.Drawing.Point(150, 30)
        $cmbBulkField.Size = New-Object System.Drawing.Size(120, 24)
        $cmbBulkField.DropDownStyle = 'DropDownList'
        $cmbBulkField.FlatStyle = 'Flat'
        $cmbBulkField.BackColor = [System.Drawing.Color]::White
        $cmbBulkField.ForeColor = [System.Drawing.Color]::Black
        foreach ($field in $bulkFields) { [void]$cmbBulkField.Items.Add($field) }
        $cmbBulkField.SelectedIndex = 0
        [void]$topTools.Controls.Add($cmbBulkField)

        $txtBulkValue = New-DayZStretchTextBox
        $txtBulkValue.Location = New-Object System.Drawing.Point(280, 30)
        $txtBulkValue.Size = New-Object System.Drawing.Size(90, 24)
        [void]$topTools.Controls.Add($txtBulkValue)

        $btnApplySelected = New-UGSMButton -Text 'Apply Selected' -X 392 -Y 28 -Width 108 -Height 28 -BackColor '#F4A300'
        $btnApplyAll = New-UGSMButton -Text 'Apply All' -X 518 -Y 28 -Width 94 -Height 28 -BackColor '#FF2C2C'
        [void]$topTools.Controls.Add($btnApplySelected)
        [void]$topTools.Controls.Add($btnApplyAll)

        $btnAddEventSpawn = New-UGSMButton -Text 'Add Event Position' -X 392 -Y 28 -Width 150 -Height 28 -BackColor '#F4A300'
        $btnRemoveEventSpawn = New-UGSMButton -Text 'Remove Selected Position' -X 552 -Y 28 -Width 180 -Height 28 -BackColor $global:UGSM_ColorDanger
        [void]$topTools.Controls.Add($btnAddEventSpawn)
        [void]$topTools.Controls.Add($btnRemoveEventSpawn)

        $lblItemCount = New-UGSMLabel -Text 'Items: 0' -X 628 -Y 32 -Width 90 -Height 18 -FontSize 8.5 -Color $Theme.Muted
        [void]$topTools.Controls.Add($lblItemCount)

        $lblPath = New-UGSMLabel -Text 'Runtime Path:' -X 0 -Y 0 -Width 100 -Height 18 -FontSize 8.5 -Color $Theme.Text
        $lblPath.Location = New-Object System.Drawing.Point(0, 154)
        [void]$rootPanel.Controls.Add($lblPath)

        $txtPath = New-DayZStretchTextBox
        $txtPath.Location = New-Object System.Drawing.Point(0, 176)
        $txtPath.Anchor = 'Top,Left,Right'
        $txtPath.ReadOnly = $true
        $txtPath.Width = [Math]::Max(900, $rootPanel.ClientSize.Width)
        [void]$rootPanel.Controls.Add($txtPath)

        $detailsPanel = New-Object System.Windows.Forms.Panel
        $detailsPanel.Anchor = 'Top,Bottom,Right'
        $detailsPanel.BackColor = [System.Drawing.Color]::White
        $detailsPanel.BorderStyle = 'FixedSingle'
        [void]$rootPanel.Controls.Add($detailsPanel)

        $lblSpawnTitle = New-UGSMLabel -Text 'Spawn Configuration' -X 12 -Y 12 -Width 220 -Height 20 -FontSize 10 -Style Bold -Color '#111111'
        [void]$detailsPanel.Controls.Add($lblSpawnTitle)

        $lblSelectedName = New-UGSMLabel -Text '' -X 12 -Y 34 -Width 320 -Height 18 -FontSize 9 -Color '#111111'
        $lblSelectedName.AutoEllipsis = $true
        $lblSelectedName.AutoSize = $false
        [void]$detailsPanel.Controls.Add($lblSelectedName)

        $grpUsage = New-Object System.Windows.Forms.GroupBox
        $grpUsage.Text = 'Usage (Spawn Areas)'
        $grpUsage.ForeColor = [System.Drawing.Color]::FromArgb(70, 70, 70)
        $grpUsage.Location = New-Object System.Drawing.Point(12, 52)
        $grpUsage.Size = New-Object System.Drawing.Size(340, 240)
        [void]$detailsPanel.Controls.Add($grpUsage)

        $grpValue = New-Object System.Windows.Forms.GroupBox
        $grpValue.Text = 'Value (Tiers)'
        $grpValue.ForeColor = [System.Drawing.Color]::FromArgb(70, 70, 70)
        $grpValue.Location = New-Object System.Drawing.Point(12, 304)
        $grpValue.Size = New-Object System.Drawing.Size(340, 66)
        [void]$detailsPanel.Controls.Add($grpValue)

        $eventDetailsPanel = New-Object System.Windows.Forms.Panel
        $eventDetailsPanel.Anchor = 'Top,Bottom,Right'
        $eventDetailsPanel.BackColor = [System.Drawing.Color]::White
        $eventDetailsPanel.BorderStyle = 'FixedSingle'
        $eventDetailsPanel.Visible = $false
        [void]$rootPanel.Controls.Add($eventDetailsPanel)

        $lblEventTitle = New-UGSMLabel -Text 'Event Configuration' -X 12 -Y 12 -Width 220 -Height 20 -FontSize 10 -Style Bold -Color '#111111'
        [void]$eventDetailsPanel.Controls.Add($lblEventTitle)

        $lblEventSelectedName = New-UGSMLabel -Text '' -X 12 -Y 36 -Width 320 -Height 18 -FontSize 9 -Color '#111111'
        $lblEventSelectedName.AutoEllipsis = $true
        $lblEventSelectedName.AutoSize = $false
        [void]$eventDetailsPanel.Controls.Add($lblEventSelectedName)


        $spawnDetailsPanel = New-Object System.Windows.Forms.Panel
        $spawnDetailsPanel.Anchor = 'Top,Bottom,Right'
        $spawnDetailsPanel.BackColor = [System.Drawing.Color]::White
        $spawnDetailsPanel.BorderStyle = 'FixedSingle'
        $spawnDetailsPanel.Visible = $false
        [void]$rootPanel.Controls.Add($spawnDetailsPanel)

        $lblSpawnNodeTitle = New-UGSMLabel -Text 'Spawnable Type Editor' -X 12 -Y 12 -Width 220 -Height 20 -FontSize 10 -Style Bold -Color '#111111'
        [void]$spawnDetailsPanel.Controls.Add($lblSpawnNodeTitle)

        $lblSpawnSelectedName = New-UGSMLabel -Text '' -X 12 -Y 36 -Width 320 -Height 18 -FontSize 9 -Color '#111111'
        $lblSpawnSelectedName.AutoEllipsis = $true
        $lblSpawnSelectedName.AutoSize = $false
        [void]$spawnDetailsPanel.Controls.Add($lblSpawnSelectedName)

        $lblSpawnSummary = New-UGSMLabel -Text '' -X 12 -Y 58 -Width 330 -Height 34 -FontSize 8.5 -Color '#333333'
        [void]$spawnDetailsPanel.Controls.Add($lblSpawnSummary)

        $lblSpawnPreview = New-UGSMLabel -Text 'Selected <type> XML' -X 12 -Y 100 -Width 180 -Height 18 -FontSize 8.5 -Style Bold -Color '#111111'
        [void]$spawnDetailsPanel.Controls.Add($lblSpawnPreview)

        $txtSpawnPreview = New-Object System.Windows.Forms.TextBox
        $txtSpawnPreview.Location = New-Object System.Drawing.Point(12, 124)
        $txtSpawnPreview.Anchor = 'Top,Bottom,Left,Right'
        $txtSpawnPreview.Multiline = $true
        $txtSpawnPreview.ScrollBars = 'Both'
        $txtSpawnPreview.WordWrap = $false
        $txtSpawnPreview.AcceptsReturn = $true
        $txtSpawnPreview.AcceptsTab = $true
        $txtSpawnPreview.Font = New-Object System.Drawing.Font('Consolas', 9)
        $txtSpawnPreview.BackColor = [System.Drawing.Color]::White
        $txtSpawnPreview.ForeColor = [System.Drawing.Color]::Black
        $txtSpawnPreview.BorderStyle = 'FixedSingle'
        [void]$spawnDetailsPanel.Controls.Add($txtSpawnPreview)

        $btnApplySpawnPreview = New-UGSMButton -Text 'Apply Selected Node' -X 12 -Y 0 -Width 150 -Height 28 -BackColor '#F4A300'
        [void]$spawnDetailsPanel.Controls.Add($btnApplySpawnPreview)

        $lblEventNominal = New-UGSMLabel -Text 'Nominal' -X 12 -Y 72 -Width 90 -Height 18 -FontSize 9 -Color '#111111'
        [void]$eventDetailsPanel.Controls.Add($lblEventNominal)
        $txtEventNominal = New-Object System.Windows.Forms.TextBox
        $txtEventNominal.Location = New-Object System.Drawing.Point(110, 70)
        $txtEventNominal.Size = New-Object System.Drawing.Size(90, 22)
        [void]$eventDetailsPanel.Controls.Add($txtEventNominal)

        $lblEventMin = New-UGSMLabel -Text 'Min' -X 12 -Y 102 -Width 90 -Height 18 -FontSize 9 -Color '#111111'
        [void]$eventDetailsPanel.Controls.Add($lblEventMin)
        $txtEventMin = New-Object System.Windows.Forms.TextBox
        $txtEventMin.Location = New-Object System.Drawing.Point(110, 100)
        $txtEventMin.Size = New-Object System.Drawing.Size(90, 22)
        [void]$eventDetailsPanel.Controls.Add($txtEventMin)

        $lblEventMax = New-UGSMLabel -Text 'Max' -X 12 -Y 132 -Width 90 -Height 18 -FontSize 9 -Color '#111111'
        [void]$eventDetailsPanel.Controls.Add($lblEventMax)
        $txtEventMax = New-Object System.Windows.Forms.TextBox
        $txtEventMax.Location = New-Object System.Drawing.Point(110, 130)
        $txtEventMax.Size = New-Object System.Drawing.Size(90, 22)
        [void]$eventDetailsPanel.Controls.Add($txtEventMax)

        $lblEventLifetime = New-UGSMLabel -Text 'Lifetime' -X 12 -Y 162 -Width 90 -Height 18 -FontSize 9 -Color '#111111'
        [void]$eventDetailsPanel.Controls.Add($lblEventLifetime)
        $txtEventLifetime = New-Object System.Windows.Forms.TextBox
        $txtEventLifetime.Location = New-Object System.Drawing.Point(110, 160)
        $txtEventLifetime.Size = New-Object System.Drawing.Size(90, 22)
        [void]$eventDetailsPanel.Controls.Add($txtEventLifetime)

        $lblEventRestock = New-UGSMLabel -Text 'Restock' -X 12 -Y 192 -Width 90 -Height 18 -FontSize 9 -Color '#111111'
        [void]$eventDetailsPanel.Controls.Add($lblEventRestock)
        $txtEventRestock = New-Object System.Windows.Forms.TextBox
        $txtEventRestock.Location = New-Object System.Drawing.Point(110, 190)
        $txtEventRestock.Size = New-Object System.Drawing.Size(90, 22)
        [void]$eventDetailsPanel.Controls.Add($txtEventRestock)

        $chkEventActive = New-Object System.Windows.Forms.CheckBox
        $chkEventActive.Text = 'Active'
        $chkEventActive.Location = New-Object System.Drawing.Point(12, 224)
        $chkEventActive.Size = New-Object System.Drawing.Size(100, 22)
        $chkEventActive.ForeColor = [System.Drawing.Color]::Black
        [void]$eventDetailsPanel.Controls.Add($chkEventActive)

        $usageCheckboxes = @{}
        $valueCheckboxes = @{}
        $flagCheckboxes = @{}

        $usageLayout = @(
            @{ Name = 'Town'; X = 12; Y = 24; W = 132 }
            @{ Name = 'Village'; X = 166; Y = 24; W = 132 }
            @{ Name = 'School'; X = 12; Y = 46; W = 132 }
            @{ Name = 'Industrial'; X = 166; Y = 46; W = 132 }
            @{ Name = 'Farm'; X = 12; Y = 68; W = 132 }
            @{ Name = 'Firefighter'; X = 166; Y = 68; W = 132 }
            @{ Name = 'Medic'; X = 12; Y = 90; W = 132 }
            @{ Name = 'Coast'; X = 166; Y = 90; W = 132 }
            @{ Name = 'Office'; X = 12; Y = 112; W = 132 }
            @{ Name = 'Police'; X = 166; Y = 112; W = 132 }
            @{ Name = 'Hunting'; X = 12; Y = 134; W = 132 }
            @{ Name = 'Military'; X = 166; Y = 134; W = 132 }
            @{ Name = 'Prison'; X = 12; Y = 156; W = 132 }
            @{ Name = 'Lunapark'; X = 166; Y = 156; W = 132 }
            @{ Name = 'SeasonalEvent'; X = 12; Y = 178; W = 132 }
            @{ Name = 'ContaminatedArea'; X = 166; Y = 178; W = 132 }
            @{ Name = 'Historical'; X = 12; Y = 200; W = 132 }
        )

        foreach ($entry in $usageLayout) {
            if (-not ($usageOptions -contains $entry.Name)) { continue }

            $chk = New-Object System.Windows.Forms.CheckBox
            $chk.Text = $entry.Name
            $chk.AutoSize = $false
            $chk.Width = $entry.W
            $chk.Height = 20
            $chk.Location = New-Object System.Drawing.Point($entry.X, $entry.Y)
            $chk.ForeColor = [System.Drawing.Color]::Black
            [void]$grpUsage.Controls.Add($chk)
            $usageCheckboxes[$entry.Name] = $chk
        }

        $valueLayout = @(
            @{ Name = 'Tier1'; X = 12; Y = 26; W = 52 }
            @{ Name = 'Tier2'; X = 76; Y = 26; W = 52 }
            @{ Name = 'Tier3'; X = 140; Y = 26; W = 52 }
            @{ Name = 'Tier4'; X = 204; Y = 26; W = 52 }
            @{ Name = 'Unique'; X = 268; Y = 26; W = 62 }
        )

        foreach ($entry in $valueLayout) {
            if (-not ($valueOptions -contains $entry.Name)) { continue }

            $chk = New-Object System.Windows.Forms.CheckBox
            $chk.Text = $entry.Name
            $chk.AutoSize = $false
            $chk.Width = $entry.W
            $chk.Height = 20
            $chk.Location = New-Object System.Drawing.Point($entry.X, $entry.Y)
            $chk.ForeColor = [System.Drawing.Color]::Black
            [void]$grpValue.Controls.Add($chk)
            $valueCheckboxes[$entry.Name] = $chk
        }

        $grpFlags = New-Object System.Windows.Forms.GroupBox
        $grpFlags.Text = 'Flags'
        $grpFlags.ForeColor = [System.Drawing.Color]::FromArgb(70, 70, 70)
        $grpFlags.Location = New-Object System.Drawing.Point(12, 382)
        $grpFlags.Size = New-Object System.Drawing.Size(340, 54)
        [void]$detailsPanel.Controls.Add($grpFlags)

        $chkDeloot = New-Object System.Windows.Forms.CheckBox
        $chkDeloot.Text = 'Dynamic Event Loot (deloot)'
        $chkDeloot.AutoSize = $false
        $chkDeloot.Width = 220
        $chkDeloot.Height = 20
        $chkDeloot.Location = New-Object System.Drawing.Point(12, 22)
        $chkDeloot.ForeColor = [System.Drawing.Color]::Black
        [void]$grpFlags.Controls.Add($chkDeloot)
        $flagCheckboxes['Deloot'] = $chkDeloot

        $gridTypes = New-Object System.Windows.Forms.DataGridView
        $gridTypes.Location = New-Object System.Drawing.Point(0, 210)
        $gridTypes.Anchor = 'Top,Bottom,Left,Right'
        $gridTypes.BackgroundColor = [System.Drawing.Color]::White
        $gridTypes.BorderStyle = 'FixedSingle'
        $gridTypes.RowHeadersVisible = $false
        $gridTypes.AllowUserToAddRows = $false
        $gridTypes.AllowUserToDeleteRows = $false
        $gridTypes.SelectionMode = 'FullRowSelect'
        $gridTypes.MultiSelect = $true
        $gridTypes.AutoSizeRowsMode = 'None'
        $gridTypes.ColumnHeadersHeightSizeMode = 'DisableResizing'
        $gridTypes.ColumnHeadersHeight = 24
        $gridTypes.EnableHeadersVisualStyles = $false
        $gridTypes.ColumnHeadersDefaultCellStyle.BackColor = [System.Drawing.Color]::FromArgb(10, 40, 120)
        $gridTypes.ColumnHeadersDefaultCellStyle.ForeColor = [System.Drawing.Color]::White
        $gridTypes.DefaultCellStyle.BackColor = [System.Drawing.Color]::White
        $gridTypes.DefaultCellStyle.ForeColor = [System.Drawing.Color]::Black
        $gridTypes.DefaultCellStyle.SelectionBackColor = [System.Drawing.Color]::FromArgb(0, 120, 215)
        $gridTypes.DefaultCellStyle.SelectionForeColor = [System.Drawing.Color]::White
        [void]$rootPanel.Controls.Add($gridTypes)

        $null = $gridTypes.Columns.Add('Name', 'Item Name')
        $null = $gridTypes.Columns.Add('Nominal', 'Nominal')
        $null = $gridTypes.Columns.Add('Lifetime', 'Lifetime')
        $null = $gridTypes.Columns.Add('Restock', 'Restock')
        $null = $gridTypes.Columns.Add('Min', 'Min')
        $null = $gridTypes.Columns.Add('Max', 'Max')
        $null = $gridTypes.Columns.Add('QuantMin', 'QuantMin')
        $null = $gridTypes.Columns.Add('QuantMax', 'QuantMax')
        $null = $gridTypes.Columns.Add('Cost', 'Cost')
        $null = $gridTypes.Columns.Add('Category', 'Category')
        $null = $gridTypes.Columns.Add('Usage', 'Usage')
        $null = $gridTypes.Columns.Add('Value', 'Value')
        $null = $gridTypes.Columns.Add('Deloot', 'Deloot')
        $null = $gridTypes.Columns.Add('CountInCargo', 'count_in_cargo')
        $null = $gridTypes.Columns.Add('CountInHoarder', 'count_in_hoarder')
        $null = $gridTypes.Columns.Add('CountInMap', 'count_in_map')
        $null = $gridTypes.Columns.Add('CountInPlayer', 'count_in_player')
        $null = $gridTypes.Columns.Add('Crafted', 'crafted')

        $gridTypes.Columns['Name'].Width = 240
        $gridTypes.Columns['Nominal'].Width = 90
        $gridTypes.Columns['Lifetime'].Width = 95
        $gridTypes.Columns['Restock'].Width = 90
        $gridTypes.Columns['Min'].Width = 70
        $gridTypes.Columns['Max'].Width = 70
        $gridTypes.Columns['QuantMin'].Width = 85
        $gridTypes.Columns['QuantMax'].Width = 85
        $gridTypes.Columns['Cost'].Width = 70
        $gridTypes.Columns['Category'].Width = 110
        $gridTypes.Columns['Usage'].Width = 180
        $gridTypes.Columns['Value'].Width = 140
        $gridTypes.Columns['Deloot'].Width = 70

        foreach ($hiddenFlagColumn in @('CountInCargo', 'CountInHoarder', 'CountInMap', 'CountInPlayer', 'Crafted')) {
            $gridTypes.Columns[$hiddenFlagColumn].Visible = $false
        }


        $gridTypes.BackgroundColor = New-UGSMColor '#0B121D'

        $gridTypes.EnableHeadersVisualStyles = $false
        $gridTypes.GridColor = New-UGSMColor '#BFC8D4'

        $gridTypes.ColumnHeadersDefaultCellStyle.BackColor = New-UGSMColor '#243447'
        $gridTypes.ColumnHeadersDefaultCellStyle.ForeColor = [System.Drawing.Color]::White

        $gridTypes.DefaultCellStyle.BackColor = New-UGSMColor '#F2F5F9'
        $gridTypes.DefaultCellStyle.ForeColor = [System.Drawing.Color]::Black
        $gridTypes.DefaultCellStyle.SelectionBackColor = New-UGSMColor '#4A6EA9'
        $gridTypes.DefaultCellStyle.SelectionForeColor = [System.Drawing.Color]::White

        $gridTypes.RowsDefaultCellStyle.BackColor = New-UGSMColor '#F2F5F9'
        $gridTypes.RowsDefaultCellStyle.ForeColor = [System.Drawing.Color]::Black

        $gridTypes.AlternatingRowsDefaultCellStyle.BackColor = New-UGSMColor '#E8EDF4'
        $gridTypes.AlternatingRowsDefaultCellStyle.ForeColor = [System.Drawing.Color]::Black

        $gridEvents = New-Object System.Windows.Forms.DataGridView
        $gridEvents.Location = New-Object System.Drawing.Point(0, 210)
        $gridEvents.Anchor = 'Top,Bottom,Left,Right'
        $gridEvents.BackgroundColor = [System.Drawing.Color]::White
        $gridEvents.BorderStyle = 'FixedSingle'
        $gridEvents.RowHeadersVisible = $false
        $gridEvents.AllowUserToAddRows = $false
        $gridEvents.AllowUserToDeleteRows = $false
        $gridEvents.SelectionMode = 'FullRowSelect'
        $gridEvents.MultiSelect = $false
        $gridEvents.AutoSizeRowsMode = 'None'
        $gridEvents.ColumnHeadersHeightSizeMode = 'DisableResizing'
        $gridEvents.ColumnHeadersHeight = 24
        $gridEvents.EnableHeadersVisualStyles = $false
        $gridEvents.ColumnHeadersDefaultCellStyle.BackColor = [System.Drawing.Color]::FromArgb(10, 40, 120)
        $gridEvents.ColumnHeadersDefaultCellStyle.ForeColor = [System.Drawing.Color]::White
        $gridEvents.DefaultCellStyle.BackColor = [System.Drawing.Color]::White
        $gridEvents.DefaultCellStyle.ForeColor = [System.Drawing.Color]::Black
        $gridEvents.DefaultCellStyle.SelectionBackColor = [System.Drawing.Color]::FromArgb(0, 120, 215)
        $gridEvents.DefaultCellStyle.SelectionForeColor = [System.Drawing.Color]::White
        $gridEvents.Visible = $false
        [void]$rootPanel.Controls.Add($gridEvents)

        $null = $gridEvents.Columns.Add('Name', 'Event Name')
        $null = $gridEvents.Columns.Add('Nominal', 'Nominal')
        $null = $gridEvents.Columns.Add('Min', 'Min')
        $null = $gridEvents.Columns.Add('Max', 'Max')
        $null = $gridEvents.Columns.Add('Lifetime', 'Lifetime')
        $null = $gridEvents.Columns.Add('Restock', 'Restock')
        $null = $gridEvents.Columns.Add('Active', 'Active')

        $gridEvents.Columns['Name'].Width = 250
        $gridEvents.Columns['Nominal'].Width = 90
        $gridEvents.Columns['Min'].Width = 70
        $gridEvents.Columns['Max'].Width = 70
        $gridEvents.Columns['Lifetime'].Width = 95
        $gridEvents.Columns['Restock'].Width = 90
        $gridEvents.Columns['Active'].Width = 70


        $gridEvents.BackgroundColor = New-UGSMColor '#0B121D'

        $gridEvents.EnableHeadersVisualStyles = $false
        $gridEvents.GridColor = New-UGSMColor '#BFC8D4'

        $gridEvents.ColumnHeadersDefaultCellStyle.BackColor = New-UGSMColor '#243447'
        $gridEvents.ColumnHeadersDefaultCellStyle.ForeColor = [System.Drawing.Color]::White

        $gridEvents.DefaultCellStyle.BackColor = New-UGSMColor '#F2F5F9'
        $gridEvents.DefaultCellStyle.ForeColor = [System.Drawing.Color]::Black
        $gridEvents.DefaultCellStyle.SelectionBackColor = New-UGSMColor '#4A6EA9'
        $gridEvents.DefaultCellStyle.SelectionForeColor = [System.Drawing.Color]::White

        $gridEvents.RowsDefaultCellStyle.BackColor = New-UGSMColor '#F2F5F9'
        $gridEvents.RowsDefaultCellStyle.ForeColor = [System.Drawing.Color]::Black

        $gridEvents.AlternatingRowsDefaultCellStyle.BackColor = New-UGSMColor '#E8EDF4'
        $gridEvents.AlternatingRowsDefaultCellStyle.ForeColor = [System.Drawing.Color]::Black


        $gridEventSpawns = New-Object System.Windows.Forms.DataGridView
        $gridEventSpawns.Location = New-Object System.Drawing.Point(0, 210)
        $gridEventSpawns.Anchor = 'Top,Bottom,Left,Right'
        $gridEventSpawns.BackgroundColor = [System.Drawing.Color]::White
        $gridEventSpawns.BorderStyle = 'FixedSingle'
        $gridEventSpawns.RowHeadersVisible = $false
        $gridEventSpawns.AllowUserToAddRows = $true
        $gridEventSpawns.AllowUserToDeleteRows = $true
        $gridEventSpawns.SelectionMode = 'FullRowSelect'
        $gridEventSpawns.MultiSelect = $true
        $gridEventSpawns.AutoSizeRowsMode = 'None'
        $gridEventSpawns.ColumnHeadersHeightSizeMode = 'DisableResizing'
        $gridEventSpawns.ColumnHeadersHeight = 24
        $gridEventSpawns.EnableHeadersVisualStyles = $false
        $gridEventSpawns.GridColor = New-UGSMColor '#BFC8D4'
        $gridEventSpawns.ColumnHeadersDefaultCellStyle.BackColor = New-UGSMColor '#243447'
        $gridEventSpawns.ColumnHeadersDefaultCellStyle.ForeColor = [System.Drawing.Color]::White
        $gridEventSpawns.DefaultCellStyle.BackColor = New-UGSMColor '#F2F5F9'
        $gridEventSpawns.DefaultCellStyle.ForeColor = [System.Drawing.Color]::Black
        $gridEventSpawns.DefaultCellStyle.SelectionBackColor = New-UGSMColor '#4A6EA9'
        $gridEventSpawns.DefaultCellStyle.SelectionForeColor = [System.Drawing.Color]::White
        $gridEventSpawns.RowsDefaultCellStyle.BackColor = New-UGSMColor '#F2F5F9'
        $gridEventSpawns.RowsDefaultCellStyle.ForeColor = [System.Drawing.Color]::Black
        $gridEventSpawns.AlternatingRowsDefaultCellStyle.BackColor = New-UGSMColor '#E8EDF4'
        $gridEventSpawns.AlternatingRowsDefaultCellStyle.ForeColor = [System.Drawing.Color]::Black
        $gridEventSpawns.Visible = $false
        [void]$rootPanel.Controls.Add($gridEventSpawns)

        foreach ($col in @(
            @{ N='EventIndex'; H='Event #'; W=70 },
            @{ N='PosIndex'; H='Node #'; W=70 },
            @{ N='NodeType'; H='Type'; W=70 },
            @{ N='EventName'; H='Event Name'; W=260 },
            @{ N='X'; H='X'; W=105 },
            @{ N='Y'; H='Y'; W=105 },
            @{ N='Z'; H='Z'; W=105 },
            @{ N='A'; H='Angle'; W=90 },
            @{ N='SMin'; H='smin'; W=70 },
            @{ N='SMax'; H='smax'; W=70 },
            @{ N='DMin'; H='dmin'; W=70 },
            @{ N='DMax'; H='dmax'; W=70 },
            @{ N='R'; H='Radius'; W=80 }
        )) {
            [void]$gridEventSpawns.Columns.Add($col.N, $col.H)
            $gridEventSpawns.Columns[$col.N].Width = $col.W
        }

        $gridSpawnableTypes = New-Object System.Windows.Forms.DataGridView
        $gridSpawnableTypes.Location = New-Object System.Drawing.Point(0, 210)
        $gridSpawnableTypes.Anchor = 'Top,Bottom,Left,Right'
        $gridSpawnableTypes.BackgroundColor = [System.Drawing.Color]::White
        $gridSpawnableTypes.BorderStyle = 'FixedSingle'
        $gridSpawnableTypes.RowHeadersVisible = $false
        $gridSpawnableTypes.AllowUserToAddRows = $false
        $gridSpawnableTypes.AllowUserToDeleteRows = $false
        $gridSpawnableTypes.SelectionMode = 'FullRowSelect'
        $gridSpawnableTypes.MultiSelect = $false
        $gridSpawnableTypes.AutoSizeRowsMode = 'None'
        $gridSpawnableTypes.ColumnHeadersHeightSizeMode = 'DisableResizing'
        $gridSpawnableTypes.ColumnHeadersHeight = 24
        $gridSpawnableTypes.EnableHeadersVisualStyles = $false
        $gridSpawnableTypes.ColumnHeadersDefaultCellStyle.BackColor = [System.Drawing.Color]::FromArgb(10, 40, 120)
        $gridSpawnableTypes.ColumnHeadersDefaultCellStyle.ForeColor = [System.Drawing.Color]::White
        $gridSpawnableTypes.DefaultCellStyle.BackColor = [System.Drawing.Color]::White
        $gridSpawnableTypes.DefaultCellStyle.ForeColor = [System.Drawing.Color]::Black
        $gridSpawnableTypes.DefaultCellStyle.SelectionBackColor = [System.Drawing.Color]::FromArgb(0, 120, 215)
        $gridSpawnableTypes.DefaultCellStyle.SelectionForeColor = [System.Drawing.Color]::White
        $gridSpawnableTypes.Visible = $false
        [void]$rootPanel.Controls.Add($gridSpawnableTypes)

        $null = $gridSpawnableTypes.Columns.Add('Name', 'Type Name')
        $null = $gridSpawnableTypes.Columns.Add('AttachmentsCount', 'Attachments')
        $null = $gridSpawnableTypes.Columns.Add('CargoCount', 'Cargo')
        $null = $gridSpawnableTypes.Columns.Add('HasAttachments', 'Has Attachments')
        $null = $gridSpawnableTypes.Columns.Add('HasCargo', 'Has Cargo')
        $null = $gridSpawnableTypes.Columns.Add('DamageMin', 'Damage Min')
        $null = $gridSpawnableTypes.Columns.Add('DamageMax', 'Damage Max')

        $gridSpawnableTypes.Columns['Name'].Width = 250
        $gridSpawnableTypes.Columns['AttachmentsCount'].Width = 90
        $gridSpawnableTypes.Columns['CargoCount'].Width = 70
        $gridSpawnableTypes.Columns['HasAttachments'].Width = 105
        $gridSpawnableTypes.Columns['HasCargo'].Width = 85
        $gridSpawnableTypes.Columns['DamageMin'].Width = 85
        $gridSpawnableTypes.Columns['DamageMax'].Width = 85


        $gridSpawnableTypes.BackgroundColor = New-UGSMColor '#0B121D'

        $gridSpawnableTypes.EnableHeadersVisualStyles = $false
        $gridSpawnableTypes.GridColor = New-UGSMColor '#BFC8D4'

        $gridSpawnableTypes.ColumnHeadersDefaultCellStyle.BackColor = New-UGSMColor '#243447'
        $gridSpawnableTypes.ColumnHeadersDefaultCellStyle.ForeColor = [System.Drawing.Color]::White

        $gridSpawnableTypes.DefaultCellStyle.BackColor = New-UGSMColor '#F2F5F9'
        $gridSpawnableTypes.DefaultCellStyle.ForeColor = [System.Drawing.Color]::Black
        $gridSpawnableTypes.DefaultCellStyle.SelectionBackColor = New-UGSMColor '#4A6EA9'
        $gridSpawnableTypes.DefaultCellStyle.SelectionForeColor = [System.Drawing.Color]::White

        $gridSpawnableTypes.RowsDefaultCellStyle.BackColor = New-UGSMColor '#F2F5F9'
        $gridSpawnableTypes.RowsDefaultCellStyle.ForeColor = [System.Drawing.Color]::Black

        $gridSpawnableTypes.AlternatingRowsDefaultCellStyle.BackColor = New-UGSMColor '#E8EDF4'
        $gridSpawnableTypes.AlternatingRowsDefaultCellStyle.ForeColor = [System.Drawing.Color]::Black

        $txtXml = New-Object System.Windows.Forms.TextBox
        $txtXml.Location = New-Object System.Drawing.Point(0, 210)
        $txtXml.Anchor = 'Top,Bottom,Left,Right'
        $txtXml.Multiline = $true
        $txtXml.ScrollBars = 'Both'
        $txtXml.WordWrap = $false
        $txtXml.AcceptsReturn = $true
        $txtXml.AcceptsTab = $true
        $txtXml.Font = New-Object System.Drawing.Font('Consolas', 9)
        $txtXml.BackColor = [System.Drawing.Color]::White
        $txtXml.ForeColor = [System.Drawing.Color]::Black
        $txtXml.BorderStyle = 'FixedSingle'
        [void]$rootPanel.Controls.Add($txtXml)

        $gridVariables = New-Object System.Windows.Forms.DataGridView
        $gridVariables.Location = New-Object System.Drawing.Point(0, 210)
        $gridVariables.Anchor = 'Top,Bottom,Left,Right'
        $gridVariables.BackgroundColor = [System.Drawing.Color]::White
        $gridVariables.BorderStyle = 'FixedSingle'
        $gridVariables.RowHeadersVisible = $false
        $gridVariables.AllowUserToAddRows = $false
        $gridVariables.AllowUserToDeleteRows = $false
        $gridVariables.SelectionMode = 'FullRowSelect'
        $gridVariables.MultiSelect = $false
        $gridVariables.AutoSizeRowsMode = 'None'
        $gridVariables.ColumnHeadersHeightSizeMode = 'DisableResizing'
        $gridVariables.ColumnHeadersHeight = 24
        $gridVariables.EnableHeadersVisualStyles = $false
        $gridVariables.ColumnHeadersDefaultCellStyle.BackColor = [System.Drawing.Color]::FromArgb(10, 40, 120)
        $gridVariables.ColumnHeadersDefaultCellStyle.ForeColor = [System.Drawing.Color]::White
        $gridVariables.DefaultCellStyle.BackColor = [System.Drawing.Color]::White
        $gridVariables.DefaultCellStyle.ForeColor = [System.Drawing.Color]::Black
        $gridVariables.DefaultCellStyle.SelectionBackColor = [System.Drawing.Color]::FromArgb(0, 120, 215)
        $gridVariables.DefaultCellStyle.SelectionForeColor = [System.Drawing.Color]::White
        $gridVariables.Visible = $false
        [void]$rootPanel.Controls.Add($gridVariables)

        $null = $gridVariables.Columns.Add('Group', 'Section')
        $null = $gridVariables.Columns.Add('Key', 'Setting')
        $null = $gridVariables.Columns.Add('Value', 'Value')
        $null = $gridVariables.Columns.Add('SourcePath', 'Source Path')
        $null = $gridVariables.Columns.Add('EntryType', 'Entry Type')
        $null = $gridVariables.Columns.Add('AttributeName', 'Attribute Name')

        $gridVariables.Columns['Group'].Width = 180
        $gridVariables.Columns['Key'].Width = 260
        $gridVariables.Columns['Value'].Width = 220
        $gridVariables.Columns['SourcePath'].Visible = $false
        $gridVariables.Columns['EntryType'].Visible = $false
        $gridVariables.Columns['AttributeName'].Visible = $false
        $gridVariables.Columns['Value'].AutoSizeMode = 'Fill'
        $gridVariables.EditMode = 'EditOnKeystrokeOrF2'

        $gridEconomy = New-Object System.Windows.Forms.DataGridView
        $gridEconomy.Location = New-Object System.Drawing.Point(0, 210)
        $gridEconomy.Anchor = 'Top,Bottom,Left,Right'
        $gridEconomy.AllowUserToAddRows = $false
        $gridEconomy.AllowUserToDeleteRows = $false
        $gridEconomy.AllowUserToResizeRows = $false
        $gridEconomy.RowHeadersVisible = $false
        $gridEconomy.SelectionMode = 'FullRowSelect'
        $gridEconomy.MultiSelect = $false
        $gridEconomy.AutoGenerateColumns = $false
        $gridEconomy.BackgroundColor = [System.Drawing.Color]::White
        $gridEconomy.Visible = $false

        [void]$gridEconomy.Columns.Add('Section', 'Section')

        $colInit = New-Object System.Windows.Forms.DataGridViewCheckBoxColumn
        $colInit.Name = 'Init'
        $colInit.HeaderText = 'Init'
        $colInit.Width = 60
        [void]$gridEconomy.Columns.Add($colInit)

        $colLoad = New-Object System.Windows.Forms.DataGridViewCheckBoxColumn
        $colLoad.Name = 'Load'
        $colLoad.HeaderText = 'Load'
        $colLoad.Width = 60
        [void]$gridEconomy.Columns.Add($colLoad)

        $colRespawn = New-Object System.Windows.Forms.DataGridViewCheckBoxColumn
        $colRespawn.Name = 'Respawn'
        $colRespawn.HeaderText = 'Respawn'
        $colRespawn.Width = 80
        [void]$gridEconomy.Columns.Add($colRespawn)

        $colSave = New-Object System.Windows.Forms.DataGridViewCheckBoxColumn
        $colSave.Name = 'Save'
        $colSave.HeaderText = 'Save'
        $colSave.Width = 60
        [void]$gridEconomy.Columns.Add($colSave)

        $gridEconomy.Columns['Section'].Width = 220
        $gridEconomy.Columns['Section'].ReadOnly = $true

        [void]$rootPanel.Controls.Add($gridEconomy)

        $gridEconomy.BackgroundColor = New-UGSMColor '#0B121D'

        $gridEconomy.EnableHeadersVisualStyles = $false
        $gridEconomy.GridColor = New-UGSMColor '#BFC8D4'

        $gridEconomy.ColumnHeadersDefaultCellStyle.BackColor = New-UGSMColor '#243447'
        $gridEconomy.ColumnHeadersDefaultCellStyle.ForeColor = [System.Drawing.Color]::White

        $gridEconomy.DefaultCellStyle.BackColor = New-UGSMColor '#F2F5F9'
        $gridEconomy.DefaultCellStyle.ForeColor = [System.Drawing.Color]::Black
        $gridEconomy.DefaultCellStyle.SelectionBackColor = New-UGSMColor '#4A6EA9'
        $gridEconomy.DefaultCellStyle.SelectionForeColor = [System.Drawing.Color]::White

        $gridEconomy.RowsDefaultCellStyle.BackColor = New-UGSMColor '#F2F5F9'
        $gridEconomy.RowsDefaultCellStyle.ForeColor = [System.Drawing.Color]::Black

        $gridEconomy.AlternatingRowsDefaultCellStyle.BackColor = New-UGSMColor '#E8EDF4'
        $gridEconomy.AlternatingRowsDefaultCellStyle.ForeColor = [System.Drawing.Color]::Black

        $cfgGameplayPanel = New-Object System.Windows.Forms.Panel
        $cfgGameplayPanel.Location = New-Object System.Drawing.Point(15, 170)
        $cfgGameplayPanel.Size = New-Object System.Drawing.Size(1120, 540)
        $cfgGameplayPanel.AutoScroll = $true
        $cfgGameplayPanel.Visible = $false
        $cfgGameplayPanel.BackColor = New-UGSMColor '#DCE3EC'
        [void]$rootPanel.Controls.Add($cfgGameplayPanel)

        $cfgGameplayInnerPanel = New-Object System.Windows.Forms.Panel
        $cfgGameplayInnerPanel.Location = New-Object System.Drawing.Point(0, 0)
        $cfgGameplayInnerPanel.Size = New-Object System.Drawing.Size(1080, 520)
        $cfgGameplayInnerPanel.BackColor = New-UGSMColor '#DCE3EC'
        [void]$cfgGameplayPanel.Controls.Add($cfgGameplayInnerPanel)





        $applyReadableDataGridStyle = {
            param([System.Windows.Forms.DataGridView]$Grid)

            if ($null -eq $Grid) { return }

            $Grid.EnableHeadersVisualStyles = $false
            $Grid.ColumnHeadersDefaultCellStyle.BackColor = [System.Drawing.Color]::FromArgb(31, 45, 61)
            $Grid.ColumnHeadersDefaultCellStyle.ForeColor = [System.Drawing.Color]::White
            $Grid.ColumnHeadersDefaultCellStyle.SelectionBackColor = [System.Drawing.Color]::FromArgb(31, 45, 61)
            $Grid.ColumnHeadersDefaultCellStyle.SelectionForeColor = [System.Drawing.Color]::White

            $Grid.DefaultCellStyle.BackColor = [System.Drawing.Color]::White
            $Grid.DefaultCellStyle.ForeColor = [System.Drawing.Color]::Black
            $Grid.DefaultCellStyle.SelectionBackColor = [System.Drawing.Color]::FromArgb(30, 136, 229)
            $Grid.DefaultCellStyle.SelectionForeColor = [System.Drawing.Color]::White

            $Grid.AlternatingRowsDefaultCellStyle.BackColor = [System.Drawing.Color]::FromArgb(235, 240, 247)
            $Grid.AlternatingRowsDefaultCellStyle.ForeColor = [System.Drawing.Color]::Black
            $Grid.AlternatingRowsDefaultCellStyle.SelectionBackColor = [System.Drawing.Color]::FromArgb(30, 136, 229)
            $Grid.AlternatingRowsDefaultCellStyle.SelectionForeColor = [System.Drawing.Color]::White

            $Grid.RowsDefaultCellStyle.BackColor = [System.Drawing.Color]::White
            $Grid.RowsDefaultCellStyle.ForeColor = [System.Drawing.Color]::Black
            $Grid.RowsDefaultCellStyle.SelectionBackColor = [System.Drawing.Color]::FromArgb(30, 136, 229)
            $Grid.RowsDefaultCellStyle.SelectionForeColor = [System.Drawing.Color]::White
        }.GetNewClosure()

        $cfgEnvironmentState = [pscustomobject]@{
            IsLoading      = $false
            FileRows       = @()
            TerritoryRows  = @()
            TerritoryFiles = @()
            ActiveFile     = ''
            ZoneRows       = @()
        }

        $cfgEnvironmentPanel = New-Object System.Windows.Forms.Panel
        $cfgEnvironmentPanel.Location = New-Object System.Drawing.Point(0, 210)
        $cfgEnvironmentPanel.Anchor = 'Top,Bottom,Left,Right'
        $cfgEnvironmentPanel.BackColor = New-UGSMColor '#0B121D'
        $cfgEnvironmentPanel.Visible = $false
        [void]$rootPanel.Controls.Add($cfgEnvironmentPanel)

        $lblEnvFiles = New-UGSMLabel -Text 'cfgenvironment.xml Territory File References' -X 0 -Y 0 -Width 360 -Height 18 -FontSize 9 -Style Bold -Color $Theme.Text
        [void]$cfgEnvironmentPanel.Controls.Add($lblEnvFiles)

        $gridEnvFiles = New-Object System.Windows.Forms.DataGridView
        $gridEnvFiles.Location = New-Object System.Drawing.Point(0, 24)
        $gridEnvFiles.Size = New-Object System.Drawing.Size(520, 180)
        $gridEnvFiles.Anchor = 'Top,Left'
        $gridEnvFiles.BackgroundColor = [System.Drawing.Color]::White
        $gridEnvFiles.BorderStyle = 'FixedSingle'
        $gridEnvFiles.RowHeadersVisible = $false
        $gridEnvFiles.AllowUserToAddRows = $true
        $gridEnvFiles.AllowUserToDeleteRows = $true
        $gridEnvFiles.SelectionMode = 'FullRowSelect'
        $gridEnvFiles.MultiSelect = $true
        $gridEnvFiles.AutoSizeRowsMode = 'None'
        $gridEnvFiles.ColumnHeadersHeightSizeMode = 'DisableResizing'
        $gridEnvFiles.ColumnHeadersHeight = 24
        [void]$cfgEnvironmentPanel.Controls.Add($gridEnvFiles)
        [void]$gridEnvFiles.Columns.Add('Index', '#')
        [void]$gridEnvFiles.Columns.Add('Path', 'Path')
        $gridEnvFiles.Columns['Index'].Width = 50
        $gridEnvFiles.Columns['Path'].Width = 430
        & $applyReadableDataGridStyle $gridEnvFiles

        $lblEnvTerritories = New-UGSMLabel -Text 'cfgenvironment.xml Territory Definitions' -X 540 -Y 0 -Width 360 -Height 18 -FontSize 9 -Style Bold -Color $Theme.Text
        [void]$cfgEnvironmentPanel.Controls.Add($lblEnvTerritories)

        $gridEnvTerritories = New-Object System.Windows.Forms.DataGridView
        $gridEnvTerritories.Location = New-Object System.Drawing.Point(540, 24)
        $gridEnvTerritories.Size = New-Object System.Drawing.Size(720, 180)
        $gridEnvTerritories.Anchor = 'Top,Left,Right'
        $gridEnvTerritories.BackgroundColor = [System.Drawing.Color]::White
        $gridEnvTerritories.BorderStyle = 'FixedSingle'
        $gridEnvTerritories.RowHeadersVisible = $false
        $gridEnvTerritories.AllowUserToAddRows = $true
        $gridEnvTerritories.AllowUserToDeleteRows = $true
        $gridEnvTerritories.SelectionMode = 'FullRowSelect'
        $gridEnvTerritories.MultiSelect = $true
        $gridEnvTerritories.AutoSizeRowsMode = 'None'
        $gridEnvTerritories.ColumnHeadersHeightSizeMode = 'DisableResizing'
        $gridEnvTerritories.ColumnHeadersHeight = 24
        [void]$cfgEnvironmentPanel.Controls.Add($gridEnvTerritories)
        foreach ($col in @(
            @{ N='Index'; H='#'; W=45 },
            @{ N='Name'; H='Name'; W=130 },
            @{ N='Type'; H='Type'; W=80 },
            @{ N='Behavior'; H='Behavior'; W=170 },
            @{ N='FileUsable'; H='File Usable'; W=170 },
            @{ N='Agents'; H='Agents'; W=60 },
            @{ N='Spawns'; H='Spawns'; W=60 },
            @{ N='Items'; H='Items'; W=60 }
        )) {
            [void]$gridEnvTerritories.Columns.Add($col.N, $col.H)
            $gridEnvTerritories.Columns[$col.N].Width = $col.W
        }
        & $applyReadableDataGridStyle $gridEnvTerritories

        $territoryPanel = New-Object System.Windows.Forms.Panel
        $territoryPanel.Location = New-Object System.Drawing.Point(0, 210)
        $territoryPanel.Anchor = 'Top,Bottom,Left,Right'
        $territoryPanel.BackColor = New-UGSMColor '#0B121D'
        $territoryPanel.Visible = $false
        [void]$rootPanel.Controls.Add($territoryPanel)

        $lblTerritoryFile = New-UGSMLabel -Text 'Territory File:' -X 0 -Y 4 -Width 90 -Height 18 -FontSize 8.5 -Color $Theme.Text
        [void]$territoryPanel.Controls.Add($lblTerritoryFile)

        $cmbTerritoryFile = New-Object System.Windows.Forms.ComboBox
        $cmbTerritoryFile.Location = New-Object System.Drawing.Point(95, 0)
        $cmbTerritoryFile.Size = New-Object System.Drawing.Size(280, 24)
        $cmbTerritoryFile.DropDownStyle = 'DropDownList'
        $cmbTerritoryFile.FlatStyle = 'Flat'
        $cmbTerritoryFile.BackColor = [System.Drawing.Color]::White
        $cmbTerritoryFile.ForeColor = [System.Drawing.Color]::Black
        [void]$territoryPanel.Controls.Add($cmbTerritoryFile)

        $btnLoadTerritoryFile = New-UGSMButton -Text 'Load Territory File' -X 390 -Y 0 -Width 150 -Height 28 -BackColor '#253341'
        $btnSaveTerritoryFile = New-UGSMButton -Text 'Save Territory File' -X 552 -Y 0 -Width 150 -Height 28 -BackColor $Theme.Accent
        $btnAddTerritoryZone = New-UGSMButton -Text 'Add Zone' -X 714 -Y 0 -Width 100 -Height 28 -BackColor '#F4A300'
        $btnRemoveTerritoryZone = New-UGSMButton -Text 'Remove Selected Zone' -X 826 -Y 0 -Width 160 -Height 28 -BackColor $global:UGSM_ColorDanger
        [void]$territoryPanel.Controls.Add($btnLoadTerritoryFile)
        [void]$territoryPanel.Controls.Add($btnSaveTerritoryFile)
        [void]$territoryPanel.Controls.Add($btnAddTerritoryZone)
        [void]$territoryPanel.Controls.Add($btnRemoveTerritoryZone)

        $gridTerritoryZones = New-Object System.Windows.Forms.DataGridView
        $gridTerritoryZones.Location = New-Object System.Drawing.Point(0, 38)
        $gridTerritoryZones.Anchor = 'Top,Bottom,Left,Right'
        $gridTerritoryZones.BackgroundColor = [System.Drawing.Color]::White
        $gridTerritoryZones.BorderStyle = 'FixedSingle'
        $gridTerritoryZones.RowHeadersVisible = $false
        $gridTerritoryZones.AllowUserToAddRows = $true
        $gridTerritoryZones.AllowUserToDeleteRows = $true
        $gridTerritoryZones.SelectionMode = 'FullRowSelect'
        $gridTerritoryZones.MultiSelect = $true
        $gridTerritoryZones.AutoSizeRowsMode = 'None'
        $gridTerritoryZones.ColumnHeadersHeightSizeMode = 'DisableResizing'
        $gridTerritoryZones.ColumnHeadersHeight = 24
        [void]$territoryPanel.Controls.Add($gridTerritoryZones)

        foreach ($col in @(
            @{ N='Territory'; H='Territory #'; W=80 },
            @{ N='Color'; H='Color'; W=120 },
            @{ N='Zone'; H='Zone #'; W=60 },
            @{ N='Name'; H='Name'; W=100 },
            @{ N='SMin'; H='smin'; W=70 },
            @{ N='SMax'; H='smax'; W=70 },
            @{ N='DMin'; H='dmin'; W=70 },
            @{ N='DMax'; H='dmax'; W=70 },
            @{ N='X'; H='X'; W=90 },
            @{ N='Z'; H='Z'; W=90 },
            @{ N='R'; H='Radius'; W=80 }
        )) {
            [void]$gridTerritoryZones.Columns.Add($col.N, $col.H)
            $gridTerritoryZones.Columns[$col.N].Width = $col.W
        }
        & $applyReadableDataGridStyle $gridTerritoryZones



        $cfgEconomyCoreState = [pscustomobject]@{
            IsLoading      = $false
            RootClassRows  = @()
            DefaultRows    = @()
        }

        $cfgEconomyCorePanel = New-Object System.Windows.Forms.Panel
        $cfgEconomyCorePanel.Location = New-Object System.Drawing.Point(0, 210)
        $cfgEconomyCorePanel.Anchor = 'Top,Bottom,Left,Right'
        $cfgEconomyCorePanel.BackColor = New-UGSMColor '#0B121D'
        $cfgEconomyCorePanel.Visible = $false
        [void]$rootPanel.Controls.Add($cfgEconomyCorePanel)

        $lblEconomyRootClasses = New-UGSMLabel -Text 'cfgeconomycore.xml Root Classes' -X 0 -Y 0 -Width 300 -Height 18 -FontSize 9 -Style Bold -Color $Theme.Text
        [void]$cfgEconomyCorePanel.Controls.Add($lblEconomyRootClasses)

        $gridEconomyRootClasses = New-Object System.Windows.Forms.DataGridView
        $gridEconomyRootClasses.Location = New-Object System.Drawing.Point(0, 24)
        $gridEconomyRootClasses.Size = New-Object System.Drawing.Size(720, 220)
        $gridEconomyRootClasses.Anchor = 'Top,Left,Right'
        $gridEconomyRootClasses.BackgroundColor = [System.Drawing.Color]::White
        $gridEconomyRootClasses.BorderStyle = 'FixedSingle'
        $gridEconomyRootClasses.RowHeadersVisible = $false
        $gridEconomyRootClasses.AllowUserToAddRows = $true
        $gridEconomyRootClasses.AllowUserToDeleteRows = $true
        $gridEconomyRootClasses.SelectionMode = 'FullRowSelect'
        $gridEconomyRootClasses.MultiSelect = $true
        $gridEconomyRootClasses.AutoSizeRowsMode = 'None'
        $gridEconomyRootClasses.ColumnHeadersHeightSizeMode = 'DisableResizing'
        $gridEconomyRootClasses.ColumnHeadersHeight = 24
        [void]$cfgEconomyCorePanel.Controls.Add($gridEconomyRootClasses)
        foreach ($col in @(
            @{ N='Index'; H='#'; W=45 },
            @{ N='Name'; H='Name'; W=260 },
            @{ N='Act'; H='Act'; W=140 },
            @{ N='ReportMemoryLOD'; H='reportMemoryLOD'; W=180 }
        )) {
            [void]$gridEconomyRootClasses.Columns.Add($col.N, $col.H)
            $gridEconomyRootClasses.Columns[$col.N].Width = $col.W
        }
        & $applyReadableDataGridStyle $gridEconomyRootClasses

        $btnAddRootClass = New-UGSMButton -Text 'Add Root Class' -X 740 -Y 24 -Width 150 -Height 28 -BackColor '#F4A300'
        $btnRemoveRootClass = New-UGSMButton -Text 'Remove Selected Root Class' -X 900 -Y 24 -Width 210 -Height 28 -BackColor $global:UGSM_ColorDanger
        [void]$cfgEconomyCorePanel.Controls.Add($btnAddRootClass)
        [void]$cfgEconomyCorePanel.Controls.Add($btnRemoveRootClass)

        $lblEconomyDefaults = New-UGSMLabel -Text 'cfgeconomycore.xml Defaults' -X 0 -Y 260 -Width 300 -Height 18 -FontSize 9 -Style Bold -Color $Theme.Text
        [void]$cfgEconomyCorePanel.Controls.Add($lblEconomyDefaults)

        $gridEconomyDefaults = New-Object System.Windows.Forms.DataGridView
        $gridEconomyDefaults.Location = New-Object System.Drawing.Point(0, 284)
        $gridEconomyDefaults.Size = New-Object System.Drawing.Size(720, 220)
        $gridEconomyDefaults.Anchor = 'Top,Bottom,Left,Right'
        $gridEconomyDefaults.BackgroundColor = [System.Drawing.Color]::White
        $gridEconomyDefaults.BorderStyle = 'FixedSingle'
        $gridEconomyDefaults.RowHeadersVisible = $false
        $gridEconomyDefaults.AllowUserToAddRows = $true
        $gridEconomyDefaults.AllowUserToDeleteRows = $true
        $gridEconomyDefaults.SelectionMode = 'FullRowSelect'
        $gridEconomyDefaults.MultiSelect = $true
        $gridEconomyDefaults.AutoSizeRowsMode = 'None'
        $gridEconomyDefaults.ColumnHeadersHeightSizeMode = 'DisableResizing'
        $gridEconomyDefaults.ColumnHeadersHeight = 24
        [void]$cfgEconomyCorePanel.Controls.Add($gridEconomyDefaults)
        foreach ($col in @(
            @{ N='Index'; H='#'; W=45 },
            @{ N='Name'; H='Name'; W=300 },
            @{ N='Value'; H='Value'; W=180 }
        )) {
            [void]$gridEconomyDefaults.Columns.Add($col.N, $col.H)
            $gridEconomyDefaults.Columns[$col.N].Width = $col.W
        }
        & $applyReadableDataGridStyle $gridEconomyDefaults

        $btnAddEconomyDefault = New-UGSMButton -Text 'Add Default' -X 740 -Y 284 -Width 150 -Height 28 -BackColor '#F4A300'
        $btnRemoveEconomyDefault = New-UGSMButton -Text 'Remove Selected Default' -X 900 -Y 284 -Width 210 -Height 28 -BackColor $global:UGSM_ColorDanger
        [void]$cfgEconomyCorePanel.Controls.Add($btnAddEconomyDefault)
        [void]$cfgEconomyCorePanel.Controls.Add($btnRemoveEconomyDefault)


        $cfgEventGroupsState = [pscustomobject]@{
            IsLoading = $false
            Rows      = @()
        }

        $cfgEventGroupsPanel = New-Object System.Windows.Forms.Panel
        $cfgEventGroupsPanel.Location = New-Object System.Drawing.Point(0, 210)
        $cfgEventGroupsPanel.Anchor = 'Top,Bottom,Left,Right'
        $cfgEventGroupsPanel.BackColor = New-UGSMColor '#0B121D'
        $cfgEventGroupsPanel.Visible = $false
        [void]$rootPanel.Controls.Add($cfgEventGroupsPanel)

        $lblEventGroups = New-UGSMLabel -Text 'cfgeventgroups.xml Group Children' -X 0 -Y 0 -Width 320 -Height 18 -FontSize 9 -Style Bold -Color $Theme.Text
        [void]$cfgEventGroupsPanel.Controls.Add($lblEventGroups)

        $gridEventGroups = New-Object System.Windows.Forms.DataGridView
        $gridEventGroups.Location = New-Object System.Drawing.Point(0, 24)
        $gridEventGroups.Anchor = 'Top,Bottom,Left,Right'
        $gridEventGroups.BackgroundColor = [System.Drawing.Color]::White
        $gridEventGroups.BorderStyle = 'FixedSingle'
        $gridEventGroups.RowHeadersVisible = $false
        $gridEventGroups.AllowUserToAddRows = $true
        $gridEventGroups.AllowUserToDeleteRows = $true
        $gridEventGroups.SelectionMode = 'FullRowSelect'
        $gridEventGroups.MultiSelect = $true
        $gridEventGroups.AutoSizeRowsMode = 'None'
        $gridEventGroups.ColumnHeadersHeightSizeMode = 'DisableResizing'
        $gridEventGroups.ColumnHeadersHeight = 24
        [void]$cfgEventGroupsPanel.Controls.Add($gridEventGroups)

        foreach ($col in @(
            @{ N='GroupIndex'; H='Group #'; W=70 },
            @{ N='ChildIndex'; H='Child #'; W=70 },
            @{ N='GroupName'; H='Group Name'; W=250 },
            @{ N='Type'; H='Type'; W=280 },
            @{ N='Deloot'; H='Deloot'; W=70 },
            @{ N='LootMax'; H='Loot Max'; W=80 },
            @{ N='LootMin'; H='Loot Min'; W=80 },
            @{ N='X'; H='X'; W=90 },
            @{ N='Z'; H='Z'; W=90 },
            @{ N='A'; H='Angle'; W=90 },
            @{ N='Y'; H='Y'; W=90 }
        )) {
            [void]$gridEventGroups.Columns.Add($col.N, $col.H)
            $gridEventGroups.Columns[$col.N].Width = $col.W
        }
        & $applyReadableDataGridStyle $gridEventGroups

        $btnAddEventGroupChild = New-UGSMButton -Text 'Add Group Child' -X 720 -Y 28 -Width 150 -Height 28 -BackColor '#F4A300'
        $btnRemoveEventGroupChild = New-UGSMButton -Text 'Remove Selected Child' -X 882 -Y 28 -Width 180 -Height 28 -BackColor $global:UGSM_ColorDanger
        [void]$topTools.Controls.Add($btnAddEventGroupChild)
        [void]$topTools.Controls.Add($btnRemoveEventGroupChild)


        $cfgIgnoreListState = [pscustomobject]@{
            IsLoading = $false
            Rows      = @()
        }

        $cfgIgnoreListPanel = New-Object System.Windows.Forms.Panel
        $cfgIgnoreListPanel.Location = New-Object System.Drawing.Point(0, 210)
        $cfgIgnoreListPanel.Anchor = 'Top,Bottom,Left,Right'
        $cfgIgnoreListPanel.BackColor = New-UGSMColor '#0B121D'
        $cfgIgnoreListPanel.Visible = $false
        [void]$rootPanel.Controls.Add($cfgIgnoreListPanel)

        $lblIgnoreList = New-UGSMLabel -Text 'cfgignorelist.xml Ignore Types' -X 0 -Y 0 -Width 280 -Height 18 -FontSize 9 -Style Bold -Color $Theme.Text
        [void]$cfgIgnoreListPanel.Controls.Add($lblIgnoreList)

        $gridIgnoreList = New-Object System.Windows.Forms.DataGridView
        $gridIgnoreList.Location = New-Object System.Drawing.Point(0, 24)
        $gridIgnoreList.Anchor = 'Top,Bottom,Left,Right'
        $gridIgnoreList.BackgroundColor = [System.Drawing.Color]::White
        $gridIgnoreList.BorderStyle = 'FixedSingle'
        $gridIgnoreList.RowHeadersVisible = $false
        $gridIgnoreList.AllowUserToAddRows = $true
        $gridIgnoreList.AllowUserToDeleteRows = $true
        $gridIgnoreList.SelectionMode = 'FullRowSelect'
        $gridIgnoreList.MultiSelect = $true
        $gridIgnoreList.AutoSizeRowsMode = 'None'
        $gridIgnoreList.ColumnHeadersHeightSizeMode = 'DisableResizing'
        $gridIgnoreList.ColumnHeadersHeight = 24
        [void]$cfgIgnoreListPanel.Controls.Add($gridIgnoreList)
        [void]$gridIgnoreList.Columns.Add('Index', '#')
        [void]$gridIgnoreList.Columns.Add('Name', 'Type Name')
        $gridIgnoreList.Columns['Index'].Width = 60
        $gridIgnoreList.Columns['Name'].Width = 420
        & $applyReadableDataGridStyle $gridIgnoreList

        $btnAddIgnoreType = New-UGSMButton -Text 'Add Ignore Type' -X 720 -Y 28 -Width 150 -Height 28 -BackColor '#F4A300'
        $btnRemoveIgnoreType = New-UGSMButton -Text 'Remove Selected Ignore Type' -X 882 -Y 28 -Width 220 -Height 28 -BackColor $global:UGSM_ColorDanger
        [void]$topTools.Controls.Add($btnAddIgnoreType)
        [void]$topTools.Controls.Add($btnRemoveIgnoreType)

        $miscEditorKinds = @('CfgEffectArea','CfgPlayerSpawnPoints','CfgRandomPresets','CfgWeather','MapGroupPos','MapGroupProto','MapGroupCluster','MapGroupDirt','MapClusterProto')
        $miscEditorState = [pscustomobject]@{
            Kind        = ''
            MainColumns = @()
            MainRows    = @()
            SubColumns  = @()
            SubRows     = @()
        }

        $miscEditorPanel = New-Object System.Windows.Forms.Panel
        $miscEditorPanel.Location = New-Object System.Drawing.Point(0, 210)
        $miscEditorPanel.Anchor = 'Top,Bottom,Left,Right'
        $miscEditorPanel.BackColor = New-UGSMColor '#0B121D'
        $miscEditorPanel.Visible = $false
        [void]$rootPanel.Controls.Add($miscEditorPanel)

        $lblMiscEditor = New-UGSMLabel -Text 'Structured Config Editor' -X 0 -Y 0 -Width 420 -Height 18 -FontSize 9 -Style Bold -Color $Theme.Text
        [void]$miscEditorPanel.Controls.Add($lblMiscEditor)

        $gridMiscMain = New-Object System.Windows.Forms.DataGridView
        $gridMiscMain.Location = New-Object System.Drawing.Point(0, 24)
        $gridMiscMain.Anchor = 'Top,Bottom,Left,Right'
        $gridMiscMain.BackgroundColor = [System.Drawing.Color]::White
        $gridMiscMain.BorderStyle = 'FixedSingle'
        $gridMiscMain.RowHeadersVisible = $false
        $gridMiscMain.AllowUserToAddRows = $true
        $gridMiscMain.AllowUserToDeleteRows = $true
        $gridMiscMain.SelectionMode = 'FullRowSelect'
        $gridMiscMain.MultiSelect = $true
        $gridMiscMain.AutoSizeRowsMode = 'None'
        $gridMiscMain.ColumnHeadersHeightSizeMode = 'DisableResizing'
        $gridMiscMain.ColumnHeadersHeight = 24
        [void]$miscEditorPanel.Controls.Add($gridMiscMain)
        & $applyReadableDataGridStyle $gridMiscMain

        $lblMiscSub = New-UGSMLabel -Text 'Secondary Rows' -X 0 -Y 240 -Width 280 -Height 18 -FontSize 9 -Style Bold -Color $Theme.Text
        $lblMiscSub.Visible = $false
        [void]$miscEditorPanel.Controls.Add($lblMiscSub)

        $gridMiscSub = New-Object System.Windows.Forms.DataGridView
        $gridMiscSub.Location = New-Object System.Drawing.Point(0, 264)
        $gridMiscSub.Anchor = 'Bottom,Left,Right'
        $gridMiscSub.BackgroundColor = [System.Drawing.Color]::White
        $gridMiscSub.BorderStyle = 'FixedSingle'
        $gridMiscSub.RowHeadersVisible = $false
        $gridMiscSub.AllowUserToAddRows = $true
        $gridMiscSub.AllowUserToDeleteRows = $true
        $gridMiscSub.SelectionMode = 'FullRowSelect'
        $gridMiscSub.MultiSelect = $true
        $gridMiscSub.AutoSizeRowsMode = 'None'
        $gridMiscSub.ColumnHeadersHeightSizeMode = 'DisableResizing'
        $gridMiscSub.ColumnHeadersHeight = 24
        $gridMiscSub.Visible = $false
        [void]$miscEditorPanel.Controls.Add($gridMiscSub)
        & $applyReadableDataGridStyle $gridMiscSub

        $btnAddMiscRow = New-UGSMButton -Text 'Add Row' -X 720 -Y 28 -Width 120 -Height 28 -BackColor '#F4A300'
        $btnRemoveMiscRow = New-UGSMButton -Text 'Remove Selected Row' -X 852 -Y 28 -Width 180 -Height 28 -BackColor $global:UGSM_ColorDanger
        [void]$topTools.Controls.Add($btnAddMiscRow)
        [void]$topTools.Controls.Add($btnRemoveMiscRow)

        $setMiscGridColumns = {
            param([System.Windows.Forms.DataGridView]$Grid, [object[]]$Columns)
            $Grid.Columns.Clear()
            foreach ($col in @($Columns)) {
                [void]$Grid.Columns.Add([string]$col.N, [string]$col.H)
                $Grid.Columns[[string]$col.N].Width = [int]$col.W
            }
            & $applyReadableDataGridStyle $Grid
        }.GetNewClosure()

        $loadMiscColumns = {
            param([string]$Kind)
            $main = @()
            $sub = @()
            switch ($Kind) {
                'CfgEffectArea' {
                    $main = @(
                        @{N='AreaName';H='Area Name';W=180}, @{N='Type';H='Type';W=170}, @{N='TriggerType';H='Trigger Type';W=150},
                        @{N='PosX';H='Pos X';W=80}, @{N='PosY';H='Pos Y';W=70}, @{N='PosZ';H='Pos Z';W=80}, @{N='Radius';H='Radius';W=70},
                        @{N='PosHeight';H='Pos Height';W=80}, @{N='NegHeight';H='Neg Height';W=80}, @{N='InnerPartDist';H='Inner Dist';W=80}, @{N='OuterOffset';H='Outer Offset';W=80},
                        @{N='ParticleName';H='Particle';W=220}, @{N='AroundPartName';H='Around Particle';W=180}, @{N='TinyPartName';H='Tiny Particle';W=180}, @{N='PPERequesterType';H='PPE Type';W=180}
                    )
                    $sub = @(
                        @{N='PosX';H='Safe X';W=90}, @{N='PosZ';H='Safe Z';W=90}
                    )
                    $lblMiscEditor.Text = 'cfgeffectarea.json Areas'
                    $lblMiscSub.Text = 'Safe Positions'
                }
                'CfgPlayerSpawnPoints' {
                    $main = @(
                        @{N='Section';H='Section';W=120}, @{N='GroupName';H='Group';W=180}, @{N='PosX';H='Pos X';W=100}, @{N='PosZ';H='Pos Z';W=100}
                    )
                    $lblMiscEditor.Text = 'cfgplayerspawnpoints.xml Spawn Points'
                }
                'CfgRandomPresets' {
                    $main = @(
                        @{N='CargoName';H='Cargo';W=180}, @{N='CargoChance';H='Cargo Chance';W=90}, @{N='ItemName';H='Item';W=220}, @{N='ItemChance';H='Item Chance';W=90}
                    )
                    $lblMiscEditor.Text = 'cfgrandompresets.xml Cargo Presets'
                }
                'CfgWeather' {
                    $main = @(
                        @{N='RootReset';H='Root Reset';W=80}, @{N='RootEnable';H='Root Enable';W=90}, @{N='Section';H='Section';W=120},
                        @{N='CurrentActual';H='Current Actual';W=90}, @{N='CurrentTime';H='Current Time';W=90}, @{N='CurrentDuration';H='Current Duration';W=130},
                        @{N='LimitsMin';H='Limits Min';W=80}, @{N='LimitsMax';H='Limits Max';W=80},
                        @{N='TimeMin';H='Time Min';W=80}, @{N='TimeMax';H='Time Max';W=80}, @{N='ChangeMin';H='Change Min';W=90}, @{N='ChangeMax';H='Change Max';W=90},
                        @{N='ThresholdMin';H='Threshold Min';W=90}, @{N='ThresholdMax';H='Threshold Max';W=105}, @{N='ThresholdEnd';H='Threshold End';W=90}
                    )
                    $lblMiscEditor.Text = 'cfgweather.xml Weather Sections'
                }
                'MapGroupPos' {
                    $main = @(
                        @{N='Name';H='Name';W=180}, @{N='PosX';H='Pos X';W=90}, @{N='PosY';H='Pos Y';W=90}, @{N='PosZ';H='Pos Z';W=90}, @{N='RpyX';H='Rpy X';W=90}, @{N='RpyY';H='Rpy Y';W=90}, @{N='RpyZ';H='Rpy Z';W=90}, @{N='A';H='A';W=70}
                    )
                    $lblMiscEditor.Text = 'mapgrouppos.xml Groups'
                }
                'MapGroupCluster' {
                    $main = @(
                        @{N='Name';H='Name';W=200}, @{N='PosX';H='Pos X';W=90}, @{N='PosY';H='Pos Y';W=90}, @{N='PosZ';H='Pos Z';W=90}, @{N='A';H='A';W=70}
                    )
                    $lblMiscEditor.Text = 'mapgroupcluster.xml Groups'
                }
                'MapGroupDirt' {
                    $main = @(
                        @{N='Name';H='Name';W=200}, @{N='PosX';H='Pos X';W=90}, @{N='PosY';H='Pos Y';W=90}, @{N='PosZ';H='Pos Z';W=90}, @{N='A';H='A';W=70}
                    )
                    $lblMiscEditor.Text = 'mapgroupdirt.xml Groups'
                }
                'MapClusterProto' {
                    $main = @(
                        @{N='Name';H='Name';W=220}, @{N='Shape';H='Shape';W=120}
                    )
                    $lblMiscEditor.Text = 'mapclusterproto.xml Clusters'
                }
                'MapGroupProto' {
                    $main = @(
                        @{N='GroupName';H='Group';W=180}, @{N='GroupLootMax';H='Group LootMax';W=90}, @{N='ContainerName';H='Container';W=180}, @{N='ContainerLootMax';H='Container LootMax';W=100},
                        @{N='Usages';H='Usages';W=160}, @{N='Categories';H='Categories';W=160}, @{N='Tags';H='Tags';W=160},
                        @{N='Pos';H='Pos';W=120}, @{N='Range';H='Range';W=80}, @{N='Height';H='Height';W=80}, @{N='Flags';H='Flags';W=80}
                    )
                    $lblMiscEditor.Text = 'mapgroupproto.xml Prototype Groups'
                }
            }
            $miscEditorState.MainColumns = @($main)
            $miscEditorState.SubColumns = @($sub)
            & $setMiscGridColumns $gridMiscMain $main
            if (@($sub).Count -gt 0) { & $setMiscGridColumns $gridMiscSub $sub }
            $gridMiscSub.Visible = (@($sub).Count -gt 0)
            $lblMiscSub.Visible = (@($sub).Count -gt 0)
        }.GetNewClosure()

        $readMiscRows = {
            param([string]$Kind, [string]$Path)
            $mainRows = @()
            $subRows = @()
            switch ($Kind) {
                'CfgEffectArea' {
                    if (Test-Path -LiteralPath $Path -PathType Leaf) {
                        $raw = Get-Content -LiteralPath $Path -Raw -ErrorAction Stop
                        if (-not [string]::IsNullOrWhiteSpace($raw)) {
                            $data = $raw | ConvertFrom-Json -ErrorAction Stop
                            foreach ($area in @($data.Areas)) {
                                $pos = @($area.Data.Pos)
                                $mainRows += [pscustomobject]@{
                                    AreaName = [string]$area.AreaName; Type = [string]$area.Type; TriggerType = [string]$area.TriggerType;
                                    PosX = if ($pos.Count -gt 0) { [string]$pos[0] } else { '' }; PosY = if ($pos.Count -gt 1) { [string]$pos[1] } else { '' }; PosZ = if ($pos.Count -gt 2) { [string]$pos[2] } else { '' };
                                    Radius = [string]$area.Data.Radius; PosHeight = [string]$area.Data.PosHeight; NegHeight = [string]$area.Data.NegHeight; InnerPartDist = [string]$area.Data.InnerPartDist; OuterOffset = [string]$area.Data.OuterOffset;
                                    ParticleName = [string]$area.Data.ParticleName; AroundPartName = [string]$area.PlayerData.AroundPartName; TinyPartName = [string]$area.PlayerData.TinyPartName; PPERequesterType = [string]$area.PlayerData.PPERequesterType
                                }
                            }
                            foreach ($safe in @($data.SafePositions)) {
                                $subRows += [pscustomobject]@{ PosX = if ($safe.Count -gt 0) { [string]$safe[0] } else { '' }; PosZ = if ($safe.Count -gt 1) { [string]$safe[1] } else { '' } }
                            }
                        }
                    }
                }
                'CfgPlayerSpawnPoints' {
                    [xml]$xml = Get-Content -LiteralPath $Path -Raw -ErrorAction Stop
                    foreach ($section in @($xml.playerspawnpoints.ChildNodes)) {
                        if ($section.NodeType -ne [System.Xml.XmlNodeType]::Element) { continue }
                        $sectionName = [string]$section.Name
                        foreach ($group in @($section.SelectNodes('./generator_posbubbles/group'))) {
                            $groupName = [string]$group.GetAttribute('name')
                            foreach ($posNode in @($group.SelectNodes('./pos'))) {
                                $mainRows += [pscustomobject]@{
                                    Section   = $sectionName
                                    GroupName = $groupName
                                    PosX      = [string]$posNode.GetAttribute('x')
                                    PosZ      = [string]$posNode.GetAttribute('z')
                                }
                            }
                        }
                    }
                }
                'CfgRandomPresets' {
                    [xml]$xml = Get-Content -LiteralPath $Path -Raw -ErrorAction Stop
                    foreach ($cargo in @($xml.SelectNodes('/randompresets/cargo'))) {
                        $items = @($cargo.SelectNodes('./item'))
                        if ($items.Count -eq 0) {
                            $mainRows += [pscustomobject]@{ CargoName=[string]$cargo.GetAttribute('name'); CargoChance=[string]$cargo.GetAttribute('chance'); ItemName=''; ItemChance='' }
                        }
                        foreach ($item in $items) {
                            $mainRows += [pscustomobject]@{ CargoName=[string]$cargo.GetAttribute('name'); CargoChance=[string]$cargo.GetAttribute('chance'); ItemName=[string]$item.GetAttribute('name'); ItemChance=[string]$item.GetAttribute('chance') }
                        }
                    }
                }
                'CfgWeather' {
                    [xml]$xml = Get-Content -LiteralPath $Path -Raw -ErrorAction Stop
                    $weatherNode = $xml.SelectSingleNode('/weather')
                    if ($weatherNode) {
                        $rootReset = [string]$weatherNode.GetAttribute('reset')
                        $rootEnable = [string]$weatherNode.GetAttribute('enable')
                        foreach ($section in @($weatherNode.ChildNodes)) {
                            if ($section.NodeType -ne [System.Xml.XmlNodeType]::Element) { continue }
                            $current = $section.SelectSingleNode('./current')
                            $limits = $section.SelectSingleNode('./limits')
                            $timelimits = $section.SelectSingleNode('./timelimits')
                            $changelimits = $section.SelectSingleNode('./changelimits')
                            $thresholds = $section.SelectSingleNode('./thresholds')
                            $mainRows += [pscustomobject]@{
                                RootReset=$rootReset; RootEnable=$rootEnable; Section=[string]$section.Name;
                                CurrentActual=if ($current) { [string]$current.GetAttribute('actual') } else { '' };
                                CurrentTime=if ($current) { [string]$current.GetAttribute('time') } else { '' };
                                CurrentDuration=if ($current) { [string]$current.GetAttribute('duration') } else { '' };
                                LimitsMin=if ($limits) { [string]$limits.GetAttribute('min') } else { '' };
                                LimitsMax=if ($limits) { [string]$limits.GetAttribute('max') } else { '' };
                                TimeMin=if ($timelimits) { [string]$timelimits.GetAttribute('min') } else { '' };
                                TimeMax=if ($timelimits) { [string]$timelimits.GetAttribute('max') } else { '' };
                                ChangeMin=if ($changelimits) { [string]$changelimits.GetAttribute('min') } else { '' };
                                ChangeMax=if ($changelimits) { [string]$changelimits.GetAttribute('max') } else { '' };
                                ThresholdMin=if ($thresholds) { [string]$thresholds.GetAttribute('min') } else { '' };
                                ThresholdMax=if ($thresholds) { [string]$thresholds.GetAttribute('max') } else { '' };
                                ThresholdEnd=if ($thresholds) { [string]$thresholds.GetAttribute('end') } else { '' }
                            }
                        }
                    }
                }
                'MapGroupPos' {
                    [xml]$xml = Get-Content -LiteralPath $Path -Raw -ErrorAction Stop
                    foreach ($node in @($xml.SelectNodes('/map/group'))) {
                        $pos = ([string]$node.GetAttribute('pos')).Split(' ', [System.StringSplitOptions]::RemoveEmptyEntries)
                        $rpy = ([string]$node.GetAttribute('rpy')).Split(' ', [System.StringSplitOptions]::RemoveEmptyEntries)
                        $mainRows += [pscustomobject]@{ Name=[string]$node.GetAttribute('name'); PosX=if($pos.Length -gt 0){$pos[0]}else{''}; PosY=if($pos.Length -gt 1){$pos[1]}else{''}; PosZ=if($pos.Length -gt 2){$pos[2]}else{''}; RpyX=if($rpy.Length -gt 0){$rpy[0]}else{''}; RpyY=if($rpy.Length -gt 1){$rpy[1]}else{''}; RpyZ=if($rpy.Length -gt 2){$rpy[2]}else{''}; A=[string]$node.GetAttribute('a') }
                    }
                }
                'MapGroupCluster' {
                    [xml]$xml = Get-Content -LiteralPath $Path -Raw -ErrorAction Stop
                    foreach ($node in @($xml.SelectNodes('/map/group'))) {
                        $pos = ([string]$node.GetAttribute('pos')).Split(' ', [System.StringSplitOptions]::RemoveEmptyEntries)
                        $mainRows += [pscustomobject]@{ Name=[string]$node.GetAttribute('name'); PosX=if($pos.Length -gt 0){$pos[0]}else{''}; PosY=if($pos.Length -gt 1){$pos[1]}else{''}; PosZ=if($pos.Length -gt 2){$pos[2]}else{''}; A=[string]$node.GetAttribute('a') }
                    }
                }
                'MapGroupDirt' {
                    [xml]$xml = Get-Content -LiteralPath $Path -Raw -ErrorAction Stop
                    foreach ($node in @($xml.SelectNodes('/map/group'))) {
                        $pos = ([string]$node.GetAttribute('pos')).Split(' ', [System.StringSplitOptions]::RemoveEmptyEntries)
                        $mainRows += [pscustomobject]@{ Name=[string]$node.GetAttribute('name'); PosX=if($pos.Length -gt 0){$pos[0]}else{''}; PosY=if($pos.Length -gt 1){$pos[1]}else{''}; PosZ=if($pos.Length -gt 2){$pos[2]}else{''}; A=[string]$node.GetAttribute('a') }
                    }
                }
                'MapClusterProto' {
                    [xml]$xml = Get-Content -LiteralPath $Path -Raw -ErrorAction Stop
                    foreach ($node in @($xml.SelectNodes('/prototype/clusters/export'))) {
                        $mainRows += [pscustomobject]@{ Name=[string]$node.GetAttribute('name'); Shape=[string]$node.GetAttribute('shape') }
                    }
                }
                'MapGroupProto' {
                    [xml]$xml = Get-Content -LiteralPath $Path -Raw -ErrorAction Stop
                    foreach ($group in @($xml.SelectNodes('/prototype/group'))) {
                        $usageList = @(); foreach ($u in @($group.SelectNodes('./usage'))) { $usageList += [string]$u.GetAttribute('name') }
                        foreach ($container in @($group.SelectNodes('./container'))) {
                            $catList = @(); foreach ($c in @($container.SelectNodes('./category'))) { $catList += [string]$c.GetAttribute('name') }
                            $tagList = @(); foreach ($t in @($container.SelectNodes('./tag'))) { $tagList += [string]$t.GetAttribute('name') }
                            $points = @($container.SelectNodes('./point'))
                            if ($points.Count -eq 0) {
                                $mainRows += [pscustomobject]@{ GroupName=[string]$group.GetAttribute('name'); GroupLootMax=[string]$group.GetAttribute('lootmax'); ContainerName=[string]$container.GetAttribute('name'); ContainerLootMax=[string]$container.GetAttribute('lootmax'); Usages=($usageList -join ', '); Categories=($catList -join ', '); Tags=($tagList -join ', '); Pos=''; Range=''; Height=''; Flags='' }
                            }
                            foreach ($point in $points) {
                                $mainRows += [pscustomobject]@{ GroupName=[string]$group.GetAttribute('name'); GroupLootMax=[string]$group.GetAttribute('lootmax'); ContainerName=[string]$container.GetAttribute('name'); ContainerLootMax=[string]$container.GetAttribute('lootmax'); Usages=($usageList -join ', '); Categories=($catList -join ', '); Tags=($tagList -join ', '); Pos=[string]$point.GetAttribute('pos'); Range=[string]$point.GetAttribute('range'); Height=[string]$point.GetAttribute('height'); Flags=[string]$point.GetAttribute('flags') }
                            }
                        }
                    }
                }
            }
            $miscEditorState.MainRows = @($mainRows)
            $miscEditorState.SubRows = @($subRows)
        }.GetNewClosure()

        $fillMiscGrid = {
            param([System.Windows.Forms.DataGridView]$Grid, [object[]]$Rows, [object[]]$Columns, [string]$SearchText)
            $Grid.Rows.Clear()
            foreach ($row in @($Rows)) {
                if (-not [string]::IsNullOrWhiteSpace($SearchText)) {
                    $parts = @(); foreach ($col in @($Columns)) { $parts += [string]$row.($col.N) }
                    if ((($parts -join ' ').IndexOf($SearchText, [System.StringComparison]::OrdinalIgnoreCase)) -lt 0) { continue }
                }
                $vals = @(); foreach ($col in @($Columns)) { $vals += [string]$row.($col.N) }
                [void]$Grid.Rows.Add($vals)
            }
        }.GetNewClosure()

        $refreshMiscEditor = {
            $searchText = [string]$txtSearch.Text
            & $fillMiscGrid $gridMiscMain @($miscEditorState.MainRows) @($miscEditorState.MainColumns) $searchText
            if ($gridMiscSub.Visible) { & $fillMiscGrid $gridMiscSub @($miscEditorState.SubRows) @($miscEditorState.SubColumns) $searchText } else { $gridMiscSub.Rows.Clear() }
            $lblItemCount.Text = ('Rows: ' + $gridMiscMain.Rows.Count + $(if ($gridMiscSub.Visible) { '  Safe: ' + $gridMiscSub.Rows.Count } else { '' }))
        }.GetNewClosure()

        $getGridRowsByColumns = {
            param([System.Windows.Forms.DataGridView]$Grid, [object[]]$Columns)
            $rows = @()
            foreach ($gridRow in @($Grid.Rows)) {
                if ($null -eq $gridRow -or $gridRow.IsNewRow) { continue }
                $obj = [ordered]@{}
                $hasData = $false
                foreach ($col in @($Columns)) {
                    $value = [string]$gridRow.Cells[[string]$col.N].Value
                    $obj[[string]$col.N] = $value
                    if (-not [string]::IsNullOrWhiteSpace($value)) { $hasData = $true }
                }
                if ($hasData) { $rows += [pscustomobject]$obj }
            }
            return @($rows)
        }.GetNewClosure()

        $writeMiscRows = {
            param([string]$Kind, [string]$Path, [object[]]$MainRows, [object[]]$SubRows)
            if ($Kind -eq 'CfgEffectArea') {
                $areas = @()
                foreach ($row in @($MainRows)) {
                    if ([string]::IsNullOrWhiteSpace([string]$row.AreaName)) { continue }
                    $areas += [ordered]@{
                        AreaName = [string]$row.AreaName
                        Type = [string]$row.Type
                        TriggerType = [string]$row.TriggerType
                        Data = [ordered]@{
                            Pos = @([double]([string]$row.PosX), [double]([string]$row.PosY), [double]([string]$row.PosZ))
                            Radius = [int]([string]$row.Radius)
                            PosHeight = [int]([string]$row.PosHeight)
                            NegHeight = [int]([string]$row.NegHeight)
                            InnerPartDist = [int]([string]$row.InnerPartDist)
                            OuterOffset = [int]([string]$row.OuterOffset)
                            ParticleName = [string]$row.ParticleName
                        }
                        PlayerData = [ordered]@{
                            AroundPartName = [string]$row.AroundPartName
                            TinyPartName = [string]$row.TinyPartName
                            PPERequesterType = [string]$row.PPERequesterType
                        }
                    }
                }
                $safePositions = @()
                foreach ($row in @($SubRows)) {
                    if ([string]::IsNullOrWhiteSpace([string]$row.PosX) -or [string]::IsNullOrWhiteSpace([string]$row.PosZ)) { continue }
                    $safePositions += ,@([double]([string]$row.PosX), [double]([string]$row.PosZ))
                }
                $json = [ordered]@{ Areas = $areas; SafePositions = $safePositions } | ConvertTo-Json -Depth 10
                [void](Write-UGSMGameDayZTextFileSafe -Path $Path -Content $json)
                return
            }
            $settings = New-Object System.Xml.XmlWriterSettings
            $settings.Indent = $true
            $settings.IndentChars = '    '
            $settings.NewLineChars = "`n"
            $settings.NewLineHandling = [System.Xml.NewLineHandling]::Replace
            $settings.Encoding = New-Object System.Text.UTF8Encoding($false)
            $memoryStream = New-Object System.IO.MemoryStream
            $writer = [System.Xml.XmlWriter]::Create($memoryStream, $settings)
            try {
                $writer.WriteStartDocument()
                switch ($Kind) {
                    'CfgPlayerSpawnPoints' {
                        [xml]$xml = Get-Content -LiteralPath $Path -Raw -ErrorAction Stop
                        $root = $xml.SelectSingleNode('/playerspawnpoints')
                        if (-not $root) { throw 'playerspawnpoints root element not found.' }

                        $rowsBySection = @{}
                        foreach ($row in @($MainRows)) {
                            $sectionName = [string]$row.Section
                            if ([string]::IsNullOrWhiteSpace($sectionName)) { $sectionName = 'fresh' }
                            if ([string]::IsNullOrWhiteSpace([string]$row.PosX) -and [string]::IsNullOrWhiteSpace([string]$row.PosZ)) { continue }
                            if (-not $rowsBySection.ContainsKey($sectionName)) { $rowsBySection[$sectionName] = @() }
                            $rowsBySection[$sectionName] += $row
                        }

                        $sectionOrder = New-Object System.Collections.Generic.List[string]
                        foreach ($sectionNode in @($root.ChildNodes)) {
                            if ($null -eq $sectionNode -or $sectionNode.NodeType -ne [System.Xml.XmlNodeType]::Element) { continue }
                            $sectionName = [string]$sectionNode.Name
                            if (-not [string]::IsNullOrWhiteSpace($sectionName) -and -not $sectionOrder.Contains($sectionName)) {
                                [void]$sectionOrder.Add($sectionName)
                            }
                        }
                        foreach ($sectionName in @($rowsBySection.Keys)) {
                            if (-not $sectionOrder.Contains([string]$sectionName)) { [void]$sectionOrder.Add([string]$sectionName) }
                        }

                        $writer.WriteStartElement('playerspawnpoints')
                        foreach ($sectionName in $sectionOrder) {
                            $sectionNode = $root.SelectSingleNode("./$sectionName")
                            $writer.WriteStartElement([string]$sectionName)

                            foreach ($childName in @('spawn_params','generator_params','group_params')) {
                                $childNode = if ($sectionNode) { $sectionNode.SelectSingleNode("./$childName") } else { $null }
                                if ($childNode) {
                                    $childNode.WriteTo($writer)
                                }
                                else {
                                    $writer.WriteStartElement($childName)
                                    $writer.WriteEndElement()
                                }
                            }

                            $writer.WriteStartElement('generator_posbubbles')
                            $groupBuckets = [ordered]@{}
                            foreach ($row in @($rowsBySection[$sectionName])) {
                                $groupName = [string]$row.GroupName
                                if ([string]::IsNullOrWhiteSpace($groupName)) { $groupName = 'NewGroup' }
                                if (-not $groupBuckets.Contains($groupName)) { $groupBuckets[$groupName] = @() }
                                $groupBuckets[$groupName] += $row
                            }
                            foreach ($groupName in @($groupBuckets.Keys)) {
                                $writer.WriteStartElement('group')
                                $writer.WriteAttributeString('name', [string]$groupName)
                                foreach ($row in @($groupBuckets[$groupName])) {
                                    $writer.WriteStartElement('pos')
                                    if (-not [string]::IsNullOrWhiteSpace([string]$row.PosX)) { $writer.WriteAttributeString('x', [string]$row.PosX) }
                                    if (-not [string]::IsNullOrWhiteSpace([string]$row.PosZ)) { $writer.WriteAttributeString('z', [string]$row.PosZ) }
                                    $writer.WriteEndElement()
                                }
                                $writer.WriteEndElement()
                            }
                            $writer.WriteEndElement()
                            $writer.WriteEndElement()
                        }
                        $writer.WriteEndElement()
                        break
                    }
                    'CfgRandomPresets' {
                        $writer.WriteStartElement('randompresets')
                        $buckets = @{}
                        foreach ($row in @($MainRows)) {
                            $key = [string]$row.CargoName + '|' + [string]$row.CargoChance
                            if (-not $buckets.ContainsKey($key)) { $buckets[$key] = @() }
                            $buckets[$key] += $row
                        }
                        foreach ($key in @($buckets.Keys)) {
                            $first = $buckets[$key][0]
                            $writer.WriteStartElement('cargo')
                            $writer.WriteAttributeString('name',[string]$first.CargoName)
                            if (-not [string]::IsNullOrWhiteSpace([string]$first.CargoChance)) { $writer.WriteAttributeString('chance',[string]$first.CargoChance) }
                            foreach ($row in @($buckets[$key])) {
                                if ([string]::IsNullOrWhiteSpace([string]$row.ItemName)) { continue }
                                $writer.WriteStartElement('item')
                                $writer.WriteAttributeString('name',[string]$row.ItemName)
                                if (-not [string]::IsNullOrWhiteSpace([string]$row.ItemChance)) { $writer.WriteAttributeString('chance',[string]$row.ItemChance) }
                                $writer.WriteEndElement()
                            }
                            $writer.WriteEndElement()
                        }
                        $writer.WriteEndElement()
                    }
                    'CfgWeather' {
                        $rootReset = '0'; $rootEnable = '1'
                        if (@($MainRows).Count -gt 0) { $rootReset = [string]$MainRows[0].RootReset; $rootEnable = [string]$MainRows[0].RootEnable }
                        $writer.WriteStartElement('weather')
                        $writer.WriteAttributeString('reset',$rootReset)
                        $writer.WriteAttributeString('enable',$rootEnable)
                        foreach ($row in @($MainRows)) {
                            if ([string]::IsNullOrWhiteSpace([string]$row.Section)) { continue }
                            $writer.WriteStartElement([string]$row.Section)
                            $writer.WriteStartElement('current'); if($row.CurrentActual -ne ''){$writer.WriteAttributeString('actual',[string]$row.CurrentActual)}; if($row.CurrentTime -ne ''){$writer.WriteAttributeString('time',[string]$row.CurrentTime)}; if($row.CurrentDuration -ne ''){$writer.WriteAttributeString('duration',[string]$row.CurrentDuration)}; $writer.WriteEndElement()
                            $writer.WriteStartElement('limits'); if($row.LimitsMin -ne ''){$writer.WriteAttributeString('min',[string]$row.LimitsMin)}; if($row.LimitsMax -ne ''){$writer.WriteAttributeString('max',[string]$row.LimitsMax)}; $writer.WriteEndElement()
                            $writer.WriteStartElement('timelimits'); if($row.TimeMin -ne ''){$writer.WriteAttributeString('min',[string]$row.TimeMin)}; if($row.TimeMax -ne ''){$writer.WriteAttributeString('max',[string]$row.TimeMax)}; $writer.WriteEndElement()
                            $writer.WriteStartElement('changelimits'); if($row.ChangeMin -ne ''){$writer.WriteAttributeString('min',[string]$row.ChangeMin)}; if($row.ChangeMax -ne ''){$writer.WriteAttributeString('max',[string]$row.ChangeMax)}; $writer.WriteEndElement()
                            if ($row.ThresholdMin -ne '' -or $row.ThresholdMax -ne '' -or $row.ThresholdEnd -ne '') { $writer.WriteStartElement('thresholds'); if($row.ThresholdMin -ne ''){$writer.WriteAttributeString('min',[string]$row.ThresholdMin)}; if($row.ThresholdMax -ne ''){$writer.WriteAttributeString('max',[string]$row.ThresholdMax)}; if($row.ThresholdEnd -ne ''){$writer.WriteAttributeString('end',[string]$row.ThresholdEnd)}; $writer.WriteEndElement() }
                            $writer.WriteEndElement()
                        }
                        $writer.WriteEndElement()
                    }
                    'MapGroupPos' {
                        $writer.WriteStartElement('map')
                        foreach ($row in @($MainRows)) { if([string]::IsNullOrWhiteSpace([string]$row.Name)){continue}; $writer.WriteStartElement('group'); $writer.WriteAttributeString('name',[string]$row.Name); $writer.WriteAttributeString('pos',((@([string]$row.PosX,[string]$row.PosY,[string]$row.PosZ) -join ' ').Trim())); $writer.WriteAttributeString('rpy',((@([string]$row.RpyX,[string]$row.RpyY,[string]$row.RpyZ) -join ' ').Trim())); if($row.A -ne ''){$writer.WriteAttributeString('a',[string]$row.A)}; $writer.WriteEndElement() }
                        $writer.WriteEndElement()
                    }
                    'MapGroupCluster' {
                        $writer.WriteStartElement('map')
                        foreach ($row in @($MainRows)) { if([string]::IsNullOrWhiteSpace([string]$row.Name)){continue}; $writer.WriteStartElement('group'); $writer.WriteAttributeString('name',[string]$row.Name); $writer.WriteAttributeString('pos',((@([string]$row.PosX,[string]$row.PosY,[string]$row.PosZ) -join ' ').Trim())); if($row.A -ne ''){$writer.WriteAttributeString('a',[string]$row.A)}; $writer.WriteEndElement() }
                        $writer.WriteEndElement()
                    }
                    'MapGroupDirt' {
                        $writer.WriteStartElement('map')
                        foreach ($row in @($MainRows)) { if([string]::IsNullOrWhiteSpace([string]$row.Name)){continue}; $writer.WriteStartElement('group'); $writer.WriteAttributeString('name',[string]$row.Name); $writer.WriteAttributeString('pos',((@([string]$row.PosX,[string]$row.PosY,[string]$row.PosZ) -join ' ').Trim())); if($row.A -ne ''){$writer.WriteAttributeString('a',[string]$row.A)}; $writer.WriteEndElement() }
                        $writer.WriteEndElement()
                    }
                    'MapClusterProto' {
                        $writer.WriteStartElement('prototype'); $writer.WriteStartElement('clusters')
                        foreach ($row in @($MainRows)) { if([string]::IsNullOrWhiteSpace([string]$row.Name)){continue}; $writer.WriteStartElement('export'); $writer.WriteAttributeString('name',[string]$row.Name); if($row.Shape -ne ''){$writer.WriteAttributeString('shape',[string]$row.Shape)}; $writer.WriteEndElement() }
                        $writer.WriteEndElement(); $writer.WriteEndElement()
                    }
                    'MapGroupProto' {
                        $writer.WriteStartElement('prototype')
                        $groupBuckets = @{}
                        foreach ($row in @($MainRows)) { $gk = [string]$row.GroupName + '|' + [string]$row.GroupLootMax + '|' + [string]$row.Usages; if (-not $groupBuckets.ContainsKey($gk)) { $groupBuckets[$gk] = @() }; $groupBuckets[$gk] += $row }
                        foreach ($gk in @($groupBuckets.Keys)) {
                            $grows = @($groupBuckets[$gk]); if ($grows.Count -eq 0) { continue }
                            $g0 = $grows[0]
                            $writer.WriteStartElement('group'); $writer.WriteAttributeString('name',[string]$g0.GroupName); if($g0.GroupLootMax -ne ''){$writer.WriteAttributeString('lootmax',[string]$g0.GroupLootMax)}
                            foreach ($usage in @(([string]$g0.Usages).Split(',', [System.StringSplitOptions]::RemoveEmptyEntries))) { $u=$usage.Trim(); if($u -eq ''){continue}; $writer.WriteStartElement('usage'); $writer.WriteAttributeString('name',$u); $writer.WriteEndElement() }
                            $containerBuckets = @{}
                            foreach ($row in $grows) { $ck = [string]$row.ContainerName + '|' + [string]$row.ContainerLootMax + '|' + [string]$row.Categories + '|' + [string]$row.Tags; if(-not $containerBuckets.ContainsKey($ck)){$containerBuckets[$ck]=@()}; $containerBuckets[$ck]+=$row }
                            foreach ($ck in @($containerBuckets.Keys)) {
                                $crows = @($containerBuckets[$ck]); $c0 = $crows[0]
                                $writer.WriteStartElement('container'); $writer.WriteAttributeString('name',[string]$c0.ContainerName); if($c0.ContainerLootMax -ne ''){$writer.WriteAttributeString('lootmax',[string]$c0.ContainerLootMax)}
                                foreach ($cat in @(([string]$c0.Categories).Split(',', [System.StringSplitOptions]::RemoveEmptyEntries))) { $v=$cat.Trim(); if($v -eq ''){continue}; $writer.WriteStartElement('category'); $writer.WriteAttributeString('name',$v); $writer.WriteEndElement() }
                                foreach ($tag in @(([string]$c0.Tags).Split(',', [System.StringSplitOptions]::RemoveEmptyEntries))) { $v=$tag.Trim(); if($v -eq ''){continue}; $writer.WriteStartElement('tag'); $writer.WriteAttributeString('name',$v); $writer.WriteEndElement() }
                                foreach ($row in $crows) { if([string]::IsNullOrWhiteSpace([string]$row.Pos)){continue}; $writer.WriteStartElement('point'); $writer.WriteAttributeString('pos',[string]$row.Pos); if($row.Range -ne ''){$writer.WriteAttributeString('range',[string]$row.Range)}; if($row.Height -ne ''){$writer.WriteAttributeString('height',[string]$row.Height)}; if($row.Flags -ne ''){$writer.WriteAttributeString('flags',[string]$row.Flags)}; $writer.WriteEndElement() }
                                $writer.WriteEndElement()
                            }
                            $writer.WriteEndElement()
                        }
                        $writer.WriteEndElement()
                    }
                }
                $writer.WriteEndDocument()
            }
            finally { if ($writer) { $writer.Flush(); $writer.Dispose() } }

            $xmlText = [System.Text.Encoding]::UTF8.GetString($memoryStream.ToArray())
            [void](Write-UGSMGameDayZTextFileSafe -Path $Path -Content $xmlText)
        }.GetNewClosure()

        $btnAddMiscRow.Add_Click({
            $targetGrid = if ($gridMiscSub.Visible -and $gridMiscSub.Focused) { $gridMiscSub } else { $gridMiscMain }
            if ($targetGrid -eq $gridMiscSub) {
                [void]$gridMiscSub.Rows.Add('0','0')
            }
            else {
                $vals = @(); foreach ($col in @($miscEditorState.MainColumns)) { $vals += '' }
                [void]$gridMiscMain.Rows.Add($vals)
            }
            $lblItemCount.Text = ('Rows: ' + $gridMiscMain.Rows.Count + $(if ($gridMiscSub.Visible) { '  Safe: ' + $gridMiscSub.Rows.Count } else { '' }))
        }.GetNewClosure())

        $btnRemoveMiscRow.Add_Click({
            $targetGrid = if ($gridMiscSub.Visible -and $gridMiscSub.Focused) { $gridMiscSub } else { $gridMiscMain }
            foreach ($row in @($targetGrid.SelectedRows)) {
                if ($row -and -not $row.IsNewRow) { $targetGrid.Rows.Remove($row) }
            }
            $lblItemCount.Text = ('Rows: ' + $gridMiscMain.Rows.Count + $(if ($gridMiscSub.Visible) { '  Safe: ' + $gridMiscSub.Rows.Count } else { '' }))
        }.GetNewClosure())

        $resizeXmlLayout = {
            $usableWidth = [Math]::Max(900, $rootPanel.ClientSize.Width)
            $usableHeight = [Math]::Max(300, $rootPanel.ClientSize.Height)

            $topBar.Width = $usableWidth
            $topTools.Width = $usableWidth
            $txtPath.Width = $usableWidth

            $detailsWidth = 370
            $gap = 12
            $gridWidth = [Math]::Max(520, $usableWidth - $detailsWidth - $gap)

            $gridTypes.Width = $gridWidth
            $gridEvents.Width = $gridWidth
            $gridEventSpawns.Width = $usableWidth
            $gridSpawnableTypes.Width = $gridWidth
            $gridVariables.Width = $usableWidth
            $gridEconomy.Width = $usableWidth
            $txtXml.Width = $usableWidth

            $editorHeight = [Math]::Max(240, $usableHeight - 220)
            $gridTypes.Height = $editorHeight
            $gridEvents.Height = $editorHeight
            $gridEventSpawns.Height = $editorHeight
            $gridSpawnableTypes.Height = $editorHeight
            $gridVariables.Height = $editorHeight
            $gridEconomy.Height = $editorHeight
            $txtXml.Height = $editorHeight

            $detailsPanel.Location = New-Object System.Drawing.Point(($gridWidth + $gap), 210)
            $detailsPanel.Size = New-Object System.Drawing.Size($detailsWidth, $editorHeight)

            $eventDetailsPanel.Location = New-Object System.Drawing.Point(($gridWidth + $gap), 210)
            $eventDetailsPanel.Size = New-Object System.Drawing.Size($detailsWidth, $editorHeight)

            $spawnDetailsPanel.Location = New-Object System.Drawing.Point(($gridWidth + $gap), 210)
            $spawnDetailsPanel.Size = New-Object System.Drawing.Size($detailsWidth, $editorHeight)
            $txtSpawnPreview.Size = New-Object System.Drawing.Size(($detailsWidth - 24), [Math]::Max(120, $editorHeight - 166))
            $btnApplySpawnPreview.Top = $editorHeight - 40

            if ($cfgGameplayPanel -is [System.Windows.Forms.Control]) {
                $cfgGameplayPanel.Location = New-Object System.Drawing.Point(0, 210)
                $cfgGameplayPanel.Size = New-Object System.Drawing.Size($usableWidth, $editorHeight)
            }

            if ($cfgGameplayInnerPanel -is [System.Windows.Forms.Control]) {
                $cfgGameplayInnerPanel.Size = New-Object System.Drawing.Size(
                    [Math]::Max(1080, $cfgGameplayPanel.ClientSize.Width - 20),
                    [Math]::Max(520, $cfgGameplayPanel.ClientSize.Height - 20)
                )
            }

            if ($cfgEnvironmentPanel -is [System.Windows.Forms.Control]) {
                $cfgEnvironmentPanel.Location = New-Object System.Drawing.Point(0, 210)
                $cfgEnvironmentPanel.Size = New-Object System.Drawing.Size($usableWidth, $editorHeight)
                $gridEnvFiles.Height = [Math]::Max(160, [Math]::Min(260, $editorHeight - 20))
                $gridEnvTerritories.Height = $gridEnvFiles.Height
                $gridEnvTerritories.Width = [Math]::Max(520, $usableWidth - 552)
            }

            if ($territoryPanel -is [System.Windows.Forms.Control]) {
                $territoryPanel.Location = New-Object System.Drawing.Point(0, 210)
                $territoryPanel.Size = New-Object System.Drawing.Size($usableWidth, $editorHeight)
                $gridTerritoryZones.Size = New-Object System.Drawing.Size($usableWidth, [Math]::Max(220, $editorHeight - 42))
            }

            if ($cfgEconomyCorePanel -is [System.Windows.Forms.Control]) {
                $cfgEconomyCorePanel.Location = New-Object System.Drawing.Point(0, 210)
                $cfgEconomyCorePanel.Size = New-Object System.Drawing.Size($usableWidth, $editorHeight)
                $gridEconomyRootClasses.Width = [Math]::Max(520, $usableWidth - 560)
                $gridEconomyDefaults.Width = [Math]::Max(520, $usableWidth - 560)
                $gridEconomyDefaults.Height = [Math]::Max(180, $editorHeight - 308)
            }

            if ($cfgEventGroupsPanel -is [System.Windows.Forms.Control]) {
                $cfgEventGroupsPanel.Location = New-Object System.Drawing.Point(0, 210)
                $cfgEventGroupsPanel.Size = New-Object System.Drawing.Size($usableWidth, $editorHeight)
                $gridEventGroups.Size = New-Object System.Drawing.Size($usableWidth, $editorHeight)
            }

            if ($cfgIgnoreListPanel -is [System.Windows.Forms.Control]) {
                $cfgIgnoreListPanel.Location = New-Object System.Drawing.Point(0, 210)
                $cfgIgnoreListPanel.Size = New-Object System.Drawing.Size($usableWidth, $editorHeight)
                $gridIgnoreList.Size = New-Object System.Drawing.Size($usableWidth, $editorHeight)
            }

            if ($miscEditorPanel -is [System.Windows.Forms.Control]) {
                $miscEditorPanel.Location = New-Object System.Drawing.Point(0, 210)
                $miscEditorPanel.Size = New-Object System.Drawing.Size($usableWidth, $editorHeight)
                if ($gridMiscSub.Visible) {
                    $mainHeight = [Math]::Max(140, [int](($editorHeight - 60) * 0.58))
                    $subTop = 24 + $mainHeight + 26
                    $gridMiscMain.Size = New-Object System.Drawing.Size($usableWidth, $mainHeight)
                    $lblMiscSub.Location = New-Object System.Drawing.Point(0, (24 + $mainHeight + 6))
                    $gridMiscSub.Location = New-Object System.Drawing.Point(0, $subTop)
                    $gridMiscSub.Size = New-Object System.Drawing.Size($usableWidth, [Math]::Max(100, $editorHeight - $subTop))
                }
                else {
                    $gridMiscMain.Size = New-Object System.Drawing.Size($usableWidth, $editorHeight)
                }
            }

            # Top tools layout
            $searchWidth = [Math]::Max(220, [Math]::Min(360, $usableWidth - 980))
            $txtSearch.Width = $searchWidth

            $btnSearch.Left = $txtSearch.Right + 10
            $btnShowAll.Left = $btnSearch.Right + 10

            $lblCategory.Left = $btnShowAll.Right + 20
            $cmbCategory.Left = $lblCategory.Right + 8

            if ($cmbCategory.Left + $cmbCategory.Width + 20 -gt $usableWidth) {
                $cmbCategory.Width = [Math]::Max(100, $usableWidth - $cmbCategory.Left - 20)
            }

            $txtBulkValue.Width = 110
            $btnApplySelected.Left = $txtBulkValue.Right + 12
            $btnApplyAll.Left = $btnApplySelected.Right + 10
            $lblItemCount.Left = $btnApplyAll.Right + 16

            if ($lblItemCount.Left + $lblItemCount.Width -gt $usableWidth) {
                $lblItemCount.Left = [Math]::Max($btnApplyAll.Right + 10, $usableWidth - $lblItemCount.Width - 10)
            }
        }.GetNewClosure()

        $rootPanel.Add_Resize({ & $resizeXmlLayout }.GetNewClosure())

        $xmlModComboMap = @{}

        $refreshXmlModCombo = {
            try {
                $selectedId = ''
                if ($cmbXmlMod.SelectedItem) {
                    $selectedText = [string]$cmbXmlMod.SelectedItem
                    if ($selectedText -match '\((\d{6,})\)\s*$') { $selectedId = [string]$Matches[1] }
                }

                $cmbXmlMod.Items.Clear()
                $xmlModComboMap = @{}

                $mods = @()

                # First preference: use the current DayZ index cache, because that reflects
                # the last Build DayZ Index Cache result and does not depend on a stale UI instance object.
                try {
                    if (Get-Command -Name Get-UGSMDayZInstanceStoragePaths -ErrorAction SilentlyContinue) {
                        $paths = Get-UGSMDayZInstanceStoragePaths -Instance $xmlInstance -Create:$false
                        $activeModsPath = [string]$paths.ActiveModsCachePath
                        if (-not [string]::IsNullOrWhiteSpace($activeModsPath) -and (Test-Path -LiteralPath $activeModsPath -PathType Leaf)) {
                            $cacheData = Get-Content -LiteralPath $activeModsPath -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
                            if ($cacheData -and $cacheData.PSObject.Properties.Name -contains 'Mods') {
                                $mods = @($cacheData.Mods)
                            }
                        }
                    }
                }
                catch { $mods = @() }

                # Second preference: read the latest folder instance.json from disk.
                if (@($mods).Count -eq 0) {
                    try {
                        if (Get-Command -Name Get-UGSMDayZInstanceDefinitionPath -ErrorAction SilentlyContinue) {
                            $instanceJsonPath = [string](Get-UGSMDayZInstanceDefinitionPath -Instance $xmlInstance -Create:$false)
                            if (-not [string]::IsNullOrWhiteSpace($instanceJsonPath) -and (Test-Path -LiteralPath $instanceJsonPath -PathType Leaf)) {
                                $diskInstance = Get-Content -LiteralPath $instanceJsonPath -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
                                if ($diskInstance -and $diskInstance.PSObject.Properties.Name -contains 'Mods') {
                                    $mods = @(Normalize-UGSMGameDayZModEntries -Mods @($diskInstance.Mods))
                                }
                            }
                        }
                    }
                    catch { $mods = @() }
                }

                # Final fallback: use the live instance object.
                if (@($mods).Count -eq 0) {
                    try { $mods = @(Get-UGSMGameDayZProfileMods -Instance $xmlInstance) } catch { $mods = @() }
                }

                foreach ($mod in @($mods)) {
                    if ($null -eq $mod) { continue }

                    $enabled = $true
                    if ($mod.PSObject.Properties.Name -contains 'Enabled') { $enabled = [bool]$mod.Enabled }
                    if (-not $enabled) { continue }

                    $id = ''
                    foreach ($idName in @('Id', 'ModId', 'WorkshopId', 'WorkshopID')) {
                        if ($mod.PSObject.Properties.Name -contains $idName) {
                            $id = [string]$mod.$idName
                            break
                        }
                    }

                    if ([string]::IsNullOrWhiteSpace($id)) { continue }
                    $id = Convert-UGSMGameDayZWorkshopInputToId -InputText $id
                    if ([string]::IsNullOrWhiteSpace($id)) { continue }

                    $name = ''
                    foreach ($nameProperty in @('Name', 'ModName', 'DisplayName')) {
                        if ($mod.PSObject.Properties.Name -contains $nameProperty) {
                            $name = [string]$mod.$nameProperty
                            break
                        }
                    }
                    # Prefer a friendly mod name. Some cache entries only have the id,
                    # so resolve the Workshop folder name the same way the Mods tab does.
                    if ([string]::IsNullOrWhiteSpace($name) -or $name -eq $id) {
                        try {
                            $sourcePath = ''
                            if ($mod.PSObject.Properties.Name -contains 'SourcePath') { $sourcePath = [string]$mod.SourcePath }
                            if ([string]::IsNullOrWhiteSpace($sourcePath)) {
                                $sourcePath = Resolve-UGSMGameDayZWorkshopModSourcePath -Instance $xmlInstance -Mod $mod
                            }

                            if (-not [string]::IsNullOrWhiteSpace($sourcePath) -and (Test-Path -LiteralPath $sourcePath -PathType Container)) {
                                $resolvedName = Get-UGSMGameDayZModNameFromSource -SourcePath $sourcePath -FallbackId $id
                                if (-not [string]::IsNullOrWhiteSpace($resolvedName)) {
                                    $name = [string]$resolvedName
                                }
                            }
                        }
                        catch { }
                    }

                    if ([string]::IsNullOrWhiteSpace($name)) { $name = $id }

                    $label = ('{0} ({1})' -f $name, $id)
                    $xmlModComboMap[$label] = $id
                    [void]$cmbXmlMod.Items.Add($label)
                }

                if ($cmbXmlMod.Items.Count -gt 0) {
                    $indexToSelect = 0
                    if (-not [string]::IsNullOrWhiteSpace($selectedId)) {
                        for ($i = 0; $i -lt $cmbXmlMod.Items.Count; $i++) {
                            $label = [string]$cmbXmlMod.Items[$i]
                            if ($xmlModComboMap.ContainsKey($label) -and [string]$xmlModComboMap[$label] -eq $selectedId) {
                                $indexToSelect = $i
                                break
                            }
                        }
                    }
                    $cmbXmlMod.SelectedIndex = $indexToSelect
                }
            }
            catch {
                if ($xmlStatusLabel) { $xmlStatusLabel.Text = 'Refreshing XML mod list failed: ' + $_.Exception.Message }
            }
        }.GetNewClosure()

        $getSelectedXmlModId = {
            if (-not $cmbXmlMod.SelectedItem) {
                & $refreshXmlModCombo
            }
            if (-not $cmbXmlMod.SelectedItem) { throw 'Select an active mod in the XML tab first. Build the DayZ index cache after adding mods, then reopen this dropdown.' }

            $label = [string]$cmbXmlMod.SelectedItem
            if ($xmlModComboMap.ContainsKey($label)) {
                $id = [string]$xmlModComboMap[$label]
                if (-not [string]::IsNullOrWhiteSpace($id)) { return $id }
            }

            if ($label -match '\((\d{6,})\)\s*$') { return [string]$Matches[1] }

            throw 'Selected XML mod does not have a workshop id.'
        }.GetNewClosure()

        & $refreshXmlModCombo
        $cmbXmlMod.Add_DropDown({ & $refreshXmlModCombo }.GetNewClosure())

        $ensureDayZFilesServiceLoaded = {
            param([string]$RequiredCommand = 'Invoke-UGSMDayZPreviewRemovedModTypesCleanup')

            if (Get-Command -Name $RequiredCommand -ErrorAction SilentlyContinue) {
                return $true
            }

            $candidatePaths = @()

            if (-not [string]::IsNullOrWhiteSpace([string]$PSScriptRoot)) {
                $candidatePaths += (Join-Path $PSScriptRoot 'UGSM_Service_DayZFiles.ps1')
                $projectRoot = Split-Path -Parent $PSScriptRoot
                if (-not [string]::IsNullOrWhiteSpace([string]$projectRoot)) {
                    $candidatePaths += (Join-Path (Join-Path $projectRoot 'Services') 'UGSM_Service_DayZFiles.ps1')
                }
            }

            try {
                $scriptPath = [string]$MyInvocation.MyCommand.Path
                if (-not [string]::IsNullOrWhiteSpace($scriptPath)) {
                    $scriptFolder = Split-Path -Parent $scriptPath
                    $candidatePaths += (Join-Path $scriptFolder 'UGSM_Service_DayZFiles.ps1')
                    $projectRootFromScript = Split-Path -Parent $scriptFolder
                    if (-not [string]::IsNullOrWhiteSpace([string]$projectRootFromScript)) {
                        $candidatePaths += (Join-Path (Join-Path $projectRootFromScript 'Services') 'UGSM_Service_DayZFiles.ps1')
                    }
                }
            }
            catch { }

            if ($global:UGSM_SourceFolder) {
                $candidatePaths += (Join-Path ([string]$global:UGSM_SourceFolder) 'UGSM_Service_DayZFiles.ps1')
            }

            if ($global:UGSM_SourcePath) {
                $candidatePaths += (Join-Path ([string]$global:UGSM_SourcePath) 'UGSM_Service_DayZFiles.ps1')
            }

            foreach ($candidatePath in @($candidatePaths | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) } | Select-Object -Unique)) {
                if (Test-Path -LiteralPath $candidatePath -PathType Leaf) {
                    try {
                        . $candidatePath
                        if (Get-Command -Name $RequiredCommand -ErrorAction SilentlyContinue) {
                            return $true
                        }
                    }
                    catch { }
                }
            }

            return $false
        }.GetNewClosure()

        $getSelectedKind = {
            if ($cmbKind.SelectedItem) { return [string]$cmbKind.SelectedItem }
            return 'Types'
        }.GetNewClosure()

        $refreshEditorMode = {
            $kind = & $getSelectedKind
            $isTypes = ($kind -eq 'Types')
            $isEvents = ($kind -eq 'Events')
            $isEventSpawns = ($kind -eq 'EventSpawns')
            $isSpawnableTypes = ($kind -eq 'SpawnableTypes')
            $isGlobals = ($kind -eq 'Globals')
            $isEconomy = ($kind -eq 'Economy')
            $isCfgGameplay = ($kind -eq 'CfgGameplay')
            $isCfgEconomyCore = ($kind -eq 'CfgEconomyCore')
            $isCfgEventGroups = ($kind -eq 'CfgEventGroups')
            $isCfgIgnoreList = ($kind -eq 'CfgIgnoreList')
            $isCfgEnvironment = ($kind -eq 'CfgEnvironment')
            $isTerritoryZones = ($kind -eq 'TerritoryZones')

            $gridTypes.Visible = $isTypes
            $detailsPanel.Visible = $isTypes

            $gridEvents.Visible = $isEvents
            $eventDetailsPanel.Visible = $isEvents

            $gridEventSpawns.Visible = $isEventSpawns

            $gridSpawnableTypes.Visible = $isSpawnableTypes
            $spawnDetailsPanel.Visible = $isSpawnableTypes

            $gridVariables.Visible = $isGlobals

            if ($gridEconomy -is [System.Windows.Forms.Control]) {
                $gridEconomy.Visible = $isEconomy
            }

            if ($cfgGameplayPanel -is [System.Windows.Forms.Control]) {
                $cfgGameplayPanel.Visible = $isCfgGameplay
            }

            if ($cfgEconomyCorePanel -is [System.Windows.Forms.Control]) {
                $cfgEconomyCorePanel.Visible = $isCfgEconomyCore
            }

            if ($cfgEventGroupsPanel -is [System.Windows.Forms.Control]) {
                $cfgEventGroupsPanel.Visible = $isCfgEventGroups
            }

            if ($cfgIgnoreListPanel -is [System.Windows.Forms.Control]) {
                $cfgIgnoreListPanel.Visible = $isCfgIgnoreList
            }

            if ($cfgEnvironmentPanel -is [System.Windows.Forms.Control]) {
                $cfgEnvironmentPanel.Visible = $isCfgEnvironment
            }

            if ($territoryPanel -is [System.Windows.Forms.Control]) {
                $territoryPanel.Visible = $isTerritoryZones
            }

            $isMiscEditor = ($miscEditorKinds -contains $kind)
            if ($miscEditorPanel -is [System.Windows.Forms.Control]) {
                $miscEditorPanel.Visible = $isMiscEditor
            }

            $isRawXml = (-not ($isTypes -or $isEvents -or $isEventSpawns -or $isSpawnableTypes -or $isGlobals -or $isEconomy -or $isCfgGameplay -or $isCfgEconomyCore -or $isCfgEventGroups -or $isCfgIgnoreList -or $isCfgEnvironment -or $isTerritoryZones -or $isMiscEditor))
            $txtXml.Visible = ($kind -eq 'Messages' -or $isRawXml)
            $topTools.Visible = ($isTypes -or $isEvents -or $isEventSpawns -or $isSpawnableTypes -or $isGlobals -or $isEconomy -or $isCfgGameplay -or $isCfgEconomyCore -or $isCfgEventGroups -or $isCfgIgnoreList -or $isCfgEnvironment -or $isTerritoryZones -or $isMiscEditor)

            $lblCategory.Visible = $isTypes
            $cmbCategory.Visible = $isTypes
            $lblBulk.Visible = $isTypes
            $cmbBulkField.Visible = $isTypes
            $txtBulkValue.Visible = $isTypes
            $btnApplySelected.Visible = $isTypes
            $btnApplyAll.Visible = $isTypes
            $btnAddEventSpawn.Visible = $isEventSpawns
            $btnRemoveEventSpawn.Visible = $isEventSpawns
            $btnAddEventGroupChild.Visible = $isCfgEventGroups
            $btnRemoveEventGroupChild.Visible = $isCfgEventGroups
            $btnAddIgnoreType.Visible = $isCfgIgnoreList
            $btnRemoveIgnoreType.Visible = $isCfgIgnoreList
            $btnAddMiscRow.Visible = $isMiscEditor
            $btnRemoveMiscRow.Visible = $isMiscEditor

            if ($isCfgEventGroups) {
                $btnAddEventGroupChild.Location = New-Object System.Drawing.Point(720, 28)
                $btnAddEventGroupChild.Size = New-Object System.Drawing.Size(150, 28)
                $btnRemoveEventGroupChild.Location = New-Object System.Drawing.Point(882, 28)
                $btnRemoveEventGroupChild.Size = New-Object System.Drawing.Size(180, 28)
            }

            if ($isCfgIgnoreList) {
                $btnAddIgnoreType.Location = New-Object System.Drawing.Point(720, 28)
                $btnAddIgnoreType.Size = New-Object System.Drawing.Size(150, 28)
                $btnRemoveIgnoreType.Location = New-Object System.Drawing.Point(882, 28)
                $btnRemoveIgnoreType.Size = New-Object System.Drawing.Size(220, 28)
            }

            $isTypesFile = ($kind -eq 'Types')
            $isSpawnableTypesFile = ($kind -eq 'SpawnableTypes')
            $isEventsFile = ($kind -eq 'Events')
            $supportsSelectedModXmlActions = ($isTypesFile -or $isSpawnableTypesFile -or $isEventsFile)

            $btnBackupXml.Enabled = $supportsSelectedModXmlActions
            $btnMergeXml.Enabled = $supportsSelectedModXmlActions
            $btnXmlPreviewRemoved.Enabled = $supportsSelectedModXmlActions
            $btnXmlApplyRemoved.Enabled = $supportsSelectedModXmlActions
            $cmbXmlMod.Enabled = $supportsSelectedModXmlActions

            if ($isSpawnableTypesFile) {
                $btnBackupXml.Text = 'Preview Selected cfgspawnabletypes.xml'
                $btnMergeXml.Text = 'Apply Selected cfgspawnabletypes.xml'
                $btnXmlPreviewRemoved.Text = 'Preview Removed cfgspawnabletypes Cleanup'
                $btnXmlApplyRemoved.Text = 'Apply Removed cfgspawnabletypes Cleanup'
            }
            elseif ($isEventsFile) {
                $btnBackupXml.Text = 'Preview Selected events.xml'
                $btnMergeXml.Text = 'Apply Selected events.xml'
                $btnXmlPreviewRemoved.Text = 'Preview Removed events.xml Cleanup'
                $btnXmlApplyRemoved.Text = 'Apply Removed events.xml Cleanup'
            }
            else {
                $btnBackupXml.Text = 'Preview Selected types.xml'
                $btnMergeXml.Text = 'Apply Selected types.xml'
                $btnXmlPreviewRemoved.Text = 'Preview Removed types.xml Cleanup'
                $btnXmlApplyRemoved.Text = 'Apply Removed types.xml Cleanup'
            }
        }.GetNewClosure()

        $xmlTypeState = [ordered]@{
            AllTypeRows           = @()
            IsLoadingTypes        = $false
            IsUpdatingTypeDetails = $false
        }

        $xmlEventState = [ordered]@{
            AllEventRows           = @()
            IsLoadingEvents        = $false
            IsUpdatingEventDetails = $false
        }

        $xmlEventSpawnState = [ordered]@{
            AllRows   = @()
            IsLoading = $false
        }

        $xmlSpawnableTypeState = [ordered]@{
            AllRows           = @()
            IsLoading         = $false
            IsUpdatingDetails = $false
        }

        $xmlVariableState = [ordered]@{
            AllRows    = @()
            IsLoading  = $false
            ActiveKind = ''
        }

        $cfgGameplayState = [pscustomobject]@{
            IsLoading = $false
            Data      = $null
            Rows      = @()
            Controls  = @()
        }

        $syncGridToAllTypeRows = {
            if ($xmlTypeState.IsLoadingTypes) { return }
            if ((& $getSelectedKind) -ne 'Types') { return }
            if (-not $gridTypes.Visible) { return }
            if ($gridTypes.Rows.Count -le 0) { return }

            if ($gridTypes.IsCurrentCellInEditMode) {
                [void]$gridTypes.EndEdit()
            }

            if ($gridTypes.EditingControl) {
                [void]$gridTypes.CommitEdit([System.Windows.Forms.DataGridViewDataErrorContexts]::Commit)
            }

            $visibleRows = @(Get-UGSMGameDayZTypesGridRows -Grid $gridTypes)
            if (@($visibleRows).Count -le 0) { return }

            $rowMap = @{}
            foreach ($r in $visibleRows) {
                if ($r -and -not [string]::IsNullOrWhiteSpace([string]$r.Name)) {
                    $rowMap[[string]$r.Name] = $r
                }
            }

            $merged = @()
            foreach ($existing in @($xmlTypeState.AllTypeRows)) {
                $key = [string]$existing.Name
                if ($rowMap.ContainsKey($key)) {
                    $merged += $rowMap[$key]
                    $rowMap.Remove($key)
                }
                else {
                    $merged += $existing
                }
            }

            foreach ($remaining in $rowMap.Values) {
                $merged += $remaining
            }

            $xmlTypeState.AllTypeRows = @($merged)
        }.GetNewClosure()

        $setCheckedValues = {
            param(
                [hashtable]$Map,
                [string[]]$Values
            )

            $valueSet = @{}
            foreach ($value in @($Values)) {
                if (-not [string]::IsNullOrWhiteSpace([string]$value)) {
                    $valueSet[$value.Trim()] = $true
                }
            }

            foreach ($key in @($Map.Keys)) {
                $Map[$key].Checked = $valueSet.ContainsKey($key)
            }
        }.GetNewClosure()

        $updateDetailsFromSelection = {
            if ($xmlTypeState.IsLoadingTypes) { return }

            $xmlTypeState.IsUpdatingTypeDetails = $true
            try {
                if (
                    -not $gridTypes.Visible -or
                    $gridTypes.IsDisposed -or
                    $gridTypes.SelectedRows.Count -le 0
                ) {
                    if ($lblSelectedName -and -not $lblSelectedName.IsDisposed) {
                        $lblSelectedName.Text = ''
                    }
                    & $setCheckedValues $usageCheckboxes @()
                    & $setCheckedValues $valueCheckboxes @()
                    & $setCheckedValues $flagCheckboxes @()
                    return
                }

                if ($gridTypes.SelectedRows.Count -gt 1) {
                    if ($lblSelectedName -and -not $lblSelectedName.IsDisposed) {
                        $lblSelectedName.AutoEllipsis = $true
                        $lblSelectedName.Text = ('Multiple selected: ' + $gridTypes.SelectedRows.Count)
                    }
                    & $setCheckedValues $usageCheckboxes @()
                    & $setCheckedValues $valueCheckboxes @()
                    & $setCheckedValues $flagCheckboxes @()
                    return
                }

                $row = $gridTypes.SelectedRows[0]
                if ($null -eq $row -or $row.IsNewRow) { return }

                $selectedName = [string]$row.Cells['Name'].Value
                if ([string]::IsNullOrWhiteSpace($selectedName)) {
                    $selectedName = ''
                }
                elseif ($selectedName.Length -gt 120) {
                    $selectedName = $selectedName.Substring(0, 120) + '...'
                }

                if ($lblSelectedName -and -not $lblSelectedName.IsDisposed) {
                    $lblSelectedName.AutoEllipsis = $true
                    $lblSelectedName.Text = $selectedName
                }

                $usageText = [string]$row.Cells['Usage'].Value
                $valueText = [string]$row.Cells['Value'].Value
                $delootText = [string]$row.Cells['Deloot'].Value

                $usageValues = @()
                if (-not [string]::IsNullOrWhiteSpace($usageText)) {
                    $usageValues = @(
                        $usageText -split ',' |
                        ForEach-Object { $_.Trim() } |
                        Where-Object { $_ -and $usageCheckboxes.ContainsKey($_) }
                    )
                }

                $valueValues = @()
                if (-not [string]::IsNullOrWhiteSpace($valueText)) {
                    $valueValues = @(
                        $valueText -split ',' |
                        ForEach-Object { $_.Trim() } |
                        Where-Object { $_ -and $valueCheckboxes.ContainsKey($_) }
                    )
                }

                $flagValues = @()
                if ($delootText -eq 'Yes' -or $delootText -eq '1' -or $delootText.ToLowerInvariant() -eq 'true') {
                    $flagValues += 'Deloot'
                }

                & $setCheckedValues $usageCheckboxes $usageValues
                & $setCheckedValues $valueCheckboxes $valueValues
                & $setCheckedValues $flagCheckboxes $flagValues
            }
            finally {
                $xmlTypeState.IsUpdatingTypeDetails = $false
            }
        }.GetNewClosure()

        $updateEventDetailsFromSelection = {
            if ($xmlEventState.IsLoadingEvents) { return }

            $xmlEventState.IsUpdatingEventDetails = $true
            try {
                if (-not $gridEvents.Visible -or $gridEvents.SelectedRows.Count -le 0) {
                    $lblEventSelectedName.Text = ''
                    $txtEventNominal.Text = ''
                    $txtEventMin.Text = ''
                    $txtEventMax.Text = ''
                    $txtEventLifetime.Text = ''
                    $txtEventRestock.Text = ''
                    $chkEventActive.Checked = $false
                    return
                }

                $row = $gridEvents.SelectedRows[0]
                if ($null -eq $row -or $row.IsNewRow) { return }

                $lblEventSelectedName.Text = [string]$row.Cells['Name'].Value
                $txtEventNominal.Text = [string]$row.Cells['Nominal'].Value
                $txtEventMin.Text = [string]$row.Cells['Min'].Value
                $txtEventMax.Text = [string]$row.Cells['Max'].Value
                $txtEventLifetime.Text = [string]$row.Cells['Lifetime'].Value
                $txtEventRestock.Text = [string]$row.Cells['Restock'].Value

                $activeText = [string]$row.Cells['Active'].Value
                $chkEventActive.Checked = ($activeText -eq '1' -or $activeText.ToLowerInvariant() -eq 'true')
            }
            finally {
                $xmlEventState.IsUpdatingEventDetails = $false
            }
        }.GetNewClosure()

        $writeCheckboxesToSelectedRow = {
            if ($xmlTypeState.IsLoadingTypes -or $xmlTypeState.IsUpdatingTypeDetails) { return }
            if (-not $gridTypes.Visible -or $gridTypes.SelectedRows.Count -le 0) { return }

            $usageValues = @()
            foreach ($name in $usageOptions) {
                if ($usageCheckboxes[$name].Checked) { $usageValues += $name }
            }

            $valueValues = @()
            foreach ($name in $valueOptions) {
                if ($valueCheckboxes[$name].Checked) { $valueValues += $name }
            }

            $usageText = ($usageValues -join ',')
            $valueText = ($valueValues -join ',')
            $delootText = if ($flagCheckboxes['Deloot'].Checked) { 'Yes' } else { 'No' }

            foreach ($row in @($gridTypes.SelectedRows)) {
                if ($null -eq $row -or $row.IsNewRow) { continue }
                $row.Cells['Usage'].Value = $usageText
                $row.Cells['Value'].Value = $valueText
                $row.Cells['Deloot'].Value = $delootText
            }

            & $syncGridToAllTypeRows
        }.GetNewClosure()

        $writeEventDetailsToSelectedRow = {
            if ($xmlEventState.IsLoadingEvents -or $xmlEventState.IsUpdatingEventDetails) { return }
            if (-not $gridEvents.Visible -or $gridEvents.SelectedRows.Count -ne 1) { return }

            $row = $gridEvents.SelectedRows[0]
            if ($null -eq $row -or $row.IsNewRow) { return }

            $activeValue = if ($chkEventActive.Checked) { '1' } else { '0' }

            $row.Cells['Nominal'].Value = [string]$txtEventNominal.Text
            $row.Cells['Min'].Value = [string]$txtEventMin.Text
            $row.Cells['Max'].Value = [string]$txtEventMax.Text
            $row.Cells['Lifetime'].Value = [string]$txtEventLifetime.Text
            $row.Cells['Restock'].Value = [string]$txtEventRestock.Text
            $row.Cells['Active'].Value = $activeValue

            if ($row.Tag) {
                $row.Tag.Nominal = [string]$txtEventNominal.Text
                $row.Tag.Min = [string]$txtEventMin.Text
                $row.Tag.Max = [string]$txtEventMax.Text
                $row.Tag.Lifetime = [string]$txtEventLifetime.Text
                $row.Tag.Restock = [string]$txtEventRestock.Text
                $row.Tag.Active = $activeValue
            }
        }.GetNewClosure()
        $updateSpawnableDetailsFromSelection = {
            if ($xmlSpawnableTypeState.IsLoading) { return }

            $xmlSpawnableTypeState.IsUpdatingDetails = $true
            try {
                if (-not $gridSpawnableTypes.Visible -or $gridSpawnableTypes.SelectedRows.Count -ne 1) {
                    $lblSpawnSelectedName.Text = ''
                    $lblSpawnSummary.Text = ''
                    $txtSpawnPreview.Text = ''
                    return
                }

                $row = $gridSpawnableTypes.SelectedRows[0]
                if ($null -eq $row -or $row.IsNewRow) { return }

                $name = [string]$row.Cells['Name'].Value
                $attachments = [string]$row.Cells['AttachmentsCount'].Value
                $cargo = [string]$row.Cells['CargoCount'].Value
                $damageMin = [string]$row.Cells['DamageMin'].Value
                $damageMax = [string]$row.Cells['DamageMax'].Value
                $tag = $row.Tag

                $lblSpawnSelectedName.Text = $name
                $lblSpawnSummary.Text = "Attachments: $attachments   Cargo: $cargo" + [Environment]::NewLine + "Damage Min/Max: $damageMin / $damageMax"
                $txtSpawnPreview.Text = if ($tag) { [string]$tag.OuterXml } else { '' }
            }
            finally {
                $xmlSpawnableTypeState.IsUpdatingDetails = $false
            }
        }.GetNewClosure()

        $applySpawnableTypeFilters = {
            if ((& $getSelectedKind) -ne 'SpawnableTypes') { return }

            $searchText = [string]$txtSearch.Text
            $filtered = @($xmlSpawnableTypeState.AllRows)

            if (-not [string]::IsNullOrWhiteSpace($searchText)) {
                $needle = $searchText.Trim().ToLowerInvariant()
                $filtered = @($filtered | Where-Object { ([string]$_.Name).ToLowerInvariant().Contains($needle) })
            }

            $gridSpawnableTypes.Rows.Clear()
            foreach ($row in @($filtered)) {
                $rowIndex = $gridSpawnableTypes.Rows.Add(
                    [string]$row.Name,
                    [string]$row.AttachmentsCount,
                    [string]$row.CargoCount,
                    [string]$row.HasAttachments,
                    [string]$row.HasCargo,
                    [string]$row.DamageMin,
                    [string]$row.DamageMax
                )
                $gridSpawnableTypes.Rows[$rowIndex].Tag = $row
            }

            $lblItemCount.Text = ('Items: ' + $gridSpawnableTypes.Rows.Count)

            if ($gridSpawnableTypes.Rows.Count -gt 0) {
                $gridSpawnableTypes.ClearSelection()
                $gridSpawnableTypes.Rows[0].Selected = $true
            }

            if ($updateSpawnableDetailsFromSelection -is [scriptblock]) {
                & $updateSpawnableDetailsFromSelection
            }
        }.GetNewClosure()

        $syncSpawnableGridToAllRows = {
            if ($xmlSpawnableTypeState.IsLoading) { return }
            if ((& $getSelectedKind) -ne 'SpawnableTypes') { return }

            $visibleRows = @(Get-UGSMGameDayZSpawnableTypesGridRows -Grid $gridSpawnableTypes)
            if (@($visibleRows).Count -le 0) { return }

            $rowMap = @{}
            foreach ($r in @($visibleRows)) {
                if ($r -and -not [string]::IsNullOrWhiteSpace([string]$r.Name)) {
                    $rowMap[[string]$r.Name] = $r
                }
            }

            $merged = @()
            foreach ($existing in @($xmlSpawnableTypeState.AllRows)) {
                $key = [string]$existing.Name
                if ($rowMap.ContainsKey($key)) {
                    $merged += $rowMap[$key]
                    $rowMap.Remove($key)
                }
                else {
                    $merged += $existing
                }
            }

            foreach ($remaining in $rowMap.Values) {
                $merged += $remaining
            }

            $xmlSpawnableTypeState.AllRows = @($merged)
        }.GetNewClosure()

        $applySpawnablePreviewToSelectedRow = {
            if ($xmlSpawnableTypeState.IsLoading -or $xmlSpawnableTypeState.IsUpdatingDetails) { return }
            if (-not $gridSpawnableTypes.Visible -or $gridSpawnableTypes.SelectedRows.Count -ne 1) { return }

            $row = $gridSpawnableTypes.SelectedRows[0]
            if ($null -eq $row -or $row.IsNewRow) { return }

            $xmlText = [string]$txtSpawnPreview.Text
            if ([string]::IsNullOrWhiteSpace($xmlText)) { return }

            $doc = New-Object System.Xml.XmlDocument
            try {
                $doc.LoadXml("<spawnabletypes>$xmlText</spawnabletypes>")
            }
            catch {
                throw "Invalid spawnable type XML: $($_.Exception.Message)"
            }

            $typeNode = $doc.DocumentElement.SelectSingleNode('./type')
            if ($null -eq $typeNode) {
                throw 'The selected node XML must contain exactly one <type> node.'
            }

            $name = [string]$typeNode.GetAttribute('name')
            if ([string]::IsNullOrWhiteSpace($name)) {
                throw "Spawnable type XML is missing the required 'name' attribute."
            }

            $attachmentsCount = @($typeNode.SelectNodes('./attachments/attachment')).Count
            $cargoCount = @($typeNode.SelectNodes('./cargo/item')).Count
            $damageNode = $typeNode.SelectSingleNode('./damage')
            $prettyXml = [string](Convert-UGSMGameDayZXmlNodeToPrettyString -Node $typeNode)

            $updatedRow = [pscustomobject]@{
                Name             = $name
                AttachmentsCount = $attachmentsCount
                CargoCount       = $cargoCount
                HasAttachments   = if ($typeNode.SelectSingleNode('./attachments')) { 'Yes' } else { 'No' }
                HasCargo         = if ($typeNode.SelectSingleNode('./cargo')) { 'Yes' } else { 'No' }
                DamageMin        = if ($damageNode) { [string]$damageNode.GetAttribute('min') } else { '' }
                DamageMax        = if ($damageNode) { [string]$damageNode.GetAttribute('max') } else { '' }
                OuterXml         = $prettyXml
            }

            $row.Cells['Name'].Value = [string]$updatedRow.Name
            $row.Cells['AttachmentsCount'].Value = [string]$updatedRow.AttachmentsCount
            $row.Cells['CargoCount'].Value = [string]$updatedRow.CargoCount
            $row.Cells['HasAttachments'].Value = [string]$updatedRow.HasAttachments
            $row.Cells['HasCargo'].Value = [string]$updatedRow.HasCargo
            $row.Cells['DamageMin'].Value = [string]$updatedRow.DamageMin
            $row.Cells['DamageMax'].Value = [string]$updatedRow.DamageMax
            $row.Tag = $updatedRow
            $txtSpawnPreview.Text = $prettyXml

            & $syncSpawnableGridToAllRows
            & $updateSpawnableDetailsFromSelection
        }.GetNewClosure()

        $applyGlobalsFilter = {
            $selectedKind = if ($cmbKind.SelectedItem) { [string]$cmbKind.SelectedItem } else { 'Types' }
            if ($selectedKind -ne 'Globals' -and $selectedKind -ne 'Economy') { return }

            $searchText = [string]$txtSearch.Text
            $rows = @($xmlVariableState.AllRows)

            if (-not [string]::IsNullOrWhiteSpace($searchText)) {
                $needle = $searchText.Trim().ToLowerInvariant()
                $rows = @($rows | Where-Object {
                        ([string]$_.Group).ToLowerInvariant().Contains($needle) -or
                        ([string]$_.Key).ToLowerInvariant().Contains($needle) -or
                        ([string]$_.Value).ToLowerInvariant().Contains($needle)
                    })
            }

            $gridVariables.Rows.Clear()
            foreach ($row in @($rows)) {
                $rowIndex = $gridVariables.Rows.Add(
                    [string]$row.Group,
                    [string]$row.Key,
                    [string]$row.Value,
                    [string]$row.SourcePath,
                    [string]$row.EntryType,
                    [string]$row.AttributeName
                )
                $gridVariables.Rows[$rowIndex].Tag = $row
            }

            $lblItemCount.Text = ('Items: ' + $gridVariables.Rows.Count)

            if ($gridVariables.Rows.Count -gt 0) {
                $gridVariables.ClearSelection()
                $gridVariables.Rows[0].Selected = $true
            }
        }.GetNewClosure()

        $applyCfgGameplayFilter = {
            $selectedKind = if ($cmbKind.SelectedItem) { [string]$cmbKind.SelectedItem } else { 'Types' }
            if ($selectedKind -ne 'CfgGameplay') { return }

            $searchText = [string]$txtSearch.Text
            $rows = @($cfgGameplayState.Rows)

            if (-not [string]::IsNullOrWhiteSpace($searchText)) {
                $needle = $searchText.Trim().ToLowerInvariant()
                $rows = @($rows | Where-Object {
                        ([string]$_.Section).ToLowerInvariant().Contains($needle) -or
                        ([string]$_.Name).ToLowerInvariant().Contains($needle) -or
                        ([string]$_.Value).ToLowerInvariant().Contains($needle)
                    })
            }

            $cfgGameplayInnerPanel.SuspendLayout()
            try {
                $cfgGameplayInnerPanel.Controls.Clear()
                $cfgGameplayState.Controls = @()

                $labelX = 18
                $editorX = 430
                $labelWidth = 390
                $editorWidth = [Math]::Max(520, $cfgGameplayPanel.ClientSize.Width - $editorX - 35)

                $y = 10
                $currentSection = ''

                foreach ($row in @($rows)) {
                    if ([string]$row.Section -ne $currentSection) {
                        $currentSection = [string]$row.Section

                        $sectionLabel = New-UGSMLabel -Text $currentSection -X 12 -Y $y -Width 900 -Height 24 -FontSize 10 -Style Bold -Color '#111111'
                        [void]$cfgGameplayInnerPanel.Controls.Add($sectionLabel)
                        $y += 30
                    }

                    $nameLabel = New-UGSMLabel -Text ([string]$row.Name) -X $labelX -Y ($y + 4) -Width $labelWidth -Height 20 -FontSize 8.5 -Color '#111111'
                    $nameLabel.AutoEllipsis = $true
                    $nameLabel.AutoSize = $false
                    [void]$cfgGameplayInnerPanel.Controls.Add($nameLabel)

                    if ($row.ValueType -eq 'bool') {
                        $chk = New-Object System.Windows.Forms.CheckBox
                        $chk.Location = New-Object System.Drawing.Point($editorX, $y)
                        $chk.Size = New-Object System.Drawing.Size(60, 22)
                        $chk.Checked = (([string]$row.Value).Trim().ToLowerInvariant() -eq 'true')
                        $chk.Tag = $row
                        $chk.ForeColor = [System.Drawing.Color]::Black
                        $chk.BackColor = [System.Drawing.Color]::Transparent
                        $chk.Add_CheckedChanged({
                                if ($cfgGameplayState.IsLoading) { return }
                                $tagRow = $this.Tag
                                if ($tagRow) {
                                    $tagRow.Value = if ($this.Checked) { 'true' } else { 'false' }
                                }
                            }.GetNewClosure())
                        [void]$cfgGameplayInnerPanel.Controls.Add($chk)
                        $cfgGameplayState.Controls += $chk
                        $y += 30
                    }
                    else {
                        $isLargeEditor = ($row.ValueType -eq 'array')

                        $txt = New-Object System.Windows.Forms.TextBox
                        $txt.Location = New-Object System.Drawing.Point($editorX, $y)
                        $txt.Width = $editorWidth
                        $txt.Text = [string]$row.Value
                        $txt.Tag = $row
                        $txt.Multiline = $isLargeEditor
                        $txt.WordWrap = $true
                        $txt.ScrollBars = if ($isLargeEditor) { 'Vertical' } else { 'None' }
                        $txt.BackColor = New-UGSMColor '#F2F5F9'
                        $txt.ForeColor = [System.Drawing.Color]::Black
                        $txt.BorderStyle = 'FixedSingle'

                        if ($isLargeEditor) {
                            $txt.Height = 70
                            $txt.AcceptsReturn = $true
                            $txt.AcceptsTab = $true
                            $txt.Font = New-Object System.Drawing.Font('Consolas', 8.5)
                        }
                        else {
                            $txt.Height = 22
                        }

                        $txt.Add_TextChanged({
                                if ($cfgGameplayState.IsLoading) { return }
                                $tagRow = $this.Tag
                                if ($tagRow) {
                                    $tagRow.Value = [string]$this.Text
                                }
                            }.GetNewClosure())

                        [void]$cfgGameplayInnerPanel.Controls.Add($txt)
                        $cfgGameplayState.Controls += $txt

                        $y += if ($isLargeEditor) { 80 } else { 30 }
                    }
                }

                $cfgGameplayInnerPanel.Size = New-Object System.Drawing.Size(
                    [Math]::Max(1200, $cfgGameplayPanel.ClientSize.Width - 15),
                    [Math]::Max(520, $y + 10)
                )

                $lblItemCount.Text = ('Items: ' + @($rows).Count)
            }
            finally {
                $cfgGameplayInnerPanel.ResumeLayout()
            }
        }.GetNewClosure()

        $gridEvents.Add_SelectionChanged({ & $updateEventDetailsFromSelection }.GetNewClosure())
        $gridSpawnableTypes.Add_SelectionChanged({ & $updateSpawnableDetailsFromSelection }.GetNewClosure())

        $txtEventNominal.Add_TextChanged({ & $writeEventDetailsToSelectedRow }.GetNewClosure())
        $txtEventMin.Add_TextChanged({ & $writeEventDetailsToSelectedRow }.GetNewClosure())
        $txtEventMax.Add_TextChanged({ & $writeEventDetailsToSelectedRow }.GetNewClosure())
        $txtEventLifetime.Add_TextChanged({ & $writeEventDetailsToSelectedRow }.GetNewClosure())
        $txtEventRestock.Add_TextChanged({ & $writeEventDetailsToSelectedRow }.GetNewClosure())
        $chkEventActive.Add_CheckedChanged({ & $writeEventDetailsToSelectedRow }.GetNewClosure())

        $refreshCategoryList = {
            $selected = if ($cmbCategory.SelectedItem) { [string]$cmbCategory.SelectedItem } else { 'All' }
            $categories = @('All') + @(
                $xmlTypeState.AllTypeRows |
                ForEach-Object { [string]$_.Category } |
                Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
                Sort-Object -Unique
            )

            $cmbCategory.Items.Clear()
            foreach ($cat in $categories) { [void]$cmbCategory.Items.Add($cat) }

            $idx = $cmbCategory.Items.IndexOf($selected)
            if ($idx -lt 0) { $idx = 0 }
            $cmbCategory.SelectedIndex = $idx
        }.GetNewClosure()

        $applyTypeFilters = {
            if ((& $getSelectedKind) -ne 'Types') { return }

            $searchText = [string]$txtSearch.Text
            $selectedCategory = if ($cmbCategory.SelectedItem) { [string]$cmbCategory.SelectedItem } else { 'All' }

            $filtered = @($xmlTypeState.AllTypeRows)

            if (-not [string]::IsNullOrWhiteSpace($searchText)) {
                $needle = $searchText.Trim().ToLowerInvariant()
                $filtered = @($filtered | Where-Object { ([string]$_.Name).ToLowerInvariant().Contains($needle) })
            }

            if ($selectedCategory -ne 'All') {
                $filtered = @($filtered | Where-Object { [string]$_.Category -eq $selectedCategory })
            }

            $gridTypes.Rows.Clear()
            foreach ($row in $filtered) {
                [void]$gridTypes.Rows.Add(
                    [string]$row.Name,
                    [string]$row.Nominal,
                    [string]$row.Lifetime,
                    [string]$row.Restock,
                    [string]$row.Min,
                    [string]$row.Max,
                    [string]$row.QuantMin,
                    [string]$row.QuantMax,
                    [string]$row.Cost,
                    [string]$row.Category,
                    [string]$row.Usage,
                    [string]$row.Value,
                    [string]$row.Deloot,
                    [string]$row.CountInCargo,
                    [string]$row.CountInHoarder,
                    [string]$row.CountInMap,
                    [string]$row.CountInPlayer,
                    [string]$row.Crafted
                )
            }

            $lblItemCount.Text = ('Items: ' + $gridTypes.Rows.Count)

            if ($gridTypes.Rows.Count -gt 0) {
                $gridTypes.ClearSelection()
                $gridTypes.Rows[0].Selected = $true
            }

            & $updateDetailsFromSelection
        }.GetNewClosure()


        $readCfgEnvironmentFileRowsLocal = {
            param([string]$Path)

            if (Get-Command -Name Read-UGSMGameDayZCfgEnvironmentFileRows -ErrorAction SilentlyContinue) {
                return @(Read-UGSMGameDayZCfgEnvironmentFileRows -Path $Path)
            }

            if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return @() }
            [xml]$xml = Get-Content -LiteralPath $Path -Raw -ErrorAction Stop
            $rows = @()
            $index = 0
            foreach ($node in @($xml.SelectNodes('/env/territories/file[@path]'))) {
                $index++
                $rows += [pscustomobject]@{
                    Index = $index
                    Path  = [string]$node.GetAttribute('path')
                }
            }
            return @($rows)
        }.GetNewClosure()

        $readCfgEnvironmentTerritoryRowsLocal = {
            param([string]$Path)

            if (Get-Command -Name Read-UGSMGameDayZCfgEnvironmentTerritoryRows -ErrorAction SilentlyContinue) {
                return @(Read-UGSMGameDayZCfgEnvironmentTerritoryRows -Path $Path)
            }

            if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return @() }
            [xml]$xml = Get-Content -LiteralPath $Path -Raw -ErrorAction Stop
            $rows = @()
            $index = 0
            foreach ($territoryNode in @($xml.SelectNodes('/env/territories/territory'))) {
                $index++
                $fileUsableValues = @()
                foreach ($fileNode in @($territoryNode.SelectNodes('./file[@usable]'))) {
                    $fileUsableValues += [string]$fileNode.GetAttribute('usable')
                }

                $outerXml = ''
                try {
                    $outerXml = [string](Convert-UGSMGameDayZXmlNodeToPrettyString -Node $territoryNode)
                }
                catch {
                    $outerXml = [string]$territoryNode.OuterXml
                }

                $rows += [pscustomobject]@{
                    Index      = $index
                    Name       = [string]$territoryNode.GetAttribute('name')
                    Type       = [string]$territoryNode.GetAttribute('type')
                    Behavior   = [string]$territoryNode.GetAttribute('behavior')
                    FileUsable = [string]($fileUsableValues -join ',')
                    Agents     = @($territoryNode.SelectNodes('./agent')).Count
                    Spawns     = @($territoryNode.SelectNodes('.//spawn')).Count
                    Items      = @($territoryNode.SelectNodes('./item')).Count
                    OuterXml   = $outerXml
                }
            }
            return @($rows)
        }.GetNewClosure()

        $getEnvFolderPathLocal = {
            if (Get-Command -Name Get-UGSMGameDayZRuntimeEnvFolderPath -ErrorAction SilentlyContinue) {
                return [string](Get-UGSMGameDayZRuntimeEnvFolderPath -Instance $xmlInstance)
            }

            $paths = Get-UGSMGameDayZProfilePaths -Instance $xmlInstance
            return (Join-Path ([string]$paths.RuntimeMissionPath) 'env')
        }.GetNewClosure()

        $readTerritoryZoneRowsLocal = {
            param([string]$Path)

            if (Get-Command -Name Read-UGSMGameDayZTerritoryZoneRows -ErrorAction SilentlyContinue) {
                return @(Read-UGSMGameDayZTerritoryZoneRows -Path $Path)
            }

            if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return @() }
            [xml]$xml = Get-Content -LiteralPath $Path -Raw -ErrorAction Stop
            $rows = @()
            $territoryIndex = 0
            foreach ($territoryNode in @($xml.SelectNodes('/territory-type/territory'))) {
                $territoryIndex++
                $color = [string]$territoryNode.GetAttribute('color')
                $zoneIndex = 0
                foreach ($zoneNode in @($territoryNode.SelectNodes('./zone'))) {
                    $zoneIndex++
                    $rows += [pscustomobject]@{
                        Territory = $territoryIndex
                        Color     = $color
                        Zone      = $zoneIndex
                        Name      = [string]$zoneNode.GetAttribute('name')
                        SMin      = [string]$zoneNode.GetAttribute('smin')
                        SMax      = [string]$zoneNode.GetAttribute('smax')
                        DMin      = [string]$zoneNode.GetAttribute('dmin')
                        DMax      = [string]$zoneNode.GetAttribute('dmax')
                        X         = [string]$zoneNode.GetAttribute('x')
                        Z         = [string]$zoneNode.GetAttribute('z')
                        R         = [string]$zoneNode.GetAttribute('r')
                    }
                }
            }
            return @($rows)
        }.GetNewClosure()

        
        $readEventSpawnsRowsLocal = {
            param([string]$Path)
            if (Get-Command -Name Read-UGSMGameDayZEventSpawnsXmlRows -ErrorAction SilentlyContinue) {
                return @(Read-UGSMGameDayZEventSpawnsXmlRows -Path $Path)
            }
            if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return @() }

            [xml]$xml = Get-Content -LiteralPath $Path -Raw -ErrorAction Stop
            $rows = @()
            $eventIndex = 0
            foreach ($eventNode in @($xml.DocumentElement.SelectNodes('./event[@name]'))) {
                $eventIndex++
                $eventName = [string]$eventNode.GetAttribute('name')
                $nodeIndex = 0
                foreach ($childNode in @($eventNode.ChildNodes)) {
                    if ($null -eq $childNode -or $childNode.NodeType -ne [System.Xml.XmlNodeType]::Element) { continue }
                    if ($childNode.Name -ne 'pos' -and $childNode.Name -ne 'zone') { continue }
                    $nodeIndex++
                    $rows += [pscustomobject]@{
                        EventIndex = $eventIndex
                        PosIndex   = $nodeIndex
                        NodeType   = [string]$childNode.Name
                        EventName  = $eventName
                        X          = [string]$childNode.GetAttribute('x')
                        Y          = [string]$childNode.GetAttribute('y')
                        Z          = [string]$childNode.GetAttribute('z')
                        A          = [string]$childNode.GetAttribute('a')
                        SMin       = [string]$childNode.GetAttribute('smin')
                        SMax       = [string]$childNode.GetAttribute('smax')
                        DMin       = [string]$childNode.GetAttribute('dmin')
                        DMax       = [string]$childNode.GetAttribute('dmax')
                        R          = [string]$childNode.GetAttribute('r')
                    }
                }
                if ($nodeIndex -eq 0) {
                    $rows += [pscustomobject]@{
                        EventIndex = $eventIndex
                        PosIndex   = 0
                        NodeType   = 'event'
                        EventName  = $eventName
                        X          = ''
                        Y          = ''
                        Z          = ''
                        A          = ''
                        SMin       = ''
                        SMax       = ''
                        DMin       = ''
                        DMax       = ''
                        R          = ''
                    }
                }
            }
            return @($rows)
        }.GetNewClosure()

        $getEventSpawnsGridRowsLocal = {
            param([System.Windows.Forms.DataGridView]$Grid)
            if (Get-Command -Name Get-UGSMGameDayZEventSpawnsGridRows -ErrorAction SilentlyContinue) {
                return @(Get-UGSMGameDayZEventSpawnsGridRows -Grid $Grid)
            }

            $rows = @()
            foreach ($gridRow in @($Grid.Rows)) {
                if ($null -eq $gridRow -or $gridRow.IsNewRow) { continue }
                $eventName = [string]$gridRow.Cells['EventName'].Value
                if ([string]::IsNullOrWhiteSpace($eventName)) { continue }

                $nodeType = [string]$gridRow.Cells['NodeType'].Value
                if ([string]::IsNullOrWhiteSpace($nodeType)) { $nodeType = 'pos' }

                $rows += [pscustomobject]@{
                    EventIndex = [string]$gridRow.Cells['EventIndex'].Value
                    PosIndex   = [string]$gridRow.Cells['PosIndex'].Value
                    NodeType   = $nodeType.Trim().ToLowerInvariant()
                    EventName  = $eventName.Trim()
                    X          = [string]$gridRow.Cells['X'].Value
                    Y          = [string]$gridRow.Cells['Y'].Value
                    Z          = [string]$gridRow.Cells['Z'].Value
                    A          = [string]$gridRow.Cells['A'].Value
                    SMin       = [string]$gridRow.Cells['SMin'].Value
                    SMax       = [string]$gridRow.Cells['SMax'].Value
                    DMin       = [string]$gridRow.Cells['DMin'].Value
                    DMax       = [string]$gridRow.Cells['DMax'].Value
                    R          = [string]$gridRow.Cells['R'].Value
                }
            }
            return @($rows)
        }.GetNewClosure()

        $writeEventSpawnsRowsLocal = {
            param([string]$Path, [object[]]$Rows)
            if (Get-Command -Name Write-UGSMGameDayZEventSpawnsXmlRows -ErrorAction SilentlyContinue) {
                return (Write-UGSMGameDayZEventSpawnsXmlRows -Path $Path -Rows $Rows)
            }

            $settings = New-Object System.Xml.XmlWriterSettings
            $settings.Indent = $true
            $settings.IndentChars = "`t"
            $settings.NewLineChars = [Environment]::NewLine
            $settings.NewLineHandling = [System.Xml.NewLineHandling]::Replace
            $settings.Encoding = New-Object System.Text.UTF8Encoding($false)

            $writer = [System.Xml.XmlWriter]::Create($Path, $settings)
            try {
                $writer.WriteStartDocument($true)
                $writer.WriteStartElement('eventposdef')

                $eventRows = @($Rows | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_.EventName) } | Sort-Object @{ Expression = { try { [int]$_.EventIndex } catch { 999999 } } }, @{ Expression = { [string]$_.EventName } }, @{ Expression = { try { [int]$_.PosIndex } catch { 999999 } } })
                $grouped = @($eventRows | Group-Object -Property EventName)
                $grouped = @($grouped | Sort-Object @{ Expression = { try { [int]($_.Group | Select-Object -First 1).EventIndex } catch { 999999 } } }, Name)

                foreach ($group in $grouped) {
                    $eventName = [string]$group.Name
                    if ([string]::IsNullOrWhiteSpace($eventName)) { continue }

                    $writer.WriteStartElement('event')
                    $writer.WriteAttributeString('name', $eventName)

                    foreach ($row in @($group.Group | Sort-Object @{ Expression = { try { [int]$_.PosIndex } catch { 999999 } } })) {
                        $nodeType = [string]$row.NodeType
                        if ([string]::IsNullOrWhiteSpace($nodeType)) { $nodeType = 'pos' }
                        $nodeType = $nodeType.Trim().ToLowerInvariant()

                        if ($nodeType -eq 'event') { continue }

                        if ($nodeType -eq 'zone') {
                            $writer.WriteStartElement('zone')
                            foreach ($attr in @(
                                    @{ Name = 'smin'; Value = [string]$row.SMin },
                                    @{ Name = 'smax'; Value = [string]$row.SMax },
                                    @{ Name = 'dmin'; Value = [string]$row.DMin },
                                    @{ Name = 'dmax'; Value = [string]$row.DMax },
                                    @{ Name = 'r';    Value = [string]$row.R }
                                )) {
                                if (-not [string]::IsNullOrWhiteSpace($attr.Value)) {
                                    $writer.WriteAttributeString($attr.Name, $attr.Value)
                                }
                            }
                            $writer.WriteEndElement()
                            continue
                        }

                        $x = [string]$row.X
                        $z = [string]$row.Z
                        if ([string]::IsNullOrWhiteSpace($x) -or [string]::IsNullOrWhiteSpace($z)) { continue }

                        $writer.WriteStartElement('pos')
                        $writer.WriteAttributeString('x', $x)
                        $writer.WriteAttributeString('z', $z)
                        if (-not [string]::IsNullOrWhiteSpace([string]$row.A)) {
                            $writer.WriteAttributeString('a', [string]$row.A)
                        }
                        if (-not [string]::IsNullOrWhiteSpace([string]$row.Y)) {
                            $writer.WriteAttributeString('y', [string]$row.Y)
                        }
                        $writer.WriteEndElement()
                    }

                    $writer.WriteEndElement()
                }

                $writer.WriteEndElement()
                $writer.WriteEndDocument()
            }
            finally {
                if ($writer) { $writer.Dispose() }
            }
            return $Path
        }.GetNewClosure()


        $readCfgEconomyCoreRootClassRowsLocal = {
            param([string]$Path)
            if (Get-Command -Name Read-UGSMGameDayZCfgEconomyCoreRootClassRows -ErrorAction SilentlyContinue) {
                return @(Read-UGSMGameDayZCfgEconomyCoreRootClassRows -Path $Path)
            }
            if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return @() }
            [xml]$xml = Get-Content -LiteralPath $Path -Raw -ErrorAction Stop
            $rows = @()
            $index = 0
            foreach ($node in @($xml.SelectNodes('/economycore/classes/rootclass[@name]'))) {
                $index++
                $rows += [pscustomobject]@{
                    Index = $index
                    Name = [string]$node.GetAttribute('name')
                    Act = [string]$node.GetAttribute('act')
                    ReportMemoryLOD = [string]$node.GetAttribute('reportMemoryLOD')
                }
            }
            return @($rows)
        }.GetNewClosure()

        $readCfgEconomyCoreDefaultRowsLocal = {
            param([string]$Path)
            if (Get-Command -Name Read-UGSMGameDayZCfgEconomyCoreDefaultRows -ErrorAction SilentlyContinue) {
                return @(Read-UGSMGameDayZCfgEconomyCoreDefaultRows -Path $Path)
            }
            if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return @() }
            [xml]$xml = Get-Content -LiteralPath $Path -Raw -ErrorAction Stop
            $rows = @()
            $index = 0
            foreach ($node in @($xml.SelectNodes('/economycore/defaults/default[@name]'))) {
                $index++
                $rows += [pscustomobject]@{
                    Index = $index
                    Name = [string]$node.GetAttribute('name')
                    Value = [string]$node.GetAttribute('value')
                }
            }
            return @($rows)
        }.GetNewClosure()

        $getCfgEconomyCoreRootClassGridRowsLocal = {
            param([System.Windows.Forms.DataGridView]$Grid)
            if (Get-Command -Name Get-UGSMGameDayZCfgEconomyCoreRootClassGridRows -ErrorAction SilentlyContinue) {
                return @(Get-UGSMGameDayZCfgEconomyCoreRootClassGridRows -Grid $Grid)
            }
            $rows = @()
            foreach ($gridRow in @($Grid.Rows)) {
                if ($null -eq $gridRow -or $gridRow.IsNewRow) { continue }
                $name = [string]$gridRow.Cells['Name'].Value
                if ([string]::IsNullOrWhiteSpace($name)) { continue }
                $rows += [pscustomobject]@{
                    Index = [string]$gridRow.Cells['Index'].Value
                    Name = $name.Trim()
                    Act = [string]$gridRow.Cells['Act'].Value
                    ReportMemoryLOD = [string]$gridRow.Cells['ReportMemoryLOD'].Value
                }
            }
            return @($rows)
        }.GetNewClosure()

        $getCfgEconomyCoreDefaultGridRowsLocal = {
            param([System.Windows.Forms.DataGridView]$Grid)
            if (Get-Command -Name Get-UGSMGameDayZCfgEconomyCoreDefaultGridRows -ErrorAction SilentlyContinue) {
                return @(Get-UGSMGameDayZCfgEconomyCoreDefaultGridRows -Grid $Grid)
            }
            $rows = @()
            foreach ($gridRow in @($Grid.Rows)) {
                if ($null -eq $gridRow -or $gridRow.IsNewRow) { continue }
                $name = [string]$gridRow.Cells['Name'].Value
                if ([string]::IsNullOrWhiteSpace($name)) { continue }
                $rows += [pscustomobject]@{
                    Index = [string]$gridRow.Cells['Index'].Value
                    Name = $name.Trim()
                    Value = [string]$gridRow.Cells['Value'].Value
                }
            }
            return @($rows)
        }.GetNewClosure()

        $writeCfgEconomyCoreRowsLocal = {
            param([string]$Path, [object[]]$RootClassRows, [object[]]$DefaultRows)
            if (Get-Command -Name Write-UGSMGameDayZCfgEconomyCoreRows -ErrorAction SilentlyContinue) {
                return (Write-UGSMGameDayZCfgEconomyCoreRows -Path $Path -RootClassRows $RootClassRows -DefaultRows $DefaultRows)
            }

            $settings = New-Object System.Xml.XmlWriterSettings
            $settings.Indent = $true
            $settings.IndentChars = "`t"
            $settings.NewLineChars = [Environment]::NewLine
            $settings.NewLineHandling = [System.Xml.NewLineHandling]::Replace
            $settings.Encoding = New-Object System.Text.UTF8Encoding($false)

            $writer = [System.Xml.XmlWriter]::Create($Path, $settings)
            try {
                $writer.WriteStartDocument($true)
                $writer.WriteStartElement('economycore')
                $writer.WriteStartElement('classes')
                foreach ($row in @($RootClassRows)) {
                    if ($null -eq $row) { continue }
                    $name = [string]$row.Name
                    if ([string]::IsNullOrWhiteSpace($name)) { continue }
                    $writer.WriteStartElement('rootclass')
                    $writer.WriteAttributeString('name', $name.Trim())
                    if (-not [string]::IsNullOrWhiteSpace([string]$row.Act)) { $writer.WriteAttributeString('act', [string]$row.Act) }
                    if (-not [string]::IsNullOrWhiteSpace([string]$row.ReportMemoryLOD)) { $writer.WriteAttributeString('reportMemoryLOD', [string]$row.ReportMemoryLOD) }
                    $writer.WriteEndElement()
                }
                $writer.WriteEndElement()
                $writer.WriteStartElement('defaults')
                foreach ($row in @($DefaultRows)) {
                    if ($null -eq $row) { continue }
                    $name = [string]$row.Name
                    if ([string]::IsNullOrWhiteSpace($name)) { continue }
                    $writer.WriteStartElement('default')
                    $writer.WriteAttributeString('name', $name.Trim())
                    $writer.WriteAttributeString('value', [string]$row.Value)
                    $writer.WriteEndElement()
                }
                $writer.WriteEndElement()
                $writer.WriteEndElement()
                $writer.WriteEndDocument()
            }
            finally {
                if ($writer) { $writer.Dispose() }
            }
            return $Path
        }.GetNewClosure()


        $readCfgEventGroupsRowsLocal = {
            param([string]$Path)
            if (Get-Command -Name Read-UGSMGameDayZCfgEventGroupsRows -ErrorAction SilentlyContinue) {
                return @(Read-UGSMGameDayZCfgEventGroupsRows -Path $Path)
            }
            if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return @() }
            [xml]$xml = Get-Content -LiteralPath $Path -Raw -ErrorAction Stop
            $rows = @()
            $groupIndex = 0
            foreach ($groupNode in @($xml.SelectNodes('/eventgroupdef/group[@name]'))) {
                $groupIndex++
                $groupName = [string]$groupNode.GetAttribute('name')
                $childIndex = 0
                foreach ($childNode in @($groupNode.SelectNodes('./child[@type]'))) {
                    $childIndex++
                    $rows += [pscustomobject]@{
                        GroupIndex = $groupIndex
                        ChildIndex = $childIndex
                        GroupName  = $groupName
                        Type       = [string]$childNode.GetAttribute('type')
                        Deloot     = [string]$childNode.GetAttribute('deloot')
                        LootMax    = [string]$childNode.GetAttribute('lootmax')
                        LootMin    = [string]$childNode.GetAttribute('lootmin')
                        X          = [string]$childNode.GetAttribute('x')
                        Z          = [string]$childNode.GetAttribute('z')
                        A          = [string]$childNode.GetAttribute('a')
                        Y          = [string]$childNode.GetAttribute('y')
                    }
                }
                if ($childIndex -eq 0) {
                    $rows += [pscustomobject]@{
                        GroupIndex = $groupIndex
                        ChildIndex = 0
                        GroupName  = $groupName
                        Type       = ''
                        Deloot     = ''
                        LootMax    = ''
                        LootMin    = ''
                        X          = ''
                        Z          = ''
                        A          = ''
                        Y          = ''
                    }
                }
            }
            return @($rows)
        }.GetNewClosure()

        $getCfgEventGroupsGridRowsLocal = {
            param([System.Windows.Forms.DataGridView]$Grid)
            if (Get-Command -Name Get-UGSMGameDayZCfgEventGroupsGridRows -ErrorAction SilentlyContinue) {
                return @(Get-UGSMGameDayZCfgEventGroupsGridRows -Grid $Grid)
            }
            $rows = @()
            foreach ($gridRow in @($Grid.Rows)) {
                if ($null -eq $gridRow -or $gridRow.IsNewRow) { continue }
                $groupName = [string]$gridRow.Cells['GroupName'].Value
                if ([string]::IsNullOrWhiteSpace($groupName)) { continue }
                $rows += [pscustomobject]@{
                    GroupIndex = [string]$gridRow.Cells['GroupIndex'].Value
                    ChildIndex = [string]$gridRow.Cells['ChildIndex'].Value
                    GroupName  = $groupName.Trim()
                    Type       = [string]$gridRow.Cells['Type'].Value
                    Deloot     = [string]$gridRow.Cells['Deloot'].Value
                    LootMax    = [string]$gridRow.Cells['LootMax'].Value
                    LootMin    = [string]$gridRow.Cells['LootMin'].Value
                    X          = [string]$gridRow.Cells['X'].Value
                    Z          = [string]$gridRow.Cells['Z'].Value
                    A          = [string]$gridRow.Cells['A'].Value
                    Y          = [string]$gridRow.Cells['Y'].Value
                }
            }
            return @($rows)
        }.GetNewClosure()

        $writeCfgEventGroupsRowsLocal = {
            param([string]$Path, [object[]]$Rows)
            if (Get-Command -Name Write-UGSMGameDayZCfgEventGroupsRows -ErrorAction SilentlyContinue) {
                return (Write-UGSMGameDayZCfgEventGroupsRows -Path $Path -Rows $Rows)
            }

            $settings = New-Object System.Xml.XmlWriterSettings
            $settings.Indent = $true
            $settings.IndentChars = "    "
            $settings.NewLineChars = [Environment]::NewLine
            $settings.NewLineHandling = [System.Xml.NewLineHandling]::Replace
            $settings.Encoding = New-Object System.Text.UTF8Encoding($false)

            $writer = [System.Xml.XmlWriter]::Create($Path, $settings)
            try {
                $writer.WriteStartDocument($true)
                $writer.WriteStartElement('eventgroupdef')

                $grouped = @($Rows | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_.GroupName) } | Sort-Object @{ Expression = { try { [int]$_.GroupIndex } catch { 999999 } } }, @{ Expression = { [string]$_.GroupName } }, @{ Expression = { try { [int]$_.ChildIndex } catch { 999999 } } } | Group-Object -Property GroupName)
                $grouped = @($grouped | Sort-Object @{ Expression = { try { [int]($_.Group | Select-Object -First 1).GroupIndex } catch { 999999 } } }, Name)

                foreach ($group in $grouped) {
                    $groupName = [string]$group.Name
                    if ([string]::IsNullOrWhiteSpace($groupName)) { continue }

                    $writer.WriteStartElement('group')
                    $writer.WriteAttributeString('name', $groupName)

                    foreach ($row in @($group.Group | Sort-Object @{ Expression = { try { [int]$_.ChildIndex } catch { 999999 } } })) {
                        $type = [string]$row.Type
                        if ([string]::IsNullOrWhiteSpace($type)) { continue }

                        $writer.WriteStartElement('child')
                        $writer.WriteAttributeString('type', $type)

                        foreach ($attr in @(
                                @{ Name = 'deloot'; Value = [string]$row.Deloot },
                                @{ Name = 'lootmax'; Value = [string]$row.LootMax },
                                @{ Name = 'lootmin'; Value = [string]$row.LootMin },
                                @{ Name = 'x'; Value = [string]$row.X },
                                @{ Name = 'z'; Value = [string]$row.Z },
                                @{ Name = 'a'; Value = [string]$row.A },
                                @{ Name = 'y'; Value = [string]$row.Y }
                            )) {
                            if (-not [string]::IsNullOrWhiteSpace($attr.Value)) {
                                $writer.WriteAttributeString($attr.Name, $attr.Value)
                            }
                        }

                        $writer.WriteEndElement()
                    }

                    $writer.WriteEndElement()
                }

                $writer.WriteEndElement()
                $writer.WriteEndDocument()
            }
            finally {
                if ($writer) { $writer.Dispose() }
            }
            return $Path
        }.GetNewClosure()


        $readCfgIgnoreListRowsLocal = {
            param([string]$Path)
            if (Get-Command -Name Read-UGSMGameDayZCfgIgnoreListRows -ErrorAction SilentlyContinue) {
                return @(Read-UGSMGameDayZCfgIgnoreListRows -Path $Path)
            }
            if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return @() }
            [xml]$xml = Get-Content -LiteralPath $Path -Raw -ErrorAction Stop
            $rows = @()
            $index = 0
            foreach ($node in @($xml.SelectNodes('/ignore/type[@name]'))) {
                $index++
                $rows += [pscustomobject]@{
                    Index = $index
                    Name  = [string]$node.GetAttribute('name')
                }
            }
            return @($rows)
        }.GetNewClosure()

        $getCfgIgnoreListGridRowsLocal = {
            param([System.Windows.Forms.DataGridView]$Grid)
            if (Get-Command -Name Get-UGSMGameDayZCfgIgnoreListGridRows -ErrorAction SilentlyContinue) {
                return @(Get-UGSMGameDayZCfgIgnoreListGridRows -Grid $Grid)
            }
            $rows = @()
            foreach ($gridRow in @($Grid.Rows)) {
                if ($null -eq $gridRow -or $gridRow.IsNewRow) { continue }
                $name = [string]$gridRow.Cells['Name'].Value
                if ([string]::IsNullOrWhiteSpace($name)) { continue }
                $rows += [pscustomobject]@{
                    Index = [string]$gridRow.Cells['Index'].Value
                    Name  = $name.Trim()
                }
            }
            return @($rows)
        }.GetNewClosure()

        $writeCfgIgnoreListRowsLocal = {
            param([string]$Path, [object[]]$Rows)
            if (Get-Command -Name Write-UGSMGameDayZCfgIgnoreListRows -ErrorAction SilentlyContinue) {
                return (Write-UGSMGameDayZCfgIgnoreListRows -Path $Path -Rows $Rows)
            }

            $settings = New-Object System.Xml.XmlWriterSettings
            $settings.Indent = $true
            $settings.IndentChars = "`t"
            $settings.NewLineChars = [Environment]::NewLine
            $settings.NewLineHandling = [System.Xml.NewLineHandling]::Replace
            $settings.Encoding = New-Object System.Text.UTF8Encoding($false)

            $writer = [System.Xml.XmlWriter]::Create($Path, $settings)
            try {
                $writer.WriteStartDocument($true)
                $writer.WriteStartElement('ignore')
                foreach ($row in @($Rows)) {
                    if ($null -eq $row) { continue }
                    $name = [string]$row.Name
                    if ([string]::IsNullOrWhiteSpace($name)) { continue }
                    $writer.WriteStartElement('type')
                    $writer.WriteAttributeString('name', $name.Trim())
                    $writer.WriteEndElement()
                }
                $writer.WriteEndElement()
                $writer.WriteEndDocument()
            }
            finally {
                if ($writer) { $writer.Dispose() }
            }
            return $Path
        }.GetNewClosure()

        $loadXml = {
            try {
                $kind = & $getSelectedKind
                $targetPath = Get-UGSMGameDayZXmlEditorTargetPath -Instance $xmlInstance -Kind $kind
                $txtPath.Text = [string]$targetPath

                if ([string]::IsNullOrWhiteSpace([string]$targetPath)) {
                    $txtXml.Text = ''
                    $gridTypes.Rows.Clear()
                    $gridEvents.Rows.Clear()
                    $gridEventSpawns.Rows.Clear()
                    $gridSpawnableTypes.Rows.Clear()
                    $gridVariables.Rows.Clear()
                    $xmlTypeState.AllTypeRows = @()
                    $xmlEventState.AllEventRows = @()
                    $xmlSpawnableTypeState.AllRows = @()
                    $xmlVariableState.AllRows = @()
                    $lblSpawnSelectedName.Text = ''
                    $lblSpawnSummary.Text = ''
                    $txtSpawnPreview.Text = ''
                    $lblItemCount.Text = 'Items: 0'
                    if ($xmlStatusLabel) { $xmlStatusLabel.Text = "No runtime XML path resolved for $kind." }
                    return
                }

                & $refreshEditorMode

                if ($kind -eq 'Types') {
                    $txtXml.Text = ''
                    $xmlTypeState.IsLoadingTypes = $true
                    try {
                        $gridTypes.Rows.Clear()
                        $xmlTypeState.AllTypeRows = @(Read-UGSMGameDayZTypesXmlRows -Path $targetPath)
                        & $refreshCategoryList
                    }
                    finally {
                        $xmlTypeState.IsLoadingTypes = $false
                    }

                    & $applyTypeFilters
                }
                elseif ($kind -eq 'EventSpawns') {
                    $txtXml.Text = ''
                    $gridTypes.Rows.Clear()
                    $gridEvents.Rows.Clear()
                    $gridEventSpawns.Rows.Clear()
                    $gridSpawnableTypes.Rows.Clear()
                    $gridVariables.Rows.Clear()

                    $xmlEventSpawnState.IsLoading = $true
                    try {
                        $xmlEventSpawnState.AllRows = @(& $readEventSpawnsRowsLocal $targetPath)
                        foreach ($row in @($xmlEventSpawnState.AllRows)) {
                            [void]$gridEventSpawns.Rows.Add(
                                [string]$row.EventIndex,
                                [string]$row.PosIndex,
                                [string]$row.NodeType,
                                [string]$row.EventName,
                                [string]$row.X,
                                [string]$row.Y,
                                [string]$row.Z,
                                [string]$row.A,
                                [string]$row.SMin,
                                [string]$row.SMax,
                                [string]$row.DMin,
                                [string]$row.DMax,
                                [string]$row.R
                            )
                        }
                    }
                    finally {
                        $xmlEventSpawnState.IsLoading = $false
                    }

                    $lblItemCount.Text = ('Positions: ' + @($xmlEventSpawnState.AllRows).Count)
                }
                elseif ($kind -eq 'Events') {
                    $txtXml.Text = ''
                    $xmlEventState.IsLoadingEvents = $true
                    try {
                        $gridEvents.Rows.Clear()
                        $xmlEventState.AllEventRows = @(Read-UGSMGameDayZEventsXmlRows -Path $targetPath)

                        foreach ($row in @($xmlEventState.AllEventRows)) {
                            $activeValue = '0'
                            if ([string]$row.Active -eq '1' -or ([string]$row.Active).ToLowerInvariant() -eq 'true') {
                                $activeValue = '1'
                            }

                            $rowIndex = $gridEvents.Rows.Add(
                                [string]$row.Name,
                                [string]$row.Nominal,
                                [string]$row.Min,
                                [string]$row.Max,
                                [string]$row.Lifetime,
                                [string]$row.Restock,
                                $activeValue
                            )

                            $gridEvents.Rows[$rowIndex].Tag = $row
                        }

                        $lblItemCount.Text = ('Items: ' + $gridEvents.Rows.Count)

                        if ($gridEvents.Rows.Count -gt 0) {
                            $gridEvents.ClearSelection()
                            $gridEvents.Rows[0].Selected = $true
                        }
                    }
                    finally {
                        $xmlEventState.IsLoadingEvents = $false
                    }

                    & $updateEventDetailsFromSelection
                }
                elseif ($kind -eq 'SpawnableTypes') {
                    $txtXml.Text = ''
                    $xmlSpawnableTypeState.IsLoading = $true
                    try {
                        $gridSpawnableTypes.Rows.Clear()
                        $xmlSpawnableTypeState.AllRows = @(Read-UGSMGameDayZSpawnableTypesXmlRows -Path $targetPath)
                    }
                    finally {
                        $xmlSpawnableTypeState.IsLoading = $false
                    }

                    & $applySpawnableTypeFilters
                }
                elseif ($kind -eq 'Globals') {
                    $txtXml.Text = ''
                    $xmlVariableState.AllRows = @()

                    $sourceRows = @(Read-UGSMGameDayZGlobalsXmlRows -Path $targetPath)

                    $xmlVariableState.AllRows = @(
                        foreach ($row in @($sourceRows)) {
                            [pscustomobject]@{
                                Group         = 'variables'
                                Key           = [string]$row.Name
                                Value         = [string]$row.Value
                                SourcePath    = [string]$targetPath
                                EntryType     = 'attribute'
                                AttributeName = [string]$row.Type
                            }
                        }
                    )

                    & $applyGlobalsFilter
                }
                elseif ($kind -eq 'Economy') {
                    $txtXml.Text = ''
                    $gridEconomy.Rows.Clear()

                    $sourceRows = @(Read-UGSMGameDayZEconomyXmlRows -Path $targetPath)
                    $matrixRows = @(Convert-UGSMGameDayZEconomyRowsToMatrix -Rows $sourceRows)

                    foreach ($row in @($matrixRows)) {
                        [void]$gridEconomy.Rows.Add(
                            [string]$row.Section,
                            [bool]$row.Init,
                            [bool]$row.Load,
                            [bool]$row.Respawn,
                            [bool]$row.Save
                        )
                    }

                    $lblItemCount.Text = ('Items: ' + @($matrixRows).Count)
                }
                elseif ($kind -eq 'CfgGameplay') {
                    $txtXml.Text = ''
                    $cfgGameplayState.IsLoading = $true
                    try {
                        $cfgGameplayState.Data = Read-UGSMGameDayZCfgGameplayJsonData -Path $targetPath
                        $cfgGameplayState.Rows = @(Get-UGSMGameDayZCfgGameplayRows -Data $cfgGameplayState.Data)
                    }
                    finally {
                        $cfgGameplayState.IsLoading = $false
                    }

                    if ($applyCfgGameplayFilter -is [scriptblock]) {
                        & $applyCfgGameplayFilter
                    }
                }
                elseif ($kind -eq 'CfgEconomyCore') {
                    $txtXml.Text = ''
                    $gridTypes.Rows.Clear()
                    $gridEvents.Rows.Clear()
                    $gridEventSpawns.Rows.Clear()
                    $gridSpawnableTypes.Rows.Clear()
                    $gridVariables.Rows.Clear()
                    $gridEconomyRootClasses.Rows.Clear()
                    $gridEconomyDefaults.Rows.Clear()

                    $cfgEconomyCoreState.IsLoading = $true
                    try {
                        $cfgEconomyCoreState.RootClassRows = @(& $readCfgEconomyCoreRootClassRowsLocal $targetPath)
                        $cfgEconomyCoreState.DefaultRows = @(& $readCfgEconomyCoreDefaultRowsLocal $targetPath)

                        foreach ($row in @($cfgEconomyCoreState.RootClassRows)) {
                            [void]$gridEconomyRootClasses.Rows.Add(
                                [string]$row.Index,
                                [string]$row.Name,
                                [string]$row.Act,
                                [string]$row.ReportMemoryLOD
                            )
                        }

                        foreach ($row in @($cfgEconomyCoreState.DefaultRows)) {
                            [void]$gridEconomyDefaults.Rows.Add(
                                [string]$row.Index,
                                [string]$row.Name,
                                [string]$row.Value
                            )
                        }
                    }
                    finally {
                        $cfgEconomyCoreState.IsLoading = $false
                    }

                    & $applyReadableDataGridStyle $gridEconomyRootClasses
                    & $applyReadableDataGridStyle $gridEconomyDefaults
                    $lblItemCount.Text = ('Root Classes: {0}  Defaults: {1}' -f @($cfgEconomyCoreState.RootClassRows).Count, @($cfgEconomyCoreState.DefaultRows).Count)
                }
                elseif ($kind -eq 'CfgEventGroups') {
                    $txtXml.Text = ''
                    $gridTypes.Rows.Clear()
                    $gridEvents.Rows.Clear()
                    $gridEventSpawns.Rows.Clear()
                    $gridSpawnableTypes.Rows.Clear()
                    $gridVariables.Rows.Clear()
                    $gridEventGroups.Rows.Clear()

                    $cfgEventGroupsState.IsLoading = $true
                    try {
                        $cfgEventGroupsState.Rows = @(& $readCfgEventGroupsRowsLocal $targetPath)
                        foreach ($row in @($cfgEventGroupsState.Rows)) {
                            [void]$gridEventGroups.Rows.Add(
                                [string]$row.GroupIndex,
                                [string]$row.ChildIndex,
                                [string]$row.GroupName,
                                [string]$row.Type,
                                [string]$row.Deloot,
                                [string]$row.LootMax,
                                [string]$row.LootMin,
                                [string]$row.X,
                                [string]$row.Z,
                                [string]$row.A,
                                [string]$row.Y
                            )
                        }
                    }
                    finally {
                        $cfgEventGroupsState.IsLoading = $false
                    }

                    & $applyReadableDataGridStyle $gridEventGroups
                    $lblItemCount.Text = ('Children: ' + @($cfgEventGroupsState.Rows).Count)
                }
                elseif ($kind -eq 'CfgIgnoreList') {
                    $txtXml.Text = ''
                    $gridTypes.Rows.Clear()
                    $gridEvents.Rows.Clear()
                    $gridEventSpawns.Rows.Clear()
                    $gridSpawnableTypes.Rows.Clear()
                    $gridVariables.Rows.Clear()
                    $gridIgnoreList.Rows.Clear()

                    $cfgIgnoreListState.IsLoading = $true
                    try {
                        $cfgIgnoreListState.Rows = @(& $readCfgIgnoreListRowsLocal $targetPath)
                        foreach ($row in @($cfgIgnoreListState.Rows)) {
                            [void]$gridIgnoreList.Rows.Add(
                                [string]$row.Index,
                                [string]$row.Name
                            )
                        }
                    }
                    finally {
                        $cfgIgnoreListState.IsLoading = $false
                    }

                    & $applyReadableDataGridStyle $gridIgnoreList
                    $lblItemCount.Text = ('Ignored Types: ' + @($cfgIgnoreListState.Rows).Count)
                }
                elseif ($kind -eq 'CfgEnvironment') {
                    $txtXml.Text = ''
                    $gridTypes.Rows.Clear()
                    $gridEvents.Rows.Clear()
                    $gridEventSpawns.Rows.Clear()
                    $gridSpawnableTypes.Rows.Clear()
                    $gridVariables.Rows.Clear()
                    $gridEnvFiles.Rows.Clear()
                    $gridEnvTerritories.Rows.Clear()

                    $cfgEnvironmentState.IsLoading = $true
                    try {
                        $cfgEnvironmentState.FileRows = @(& $readCfgEnvironmentFileRowsLocal $targetPath)
                        $cfgEnvironmentState.TerritoryRows = @(& $readCfgEnvironmentTerritoryRowsLocal $targetPath)

                        foreach ($row in @($cfgEnvironmentState.FileRows)) {
                            [void]$gridEnvFiles.Rows.Add([string]$row.Index, [string]$row.Path)
                        }

                        foreach ($row in @($cfgEnvironmentState.TerritoryRows)) {
                            $rowIndex = $gridEnvTerritories.Rows.Add(
                                [string]$row.Index,
                                [string]$row.Name,
                                [string]$row.Type,
                                [string]$row.Behavior,
                                [string]$row.FileUsable,
                                [string]$row.Agents,
                                [string]$row.Spawns,
                                [string]$row.Items
                            )
                            $gridEnvTerritories.Rows[$rowIndex].Tag = $row
                        }

                        $cmbTerritoryFile.Items.Clear()
                        $envFolder = & $getEnvFolderPathLocal
                        if (-not [string]::IsNullOrWhiteSpace($envFolder) -and (Test-Path -LiteralPath $envFolder -PathType Container)) {
                            foreach ($file in @(Get-ChildItem -LiteralPath $envFolder -Filter '*.xml' -File -ErrorAction SilentlyContinue | Sort-Object Name)) {
                                [void]$cmbTerritoryFile.Items.Add($file.Name)
                            }
                        }
                    }
                    finally {
                        $cfgEnvironmentState.IsLoading = $false
                    }

                    & $applyReadableDataGridStyle $gridEnvFiles
                    & $applyReadableDataGridStyle $gridEnvTerritories
                    $lblItemCount.Text = ('Files: {0}  Territories: {1}' -f $gridEnvFiles.Rows.Count, $gridEnvTerritories.Rows.Count)
                }
                elseif ($kind -eq 'TerritoryZones') {
                    $txtXml.Text = ''
                    $gridTypes.Rows.Clear()
                    $gridEvents.Rows.Clear()
                    $gridEventSpawns.Rows.Clear()
                    $gridSpawnableTypes.Rows.Clear()
                    $gridVariables.Rows.Clear()
                    $gridTerritoryZones.Rows.Clear()

                    $envFolder = & $getEnvFolderPathLocal
                    $cmbTerritoryFile.Items.Clear()
                    if (-not [string]::IsNullOrWhiteSpace($envFolder) -and (Test-Path -LiteralPath $envFolder -PathType Container)) {
                        foreach ($file in @(Get-ChildItem -LiteralPath $envFolder -Filter '*.xml' -File -ErrorAction SilentlyContinue | Sort-Object Name)) {
                            [void]$cmbTerritoryFile.Items.Add($file.Name)
                        }
                    }

                    if ($cmbTerritoryFile.Items.Count -gt 0) {
                        $preferred = Split-Path -Leaf $targetPath
                        $index = 0
                        for ($i = 0; $i -lt $cmbTerritoryFile.Items.Count; $i++) {
                            if ([string]$cmbTerritoryFile.Items[$i] -eq $preferred) { $index = $i; break }
                        }
                        $cmbTerritoryFile.SelectedIndex = $index
                    }

                    if ($loadSelectedTerritoryFile -is [scriptblock]) {
                        & $loadSelectedTerritoryFile
                    }
                }
                elseif ($miscEditorKinds -contains $kind) {
                    $txtXml.Text = ''
                    $gridTypes.Rows.Clear(); $gridEvents.Rows.Clear(); $gridEventSpawns.Rows.Clear(); $gridSpawnableTypes.Rows.Clear(); $gridVariables.Rows.Clear()
                    & $loadMiscColumns $kind
                    & $readMiscRows $kind $targetPath
                    & $refreshMiscEditor
                }
                elseif ($kind -eq 'Messages') {
                    $gridTypes.Rows.Clear()
                    $gridEvents.Rows.Clear()
                    $gridEventSpawns.Rows.Clear()
                    $gridSpawnableTypes.Rows.Clear()
                    $gridVariables.Rows.Clear()
                    $lblSpawnSelectedName.Text = ''
                    $lblSpawnSummary.Text = ''
                    $txtSpawnPreview.Text = ''
                    $txtXml.Text = Read-UGSMGameDayZTextFileSafe -Path $targetPath
                    $lblItemCount.Text = 'Items: 0'
                }
                else {
                    $gridTypes.Rows.Clear()
                    $gridEvents.Rows.Clear()
                    $gridEventSpawns.Rows.Clear()
                    $gridSpawnableTypes.Rows.Clear()
                    $gridVariables.Rows.Clear()
                    $lblSpawnSelectedName.Text = ''
                    $lblSpawnSummary.Text = ''
                    $txtSpawnPreview.Text = ''
                    $txtXml.Text = Read-UGSMGameDayZTextFileSafe -Path $targetPath
                    $lblItemCount.Text = 'Raw XML'
                }

                if ($xmlStatusLabel) { $xmlStatusLabel.Text = "Loaded DayZ XML: $kind" }
            }
            catch {
                if ($xmlStatusLabel) { $xmlStatusLabel.Text = 'Loading DayZ XML failed: ' + $_.Exception.Message }
            }
        }.GetNewClosure()


        $loadSelectedTerritoryFile = {
            try {
                $envFolder = & $getEnvFolderPathLocal
                if ([string]::IsNullOrWhiteSpace($envFolder)) { throw 'DayZ env folder could not be resolved.' }

                $selectedFile = if ($cmbTerritoryFile.SelectedItem) { [string]$cmbTerritoryFile.SelectedItem } else { '' }
                if ([string]::IsNullOrWhiteSpace($selectedFile)) {
                    $selectedFile = 'bear_territories.xml'
                }

                $territoryPath = Join-Path $envFolder $selectedFile
                if (-not (Test-Path -LiteralPath $territoryPath -PathType Leaf)) {
                    throw "Territory file was not found: $territoryPath"
                }

                $cfgEnvironmentState.ActiveFile = $territoryPath
                $gridTerritoryZones.Rows.Clear()
                $zoneRows = @(& $readTerritoryZoneRowsLocal $territoryPath)
                $cfgEnvironmentState.ZoneRows = @($zoneRows)

                foreach ($row in @($zoneRows)) {
                    [void]$gridTerritoryZones.Rows.Add(
                        [string]$row.Territory,
                        [string]$row.Color,
                        [string]$row.Zone,
                        [string]$row.Name,
                        [string]$row.SMin,
                        [string]$row.SMax,
                        [string]$row.DMin,
                        [string]$row.DMax,
                        [string]$row.X,
                        [string]$row.Z,
                        [string]$row.R
                    )
                }

                & $applyReadableDataGridStyle $gridTerritoryZones
                $txtPath.Text = $territoryPath
                $lblItemCount.Text = ('Zones: ' + $gridTerritoryZones.Rows.Count)
                if ($xmlStatusLabel) { $xmlStatusLabel.Text = ('Loaded territory file: ' + $selectedFile) }
            }
            catch {
                if ($xmlStatusLabel) { $xmlStatusLabel.Text = 'Loading territory file failed: ' + $_.Exception.Message }
            }
        }.GetNewClosure()


        $getTerritoryZoneGridRowsLocal = {
            param([System.Windows.Forms.DataGridView]$Grid)

            if (Get-Command -Name Get-UGSMGameDayZTerritoryZoneGridRows -ErrorAction SilentlyContinue) {
                return @(Get-UGSMGameDayZTerritoryZoneGridRows -Grid $Grid)
            }

            $rows = @()
            foreach ($gridRow in @($Grid.Rows)) {
                if ($null -eq $gridRow -or $gridRow.IsNewRow) { continue }

                $territory = [string]$gridRow.Cells['Territory'].Value
                $x = [string]$gridRow.Cells['X'].Value
                $z = [string]$gridRow.Cells['Z'].Value
                $r = [string]$gridRow.Cells['R'].Value

                if ([string]::IsNullOrWhiteSpace($territory) -or [string]::IsNullOrWhiteSpace($x) -or [string]::IsNullOrWhiteSpace($z) -or [string]::IsNullOrWhiteSpace($r)) {
                    continue
                }

                $rows += [pscustomobject]@{
                    Territory = $territory
                    Color     = [string]$gridRow.Cells['Color'].Value
                    Zone      = [string]$gridRow.Cells['Zone'].Value
                    Name      = [string]$gridRow.Cells['Name'].Value
                    SMin      = [string]$gridRow.Cells['SMin'].Value
                    SMax      = [string]$gridRow.Cells['SMax'].Value
                    DMin      = [string]$gridRow.Cells['DMin'].Value
                    DMax      = [string]$gridRow.Cells['DMax'].Value
                    X         = $x
                    Z         = $z
                    R         = $r
                }
            }

            return @($rows)
        }.GetNewClosure()

        $writeTerritoryZoneRowsLocal = {
            param(
                [string]$Path,
                [object[]]$Rows
            )

            if (Get-Command -Name Write-UGSMGameDayZTerritoryZoneRows -ErrorAction SilentlyContinue) {
                return (Write-UGSMGameDayZTerritoryZoneRows -Path $Path -Rows $Rows)
            }

            $settings = New-Object System.Xml.XmlWriterSettings
            $settings.Indent = $true
            $settings.IndentChars = '    '
            $settings.NewLineChars = [Environment]::NewLine
            $settings.NewLineHandling = [System.Xml.NewLineHandling]::Replace
            $settings.Encoding = New-Object System.Text.UTF8Encoding($false)

            $parent = Split-Path -Parent $Path
            if (-not [string]::IsNullOrWhiteSpace([string]$parent) -and -not (Test-Path -LiteralPath $parent -PathType Container)) {
                New-Item -ItemType Directory -Path $parent -Force | Out-Null
            }

            $writer = [System.Xml.XmlWriter]::Create($Path, $settings)
            try {
                $writer.WriteStartDocument()
                $writer.WriteStartElement('territory-type')

                $grouped = @($Rows | Sort-Object {[int]$_.Territory}, {[int]$_.Zone} | Group-Object -Property Territory)
                foreach ($group in $grouped) {
                    $groupRows = @($group.Group)
                    if (@($groupRows).Count -le 0) { continue }

                    $color = [string]$groupRows[0].Color
                    if ([string]::IsNullOrWhiteSpace($color)) { $color = '4294923520' }

                    $writer.WriteStartElement('territory')
                    $writer.WriteAttributeString('color', $color)

                    foreach ($row in $groupRows) {
                        $writer.WriteStartElement('zone')
                        $writer.WriteAttributeString('name', ([string]$row.Name))
                        $writer.WriteAttributeString('smin', ([string]$row.SMin))
                        $writer.WriteAttributeString('smax', ([string]$row.SMax))
                        $writer.WriteAttributeString('dmin', ([string]$row.DMin))
                        $writer.WriteAttributeString('dmax', ([string]$row.DMax))
                        $writer.WriteAttributeString('x', ([string]$row.X))
                        $writer.WriteAttributeString('z', ([string]$row.Z))
                        $writer.WriteAttributeString('r', ([string]$row.R))
                        $writer.WriteEndElement()
                    }

                    $writer.WriteEndElement()
                }

                $writer.WriteEndElement()
                $writer.WriteEndDocument()
            }
            finally {
                if ($writer) { $writer.Dispose() }
            }

            return $Path
        }.GetNewClosure()

        $saveSelectedTerritoryFile = {
            try {
                $activePath = [string]$cfgEnvironmentState.ActiveFile
                if ([string]::IsNullOrWhiteSpace($activePath)) { throw 'No territory file is loaded.' }

                [void](Backup-UGSMGameDayZXmlFile -TargetPath $activePath)
                $zoneRows = @(& $getTerritoryZoneGridRowsLocal $gridTerritoryZones)
                [void](& $writeTerritoryZoneRowsLocal $activePath $zoneRows)
                $cfgEnvironmentState.ZoneRows = @($zoneRows)
                $lblItemCount.Text = ('Zones: ' + @($zoneRows).Count)
                if ($xmlStatusLabel) { $xmlStatusLabel.Text = ('Saved territory file: ' + (Split-Path -Leaf $activePath)) }
            }
            catch {
                if ($xmlStatusLabel) { $xmlStatusLabel.Text = 'Saving territory file failed: ' + $_.Exception.Message }
            }
        }.GetNewClosure()


        $applyEventSpawnFilters = {
            $gridEventSpawns.Rows.Clear()
            $searchText = [string]$txtSearch.Text

            foreach ($row in @($xmlEventSpawnState.AllRows)) {
                if (-not [string]::IsNullOrWhiteSpace($searchText)) {
                    $haystack = ('{0} {1} {2} {3} {4} {5}' -f [string]$row.EventName, [string]$row.NodeType, [string]$row.X, [string]$row.Y, [string]$row.Z, [string]$row.A)
                    if ($haystack.IndexOf($searchText, [System.StringComparison]::OrdinalIgnoreCase) -lt 0) {
                        continue
                    }
                }

                [void]$gridEventSpawns.Rows.Add(
                    [string]$row.EventIndex,
                    [string]$row.PosIndex,
                    [string]$row.NodeType,
                    [string]$row.EventName,
                    [string]$row.X,
                    [string]$row.Y,
                    [string]$row.Z,
                    [string]$row.A,
                    [string]$row.SMin,
                    [string]$row.SMax,
                    [string]$row.DMin,
                    [string]$row.DMax,
                    [string]$row.R
                )
            }

            $lblItemCount.Text = ('Positions: ' + $gridEventSpawns.Rows.Count)
        }.GetNewClosure()

        $gridTypes.Add_SelectionChanged({ & $updateDetailsFromSelection }.GetNewClosure())

        foreach ($name in $usageOptions) {
            $usageCheckboxes[$name].Add_CheckedChanged({ & $writeCheckboxesToSelectedRow }.GetNewClosure())
        }

        foreach ($name in $valueOptions) {
            $valueCheckboxes[$name].Add_CheckedChanged({ & $writeCheckboxesToSelectedRow }.GetNewClosure())
        }

        $chkDeloot.Add_CheckedChanged({ & $writeCheckboxesToSelectedRow }.GetNewClosure())

        $btnSearch.Add_Click({
                $selectedKind = if ($cmbKind.SelectedItem) { [string]$cmbKind.SelectedItem } else { 'Types' }
                if ($selectedKind -eq 'SpawnableTypes') {
                    & $applySpawnableTypeFilters
                }
                elseif ($selectedKind -eq 'Globals' -or $selectedKind -eq 'Economy') {
                    & $applyGlobalsFilter
                }
                elseif ($selectedKind -eq 'EventSpawns') {
                    & $applyEventSpawnFilters
                }
                elseif ($selectedKind -eq 'EventSpawns') {
                    & $applyEventSpawnFilters
                }
                elseif ($selectedKind -eq 'CfgGameplay') {
                    & $applyCfgGameplayFilter
                }
                elseif ($selectedKind -eq 'CfgEconomyCore') {
                    $lblItemCount.Text = ('Root Classes: {0}  Defaults: {1}' -f $gridEconomyRootClasses.Rows.Count, $gridEconomyDefaults.Rows.Count)
                }
                elseif ($selectedKind -eq 'CfgEventGroups') {
                    $lblItemCount.Text = ('Children: ' + $gridEventGroups.Rows.Count)
                }
                elseif ($selectedKind -eq 'CfgIgnoreList') {
                    $lblItemCount.Text = ('Ignored Types: ' + $gridIgnoreList.Rows.Count)
                }
                elseif ($selectedKind -eq 'CfgEnvironment') {
                    $lblItemCount.Text = ('Files: {0}  Territories: {1}' -f $gridEnvFiles.Rows.Count, $gridEnvTerritories.Rows.Count)
                }
                elseif ($selectedKind -eq 'TerritoryZones') {
                    $lblItemCount.Text = ('Zones: ' + $gridTerritoryZones.Rows.Count)
                }
                elseif ($miscEditorKinds -contains $selectedKind) {
                    & $refreshMiscEditor
                }
                else {
                    & $applyTypeFilters
                }
            }.GetNewClosure())

        $btnShowAll.Add_Click({
                $txtSearch.Text = ''
                if ($cmbCategory.Items.Count -gt 0) { $cmbCategory.SelectedIndex = 0 }
                $selectedKind = if ($cmbKind.SelectedItem) { [string]$cmbKind.SelectedItem } else { 'Types' }
                if ($selectedKind -eq 'SpawnableTypes') {
                    & $applySpawnableTypeFilters
                }
                elseif ($selectedKind -eq 'Globals' -or $selectedKind -eq 'Economy') {
                    & $applyGlobalsFilter
                }
                elseif ($selectedKind -eq 'CfgGameplay') {
                    & $applyCfgGameplayFilter
                }
                elseif ($selectedKind -eq 'CfgEconomyCore') {
                    $lblItemCount.Text = ('Root Classes: {0}  Defaults: {1}' -f $gridEconomyRootClasses.Rows.Count, $gridEconomyDefaults.Rows.Count)
                }
                elseif ($selectedKind -eq 'CfgEventGroups') {
                    $lblItemCount.Text = ('Children: ' + $gridEventGroups.Rows.Count)
                }
                elseif ($selectedKind -eq 'CfgIgnoreList') {
                    $lblItemCount.Text = ('Ignored Types: ' + $gridIgnoreList.Rows.Count)
                }
                elseif ($selectedKind -eq 'CfgEnvironment') {
                    $lblItemCount.Text = ('Files: {0}  Territories: {1}' -f $gridEnvFiles.Rows.Count, $gridEnvTerritories.Rows.Count)
                }
                elseif ($selectedKind -eq 'TerritoryZones') {
                    $lblItemCount.Text = ('Zones: ' + $gridTerritoryZones.Rows.Count)
                }
                elseif ($miscEditorKinds -contains $selectedKind) {
                    & $refreshMiscEditor
                }
                else {
                    & $applyTypeFilters
                }
            }.GetNewClosure())

        $btnLoadTerritoryFile.Add_Click({ & $loadSelectedTerritoryFile }.GetNewClosure())
        $btnSaveTerritoryFile.Add_Click({ & $saveSelectedTerritoryFile }.GetNewClosure())

        $btnAddTerritoryZone.Add_Click({
                $nextTerritory = 1
                $nextZone = $gridTerritoryZones.Rows.Count + 1
                if ($gridTerritoryZones.SelectedRows.Count -gt 0) {
                    $selectedRow = $gridTerritoryZones.SelectedRows[0]
                    $nextTerritory = [string]$selectedRow.Cells['Territory'].Value
                    $nextZone = $gridTerritoryZones.Rows.Count + 1
                }

                [void]$gridTerritoryZones.Rows.Add(
                    [string]$nextTerritory,
                    '4294923520',
                    [string]$nextZone,
                    'Graze',
                    '0',
                    '0',
                    '0',
                    '0',
                    '0',
                    '0',
                    '100'
                )

                $lblItemCount.Text = ('Zones: ' + $gridTerritoryZones.Rows.Count)
            }.GetNewClosure())

        $btnRemoveTerritoryZone.Add_Click({
                foreach ($row in @($gridTerritoryZones.SelectedRows)) {
                    if ($row -and -not $row.IsNewRow) {
                        $gridTerritoryZones.Rows.Remove($row)
                    }
                }
                $lblItemCount.Text = ('Zones: ' + $gridTerritoryZones.Rows.Count)
            }.GetNewClosure())

        $btnAddEventSpawn.Add_Click({
                $eventName = ''
                $eventIndex = 1
                $posIndex = $gridEventSpawns.Rows.Count + 1

                if ($gridEventSpawns.SelectedRows.Count -gt 0) {
                    $selectedRow = $gridEventSpawns.SelectedRows[0]
                    $eventName = [string]$selectedRow.Cells['EventName'].Value
                    $eventIndex = [string]$selectedRow.Cells['EventIndex'].Value
                }

                if ([string]::IsNullOrWhiteSpace($eventName)) {
                    $eventName = 'NewEvent'
                }

                [void]$gridEventSpawns.Rows.Add(
                    [string]$eventIndex,
                    [string]$posIndex,
                    'pos',
                    $eventName,
                    '0',
                    '',
                    '0',
                    '0',
                    '',
                    '',
                    '',
                    '',
                    ''
                )

                $lblItemCount.Text = ('Positions: ' + $gridEventSpawns.Rows.Count)
            }.GetNewClosure())

        $btnRemoveEventSpawn.Add_Click({
                foreach ($row in @($gridEventSpawns.SelectedRows)) {
                    if ($row -and -not $row.IsNewRow) {
                        $gridEventSpawns.Rows.Remove($row)
                    }
                }

                $lblItemCount.Text = ('Positions: ' + $gridEventSpawns.Rows.Count)
            }.GetNewClosure())

        $btnAddRootClass.Add_Click({
                [void]$gridEconomyRootClasses.Rows.Add('', 'NewRootClass', '', '')
                $lblItemCount.Text = ('Root Classes: {0}  Defaults: {1}' -f $gridEconomyRootClasses.Rows.Count, $gridEconomyDefaults.Rows.Count)
            }.GetNewClosure())

        $btnRemoveRootClass.Add_Click({
                foreach ($row in @($gridEconomyRootClasses.SelectedRows)) {
                    if ($row -and -not $row.IsNewRow) {
                        $gridEconomyRootClasses.Rows.Remove($row)
                    }
                }
                $lblItemCount.Text = ('Root Classes: {0}  Defaults: {1}' -f $gridEconomyRootClasses.Rows.Count, $gridEconomyDefaults.Rows.Count)
            }.GetNewClosure())

        $btnAddEconomyDefault.Add_Click({
                [void]$gridEconomyDefaults.Rows.Add('', 'new_default_name', '')
                $lblItemCount.Text = ('Root Classes: {0}  Defaults: {1}' -f $gridEconomyRootClasses.Rows.Count, $gridEconomyDefaults.Rows.Count)
            }.GetNewClosure())

        $btnRemoveEconomyDefault.Add_Click({
                foreach ($row in @($gridEconomyDefaults.SelectedRows)) {
                    if ($row -and -not $row.IsNewRow) {
                        $gridEconomyDefaults.Rows.Remove($row)
                    }
                }
                $lblItemCount.Text = ('Root Classes: {0}  Defaults: {1}' -f $gridEconomyRootClasses.Rows.Count, $gridEconomyDefaults.Rows.Count)
            }.GetNewClosure())

        $btnAddEventGroupChild.Add_Click({
                $groupName = 'NewGroup'
                $groupIndex = 1
                $childIndex = $gridEventGroups.Rows.Count + 1

                if ($gridEventGroups.SelectedRows.Count -gt 0) {
                    $selectedRow = $gridEventGroups.SelectedRows[0]
                    $groupName = [string]$selectedRow.Cells['GroupName'].Value
                    $groupIndex = [string]$selectedRow.Cells['GroupIndex'].Value
                }

                [void]$gridEventGroups.Rows.Add(
                    [string]$groupIndex,
                    [string]$childIndex,
                    $groupName,
                    'NewType',
                    '0',
                    '',
                    '',
                    '0',
                    '0',
                    '0',
                    ''
                )
                $lblItemCount.Text = ('Children: ' + $gridEventGroups.Rows.Count)
            }.GetNewClosure())

        $btnRemoveEventGroupChild.Add_Click({
                foreach ($row in @($gridEventGroups.SelectedRows)) {
                    if ($row -and -not $row.IsNewRow) {
                        $gridEventGroups.Rows.Remove($row)
                    }
                }
                $lblItemCount.Text = ('Children: ' + $gridEventGroups.Rows.Count)
            }.GetNewClosure())

        $btnAddIgnoreType.Add_Click({
                [void]$gridIgnoreList.Rows.Add('', 'NewIgnoredType')
                $lblItemCount.Text = ('Ignored Types: ' + $gridIgnoreList.Rows.Count)
            }.GetNewClosure())

        $btnRemoveIgnoreType.Add_Click({
                foreach ($row in @($gridIgnoreList.SelectedRows)) {
                    if ($row -and -not $row.IsNewRow) {
                        $gridIgnoreList.Rows.Remove($row)
                    }
                }
                $lblItemCount.Text = ('Ignored Types: ' + $gridIgnoreList.Rows.Count)
            }.GetNewClosure())

        $cmbCategory.Add_SelectedIndexChanged({
                & $applyTypeFilters
            }.GetNewClosure())

        $btnApplySpawnPreview.Add_Click({
                try {
                    & $applySpawnablePreviewToSelectedRow
                }
                catch {
                    if ($xmlStatusLabel) { $xmlStatusLabel.Text = 'Updating spawnable type failed: ' + $_.Exception.Message }
                }
            }.GetNewClosure())

        $btnApplySelected.Add_Click({
                if ($gridTypes.SelectedRows.Count -le 0) { return }
                $fieldName = [string]$cmbBulkField.SelectedItem
                $value = [string]$txtBulkValue.Text
                if ([string]::IsNullOrWhiteSpace($fieldName)) { return }

                $columnName = (Get-Culture).TextInfo.ToTitleCase($fieldName.ToLowerInvariant())
                if ($fieldName -eq 'quantmin') { $columnName = 'QuantMin' }
                elseif ($fieldName -eq 'quantmax') { $columnName = 'QuantMax' }
                elseif ($fieldName -eq 'max') { $columnName = 'Max' }
                elseif ($fieldName -eq 'deloot') { $columnName = 'Deloot' }

                foreach ($row in @($gridTypes.SelectedRows)) {
                    if ($row -and -not $row.IsNewRow) {
                        $row.Cells[$columnName].Value = $value
                    }
                }

                & $syncGridToAllTypeRows
                & $refreshCategoryList
            }.GetNewClosure())

        $btnApplyAll.Add_Click({
                $fieldName = [string]$cmbBulkField.SelectedItem
                $value = [string]$txtBulkValue.Text
                if ([string]::IsNullOrWhiteSpace($fieldName)) { return }

                $columnName = (Get-Culture).TextInfo.ToTitleCase($fieldName.ToLowerInvariant())
                if ($fieldName -eq 'quantmin') { $columnName = 'QuantMin' }
                elseif ($fieldName -eq 'quantmax') { $columnName = 'QuantMax' }
                elseif ($fieldName -eq 'max') { $columnName = 'Max' }
                elseif ($fieldName -eq 'deloot') { $columnName = 'Deloot' }

                foreach ($row in @($gridTypes.Rows)) {
                    if ($row -and -not $row.IsNewRow) {
                        $row.Cells[$columnName].Value = $value
                    }
                }

                & $syncGridToAllTypeRows
                & $refreshCategoryList
            }.GetNewClosure())

        $cmbKind.Add_SelectedIndexChanged({
                & $refreshEditorMode
                & $loadXml
            }.GetNewClosure())

        $cmbTerritoryFile.Add_SelectedIndexChanged({ if ((& $getSelectedKind) -eq 'TerritoryZones') { & $loadSelectedTerritoryFile } }.GetNewClosure())

        $btnLoadXml.Add_Click({
                & $loadXml
            }.GetNewClosure())

        
        $getCfgEnvironmentGridFileRowsLocal = {
            param([System.Windows.Forms.DataGridView]$Grid)

            if (Get-Command -Name Get-UGSMGameDayZCfgEnvironmentGridFileRows -ErrorAction SilentlyContinue) {
                return @(Get-UGSMGameDayZCfgEnvironmentGridFileRows -Grid $Grid)
            }

            $rows = @()
            foreach ($gridRow in @($Grid.Rows)) {
                if ($null -eq $gridRow -or $gridRow.IsNewRow) { continue }
                $pathValue = [string]$gridRow.Cells['Path'].Value
                if ([string]::IsNullOrWhiteSpace($pathValue)) { continue }
                $rows += [pscustomobject]@{
                    Index = [string]$gridRow.Cells['Index'].Value
                    Path  = $pathValue.Trim()
                }
            }
            return @($rows)
        }.GetNewClosure()

        $getCfgEnvironmentGridTerritoryRowsLocal = {
            param([System.Windows.Forms.DataGridView]$Grid)

            if (Get-Command -Name Get-UGSMGameDayZCfgEnvironmentGridTerritoryRows -ErrorAction SilentlyContinue) {
                return @(Get-UGSMGameDayZCfgEnvironmentGridTerritoryRows -Grid $Grid)
            }

            $rows = @()
            foreach ($gridRow in @($Grid.Rows)) {
                if ($null -eq $gridRow -or $gridRow.IsNewRow) { continue }
                $name = [string]$gridRow.Cells['Name'].Value
                if ([string]::IsNullOrWhiteSpace($name)) { continue }
                $tag = $gridRow.Tag
                $rows += [pscustomobject]@{
                    Index      = [string]$gridRow.Cells['Index'].Value
                    Name       = $name.Trim()
                    Type       = [string]$gridRow.Cells['Type'].Value
                    Behavior   = [string]$gridRow.Cells['Behavior'].Value
                    FileUsable = [string]$gridRow.Cells['FileUsable'].Value
                    Agents     = [string]$gridRow.Cells['Agents'].Value
                    Spawns     = [string]$gridRow.Cells['Spawns'].Value
                    Items      = [string]$gridRow.Cells['Items'].Value
                    OuterXml   = if ($tag -and $tag.PSObject.Properties.Name -contains 'OuterXml') { [string]$tag.OuterXml } else { '' }
                }
            }
            return @($rows)
        }.GetNewClosure()


        $writeCfgEnvironmentRowsLocal = {
            param(
                [string]$Path,
                [object[]]$FileRows,
                [object[]]$TerritoryRows
            )

            if (Get-Command -Name Write-UGSMGameDayZCfgEnvironmentRows -ErrorAction SilentlyContinue) {
                return (Write-UGSMGameDayZCfgEnvironmentRows -Path $Path -FileRows $FileRows -TerritoryRows $TerritoryRows)
            }

            $settings = New-Object System.Xml.XmlWriterSettings
            $settings.Indent = $true
            $settings.IndentChars = '    '
            $settings.NewLineChars = [Environment]::NewLine
            $settings.NewLineHandling = [System.Xml.NewLineHandling]::Replace
            $settings.Encoding = New-Object System.Text.UTF8Encoding($false)

            $parent = Split-Path -Parent $Path
            if (-not [string]::IsNullOrWhiteSpace([string]$parent) -and -not (Test-Path -LiteralPath $parent -PathType Container)) {
                New-Item -ItemType Directory -Path $parent -Force | Out-Null
            }

            $writer = [System.Xml.XmlWriter]::Create($Path, $settings)
            try {
                $writer.WriteStartDocument()
                $writer.WriteStartElement('env')
                $writer.WriteStartElement('territories')

                foreach ($fileRow in @($FileRows)) {
                    if ($null -eq $fileRow) { continue }

                    $pathValue = [string]$fileRow.Path
                    if ([string]::IsNullOrWhiteSpace($pathValue)) { continue }

                    $writer.WriteStartElement('file')
                    $writer.WriteAttributeString('path', $pathValue.Trim())
                    $writer.WriteEndElement()
                }

                foreach ($territoryRow in @($TerritoryRows)) {
                    if ($null -eq $territoryRow) { continue }

                    $name = [string]$territoryRow.Name
                    if ([string]::IsNullOrWhiteSpace($name)) { continue }

                    $outerXml = [string]$territoryRow.OuterXml
                    $fragmentDoc = New-Object System.Xml.XmlDocument
                    $territoryNode = $null

                    if (-not [string]::IsNullOrWhiteSpace($outerXml)) {
                        try {
                            $fragmentDoc.LoadXml("<root>$outerXml</root>")
                            $territoryNode = $fragmentDoc.DocumentElement.SelectSingleNode('./territory')
                        }
                        catch {
                            $territoryNode = $null
                        }
                    }

                    if ($null -eq $territoryNode) {
                        $territoryNode = $fragmentDoc.CreateElement('territory')
                    }

                    [void]$territoryNode.SetAttribute('name', $name.Trim())
                    [void]$territoryNode.SetAttribute('type', ([string]$territoryRow.Type).Trim())
                    [void]$territoryNode.SetAttribute('behavior', ([string]$territoryRow.Behavior).Trim())

                    foreach ($oldFile in @($territoryNode.SelectNodes('./file'))) {
                        [void]$territoryNode.RemoveChild($oldFile)
                    }

                    $firstChild = $territoryNode.FirstChild
                    $fileUsables = @(([string]$territoryRow.FileUsable -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ }))
                    foreach ($usable in $fileUsables) {
                        $fileNode = $fragmentDoc.CreateElement('file')
                        [void]$fileNode.SetAttribute('usable', $usable)
                        if ($firstChild) {
                            [void]$territoryNode.InsertBefore($fileNode, $firstChild)
                        }
                        else {
                            [void]$territoryNode.AppendChild($fileNode)
                        }
                    }

                    try {
                        $writer.WriteRaw([string](Convert-UGSMGameDayZXmlNodeToPrettyString -Node $territoryNode))
                    }
                    catch {
                        $writer.WriteRaw([string]$territoryNode.OuterXml)
                    }
                }

                $writer.WriteEndElement()
                $writer.WriteEndElement()
                $writer.WriteEndDocument()
            }
            finally {
                if ($writer) { $writer.Dispose() }
            }

            return $Path
        }.GetNewClosure()

$btnSaveXml.Add_Click({
                try {
                    $kind = & $getSelectedKind
                    $targetPath = Get-UGSMGameDayZXmlEditorTargetPath -Instance $xmlInstance -Kind $kind
                    if ([string]::IsNullOrWhiteSpace([string]$targetPath)) { throw "No runtime XML path resolved for $kind." }

                    [void](Backup-UGSMGameDayZXmlFile -TargetPath $targetPath)

                    if ($kind -eq 'Types') {
                        if ($gridTypes.IsCurrentCellInEditMode) {
                            [void]$gridTypes.EndEdit()
                        }

                        & $syncGridToAllTypeRows
                        $rows = @($xmlTypeState.AllTypeRows)
                        [void](Write-UGSMGameDayZTypesXmlRows -Path $targetPath -Rows $rows)
                    }
                    elseif ($kind -eq 'EventSpawns') {
                        if ($gridEventSpawns.IsCurrentCellInEditMode) {
                            [void]$gridEventSpawns.EndEdit()
                        }
                        $rows = @(& $getEventSpawnsGridRowsLocal $gridEventSpawns)
                        [void](& $writeEventSpawnsRowsLocal $targetPath $rows)
                        $xmlEventSpawnState.AllRows = @($rows)
                    }
                    elseif ($kind -eq 'Events') {
                        $rows = @()

                        foreach ($gridRow in @($gridEvents.Rows)) {
                            if ($null -eq $gridRow -or $gridRow.IsNewRow) { continue }

                            $name = [string]$gridRow.Cells['Name'].Value
                            if ([string]::IsNullOrWhiteSpace($name)) { continue }

                            $tag = $gridRow.Tag

                            $rows += [pscustomobject]@{
                                Name               = $name.Trim()
                                Nominal            = [string]$gridRow.Cells['Nominal'].Value
                                Min                = [string]$gridRow.Cells['Min'].Value
                                Max                = [string]$gridRow.Cells['Max'].Value
                                Lifetime           = [string]$gridRow.Cells['Lifetime'].Value
                                Restock            = [string]$gridRow.Cells['Restock'].Value
                                Active             = [string]$gridRow.Cells['Active'].Value

                                SafeRadius         = if ($tag) { [string]$tag.SafeRadius } else { '' }
                                DistanceRadius     = if ($tag) { [string]$tag.DistanceRadius } else { '' }
                                CleanupRadius      = if ($tag) { [string]$tag.CleanupRadius } else { '' }
                                Position           = if ($tag) { [string]$tag.Position } else { '' }
                                Limit              = if ($tag) { [string]$tag.Limit } else { '' }

                                FlagsDeletable     = if ($tag) { [string]$tag.FlagsDeletable } else { '' }
                                FlagsInitRandom    = if ($tag) { [string]$tag.FlagsInitRandom } else { '' }
                                FlagsRemoveDamaged = if ($tag) { [string]$tag.FlagsRemoveDamaged } else { '' }

                                SecondaryOuterXml  = if ($tag) { [string]$tag.SecondaryOuterXml } else { '' }
                                ChildrenOuterXml   = if ($tag) { [string]$tag.ChildrenOuterXml } else { '' }
                                SecondaryNodesOuterXml = if ($tag) { [string]$tag.SecondaryNodesOuterXml } else { '' }
                            }
                        }

                        $xmlEventState.AllEventRows = @($rows)
                        [void](Write-UGSMGameDayZEventsXmlRows -Path $targetPath -Rows $rows)
                    }
                    elseif ($kind -eq 'SpawnableTypes') {
                        & $syncSpawnableGridToAllRows
                        $rows = @($xmlSpawnableTypeState.AllRows)
                        [void](Write-UGSMGameDayZSpawnableTypesXmlRows -Path $targetPath -Rows $rows)
                    }
                    elseif ($kind -eq 'Globals') {
                        $writerRows = @(Get-UGSMGameDayZGlobalsGridRows -Grid $gridVariables)
                        [void](Write-UGSMGameDayZGlobalsXmlRows -Path $targetPath -Rows $writerRows)
                    }
                    elseif ($kind -eq 'Economy') {
                        $writerRows = @(Get-UGSMGameDayZEconomyMatrixRowsFromGrid -Grid $gridEconomy)
                        [void](Write-UGSMGameDayZEconomyXmlRows -Path $targetPath -Rows $writerRows)
                    }
                    elseif ($kind -eq 'CfgGameplay') {
                        $updatedData = Update-UGSMGameDayZCfgGameplayDataFromRows -Data $cfgGameplayState.Data -Rows @($cfgGameplayState.Rows)
                        Write-UGSMGameDayZCfgGameplayJsonData -Path $targetPath -Data $updatedData
                    }
                    elseif ($kind -eq 'CfgEconomyCore') {
                        $rootClassRows = @(& $getCfgEconomyCoreRootClassGridRowsLocal $gridEconomyRootClasses)
                        $defaultRows = @(& $getCfgEconomyCoreDefaultGridRowsLocal $gridEconomyDefaults)
                        [void](& $writeCfgEconomyCoreRowsLocal $targetPath $rootClassRows $defaultRows)
                        $cfgEconomyCoreState.RootClassRows = @($rootClassRows)
                        $cfgEconomyCoreState.DefaultRows = @($defaultRows)
                    }
                    elseif ($kind -eq 'CfgEnvironment') {
                        $fileRows = @(& $getCfgEnvironmentGridFileRowsLocal $gridEnvFiles)
                        $territoryRows = @(& $getCfgEnvironmentGridTerritoryRowsLocal $gridEnvTerritories)
                        [void](& $writeCfgEnvironmentRowsLocal $targetPath $fileRows $territoryRows)
                    }
                    elseif ($kind -eq 'CfgEventGroups') {
                        if ($gridEventGroups.IsCurrentCellInEditMode) {
                            [void]$gridEventGroups.EndEdit()
                        }
                        $rows = @(& $getCfgEventGroupsGridRowsLocal $gridEventGroups)
                        [void](& $writeCfgEventGroupsRowsLocal $targetPath $rows)
                        $cfgEventGroupsState.Rows = @($rows)
                    }
                    elseif ($kind -eq 'CfgIgnoreList') {
                        if ($gridIgnoreList.IsCurrentCellInEditMode) {
                            [void]$gridIgnoreList.EndEdit()
                        }
                        $rows = @(& $getCfgIgnoreListGridRowsLocal $gridIgnoreList)
                        [void](& $writeCfgIgnoreListRowsLocal $targetPath $rows)
                        $cfgIgnoreListState.Rows = @($rows)
                    }
                    elseif ($kind -eq 'TerritoryZones') {
                        $activePath = [string]$cfgEnvironmentState.ActiveFile
                        if ([string]::IsNullOrWhiteSpace($activePath)) {
                            $activePath = [string]$targetPath
                        }

                        [void](Backup-UGSMGameDayZXmlFile -TargetPath $activePath)
                        $zoneRows = @(& $getTerritoryZoneGridRowsLocal $gridTerritoryZones)
                        [void](& $writeTerritoryZoneRowsLocal $activePath $zoneRows)
                    }
                    elseif ($miscEditorKinds -contains $kind) {
                        if ($gridMiscMain.IsCurrentCellInEditMode) { [void]$gridMiscMain.EndEdit() }
                        if ($gridMiscSub.Visible -and $gridMiscSub.IsCurrentCellInEditMode) { [void]$gridMiscSub.EndEdit() }
                        $mainRows = @(& $getGridRowsByColumns $gridMiscMain $miscEditorState.MainColumns)
                        $subRows = @(& $getGridRowsByColumns $gridMiscSub $miscEditorState.SubColumns)
                        [void](& $writeMiscRows $kind $targetPath $mainRows $subRows)
                        $miscEditorState.MainRows = @($mainRows)
                        $miscEditorState.SubRows = @($subRows)
                    }
                    elseif ($kind -eq 'Messages') {
                        [void](Write-UGSMGameDayZTextFileSafe -Path $targetPath -Content $txtXml.Text)
                    }
                    else {
                        [void](Write-UGSMGameDayZTextFileSafe -Path $targetPath -Content $txtXml.Text)
                    }

                    if ($xmlStatusLabel) { $xmlStatusLabel.Text = "Saved DayZ XML: $kind" }
                }
                catch {
                    if ($xmlStatusLabel) { $xmlStatusLabel.Text = 'Saving DayZ XML failed: ' + $_.Exception.Message }
                }
            }.GetNewClosure())

        $btnBackupXml.Add_Click({
                try {
                    $kind = & $getSelectedKind
                    $selectedModId = & $getSelectedXmlModId

                    if ($kind -eq 'Types') {
                        if (-not (& $ensureDayZFilesServiceLoaded 'Invoke-UGSMDayZPreviewSelectedModTypesMerge')) {
                            throw 'DayZFiles service type merge functions are not loaded. Make sure UGSM_Service_DayZFiles.ps1 v14+ is in the Services folder.'
                        }

                        if ($xmlStatusLabel) { $xmlStatusLabel.Text = ('Building selected mod types.xml preview for mod {0}...' -f $selectedModId) }
                        [System.Windows.Forms.Application]::DoEvents()

                        $plan = Invoke-UGSMDayZPreviewSelectedModTypesMerge -Instance $xmlInstance -ModId $selectedModId
                        if ($xmlStatusLabel) {
                            $xmlStatusLabel.Text = ('types.xml preview built for mod {0}. TypeFiles={1} Incoming={2} Add={3} SkipExisting={4} SkipDuplicate={5}.' -f $selectedModId, [int]$plan.ModTypeFileCount, [int]$plan.TotalIncomingTypeCount, [int]$plan.AddCount, [int]$plan.SkipExistingCount, [int]$plan.SkipDuplicateIncomingCount)
                        }
                    }
                    elseif ($kind -eq 'SpawnableTypes') {
                        if (-not (& $ensureDayZFilesServiceLoaded 'Invoke-UGSMDayZPreviewSelectedModSpawnableTypesMerge')) {
                            throw 'DayZFiles service spawnabletypes merge functions are not loaded. Make sure UGSM_Service_DayZFiles.ps1 v15+ is in the Services folder.'
                        }

                        if ($xmlStatusLabel) { $xmlStatusLabel.Text = ('Building selected mod cfgspawnabletypes.xml preview for mod {0}...' -f $selectedModId) }
                        [System.Windows.Forms.Application]::DoEvents()

                        $plan = Invoke-UGSMDayZPreviewSelectedModSpawnableTypesMerge -Instance $xmlInstance -ModId $selectedModId
                        if ($xmlStatusLabel) {
                            $xmlStatusLabel.Text = ('cfgspawnabletypes.xml preview built for mod {0}. Files={1} Incoming={2} Add={3} SkipExisting={4} SkipDuplicate={5}.' -f $selectedModId, [int]$plan.ModSpawnableTypeFileCount, [int]$plan.TotalIncomingSpawnableTypeCount, [int]$plan.AddCount, [int]$plan.SkipExistingCount, [int]$plan.SkipDuplicateIncomingCount)
                        }
                    }
                    elseif ($kind -eq 'Events') {
                        if (-not (& $ensureDayZFilesServiceLoaded 'Invoke-UGSMDayZPreviewSelectedModEventsMerge')) {
                            throw 'DayZFiles service events merge functions are not loaded. Make sure UGSM_Service_DayZFiles.ps1 v16+ is in the Services folder.'
                        }

                        if ($xmlStatusLabel) { $xmlStatusLabel.Text = ('Building selected mod events.xml preview for mod {0}...' -f $selectedModId) }
                        [System.Windows.Forms.Application]::DoEvents()

                        $plan = Invoke-UGSMDayZPreviewSelectedModEventsMerge -Instance $xmlInstance -ModId $selectedModId
                        if ($xmlStatusLabel) {
                            $xmlStatusLabel.Text = ('events.xml preview built for mod {0}. Files={1} Incoming={2} Add={3} SkipExisting={4} SkipDuplicate={5}.' -f $selectedModId, [int]$plan.ModEventFileCount, [int]$plan.TotalIncomingEventCount, [int]$plan.AddCount, [int]$plan.SkipExistingCount, [int]$plan.SkipDuplicateIncomingCount)
                        }
                    }
                    else {
                        throw 'Selected-mod apply is currently wired for types.xml, cfgspawnabletypes.xml, and events.xml only.'
                    }
                }
                catch {
                    if ($xmlStatusLabel) { $xmlStatusLabel.Text = 'Preview selected XML entries failed: ' + $_.Exception.Message }
                }
            }.GetNewClosure())

        $btnMergeXml.Add_Click({
                try {
                    $kind = & $getSelectedKind
                    $selectedModId = & $getSelectedXmlModId

                    if ($kind -eq 'Types') {
                        if (-not (& $ensureDayZFilesServiceLoaded 'Invoke-UGSMDayZApplySelectedModTypesMerge')) {
                            throw 'DayZFiles service type merge functions are not loaded. Make sure UGSM_Service_DayZFiles.ps1 v14+ is in the Services folder.'
                        }

                        $confirmText = ('This will add missing <type> entries from selected mod {0} into live db\types.xml. A backup will be made first. Continue?' -f $selectedModId)
                        $confirmTitle = 'Apply selected types.xml entries'
                    }
                    elseif ($kind -eq 'SpawnableTypes') {
                        if (-not (& $ensureDayZFilesServiceLoaded 'Invoke-UGSMDayZApplySelectedModSpawnableTypesMerge')) {
                            throw 'DayZFiles service spawnabletypes merge functions are not loaded. Make sure UGSM_Service_DayZFiles.ps1 v15+ is in the Services folder.'
                        }

                        $confirmText = ('This will add missing <type> entries from selected mod {0} into live cfgspawnabletypes.xml. Existing live type blocks are skipped. A backup will be made first. Continue?' -f $selectedModId)
                        $confirmTitle = 'Apply selected cfgspawnabletypes.xml entries'
                    }
                    elseif ($kind -eq 'Events') {
                        if (-not (& $ensureDayZFilesServiceLoaded 'Invoke-UGSMDayZApplySelectedModEventsMerge')) {
                            throw 'DayZFiles service events merge functions are not loaded. Make sure UGSM_Service_DayZFiles.ps1 v16+ is in the Services folder.'
                        }

                        $confirmText = ('This will add missing <event> entries from selected mod {0} into live db\events.xml. Existing live events are skipped. A backup will be made first. Continue?' -f $selectedModId)
                        $confirmTitle = 'Apply selected events.xml entries'
                    }
                    else {
                        throw 'Selected-mod apply is currently wired for types.xml, cfgspawnabletypes.xml, and events.xml only.'
                    }

                    $confirm = [System.Windows.Forms.MessageBox]::Show(
                        $confirmText,
                        $confirmTitle,
                        [System.Windows.Forms.MessageBoxButtons]::YesNo,
                        [System.Windows.Forms.MessageBoxIcon]::Warning
                    )
                    if ($confirm -ne [System.Windows.Forms.DialogResult]::Yes) {
                        if ($xmlStatusLabel) { $xmlStatusLabel.Text = 'Selected XML apply cancelled.' }
                        return
                    }

                    if ($kind -eq 'Types') {
                        if ($xmlStatusLabel) { $xmlStatusLabel.Text = ('Applying selected mod types.xml entries for mod {0}...' -f $selectedModId) }
                        [System.Windows.Forms.Application]::DoEvents()
                        $result = Invoke-UGSMDayZApplySelectedModTypesMerge -Instance $xmlInstance -ModId $selectedModId
                        if ($xmlStatusLabel) {
                            $xmlStatusLabel.Text = ('types.xml apply complete for mod {0}. Added={1} Skipped={2}. Backup={3}' -f $selectedModId, [int]$result.AddedCount, [int]$result.SkippedCount, [string]$result.BackupPath)
                        }
                    }
                    elseif ($kind -eq 'SpawnableTypes') {
                        if ($xmlStatusLabel) { $xmlStatusLabel.Text = ('Applying selected mod cfgspawnabletypes.xml entries for mod {0}...' -f $selectedModId) }
                        [System.Windows.Forms.Application]::DoEvents()
                        $result = Invoke-UGSMDayZApplySelectedModSpawnableTypesMerge -Instance $xmlInstance -ModId $selectedModId
                        if ($xmlStatusLabel) {
                            $xmlStatusLabel.Text = ('cfgspawnabletypes.xml apply complete for mod {0}. Added={1} Skipped={2}. Backup={3}' -f $selectedModId, [int]$result.AddedCount, [int]$result.SkippedCount, [string]$result.BackupPath)
                        }
                    }
                    elseif ($kind -eq 'Events') {
                        if ($xmlStatusLabel) { $xmlStatusLabel.Text = ('Applying selected mod events.xml entries for mod {0}...' -f $selectedModId) }
                        [System.Windows.Forms.Application]::DoEvents()
                        $result = Invoke-UGSMDayZApplySelectedModEventsMerge -Instance $xmlInstance -ModId $selectedModId
                        if ($xmlStatusLabel) {
                            $xmlStatusLabel.Text = ('events.xml apply complete for mod {0}. Added={1} Skipped={2}. Backup={3}' -f $selectedModId, [int]$result.AddedCount, [int]$result.SkippedCount, [string]$result.BackupPath)
                        }
                    }

                    & $loadXml
                }
                catch {
                    if ($xmlStatusLabel) { $xmlStatusLabel.Text = 'Apply selected XML entries failed: ' + $_.Exception.Message }
                }
            }.GetNewClosure())

        $btnXmlPreviewRemoved.Add_Click({
                try {
                    $kind = & $getSelectedKind

                    if ($kind -eq 'Types') {
                        if (-not (& $ensureDayZFilesServiceLoaded 'Invoke-UGSMDayZPreviewRemovedModTypesCleanup')) {
                            throw 'DayZFiles service cleanup functions are not loaded. Make sure UGSM_Service_DayZFiles.ps1 v14+ is in the Services folder.'
                        }

                        if ($xmlStatusLabel) { $xmlStatusLabel.Text = 'Building removed mod types.xml cleanup preview...' }
                        [System.Windows.Forms.Application]::DoEvents()

                        $plan = Invoke-UGSMDayZPreviewRemovedModTypesCleanup -Instance $xmlInstance
                        $label = 'types.xml'
                    }
                    elseif ($kind -eq 'SpawnableTypes') {
                        if (-not (& $ensureDayZFilesServiceLoaded 'Invoke-UGSMDayZPreviewRemovedModSpawnableTypesCleanup')) {
                            throw 'DayZFiles service spawnabletypes cleanup functions are not loaded. Make sure UGSM_Service_DayZFiles.ps1 v15+ is in the Services folder.'
                        }

                        if ($xmlStatusLabel) { $xmlStatusLabel.Text = 'Building removed mod cfgspawnabletypes.xml cleanup preview...' }
                        [System.Windows.Forms.Application]::DoEvents()

                        $plan = Invoke-UGSMDayZPreviewRemovedModSpawnableTypesCleanup -Instance $xmlInstance
                        $label = 'cfgspawnabletypes.xml'
                    }
                    elseif ($kind -eq 'Events') {
                        if (-not (& $ensureDayZFilesServiceLoaded 'Invoke-UGSMDayZPreviewRemovedModEventsCleanup')) {
                            throw 'DayZFiles service events cleanup functions are not loaded. Make sure UGSM_Service_DayZFiles.ps1 v16+ is in the Services folder.'
                        }

                        if ($xmlStatusLabel) { $xmlStatusLabel.Text = 'Building removed mod events.xml cleanup preview...' }
                        [System.Windows.Forms.Application]::DoEvents()

                        $plan = Invoke-UGSMDayZPreviewRemovedModEventsCleanup -Instance $xmlInstance
                        $label = 'events.xml'
                    }
                    else {
                        throw 'Removed-mod cleanup is currently wired for types.xml, cfgspawnabletypes.xml, and events.xml only.'
                    }

                    $inactiveText = ''
                    if ($plan.InactiveModIds -and @($plan.InactiveModIds).Count -gt 0) {
                        $inactiveText = ' RemovedMods=' + ((@($plan.InactiveModIds) -join ','))
                    }

                    if ($xmlStatusLabel) {
                        $xmlStatusLabel.Text = ('{0} cleanup preview built. Ledger={1} Remove={2} SkipActive={3} SkipMissing={4}.{5}' -f $label, [int]$plan.LedgerEntryCount, [int]$plan.RemoveCount, [int]$plan.SkipActiveCount, [int]$plan.SkipMissingLiveCount, $inactiveText)
                    }
                }
                catch {
                    if ($xmlStatusLabel) { $xmlStatusLabel.Text = 'Preview removed XML cleanup failed: ' + $_.Exception.Message }
                }
            }.GetNewClosure())

        $btnXmlApplyRemoved.Add_Click({
                try {
                    $kind = & $getSelectedKind

                    if ($kind -eq 'Types') {
                        if (-not (& $ensureDayZFilesServiceLoaded 'Invoke-UGSMDayZApplyRemovedModTypesCleanup')) {
                            throw 'DayZFiles service cleanup functions are not loaded. Make sure UGSM_Service_DayZFiles.ps1 v14+ is in the Services folder.'
                        }

                        $preview = Invoke-UGSMDayZPreviewRemovedModTypesCleanup -Instance $xmlInstance
                        $label = 'types.xml'
                        $applyCommand = 'Types'
                    }
                    elseif ($kind -eq 'SpawnableTypes') {
                        if (-not (& $ensureDayZFilesServiceLoaded 'Invoke-UGSMDayZApplyRemovedModSpawnableTypesCleanup')) {
                            throw 'DayZFiles service spawnabletypes cleanup functions are not loaded. Make sure UGSM_Service_DayZFiles.ps1 v15+ is in the Services folder.'
                        }

                        $preview = Invoke-UGSMDayZPreviewRemovedModSpawnableTypesCleanup -Instance $xmlInstance
                        $label = 'cfgspawnabletypes.xml'
                        $applyCommand = 'SpawnableTypes'
                    }
                    elseif ($kind -eq 'Events') {
                        if (-not (& $ensureDayZFilesServiceLoaded 'Invoke-UGSMDayZApplyRemovedModEventsCleanup')) {
                            throw 'DayZFiles service events cleanup functions are not loaded. Make sure UGSM_Service_DayZFiles.ps1 v16+ is in the Services folder.'
                        }

                        $preview = Invoke-UGSMDayZPreviewRemovedModEventsCleanup -Instance $xmlInstance
                        $label = 'events.xml'
                        $applyCommand = 'Events'
                    }
                    else {
                        throw 'Removed-mod cleanup is currently wired for types.xml, cfgspawnabletypes.xml, and events.xml only.'
                    }

                    if ([int]$preview.RemoveCount -le 0) {
                        if ($xmlStatusLabel) { $xmlStatusLabel.Text = ('No removed mod {0} entries need cleanup.' -f $label) }
                        return
                    }

                    $inactiveText = ''
                    if ($preview.InactiveModIds -and @($preview.InactiveModIds).Count -gt 0) {
                        $inactiveText = (@($preview.InactiveModIds) -join ', ')
                    }

                    $confirm = [System.Windows.Forms.MessageBox]::Show(
                        ('This will remove {0} UGSM-owned entries from live {1} for removed/disabled mod(s): {2}. Continue?' -f [int]$preview.RemoveCount, $label, $inactiveText),
                        ('Apply removed {0} cleanup' -f $label),
                        [System.Windows.Forms.MessageBoxButtons]::YesNo,
                        [System.Windows.Forms.MessageBoxIcon]::Warning
                    )
                    if ($confirm -ne [System.Windows.Forms.DialogResult]::Yes) {
                        if ($xmlStatusLabel) { $xmlStatusLabel.Text = ('Removed {0} cleanup cancelled.' -f $label) }
                        return
                    }

                    if ($xmlStatusLabel) { $xmlStatusLabel.Text = ('Applying removed mod {0} cleanup...' -f $label) }
                    [System.Windows.Forms.Application]::DoEvents()

                    if ($applyCommand -eq 'Types') {
                        $result = Invoke-UGSMDayZApplyRemovedModTypesCleanup -Instance $xmlInstance
                    }
                    elseif ($applyCommand -eq 'SpawnableTypes') {
                        $result = Invoke-UGSMDayZApplyRemovedModSpawnableTypesCleanup -Instance $xmlInstance
                    }
                    else {
                        $result = Invoke-UGSMDayZApplyRemovedModEventsCleanup -Instance $xmlInstance
                    }

                    if ($xmlStatusLabel) {
                        $xmlStatusLabel.Text = ('{0} cleanup complete. Removed={1} Skipped={2}. Backup={3}' -f $label, [int]$result.RemovedCount, [int]$result.SkippedCount, [string]$result.BackupPath)
                    }

                    & $loadXml
                }
                catch {
                    if ($xmlStatusLabel) { $xmlStatusLabel.Text = 'Apply removed XML cleanup failed: ' + $_.Exception.Message }
                }
            }.GetNewClosure())

        & $resizeXmlLayout
        & $refreshEditorMode
        & $loadXml
    }

    function New-DayZVppAdminContent {
        param(
            [Parameter(Mandatory)][System.Windows.Forms.Control]$Parent
        )

        $adminInstance = $editorInstance
        $adminStatusLabel = $editorStatusLabel

        $roleDefaults = @('SuperAdmin', 'Admin', 'Moderator')

        $scroll = New-Object System.Windows.Forms.Panel
        $scroll.Dock = 'Fill'
        $scroll.AutoScroll = $true
        $scroll.BackColor = New-UGSMColor '#0B121D'
        [void]$Parent.Controls.Add($scroll)

        $content = New-Object System.Windows.Forms.Panel
        $content.Dock = 'Top'
        $content.Height = 720
        $content.Padding = New-Object System.Windows.Forms.Padding(12, 10, 12, 10)
        $content.BackColor = New-UGSMColor '#0B121D'
        [void]$scroll.Controls.Add($content)

        $desc = New-UGSMLabel -Text 'Manage VPPAdminTools runtime admin files for this DayZ instance.' -X 0 -Y 0 -Width 1200 -Height 20 -FontSize 8.5 -Color $Theme.Muted
        [void]$content.Controls.Add($desc)

        $lblInfo = New-UGSMLabel -Text '' -X 0 -Y 22 -Width 1500 -Height 18 -FontSize 8 -Color $Theme.Muted
        [void]$content.Controls.Add($lblInfo)

        $leftGroup = New-Object System.Windows.Forms.GroupBox
        $leftGroup.Text = 'Super Admins (SuperAdmins.txt)'
        $leftGroup.Location = New-Object System.Drawing.Point(0, 52)
        $leftGroup.Size = New-Object System.Drawing.Size(450, 250)
        $leftGroup.ForeColor = [System.Drawing.Color]::White
        [void]$content.Controls.Add($leftGroup)

        $lstSuperAdmins = New-Object System.Windows.Forms.ListBox
        $lstSuperAdmins.Location = New-Object System.Drawing.Point(15, 25)
        $lstSuperAdmins.Size = New-Object System.Drawing.Size(280, 150)
        [void]$leftGroup.Controls.Add($lstSuperAdmins)

        $lblSuperId = New-UGSMLabel -Text 'Steam64 ID:' -X 15 -Y 188 -Width 80 -Height 20 -FontSize 8.5 -Color $Theme.Text
        [void]$leftGroup.Controls.Add($lblSuperId)

        $txtSuperAdminId = New-DayZTextBox -Width 190
        $txtSuperAdminId.Location = New-Object System.Drawing.Point(100, 184)
        [void]$leftGroup.Controls.Add($txtSuperAdminId)

        $btnAddSuper = New-UGSMButton -Text 'Add' -X 315 -Y 184 -Width 80 -Height 28 -BackColor $Theme.AccentBlue
        $btnRemoveSuper = New-UGSMButton -Text 'Remove' -X 315 -Y 148 -Width 80 -Height 28 -BackColor '#253341'
        [void]$leftGroup.Controls.Add($btnAddSuper)
        [void]$leftGroup.Controls.Add($btnRemoveSuper)

        $credGroup = New-Object System.Windows.Forms.GroupBox
        $credGroup.Text = 'In-Game Login Password (credentials.txt)'
        $credGroup.Location = New-Object System.Drawing.Point(0, 320)
        $credGroup.Size = New-Object System.Drawing.Size(450, 100)
        $credGroup.ForeColor = [System.Drawing.Color]::White
        [void]$content.Controls.Add($credGroup)

        $lblCred = New-UGSMLabel -Text 'Password:' -X 15 -Y 28 -Width 75 -Height 20 -FontSize 8.5 -Color $Theme.Text
        [void]$credGroup.Controls.Add($lblCred)

        $txtCredentials = New-DayZTextBox -Width 292
        $txtCredentials.Location = New-Object System.Drawing.Point(100, 24)
        [void]$credGroup.Controls.Add($txtCredentials)

        $credHint = New-UGSMLabel -Text 'All admins (including Super Admins) use this password to log in.' -X 15 -Y 58 -Width 400 -Height 18 -FontSize 8 -Color $Theme.Muted
        [void]$credGroup.Controls.Add($credHint)

        $btnLoadAdmin = New-UGSMButton -Text 'Load All VPP Files' -X 0 -Y 438 -Width 150 -Height 30 -BackColor '#253341'
        $btnSaveAdmin = New-UGSMButton -Text 'Save All VPP Files' -X 165 -Y 438 -Width 150 -Height 30 -BackColor $Theme.Accent
        [void]$content.Controls.Add($btnLoadAdmin)
        [void]$content.Controls.Add($btnSaveAdmin)

        $rightGroup = New-Object System.Windows.Forms.GroupBox
        $rightGroup.Text = 'Role Permissions (Permissions.json)'
        $rightGroup.Location = New-Object System.Drawing.Point(480, 52)
        $rightGroup.Size = New-Object System.Drawing.Size(600, 430)
        $rightGroup.ForeColor = [System.Drawing.Color]::White
        [void]$content.Controls.Add($rightGroup)

        $permHint = New-UGSMLabel -Text 'Manage roles like Admin, Moderator, etc. These users still need the password below to log in.' -X 15 -Y 20 -Width 560 -Height 18 -FontSize 8 -Color $Theme.Muted
        [void]$rightGroup.Controls.Add($permHint)

        $gridPlayers = New-Object System.Windows.Forms.DataGridView
        $gridPlayers.Location = New-Object System.Drawing.Point(15, 45)
        $gridPlayers.Size = New-Object System.Drawing.Size(560, 250)
        $gridPlayers.AllowUserToAddRows = $false
        $gridPlayers.AllowUserToDeleteRows = $false
        $gridPlayers.AllowUserToResizeRows = $false
        $gridPlayers.RowHeadersVisible = $false
        $gridPlayers.SelectionMode = 'FullRowSelect'
        $gridPlayers.MultiSelect = $false
        $gridPlayers.BackgroundColor = [System.Drawing.Color]::White
        $gridPlayers.BorderStyle = 'FixedSingle'
        [void]$gridPlayers.Columns.Add('SteamID', 'Steam64 ID')
        [void]$gridPlayers.Columns.Add('RoleName', 'Role')
        $gridPlayers.Columns[0].Width = 280
        $gridPlayers.Columns[1].Width = 220
        [void]$rightGroup.Controls.Add($gridPlayers)

        $gridPlayers.DefaultCellStyle.ForeColor = [System.Drawing.Color]::Black
        $gridPlayers.DefaultCellStyle.BackColor = [System.Drawing.Color]::White
        $gridPlayers.DefaultCellStyle.SelectionForeColor = [System.Drawing.Color]::White
        $gridPlayers.DefaultCellStyle.SelectionBackColor = [System.Drawing.Color]::FromArgb(0, 120, 215)

        $gridPlayers.RowsDefaultCellStyle.ForeColor = [System.Drawing.Color]::Black
        $gridPlayers.RowsDefaultCellStyle.BackColor = [System.Drawing.Color]::White
        $gridPlayers.AlternatingRowsDefaultCellStyle.ForeColor = [System.Drawing.Color]::Black
        $gridPlayers.AlternatingRowsDefaultCellStyle.BackColor = [System.Drawing.Color]::White

        $gridPlayers.ColumnHeadersDefaultCellStyle.ForeColor = [System.Drawing.Color]::Black
        $gridPlayers.ColumnHeadersDefaultCellStyle.BackColor = [System.Drawing.Color]::White
        $gridPlayers.EnableHeadersVisualStyles = $false

        $lblPlayerId = New-UGSMLabel -Text 'Steam64 ID:' -X 15 -Y 320 -Width 80 -Height 20 -FontSize 8.5 -Color $Theme.Text
        [void]$rightGroup.Controls.Add($lblPlayerId)

        $txtPlayerSteamId = New-DayZTextBox -Width 190
        $txtPlayerSteamId.Location = New-Object System.Drawing.Point(100, 316)
        [void]$rightGroup.Controls.Add($txtPlayerSteamId)

        $lblRole = New-UGSMLabel -Text 'Role:' -X 310 -Y 320 -Width 40 -Height 20 -FontSize 8.5 -Color $Theme.Text
        [void]$rightGroup.Controls.Add($lblRole)

        $cmbPlayerRole = New-Object System.Windows.Forms.ComboBox
        $cmbPlayerRole.DropDownStyle = [System.Windows.Forms.ComboBoxStyle]::DropDownList
        $cmbPlayerRole.Location = New-Object System.Drawing.Point(355, 316)
        $cmbPlayerRole.Size = New-Object System.Drawing.Size(120, 22)
        [void]$rightGroup.Controls.Add($cmbPlayerRole)

        $btnAddPlayer = New-UGSMButton -Text 'Add/Set' -X 490 -Y 314 -Width 80 -Height 28 -BackColor $Theme.AccentBlue
        $btnRemovePlayer = New-UGSMButton -Text 'Remove Selected' -X 15 -Y 370 -Width 120 -Height 28 -BackColor '#253341'
        [void]$rightGroup.Controls.Add($btnAddPlayer)
        [void]$rightGroup.Controls.Add($btnRemovePlayer)

        $setRoleOptions = {
            param([object[]]$Names)

            $selectedText = [string]$cmbPlayerRole.Text
            $items = @()
            foreach ($name in @($roleDefaults + @($Names))) {
                $text = [string]$name
                if ([string]::IsNullOrWhiteSpace($text)) { continue }
                if ($items -notcontains $text) { $items += $text }
            }

            $cmbPlayerRole.Items.Clear()
            foreach ($item in @($items)) {
                [void]$cmbPlayerRole.Items.Add($item)
            }

            if (-not [string]::IsNullOrWhiteSpace($selectedText) -and $cmbPlayerRole.Items.Contains($selectedText)) {
                $cmbPlayerRole.SelectedItem = $selectedText
            }
            elseif ($cmbPlayerRole.Items.Count -gt 0) {
                $cmbPlayerRole.SelectedIndex = 0
            }
        }.GetNewClosure()

        $loadAdmin = {
            try {
                $data = Read-UGSMGameDayZVppAdminData -Instance $adminInstance

                $roleNames = @()
                if ($data.RawPermissions) {
                    if ($data.RawPermissions.PSObject.Properties.Name -contains 'UserGroups' -and $data.RawPermissions.UserGroups) {
                        foreach ($group in @($data.RawPermissions.UserGroups)) {
                            if ($null -eq $group) { continue }
                            $groupName = ''
                            if ($group.PSObject.Properties.Name -contains 'GroupName') { $groupName = [string]$group.GroupName }
                            elseif ($group.PSObject.Properties.Name -contains 'Name') { $groupName = [string]$group.Name }
                            if (-not [string]::IsNullOrWhiteSpace($groupName)) { $roleNames += $groupName }
                        }
                    }
                    elseif ($data.RawPermissions.PSObject.Properties.Name -contains 'Roles' -and $data.RawPermissions.Roles) {
                        foreach ($role in @($data.RawPermissions.Roles)) {
                            $roleName = [string]$role
                            if (-not [string]::IsNullOrWhiteSpace($roleName)) { $roleNames += $roleName }
                        }
                    }
                }
                & $setRoleOptions @($roleNames)

                $gridPlayers.Rows.Clear()
                foreach ($player in @($data.Players)) {
                    [void]$gridPlayers.Rows.Add([string]$player.SteamID, [string]$player.RoleName)
                }

                $lstSuperAdmins.Items.Clear()
                foreach ($steamId in @($data.SuperAdmins)) {
                    [void]$lstSuperAdmins.Items.Add([string]$steamId)
                }

                $txtCredentials.Text = [string]$data.Credentials
                $txtPlayerSteamId.Clear()
                $txtSuperAdminId.Clear()

                if ($gridPlayers.Rows.Count -gt 0) {
                    $gridPlayers.ClearSelection()
                    $gridPlayers.Rows[0].Selected = $true
                    $txtPlayerSteamId.Text = [string]$gridPlayers.Rows[0].Cells[0].Value
                    $roleText = [string]$gridPlayers.Rows[0].Cells[1].Value
                    if ($cmbPlayerRole.Items.Contains($roleText)) { $cmbPlayerRole.SelectedItem = $roleText }
                }

                if ($data.Messages -and @($data.Messages).Count -gt 0) {
                    $lblInfo.Text = ((@($data.Messages)) -join ' | ')
                }
                else {
                    $lblInfo.Text = ('Loaded VPP admin runtime files from ' + [string]$data.Paths.PermissionsRoot)
                }

                if ($adminStatusLabel) { $adminStatusLabel.Text = 'Loaded DayZ VPP admin data.' }
            }
            catch {
                if ($adminStatusLabel) { $adminStatusLabel.Text = 'Loading DayZ VPP admin data failed: ' + $_.Exception.Message }
            }
        }.GetNewClosure()

        $btnLoadAdmin.Add_Click({ & $loadAdmin }.GetNewClosure())

        $gridPlayers.Add_SelectionChanged({
                if ($gridPlayers.SelectedRows.Count -gt 0) {
                    $row = $gridPlayers.SelectedRows[0]
                    $txtPlayerSteamId.Text = [string]$row.Cells[0].Value
                    $roleText = [string]$row.Cells[1].Value
                    if ($cmbPlayerRole.Items.Contains($roleText)) {
                        $cmbPlayerRole.SelectedItem = $roleText
                    }
                }
            }.GetNewClosure())

        $lstSuperAdmins.Add_SelectedIndexChanged({
                if ($lstSuperAdmins.SelectedIndex -ge 0) {
                    $txtSuperAdminId.Text = [string]$lstSuperAdmins.SelectedItem
                }
            }.GetNewClosure())

        $btnAddPlayer.Add_Click({
                try {
                    $steamId = [string]$txtPlayerSteamId.Text
                    $roleName = [string]$cmbPlayerRole.Text
                    if ([string]::IsNullOrWhiteSpace($steamId)) { throw 'Enter a Steam64 ID first.' }
                    if ([string]::IsNullOrWhiteSpace($roleName)) { throw 'Select a role first.' }

                    $steamId = $steamId.Trim()
                    $roleName = $roleName.Trim()

                    $updated = $false
                    foreach ($row in @($gridPlayers.Rows)) {
                        if ($null -eq $row -or $row.IsNewRow) { continue }
                        if ([string]$row.Cells[0].Value -eq $steamId) {
                            $row.Cells[1].Value = $roleName
                            $updated = $true
                            break
                        }
                    }

                    if (-not $updated) {
                        [void]$gridPlayers.Rows.Add($steamId, $roleName)
                    }

                    if ($adminStatusLabel) { $adminStatusLabel.Text = 'Updated VPP permissions entry.' }
                }
                catch {
                    if ($adminStatusLabel) { $adminStatusLabel.Text = 'Updating VPP permissions entry failed: ' + $_.Exception.Message }
                }
            }.GetNewClosure())

        $btnRemovePlayer.Add_Click({
                if ($gridPlayers.SelectedRows.Count -gt 0) {
                    $gridPlayers.Rows.Remove($gridPlayers.SelectedRows[0])
                    if ($adminStatusLabel) { $adminStatusLabel.Text = 'Removed selected VPP permissions entry.' }
                }
            }.GetNewClosure())

        $btnAddSuper.Add_Click({
                try {
                    $steamId = [string]$txtSuperAdminId.Text
                    if ([string]::IsNullOrWhiteSpace($steamId)) { throw 'Enter a Steam64 ID first.' }
                    $steamId = $steamId.Trim()
                    if (-not $lstSuperAdmins.Items.Contains($steamId)) {
                        [void]$lstSuperAdmins.Items.Add($steamId)
                    }
                    if ($adminStatusLabel) { $adminStatusLabel.Text = 'Added VPP Super Admin.' }
                }
                catch {
                    if ($adminStatusLabel) { $adminStatusLabel.Text = 'Adding VPP Super Admin failed: ' + $_.Exception.Message }
                }
            }.GetNewClosure())

        $btnRemoveSuper.Add_Click({
                if ($lstSuperAdmins.SelectedIndex -ge 0) {
                    $lstSuperAdmins.Items.RemoveAt($lstSuperAdmins.SelectedIndex)
                    $txtSuperAdminId.Clear()
                    if ($adminStatusLabel) { $adminStatusLabel.Text = 'Removed VPP Super Admin.' }
                }
            }.GetNewClosure())

        $btnSaveAdmin.Add_Click({
                try {
                    $players = @()
                    foreach ($row in @($gridPlayers.Rows)) {
                        if ($null -eq $row -or $row.IsNewRow) { continue }
                        $steamId = [string]$row.Cells[0].Value
                        $roleName = [string]$row.Cells[1].Value
                        if ([string]::IsNullOrWhiteSpace($steamId)) { continue }
                        if ([string]::IsNullOrWhiteSpace($roleName)) { continue }
                        $players += [pscustomobject]@{ SteamID = $steamId.Trim(); RoleName = $roleName.Trim() }
                    }

                    $superAdmins = @()
                    foreach ($item in @($lstSuperAdmins.Items)) {
                        $value = [string]$item
                        if ([string]::IsNullOrWhiteSpace($value)) { continue }
                        $superAdmins += $value.Trim()
                    }

                    $credentials = [string]$txtCredentials.Text

                    [void](Save-UGSMGameDayZVppAdminData -Instance $adminInstance -Players $players -SuperAdmins $superAdmins -Credentials $credentials)
                    if ($adminStatusLabel) { $adminStatusLabel.Text = 'Saved DayZ VPP admin runtime files.' }
                    & $loadAdmin
                }
                catch {
                    if ($adminStatusLabel) { $adminStatusLabel.Text = 'Saving DayZ VPP admin data failed: ' + $_.Exception.Message }
                }
            }.GetNewClosure())

        & $setRoleOptions @()
        & $loadAdmin
    }


    

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

    $title = New-UGSMLabel -Text ('DayZ Profile Editor - ' + [string]$Instance.Name) -X 12 -Y 10 -Width 420 -Height 18 -FontSize 10 -Style Bold -Color $Theme.Text
    $pathLabel = New-UGSMLabel -Text ([string]$paths.ProfileRoot) -X 12 -Y 28 -Width 760 -Height 16 -FontSize 8 -Color $Theme.Muted
    [void]$header.Controls.Add($title)
    [void]$header.Controls.Add($pathLabel)

    $toolbar = New-Object System.Windows.Forms.Panel
    $toolbar.Dock = 'Fill'
    $toolbar.BackColor = New-UGSMColor '#09111B'
    [void]$root.Controls.Add($toolbar, 0, 1)

    $btnReload = New-UGSMButton -Text 'Reload' -X 0 -Y 6 -Width 84 -Height 28 -BackColor '#253341'
    $btnSave = New-UGSMButton -Text 'Save All' -X 0 -Y 6 -Width 96 -Height 28 -BackColor $Theme.Accent

    $btnReload.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Right
    $btnSave.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Right

    [void]$toolbar.Controls.Add($btnReload)
    [void]$toolbar.Controls.Add($btnSave)

    $positionToolbarButtons = {
        if (-not $toolbar -or $toolbar.IsDisposed) { return }
        $rightPadding = 10
        $top = 6

        $btnSave.Left = $toolbar.ClientSize.Width - $btnSave.Width - $rightPadding
        $btnSave.Top = $top

        $btnReload.Left = $btnSave.Left - $btnReload.Width - 8
        $btnReload.Top = $top

        $btnSave.BringToFront()
        $btnReload.BringToFront()
    }.GetNewClosure()

    & $positionToolbarButtons
    $toolbar.Add_SizeChanged({ & $positionToolbarButtons }.GetNewClosure())


    $btnSave.Add_Click({
            try {
                if ($StatusLabel) {
                    $StatusLabel.Text = 'Saving DayZ runtime settings...'
                    $StatusLabel.Refresh()
                }

                $result = Save-UGSMGameDayZInstanceEditor -Instance $editorInstance -EditorState $controlMap

                if ($result -and $result.PSObject.Properties.Name -contains 'Instance' -and $null -ne $result.Instance) {
                    $editorInstance = $result.Instance
                    $editorPaths = Get-UGSMGameDayZProfilePaths -Instance $editorInstance
                }

                if ($StatusLabel) {
                    $StatusLabel.Text = [string]$(if ($result -and $result.PSObject.Properties.Name -contains 'Message') {
                            $result.Message
                        }
                        else {
                            'Saved DayZ runtime settings.'
                        })
                    $StatusLabel.Refresh()
                }

                $HostPanel.Refresh()
            }
            catch {
                if ($StatusLabel) {
                    $StatusLabel.Text = 'DayZ save failed: ' + $_.Exception.Message
                    $StatusLabel.Refresh()
                }
            }
        }.GetNewClosure())

    $btnReload.Add_Click({
            try {
                if ($StatusLabel) {
                    $StatusLabel.Text = 'Reloading DayZ runtime settings...'
                    $StatusLabel.Refresh()
                }

                [void](New-UGSMGameDayZInstanceEditor -Instance $editorInstance -Theme $Theme -HostPanel $HostPanel -StatusLabel $StatusLabel)

                $HostPanel.PerformLayout()
                $HostPanel.Refresh()

                if ($StatusLabel) {
                    $StatusLabel.Text = 'DayZ profile editor reloaded.'
                    $StatusLabel.Refresh()
                }
            }
            catch {
                if ($StatusLabel) {
                    $StatusLabel.Text = 'DayZ reload failed: ' + $_.Exception.Message
                    $StatusLabel.Refresh()
                }
            }
        }.GetNewClosure())

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
                New-DayZEditorContent -Parent $subPage -Description ([string]$(if ($subDef.PSObject.Properties.Name -contains 'Description') { $subDef.Description } else { '' })) -Fields @($subDef.Fields)
            }
        }
        else {
            New-DayZEditorContent -Parent $tabPage -Description ([string]$(if ($tabDef.PSObject.Properties.Name -contains 'Description') { $tabDef.Description } else { '' })) -Fields @($tabDef.Fields)
        }
    }

    #Write-UGSMGameDayZDebug "Starting DayZ editor build."

    $modsTab = New-Object System.Windows.Forms.TabPage
    $modsTab.Text = 'Mods'
    $modsTab.BackColor = New-UGSMColor '#0B121D'
    [void]$tabs.TabPages.Add($modsTab)
    #Write-UGSMGameDayZDebug "Added Mods tab."
    New-DayZModsContent -Parent $modsTab
    #Write-UGSMGameDayZDebug "Built Mods tab content."

    $xmlTab = New-Object System.Windows.Forms.TabPage
    $xmlTab.Text = 'XML'
    $xmlTab.BackColor = New-UGSMColor '#0B121D'
    [void]$tabs.TabPages.Add($xmlTab)
    #Write-UGSMGameDayZDebug "Added XML tab."
    try {
        New-DayZXmlContent -Parent $xmlTab
        #Write-UGSMGameDayZDebug "Built XML tab content."
    }
    catch {
        #Write-UGSMGameDayZDebug ("XML tab init failed: " + $_.Exception.Message)
        throw
    }

    $traderPlusTab = New-Object System.Windows.Forms.TabPage
    $traderPlusTab.Text = 'TraderPlus'
    $traderPlusTab.BackColor = New-UGSMColor '#0B121D'
    [void]$tabs.TabPages.Add($traderPlusTab)
    try {
        if (Get-Command -Name New-DayZTraderPlusContent -ErrorAction SilentlyContinue) {
            New-DayZTraderPlusContent -Parent $traderPlusTab -Instance $editorInstance -Theme $Theme -StatusLabel $editorStatusLabel
        }
        else {
            throw 'New-DayZTraderPlusContent was not found.'
        }
    }
    catch {
        throw
    }


    Write-UGSMGameDayZDebug ('Expansion function found: ' + [string][bool](Get-Command -Name New-DayZExpansionContent -ErrorAction SilentlyContinue))

    $expansionTab = New-Object System.Windows.Forms.TabPage
    $expansionTab.Text = 'Expansion'
    $expansionTab.BackColor = New-UGSMColor '#0B121D'
    [void]$tabs.TabPages.Add($expansionTab)

    try {
        if (Get-Command -Name New-DayZExpansionContent -ErrorAction SilentlyContinue) {
            New-DayZExpansionContent -Parent $expansionTab -Instance $editorInstance -StatusLabel $editorStatusLabel
        }
        else {
            $label = New-Object System.Windows.Forms.Label
            $label.Text = 'New-DayZExpansionContent was not found.'
            $label.ForeColor = [System.Drawing.Color]::White
            $label.AutoSize = $true
            $label.Location = New-Object System.Drawing.Point(12, 12)
            [void]$expansionTab.Controls.Add($label)
        }
    }
    catch {
        $label = New-Object System.Windows.Forms.Label
        $label.Text = ('Expansion tab failed: ' + $_.Exception.Message)
        $label.ForeColor = [System.Drawing.Color]::White
        $label.AutoSize = $true
        $label.Location = New-Object System.Drawing.Point(12, 12)
        [void]$expansionTab.Controls.Add($label)

        Write-UGSMGameDayZDebug ('Expansion tab init failed: ' + $_.Exception.Message)
    }
   

    $adminTab = New-Object System.Windows.Forms.TabPage
    $adminTab.Text = 'Admin'
    $adminTab.BackColor = New-UGSMColor '#0B121D'
    [void]$tabs.TabPages.Add($adminTab)
    #Write-UGSMGameDayZDebug "Added Admin tab."
    try {
        New-DayZVppAdminContent -Parent $adminTab
        #Write-UGSMGameDayZDebug "Built Admin tab content."
    }
    catch {
        Write-UGSMGameDayZDebug ("Admin tab init failed: " + $_.Exception.Message)
        throw
    }

    $toolbar.BringToFront()
    $btnSave.BringToFront()
    $btnReload.BringToFront()

    $root.Tag = [pscustomobject]@{
        Instance   = $Instance
        Paths      = $paths
        ControlMap = $controlMap
        Schema     = $schema
        Status     = $StatusLabel
    }

    if ($StatusLabel) { $StatusLabel.Text = ('DayZ profile editor loaded. Tabs=' + $tabs.TabPages.Count) }
    return $root
}


function Get-UGSMGameDayZXmlElementPath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][System.Xml.XmlElement]$Element
    )

    $segments = New-Object System.Collections.Generic.List[string]
    $current = $Element

    while ($current -is [System.Xml.XmlElement]) {
        $parent = $current.ParentNode
        $index = 1

        if ($parent -is [System.Xml.XmlElement] -or $parent -is [System.Xml.XmlDocument]) {
            foreach ($sibling in @($parent.ChildNodes)) {
                if ($sibling -isnot [System.Xml.XmlElement]) { continue }
                if ($sibling.Name -ne $current.Name) { continue }
                if ($sibling -eq $current) { break }
                $index++
            }
        }

        $segments.Insert(0, ('{0}[{1}]' -f $current.Name, $index))
        $current = if ($parent -is [System.Xml.XmlElement]) { $parent } else { $null }
    }

    return '/' + ($segments -join '/')
}

function Read-UGSMGameDayZSimpleXmlRows {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Path
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "XML file not found: $Path"
    }

    $doc = New-Object System.Xml.XmlDocument
    $doc.PreserveWhitespace = $true
    $doc.Load($Path)

    $rows = New-Object System.Collections.Generic.List[object]

    $visit = $null
    $visit = {
        param([System.Xml.XmlElement]$Element)

        $elementPath = Get-UGSMGameDayZXmlElementPath -Element $Element
        $groupName = if ($Element.ParentNode -is [System.Xml.XmlElement]) { [string]$Element.ParentNode.Name } else { [string]$Element.Name }

        if ($Element.Name -eq 'var' -and $Element.HasAttribute('name') -and $Element.HasAttribute('value')) {
            $rows.Add([pscustomobject]@{
                    Group         = if ($Element.ParentNode -is [System.Xml.XmlElement]) { [string]$Element.ParentNode.Name } else { 'variables' }
                    Key           = [string]$Element.GetAttribute('name')
                    Value         = [string]$Element.GetAttribute('value')
                    SourcePath    = [string]$elementPath
                    EntryType     = 'attribute'
                    AttributeName = 'value'
                })
        }
        elseif ($Element.ChildNodes.Count -eq 0 -and $Element.Attributes.Count -eq 0) {
            # nothing
        }
        elseif (@($Element.ChildNodes | Where-Object { $_ -is [System.Xml.XmlElement] }).Count -eq 0) {
            if ($Element.Attributes.Count -gt 0) {
                $addedValueAttribute = $false
                foreach ($attribute in @($Element.Attributes)) {
                    if ($attribute.Name -eq 'name') { continue }

                    $keyName = if ($Element.HasAttribute('name')) {
                        '{0}.{1}' -f $Element.GetAttribute('name'), $attribute.Name
                    }
                    else {
                        '{0}.{1}' -f $Element.Name, $attribute.Name
                    }

                    $rows.Add([pscustomobject]@{
                            Group         = [string]$groupName
                            Key           = [string]$keyName
                            Value         = [string]$attribute.Value
                            SourcePath    = [string]$elementPath
                            EntryType     = 'attribute'
                            AttributeName = [string]$attribute.Name
                        })

                    if ($attribute.Name -eq 'value') { $addedValueAttribute = $true }
                }

                $innerText = [string]$Element.InnerText
                if (-not $addedValueAttribute -and -not [string]::IsNullOrWhiteSpace($innerText)) {
                    $keyName = if ($Element.HasAttribute('name')) {
                        [string]$Element.GetAttribute('name')
                    }
                    else {
                        [string]$Element.Name
                    }

                    $rows.Add([pscustomobject]@{
                            Group         = [string]$groupName
                            Key           = [string]$keyName
                            Value         = [string]$innerText
                            SourcePath    = [string]$elementPath
                            EntryType     = 'text'
                            AttributeName = ''
                        })
                }
            }
            else {
                $innerText = [string]$Element.InnerText
                if (-not [string]::IsNullOrWhiteSpace($innerText)) {
                    $keyName = if ($Element.HasAttribute('name')) {
                        [string]$Element.GetAttribute('name')
                    }
                    else {
                        [string]$Element.Name
                    }

                    $rows.Add([pscustomobject]@{
                            Group         = [string]$groupName
                            Key           = [string]$keyName
                            Value         = [string]$innerText
                            SourcePath    = [string]$elementPath
                            EntryType     = 'text'
                            AttributeName = ''
                        })
                }
            }
        }

        foreach ($child in @($Element.ChildNodes)) {
            if ($child -is [System.Xml.XmlElement]) {
                & $visit $child
            }
        }
    }.GetNewClosure()

    if ($doc.DocumentElement -is [System.Xml.XmlElement]) {
        & $visit $doc.DocumentElement
    }

    return @($rows)
}

function Write-UGSMGameDayZSimpleXmlRows {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][object[]]$Rows
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "XML file not found: $Path"
    }

    $doc = New-Object System.Xml.XmlDocument
    $doc.PreserveWhitespace = $true
    $doc.Load($Path)

    foreach ($row in @($Rows)) {
        if ($null -eq $row) { continue }

        $sourcePath = [string]$row.SourcePath
        $entryType = [string]$row.EntryType
        $attributeName = [string]$row.AttributeName
        $value = [string]$row.Value

        if ([string]::IsNullOrWhiteSpace($sourcePath)) { continue }

        $node = $doc.SelectSingleNode($sourcePath)
        if ($node -isnot [System.Xml.XmlElement]) { continue }

        if ($entryType -eq 'attribute') {
            if ([string]::IsNullOrWhiteSpace($attributeName)) { continue }
            [void]$node.SetAttribute($attributeName, $value)
        }
        else {
            $node.InnerText = $value
        }
    }

    $doc.Save($Path)
    return $true
}

function Read-UGSMGameDayZGlobalsXmlRows {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Path
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        return @()
    }

    [xml]$doc = Get-Content -LiteralPath $Path -Raw -ErrorAction Stop
    $rows = @()

    $varNodes = @($doc.SelectNodes('/variables/var'))
    foreach ($node in $varNodes) {
        if ($null -eq $node) { continue }

        $rows += [pscustomobject]@{
            Name  = [string]$node.GetAttribute('name')
            Type  = [string]$node.GetAttribute('type')
            Value = [string]$node.GetAttribute('value')
        }
    }

    return @($rows)
}

function Get-UGSMGameDayZGlobalsGridRows {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][System.Windows.Forms.DataGridView]$Grid
    )

    $rows = @()

    foreach ($gridRow in @($Grid.Rows)) {
        if ($null -eq $gridRow -or $gridRow.IsNewRow) { continue }
        if ($gridRow.Cells.Count -lt 6) { continue }

        $name = [string]$gridRow.Cells[1].Value
        $value = [string]$gridRow.Cells[2].Value
        if ([string]::IsNullOrWhiteSpace($name)) { continue }

        $typeValue = ''
        if ($gridRow.Tag -and $gridRow.Tag.PSObject.Properties.Name -contains 'AttributeName') {
            $typeValue = [string]$gridRow.Tag.AttributeName
        }
        elseif ($gridRow.Cells.Count -gt 5) {
            $typeValue = [string]$gridRow.Cells[5].Value
        }
        if ([string]::IsNullOrWhiteSpace($typeValue)) { $typeValue = '0' }

        $rows += [pscustomobject]@{
            Name  = $name.Trim()
            Type  = $typeValue
            Value = $value
        }
    }

    return @($rows)
}

function Write-UGSMGameDayZGlobalsXmlRows {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Path,
        [object[]]$Rows = @()
    )

    $settings = New-Object System.Xml.XmlWriterSettings
    $settings.Indent = $true
    $settings.IndentChars = '    '
    $settings.OmitXmlDeclaration = $false
    $settings.Encoding = [System.Text.UTF8Encoding]::new($false)

    $writer = [System.Xml.XmlWriter]::Create($Path, $settings)
    try {
        $writer.WriteStartDocument()
        $writer.WriteStartElement('variables')

        foreach ($row in @($Rows)) {
            if ($null -eq $row) { continue }
            if ([string]::IsNullOrWhiteSpace([string]$row.Name)) { continue }

            $writer.WriteStartElement('var')
            $writer.WriteAttributeString('name', [string]$row.Name)
            $writer.WriteAttributeString('type', [string]$row.Type)
            $writer.WriteAttributeString('value', [string]$row.Value)
            $writer.WriteEndElement()
        }

        $writer.WriteEndElement()
        $writer.WriteEndDocument()
    }
    finally {
        if ($writer) { $writer.Dispose() }
    }

    return $Path
}

function Read-UGSMGameDayZEconomyXmlRows {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Path
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        return @()
    }

    [xml]$doc = Get-Content -LiteralPath $Path -Raw -ErrorAction Stop
    $rows = @()

    $sectionNodes = @($doc.SelectNodes('/economy/*'))
    foreach ($node in $sectionNodes) {
        if ($null -eq $node) { continue }

        foreach ($attribute in @($node.Attributes)) {
            if ($null -eq $attribute) { continue }

            $rows += [pscustomobject]@{
                Section = [string]$node.Name
                Setting = [string]$attribute.Name
                Value   = [string]$attribute.Value
            }
        }
    }

    return @($rows)
}

function Get-UGSMGameDayZEconomyGridRows {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][System.Windows.Forms.DataGridView]$Grid
    )

    $rows = @()

    foreach ($gridRow in @($Grid.Rows)) {
        if ($null -eq $gridRow -or $gridRow.IsNewRow) { continue }
        if ($gridRow.Cells.Count -lt 6) { continue }

        $section = [string]$gridRow.Cells[0].Value
        $setting = [string]$gridRow.Cells[1].Value
        $value = [string]$gridRow.Cells[2].Value

        if ([string]::IsNullOrWhiteSpace($section) -or [string]::IsNullOrWhiteSpace($setting)) { continue }

        $rows += [pscustomobject]@{
            Section = $section.Trim()
            Setting = $setting.Trim()
            Value   = $value
        }
    }

    return @($rows)
}

function Write-UGSMGameDayZEconomyXmlRows {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Path,
        [object[]]$Rows = @()
    )

    $grouped = [ordered]@{}
    foreach ($row in @($Rows)) {
        if ($null -eq $row) { continue }

        $section = [string]$row.Section
        $setting = [string]$row.Setting
        $value = [string]$row.Value

        if ([string]::IsNullOrWhiteSpace($section) -or [string]::IsNullOrWhiteSpace($setting)) { continue }

        if (-not $grouped.Contains($section)) {
            $grouped[$section] = [ordered]@{}
        }

        $grouped[$section][$setting] = $value
    }

    $settings = New-Object System.Xml.XmlWriterSettings
    $settings.Indent = $true
    $settings.IndentChars = '    '
    $settings.OmitXmlDeclaration = $false
    $settings.Encoding = [System.Text.UTF8Encoding]::new($false)

    $writer = [System.Xml.XmlWriter]::Create($Path, $settings)
    try {
        $writer.WriteStartDocument()
        $writer.WriteStartElement('economy')

        foreach ($sectionName in @($grouped.Keys)) {
            $writer.WriteStartElement([string]$sectionName)
            foreach ($attributeName in @($grouped[$sectionName].Keys)) {
                $writer.WriteAttributeString([string]$attributeName, [string]$grouped[$sectionName][$attributeName])
            }
            $writer.WriteEndElement()
        }

        $writer.WriteEndElement()
        $writer.WriteEndDocument()
    }
    finally {
        if ($writer) { $writer.Dispose() }
    }

    return $Path
}

function Convert-UGSMGameDayZEconomyRowsToMatrix {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object[]]$Rows
    )

    $map = [ordered]@{}

    foreach ($row in @($Rows)) {
        if ($null -eq $row) { continue }

        $section = [string]$row.Section
        $setting = ([string]$row.Setting).Trim().ToLowerInvariant()
        $value = [string]$row.Value

        if ([string]::IsNullOrWhiteSpace($section)) { continue }

        if (-not $map.Contains($section)) {
            $map[$section] = [ordered]@{
                Section = $section
                Init    = $false
                Load    = $false
                Respawn = $false
                Save    = $false
            }
        }

        $boolValue = ($value -eq '1')

        switch ($setting) {
            'init' { $map[$section].Init = $boolValue }
            'load' { $map[$section].Load = $boolValue }
            'respawn' { $map[$section].Respawn = $boolValue }
            'save' { $map[$section].Save = $boolValue }
        }
    }

    return @(
        foreach ($sectionName in @($map.Keys)) {
            [pscustomobject]$map[$sectionName]
        }
    )
}

function Get-UGSMGameDayZEconomyMatrixRowsFromGrid {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][System.Windows.Forms.DataGridView]$Grid
    )

    $rows = @()

    foreach ($gridRow in @($Grid.Rows)) {
        if ($null -eq $gridRow -or $gridRow.IsNewRow) { continue }
        if ($gridRow.Cells.Count -lt 5) { continue }

        $section = [string]$gridRow.Cells[0].Value
        if ([string]::IsNullOrWhiteSpace($section)) { continue }

        $initValue = [bool]($gridRow.Cells[1].Value)
        $loadValue = [bool]($gridRow.Cells[2].Value)
        $respawnValue = [bool]($gridRow.Cells[3].Value)
        $saveValue = [bool]($gridRow.Cells[4].Value)

        $rows += [pscustomobject]@{ Section = $section.Trim(); Setting = 'init'; Value = if ($initValue) { '1' } else { '0' } }
        $rows += [pscustomobject]@{ Section = $section.Trim(); Setting = 'load'; Value = if ($loadValue) { '1' } else { '0' } }
        $rows += [pscustomobject]@{ Section = $section.Trim(); Setting = 'respawn'; Value = if ($respawnValue) { '1' } else { '0' } }
        $rows += [pscustomobject]@{ Section = $section.Trim(); Setting = 'save'; Value = if ($saveValue) { '1' } else { '0' } }
    }

    return @($rows)
}

function Read-UGSMGameDayZCfgGameplayJsonData {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Path
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        return [ordered]@{}
    }

    $raw = Get-Content -LiteralPath $Path -Raw -ErrorAction Stop
    if ([string]::IsNullOrWhiteSpace($raw)) {
        return [ordered]@{}
    }

    $data = $raw | ConvertFrom-Json -ErrorAction Stop
    return $data
}

function Write-UGSMGameDayZCfgGameplayJsonData {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)]$Data
    )

    $json = $Data | ConvertTo-Json -Depth 100
    [System.IO.File]::WriteAllText($Path, $json, (New-Object System.Text.UTF8Encoding($false)))
}

function Get-UGSMGameDayZCfgGameplaySections {
    [CmdletBinding()]
    param()

    return @(
        'GeneralData',
        'PlayerData',
        'WorldsData',
        'BaseBuildingData',
        'UIData',
        'MapData',
        'VehicleData'
    )
}

function Get-UGSMGameDayZCfgGameplayRows {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Data
    )

    $rows = New-Object System.Collections.ArrayList

    function Add-UGSMCfgGameplayLeafRows {
        param(
            [string]$SectionName,
            [string]$PathPrefix,
            $Node
        )

        if ($null -eq $Node) {
            [void]$rows.Add([pscustomobject]@{
                    Section       = $SectionName
                    Name          = $PathPrefix
                    ValueType     = 'null'
                    Value         = ''
                    OriginalValue = $null
                })
            return
        }

        if ($Node -is [bool]) {
            [void]$rows.Add([pscustomobject]@{
                    Section       = $SectionName
                    Name          = $PathPrefix
                    ValueType     = 'bool'
                    Value         = if ($Node) { 'true' } else { 'false' }
                    OriginalValue = $Node
                })
            return
        }

        if ($Node -is [int] -or $Node -is [long] -or $Node -is [double] -or $Node -is [float] -or $Node -is [decimal]) {
            [void]$rows.Add([pscustomobject]@{
                    Section       = $SectionName
                    Name          = $PathPrefix
                    ValueType     = 'number'
                    Value         = [string]$Node
                    OriginalValue = $Node
                })
            return
        }

        if ($Node -is [string]) {
            [void]$rows.Add([pscustomobject]@{
                    Section       = $SectionName
                    Name          = $PathPrefix
                    ValueType     = 'text'
                    Value         = [string]$Node
                    OriginalValue = $Node
                })
            return
        }

        if ($Node -is [System.Array]) {
            $items = @($Node)
            [void]$rows.Add([pscustomobject]@{
                    Section       = $SectionName
                    Name          = $PathPrefix
                    ValueType     = 'array'
                    Value         = ($items | ForEach-Object { [string]$_ }) -join [Environment]::NewLine
                    OriginalValue = $Node
                })
            return
        }

        $noteProps = @()
        if ($Node -and $Node.PSObject) {
            $noteProps = @($Node.PSObject.Properties | Where-Object { $_.MemberType -eq 'NoteProperty' })
        }

        if ($noteProps.Count -gt 0) {
            foreach ($prop in $noteProps) {
                $childPath = if ([string]::IsNullOrWhiteSpace($PathPrefix)) {
                    [string]$prop.Name
                }
                else {
                    '{0}.{1}' -f $PathPrefix, $prop.Name
                }

                Add-UGSMCfgGameplayLeafRows -SectionName $SectionName -PathPrefix $childPath -Node $prop.Value
            }
            return
        }

        [void]$rows.Add([pscustomobject]@{
                Section       = $SectionName
                Name          = $PathPrefix
                ValueType     = 'text'
                Value         = [string]$Node
                OriginalValue = $Node
            })
    }

    foreach ($sectionName in @(Get-UGSMGameDayZCfgGameplaySections)) {
        if ($null -eq $Data) { continue }
        if (-not ($Data.PSObject.Properties.Name -contains $sectionName)) { continue }

        $section = $Data.$sectionName
        if ($null -eq $section) { continue }

        $sectionProps = @($section.PSObject.Properties | Where-Object { $_.MemberType -eq 'NoteProperty' })
        foreach ($prop in $sectionProps) {
            Add-UGSMCfgGameplayLeafRows -SectionName $sectionName -PathPrefix ([string]$prop.Name) -Node $prop.Value
        }
    }

    return @($rows)
}

function Update-UGSMGameDayZCfgGameplayDataFromRows {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Data,
        [Parameter(Mandatory)][object[]]$Rows
    )

    foreach ($row in @($Rows)) {
        if ($null -eq $row) { continue }

        $sectionName = [string]$row.Section
        $propertyPath = [string]$row.Name
        $valueType = [string]$row.ValueType
        $valueText = [string]$row.Value
        $original = $row.OriginalValue

        if (-not ($Data.PSObject.Properties.Name -contains $sectionName)) { continue }

        $target = $Data.$sectionName
        if ($null -eq $target) { continue }

        $pathParts = @($propertyPath -split '\.')
        if ($pathParts.Count -eq 0) { continue }

        for ($i = 0; $i -lt ($pathParts.Count - 1); $i++) {
            $part = [string]$pathParts[$i]
            if (-not ($target.PSObject.Properties.Name -contains $part)) {
                $target | Add-Member -NotePropertyName $part -NotePropertyValue ([pscustomobject]@{}) -Force
            }
            $target = $target.$part
            if ($null -eq $target) { break }
        }

        if ($null -eq $target) { continue }

        $leafName = [string]$pathParts[-1]
        $newValue = $null

        switch ($valueType) {
            'bool' {
                $newValue = (([string]$valueText).Trim().ToLowerInvariant() -eq 'true')
            }
            'null' {
                $trimmed = ([string]$valueText).Trim()
                $newValue = if ([string]::IsNullOrWhiteSpace($trimmed)) { $null } else { $trimmed }
            }
            'array' {
                $parts = @()
                foreach ($line in @(([string]$valueText) -split "(`r`n|`n|`r)")) {
                    $p = $line.Trim()
                    if (-not [string]::IsNullOrWhiteSpace($p)) { $parts += $p }
                }

                if ($original -is [System.Collections.IEnumerable] -and -not ($original -is [string]) -and @($original).Count -gt 0) {
                    $first = @($original)[0]

                    if ($first -is [int]) {
                        $newValue = @($parts | ForEach-Object { [int]$_ })
                    }
                    elseif ($first -is [long]) {
                        $newValue = @($parts | ForEach-Object { [long]$_ })
                    }
                    elseif ($first -is [double] -or $first -is [float] -or $first -is [decimal]) {
                        $newValue = @($parts | ForEach-Object { [double]$_ })
                    }
                    elseif ($first -is [bool]) {
                        $newValue = @($parts | ForEach-Object { ([string]$_).Trim().ToLowerInvariant() -eq 'true' })
                    }
                    else {
                        $newValue = @($parts)
                    }
                }
                else {
                    $newValue = @($parts)
                }
            }
            'number' {
                if ($original -is [int]) {
                    $newValue = [int]$valueText
                }
                elseif ($original -is [long]) {
                    $newValue = [long]$valueText
                }
                elseif ($original -is [double] -or $original -is [float] -or $original -is [decimal]) {
                    $newValue = [double]$valueText
                }
                else {
                    $newValue = [double]$valueText
                }
            }
            default {
                $newValue = [string]$valueText
            }
        }

        $target.$leafName = $newValue
    }

    return $Data
}

function Get-UGSMGameDayZModNameFromSource {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$SourcePath,
        [string]$FallbackId = ''
    )

    try {
        $metaPath = Join-Path $SourcePath 'meta.cpp'
        if (Test-Path -LiteralPath $metaPath -PathType Leaf) {
            $raw = Get-Content -LiteralPath $metaPath -Raw -ErrorAction SilentlyContinue
            if (-not [string]::IsNullOrWhiteSpace($raw)) {
                $match = [regex]::Match($raw, 'name\s*=\s*"([^"]+)"', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
                if ($match.Success) {
                    $resolved = [string]$match.Groups[1].Value.Trim()
                    if (-not [string]::IsNullOrWhiteSpace($resolved)) {
                        return $resolved
                    }
                }
            }
        }
    }
    catch {}

    if (-not [string]::IsNullOrWhiteSpace($FallbackId)) {
        return $FallbackId
    }

    return [System.IO.Path]::GetFileName($SourcePath)
}

function Invoke-UGSMGameDayZOpenPath {
    [CmdletBinding()]
    param(
        [AllowEmptyString()][AllowNull()][string]$Path,
        [switch]$EnsureFile,
        [switch]$EnsureFolder,
        [AllowNull()][System.Windows.Forms.Label]$StatusLabel,
        [string]$OpenedMessage = 'Opened path.'
    )

    if ([string]::IsNullOrWhiteSpace([string]$Path)) {
        throw 'DayZ open failed: target path was blank.'
    }

    if ($EnsureFolder) {
        if (-not (Test-Path -LiteralPath $Path -PathType Container)) {
            throw ("DayZ open failed: folder does not exist: {0}" -f $Path)
        }

        Start-Process -FilePath 'explorer.exe' -ArgumentList @($Path) -ErrorAction Stop | Out-Null
        if ($StatusLabel) { $StatusLabel.Text = $OpenedMessage }
        return
    }

    if ($EnsureFile) {
        $parent = Split-Path -Parent $Path
        if ([string]::IsNullOrWhiteSpace([string]$parent)) {
            throw 'DayZ open failed: file parent path could not be resolved.'
        }

        if (-not (Test-Path -LiteralPath $parent -PathType Container)) {
            throw ("DayZ open failed: folder does not exist: {0}" -f $parent)
        }

        if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
            throw ("DayZ open failed: file does not exist: {0}" -f $Path)
        }

        Start-Process -FilePath 'notepad.exe' -ArgumentList @($Path) -ErrorAction Stop | Out-Null
        if ($StatusLabel) { $StatusLabel.Text = $OpenedMessage }
        return
    }

    Start-Process -FilePath 'explorer.exe' -ArgumentList @($Path) -ErrorAction Stop | Out-Null
    if ($StatusLabel) { $StatusLabel.Text = $OpenedMessage }
}

function Resolve-UGSMGameDayZEditorPath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$Instance,
        [AllowNull()]$Paths,
        [Parameter(Mandatory)][string]$Target
    )

    if (-not $Instance) {
        throw 'DayZ action failed: selected instance was null.'
    }

    if (-not $Paths) {
        $Paths = Get-UGSMGameDayZProfilePaths -Instance $Instance
    }

    if (-not $Paths) {
        throw ("DayZ action failed: could not resolve paths for '{0}'." -f $Target)
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
        throw ("DayZ action failed: could not resolve path for '{0}'." -f $Target)
    }

    return [string]$candidate
}

function Invoke-UGSMGameDayZEditorAction {
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

    $resolvedPath = Resolve-UGSMGameDayZEditorPath -Instance $Instance -Paths $Paths -Target $Target

    Invoke-UGSMGameDayZOpenPath `
        -Path $resolvedPath `
        -EnsureFile:$EnsureFile `
        -EnsureFolder:$EnsureFolder `
        -StatusLabel $StatusLabel `
        -OpenedMessage $OpenedMessage
}

function Get-UGSMGameDayZEditorFieldCurrentValue {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][hashtable]$Field,
        [Parameter(Mandatory)]$Paths
    )

    $defaultValue = if ($Field.ContainsKey('DefaultValue')) { $Field.DefaultValue } else { $null }

    if ($null -eq $Field) {
        return $defaultValue
    }

    $fieldType = [string]$Field.Type
    if ($fieldType -in @('InstanceText', 'InstanceBoolean')) {
        $instance = $null
        if ($Paths -and $Paths.PSObject.Properties.Name -contains 'Instance') {
            $instance = $Paths.Instance
        }

        if ($instance -and [string]$Field.Model -eq 'Discord') {
            $discordModel = Get-UGSMInstanceDiscordSettingsModel -Instance $instance
            if ($discordModel -and $discordModel.PSObject.Properties.Name -contains [string]$Field.Property) {
                return $discordModel.([string]$Field.Property)
            }
        }

        return $defaultValue
    }

    $targetPath = Resolve-UGSMGameDayZEditorFieldPath -Field $Field -Paths $Paths
    if ([string]::IsNullOrWhiteSpace([string]$targetPath)) {
        return $defaultValue
    }

    $format = ''
    if ($Field.ContainsKey('Format') -and $null -ne $Field.Format) {
        $format = [string]$Field.Format
    }

    switch ($format) {
        'Cfg' {
            if (-not (Test-Path -LiteralPath $targetPath)) {
                return $defaultValue
            }

            if (-not $Field.ContainsKey('Key') -or [string]::IsNullOrWhiteSpace([string]$Field.Key)) {
                return $defaultValue
            }

            return Get-UGSMGameDayZCfgValue -Path $targetPath -Key ([string]$Field.Key) -DefaultValue $defaultValue
        }

        default {
            if ($Field.ContainsKey('Key') -and -not [string]::IsNullOrWhiteSpace([string]$Field.Key)) {
                if (-not (Test-Path -LiteralPath $targetPath)) {
                    return $defaultValue
                }

                $iniData = Read-UGSMGameDayZIniFile -Path $targetPath
                return Get-UGSMGameDayZIniValue -IniData $iniData -Section $Field.Section -Key $Field.Key -DefaultValue $defaultValue
            }

            if (Test-Path -LiteralPath $targetPath) {
                return [string](Get-Content -LiteralPath $targetPath -Raw -ErrorAction SilentlyContinue)
            }

            return $defaultValue
        }
    }
}

function Get-UGSMGameDayZVppPaths {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$Instance
    )

    $paths = Get-UGSMGameDayZProfilePaths -Instance $Instance
    $runtimeProfilesRoot = Join-Path $paths.RuntimeInstallRoot 'profiles'
    $vppRoot = Join-Path $runtimeProfilesRoot 'VPPAdminTools'
    $permissionsRoot = Join-Path $vppRoot 'Permissions'
    $superAdminsRoot = Join-Path $permissionsRoot 'SuperAdmins'
    $userGroupsRoot = Join-Path $permissionsRoot 'UserGroups'

    return [pscustomobject]@{
        RuntimeProfilesRoot = $runtimeProfilesRoot
        VppRoot             = $vppRoot
        PermissionsRoot     = $permissionsRoot
        SuperAdminsRoot     = $superAdminsRoot
        UserGroupsRoot      = $userGroupsRoot
        PermissionsPath     = (Join-Path $permissionsRoot 'Permissions.json')
        SuperAdminsPath     = (Join-Path $superAdminsRoot 'SuperAdmins.txt')
        CredentialsPath     = (Join-Path $permissionsRoot 'credentials.txt')
        UserGroupsPath      = (Join-Path $userGroupsRoot 'UserGroups.json')
    }
}

function Test-UGSMGameDayZVppAdminEnabled {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$Instance
    )

    foreach ($mod in @(Get-UGSMGameDayZStoredMods -Instance $Instance)) {
        if ($null -eq $mod) { continue }
        $id = [string]$mod.Id
        $name = [string]$mod.Name
        if ($id -eq '1828439124' -or $name -like '*VPPAdminTools*') {
            return $true
        }
    }

    return $false
}

function Get-UGSMGameDayZDefaultVppAdminPermissions {
    [CmdletBinding()]
    param()

    return @(
        'DeleteObjectAtCrosshair', 'TeleportToCrosshair', 'FreeCamera', 'RepairVehiclesAtCrosshair',
        'MenuItemManager', 'MenuItemManager:SpawnItem', 'MenuItemManager:EditPreset', 'MenuItemManager:SpawnPreset',
        'MenuItemManager:DeletePreset', 'MenuItemManager:AddPreset', 'MenuServerManager', 'ServerManager:RestartServer',
        'ServerManager:LockServer', 'ServerManager:KickAllPlayers', 'ServerManager:LoadScripts', 'MenuWeatherManager',
        'WeatherManager:ApplyWeather', 'WeatherManager:ApplyTime', 'WeatherManager:SavePreset', 'WeatherManager:DeletePreset',
        'WeatherManager:ApplyPreset', 'WeatherManager:ApplyTimePreset', 'WeatherManager:SaveTimePreset', 'WeatherManager:DeleteTimePreset',
        'MenuObjectManager', 'MenuObjectManager:CreateNewSet', 'MenuObjectManager:UpdateSet', 'MenuObjectManager:DeleteSet',
        'MenuObjectManager:EditSet', 'MenuPermissionsEditor', 'PermissionsEditor:RemoveUser', 'PermissionsEditor:AddUser',
        'PermissionsEditor:CreateUserGroup', 'PermissionsEditor:DeleteUserGroup', 'PermissionsEditor:ChangePermLevel', 'MenuPlayerManager',
        'PlayerManager:GiveGodmode', 'PlayerManager:BanPlayer', 'PlayerManager:KickPlayer', 'PlayerManager:HealPlayers',
        'PlayerManager:SetPlayerStats', 'PlayerManager:KillPlayers', 'PlayerManager:GodMode', 'PlayerManager:SpectatePlayer',
        'PlayerManager:TeleportToPlayer', 'PlayerManager:TeleportPlayerTo', 'PlayerManager:SetPlayerInvisible', 'PlayerManager:SendMessage',
        'PlayerManager:GiveUnlimitedAmmo', 'PlayerManager:MakePlayerVomit', 'PlayerManager:FreezePlayers', 'PlayerManager:ChangeScale',
        'MenuBansManager', 'BansManager:UnbanPlayer', 'BansManager:UpdateBanDuration', 'BansManager:UpdateBanReason',
        'MenuWebHooks', 'MenuWebHooks:Create', 'MenuWebHooks:Edit', 'MenuWebHooks:Delete', 'MenuTeleportManager',
        'TeleportManager:ViewPlayerPositions', 'TeleportManager:TPPlayers', 'TeleportManager:TPSelf', 'TeleportManager:DeletePreset',
        'TeleportManager:AddNewPreset', 'TeleportManager:EditPreset', 'TeleportManager:TeleportEntity', 'EspToolsMenu',
        'EspToolsMenu:DeleteObjects', 'EspToolsMenu:PlayerESP', 'EspToolsMenu:RestPasscodeFence', 'EspToolsMenu:RetriveCodeFromObj',
        'EspToolsMenu:PlayerMeshEsp', 'EspToolsMenu:InstantBaseBuild', 'MenuXMLEditor', 'MenuCommandsConsole'
    )
}

function Read-UGSMGameDayZVppAdminData {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$Instance
    )

    $paths = Get-UGSMGameDayZVppPaths -Instance $Instance
    $enabled = Test-UGSMGameDayZVppAdminEnabled -Instance $Instance

    $result = [ordered]@{
        Enabled        = $enabled
        Paths          = $paths
        Players        = @()
        SuperAdmins    = @()
        Credentials    = ''
        HashedCreds    = $false
        Messages       = @()
        RawPermissions = $null
        RawUserGroups  = @()
    }

    if (-not $enabled) {
        $result.Messages += 'VPPAdminTools is not present in the instance mod list.'
    }

    if (-not (Test-Path -LiteralPath $paths.PermissionsPath -PathType Leaf)) {
        $result.Messages += 'Permissions.json not found. Run the server once with VPPAdminTools enabled.'
    }
    else {
        try {
            $perms = Get-Content -LiteralPath $paths.PermissionsPath -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
            $result.RawPermissions = $perms

            if ($perms.PSObject.Properties.Name -contains 'Players' -and $perms.Players) {
                foreach ($player in @($perms.Players)) {
                    $result.Players += [pscustomobject]@{
                        SteamID  = [string]$player.SteamID
                        RoleName = [string]$player.RoleName
                    }
                }
            }
            elseif ($perms.PSObject.Properties.Name -contains 'Users' -and $perms.Users) {
                foreach ($user in @($perms.Users)) {
                    $result.Players += [pscustomobject]@{
                        SteamID  = [string]$user.id
                        RoleName = [string]$user.UserGroup
                    }
                }
            }
        }
        catch {
            throw "Failed to read VPP Permissions.json: $($_.Exception.Message)"
        }
    }

    if (Test-Path -LiteralPath $paths.UserGroupsPath -PathType Leaf) {
        try {
            $userGroups = Get-Content -LiteralPath $paths.UserGroupsPath -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
            $result.RawUserGroups = @($userGroups)
        }
        catch {
            throw "Failed to read VPP UserGroups.json: $($_.Exception.Message)"
        }
    }
    else {
        $result.Messages += 'UserGroups.json not found.'
    }

    if (Test-Path -LiteralPath $paths.SuperAdminsPath -PathType Leaf) {
        try {
            $result.SuperAdmins = @(
                Get-Content -LiteralPath $paths.SuperAdminsPath -ErrorAction Stop |
                Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) } |
                ForEach-Object { [string]$_.Trim() }
            )
        }
        catch {
            throw "Failed to read VPP SuperAdmins.txt: $($_.Exception.Message)"
        }
    }
    else {
        $result.Messages += 'SuperAdmins.txt not found.'
    }

    if (Test-Path -LiteralPath $paths.CredentialsPath -PathType Leaf) {
        try {
            $credContent = Get-Content -LiteralPath $paths.CredentialsPath -ErrorAction Stop | Select-Object -First 1
            if ($null -ne $credContent) {
                $credText = [string]$credContent
                if ($credText -match 'REMOVE THIS LINE') {
                    $result.Credentials = ''
                }
                elseif (-not [string]::IsNullOrWhiteSpace($credText)) {
                    $result.Credentials = '<Hashed - Enter new to reset>'
                    $result.HashedCreds = $true
                }
            }
        }
        catch {
            throw "Failed to read VPP credentials.txt: $($_.Exception.Message)"
        }
    }
    else {
        $result.Messages += 'credentials.txt not found.'
    }

    return [pscustomobject]$result
}

function Save-UGSMGameDayZVppAdminData {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$Instance,
        [Parameter()][object[]]$Players = @(),
        [Parameter()][string[]]$SuperAdmins = @(),
        [Parameter()][AllowEmptyString()][string]$Credentials = ''
    )

    $paths = Get-UGSMGameDayZVppPaths -Instance $Instance

    if (-not (Test-Path -LiteralPath $paths.VppRoot -PathType Container)) {
        New-Item -Path $paths.VppRoot -ItemType Directory -Force | Out-Null
    }
    if (-not (Test-Path -LiteralPath $paths.PermissionsRoot -PathType Container)) {
        New-Item -Path $paths.PermissionsRoot -ItemType Directory -Force | Out-Null
    }
    if (-not (Test-Path -LiteralPath $paths.SuperAdminsRoot -PathType Container)) {
        New-Item -Path $paths.SuperAdminsRoot -ItemType Directory -Force | Out-Null
    }
    if (-not (Test-Path -LiteralPath $paths.UserGroupsRoot -PathType Container)) {
        New-Item -Path $paths.UserGroupsRoot -ItemType Directory -Force | Out-Null
    }

    $permissionsObject = $null
    if (Test-Path -LiteralPath $paths.PermissionsPath -PathType Leaf) {
        try {
            $permissionsObject = Get-Content -LiteralPath $paths.PermissionsPath -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
        }
        catch {
            throw 'Permissions.json is corrupted and could not be read. Fix or remove it, then try again.'
        }
    }
    else {
        $permissionsObject = [pscustomobject]@{
            m_Version  = 1
            UserGroups = @()
            Players    = @()
        }
    }

    $normalizedPlayers = @()
    foreach ($entry in @($Players)) {
        if ($null -eq $entry) { continue }
        $steamId = [string]$(if ($entry.PSObject.Properties.Name -contains 'SteamID') { $entry.SteamID } elseif ($entry.PSObject.Properties.Name -contains 'Id') { $entry.Id } else { '' })
        $roleName = [string]$(if ($entry.PSObject.Properties.Name -contains 'RoleName') { $entry.RoleName } elseif ($entry.PSObject.Properties.Name -contains 'Role') { $entry.Role } else { '' })
        if ([string]::IsNullOrWhiteSpace($steamId) -or [string]::IsNullOrWhiteSpace($roleName)) { continue }
        $normalizedPlayers += [ordered]@{
            SteamID  = $steamId.Trim()
            RoleName = $roleName.Trim()
        }
    }

    $permissionsObject.Players = @($normalizedPlayers)
    $permissionsJson = $permissionsObject | ConvertTo-Json -Depth 8
    [System.IO.File]::WriteAllText($paths.PermissionsPath, $permissionsJson, (New-Object System.Text.UTF8Encoding($false)))

    $normalizedSuperAdmins = @()
    foreach ($value in @($SuperAdmins)) {
        $text = [string]$value
        if ([string]::IsNullOrWhiteSpace($text)) { continue }
        $clean = $text.Trim()
        if ($normalizedSuperAdmins -notcontains $clean) {
            $normalizedSuperAdmins += $clean
        }
    }
    $superAdminText = ($normalizedSuperAdmins -join "`r`n")
    [System.IO.File]::WriteAllText($paths.SuperAdminsPath, $superAdminText, (New-Object System.Text.UTF8Encoding($false)))

    $existingUserGroups = @()
    if (-not (Test-Path -LiteralPath $paths.UserGroupsRoot -PathType Container)) {
        New-Item -Path $paths.UserGroupsRoot -ItemType Directory -Force | Out-Null
    }

    $existingGroups = @()
    if (-not (Test-Path -LiteralPath $paths.UserGroupsRoot -PathType Container)) {
        New-Item -Path $paths.UserGroupsRoot -ItemType Directory -Force | Out-Null
    }

    $defaultPermissions = @(
        'DeleteObjectAtCrosshair',
        'TeleportToCrosshair',
        'TeleportPlayerToCrosshair',
        'TeleportByMenu',
        'DisplayPlayerInfo',
        'DeletePlayerAtCrosshair',
        'SetGodMode',
        'CommandScript',
        'CommandSetHealth',
        'CommandSetBlood',
        'CommandSetFood',
        'CommandSetWater',
        'SpawnItemByName',
        'SpawnVehicleByName',
        'CameraTools',
        'FreeCamera',
        'PlayerSetGroup',
        'PlayerRemoveGroup',
        'PlayerAddPermission',
        'PlayerRemovePermission',
        'PlayerAddToWhitelist',
        'PlayerRemoveFromWhitelist',
        'PlayerSetPriority',
        'PlayerViewLogs',
        'PlayerMessage',
        'PlayerKick',
        'PlayerBan',
        'PermissionsManager'
    )

    $adminsPermissions = @($defaultPermissions)
    $adminsPermissionLevel = 1
    $adminsForceSavedName = 0
    $existingMemberNames = @{}

    if (Test-Path -LiteralPath $paths.UserGroupsPath -PathType Leaf) {
        try {
            $rawGroups = Get-Content -LiteralPath $paths.UserGroupsPath -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop

            foreach ($group in @($rawGroups)) {
                if ($null -eq $group) { continue }
                if (-not ($group.PSObject.Properties.Name -contains 'm_groupName')) { continue }
                if ([string]$group.m_groupName -ne 'Admins') { continue }

                if ($group.PSObject.Properties.Name -contains 'm_Permissions' -and @($group.m_Permissions).Count -gt 0) {
                    $adminsPermissions = @(
                        foreach ($perm in @($group.m_Permissions)) {
                            $p = [string]$perm
                            if (-not [string]::IsNullOrWhiteSpace($p)) { $p.Trim() }
                        }
                    )
                }

                if ($group.PSObject.Properties.Name -contains 'm_permissionLevel') {
                    $adminsPermissionLevel = [int]$group.m_permissionLevel
                }

                if ($group.PSObject.Properties.Name -contains 'm_ForceSavedName') {
                    $adminsForceSavedName = [int]$group.m_ForceSavedName
                }

                if ($group.PSObject.Properties.Name -contains 'm_GroupMembers') {
                    foreach ($member in @($group.m_GroupMembers)) {
                        if ($null -eq $member) { continue }
                        $sid = [string]$member.m_Steam64ID
                        $uname = [string]$member.m_UserName
                        if ([string]::IsNullOrWhiteSpace($sid)) { continue }
                        $sid = $sid.Trim()
                        if ($sid -notmatch '^\d{17}$') { continue }

                        if (-not [string]::IsNullOrWhiteSpace($uname)) {
                            $existingMemberNames[$sid] = $uname.Trim()
                        }
                    }
                }

                break
            }
        }
        catch {
        }
    }

    $adminIds = New-Object System.Collections.Generic.List[string]

    foreach ($value in @($normalizedSuperAdmins)) {
        $sid = [string]$value
        if ([string]::IsNullOrWhiteSpace($sid)) { continue }
        $sid = $sid.Trim()
        if ($sid -notmatch '^\d{17}$') { continue }
        if (-not $adminIds.Contains($sid)) {
            $adminIds.Add($sid)
        }
    }

    foreach ($entry in @($normalizedPlayers)) {
        if ($null -eq $entry) { continue }
        $sid = [string]$entry.SteamID
        $role = [string]$entry.RoleName
        if ([string]::IsNullOrWhiteSpace($sid) -or [string]::IsNullOrWhiteSpace($role)) { continue }
        $sid = $sid.Trim()
        if ($sid -notmatch '^\d{17}$') { continue }

        if ($role -eq 'SuperAdmin' -or $role -eq 'Admin' -or $role -eq 'Admins') {
            if (-not $adminIds.Contains($sid)) {
                $adminIds.Add($sid)
            }
        }
    }

    $adminMembers = @()
    foreach ($sid in @($adminIds)) {
        $userName = $sid
        if ($existingMemberNames.ContainsKey($sid)) {
            $userName = [string]$existingMemberNames[$sid]
        }

        $adminMembers += [pscustomobject]@{
            m_UserName  = $userName
            m_Steam64ID = $sid
            m_SessionId = -1
        }
    }

    $userGroupsToSave = @(
        [pscustomobject]@{
            m_groupName       = 'Admins'
            m_permissionLevel = $adminsPermissionLevel
            m_GroupMembers    = @($adminMembers)
            m_Permissions     = @($adminsPermissions)
            m_ForceSavedName  = $adminsForceSavedName
        }
    )

    $userGroupsJson = $userGroupsToSave | ConvertTo-Json -Depth 10
    [System.IO.File]::WriteAllText($paths.UserGroupsPath, $userGroupsJson, (New-Object System.Text.UTF8Encoding($false)))

    $credentialsUpdated = $false
    if ($Credentials -ne '<Hashed - Enter new to reset>' -and -not [string]::IsNullOrWhiteSpace([string]$Credentials)) {
        $credentialText = ([string]$Credentials).Trim()
        [System.IO.File]::WriteAllText($paths.CredentialsPath, $credentialText, (New-Object System.Text.UTF8Encoding($false)))
        $credentialsUpdated = $true
    }

    return [pscustomobject]@{
        PermissionsPath    = $paths.PermissionsPath
        SuperAdminsPath    = $paths.SuperAdminsPath
        CredentialsPath    = $paths.CredentialsPath
        UserGroupsPath     = $paths.UserGroupsPath
        PlayersSaved       = @($normalizedPlayers).Count
        SuperAdminsSaved   = @($normalizedSuperAdmins).Count
        UserGroupsSaved    = @($adminMembers).Count
        CredentialsUpdated = $credentialsUpdated
    }
}

function Read-UGSMGameDayZEventsXmlRows {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Path
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        return @()
    }

    $xml = Read-UGSMGameDayZXmlDocumentSafe -Path $Path
    if ($null -eq $xml -or $null -eq $xml.DocumentElement) {
        return @()
    }

    $rows = @()
    $eventNodes = $xml.DocumentElement.SelectNodes('./event')

    foreach ($eventNode in $eventNodes) {
        if ($null -eq $eventNode) { continue }

        $flagsNode = $eventNode.SelectSingleNode('./flags')
        $secondaryNode = $eventNode.SelectSingleNode('./secondary')
        $childrenNode = $eventNode.SelectSingleNode('./children')
        $secondaryNodesNode = $eventNode.SelectSingleNode('./secondaryNodes')

        $rows += [pscustomobject]@{
            Name               = [string]$eventNode.GetAttribute('name')
            Nominal            = [string]($eventNode.SelectSingleNode('./nominal').InnerText)
            Min                = [string]($eventNode.SelectSingleNode('./min').InnerText)
            Max                = [string]($eventNode.SelectSingleNode('./max').InnerText)
            Lifetime           = [string]($eventNode.SelectSingleNode('./lifetime').InnerText)
            Restock            = [string]($eventNode.SelectSingleNode('./restock').InnerText)
            Active             = [string]($eventNode.SelectSingleNode('./active').InnerText)

            SafeRadius         = [string]($eventNode.SelectSingleNode('./saferadius').InnerText)
            DistanceRadius     = [string]($eventNode.SelectSingleNode('./distanceradius').InnerText)
            CleanupRadius      = [string]($eventNode.SelectSingleNode('./cleanupradius').InnerText)
            Position           = [string]($eventNode.SelectSingleNode('./position').InnerText)
            Limit              = [string]($eventNode.SelectSingleNode('./limit').InnerText)

            FlagsDeletable     = if ($flagsNode) { [string]$flagsNode.GetAttribute('deletable') } else { '' }
            FlagsInitRandom    = if ($flagsNode) { [string]$flagsNode.GetAttribute('init_random') } else { '' }
            FlagsRemoveDamaged = if ($flagsNode) { [string]$flagsNode.GetAttribute('remove_damaged') } else { '' }

            SecondaryOuterXml  = if ($secondaryNode) { [string]$secondaryNode.OuterXml } else { '' }
            ChildrenOuterXml   = if ($childrenNode) { [string]$childrenNode.OuterXml } else { '' }
            SecondaryNodesOuterXml = if ($secondaryNodesNode) { [string]$secondaryNodesNode.OuterXml } else { '' }
        }
    }

    return @($rows)
}

function Get-UGSMGameDayZEventsGridRows {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][System.Windows.Forms.DataGridView]$Grid
    )

    $rows = @()

    foreach ($gridRow in @($Grid.Rows)) {
        if ($null -eq $gridRow -or $gridRow.IsNewRow) { continue }

        $name = [string]$gridRow.Cells['Name'].Value
        if ([string]::IsNullOrWhiteSpace($name)) { continue }

        $rows += [pscustomobject]@{
            Name               = $name.Trim()
            Nominal            = [string]$gridRow.Cells['Nominal'].Value
            Min                = [string]$gridRow.Cells['Min'].Value
            Max                = [string]$gridRow.Cells['Max'].Value
            Lifetime           = [string]$gridRow.Cells['Lifetime'].Value
            Restock            = [string]$gridRow.Cells['Restock'].Value
            Active             = [string]$gridRow.Cells['Active'].Value

            SafeRadius         = [string]$gridRow.Tag.SafeRadius
            DistanceRadius     = [string]$gridRow.Tag.DistanceRadius
            CleanupRadius      = [string]$gridRow.Tag.CleanupRadius
            Position           = [string]$gridRow.Tag.Position
            Limit              = [string]$gridRow.Tag.Limit
            FlagsDeletable     = [string]$gridRow.Tag.FlagsDeletable
            FlagsInitRandom    = [string]$gridRow.Tag.FlagsInitRandom
            FlagsRemoveDamaged = [string]$gridRow.Tag.FlagsRemoveDamaged
            SecondaryOuterXml  = [string]$gridRow.Tag.SecondaryOuterXml
            ChildrenOuterXml   = [string]$gridRow.Tag.ChildrenOuterXml
            SecondaryNodesOuterXml = [string]$gridRow.Tag.SecondaryNodesOuterXml
        }
    }

    return @($rows)
}

function Write-UGSMGameDayZEventsXmlRows {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][object[]]$Rows
    )

    $settings = New-Object System.Xml.XmlWriterSettings
    $settings.Indent = $true
    $settings.IndentChars = "    "
    $settings.OmitXmlDeclaration = $false
    $settings.Encoding = New-Object System.Text.UTF8Encoding($false)

    $writer = [System.Xml.XmlWriter]::Create($Path, $settings)

    function Write-UGSMGameDayZEventXmlNode {
        param(
            [Parameter(Mandatory)][System.Xml.XmlWriter]$XmlWriter,
            [Parameter(Mandatory)][System.Xml.XmlNode]$Node
        )

        switch ($Node.NodeType) {
            ([System.Xml.XmlNodeType]::Element) {
                $XmlWriter.WriteStartElement($Node.Prefix, $Node.LocalName, $Node.NamespaceURI)

                if ($Node.Attributes) {
                    foreach ($attr in @($Node.Attributes)) {
                        if ($attr.Prefix -eq 'xmlns') {
                            $XmlWriter.WriteAttributeString($attr.Prefix, $attr.LocalName, $attr.NamespaceURI, $attr.Value)
                        }
                        elseif ($attr.Name -eq 'xmlns') {
                            $XmlWriter.WriteAttributeString($attr.Name, $attr.Value)
                        }
                        else {
                            $XmlWriter.WriteAttributeString($attr.Prefix, $attr.LocalName, $attr.NamespaceURI, $attr.Value)
                        }
                    }
                }

                if ($Node.HasChildNodes) {
                    foreach ($child in @($Node.ChildNodes)) {
                        Write-UGSMGameDayZEventXmlNode -XmlWriter $XmlWriter -Node $child
                    }
                }

                $XmlWriter.WriteEndElement()
            }
            ([System.Xml.XmlNodeType]::Text) {
                $XmlWriter.WriteString($Node.Value)
            }
            ([System.Xml.XmlNodeType]::CDATA) {
                $XmlWriter.WriteCData($Node.Value)
            }
            ([System.Xml.XmlNodeType]::Comment) {
                $XmlWriter.WriteComment($Node.Value)
            }
            default {
                if (-not [string]::IsNullOrWhiteSpace([string]$Node.Value)) {
                    $XmlWriter.WriteString([string]$Node.Value)
                }
            }
        }
    }

    function Write-UGSMGameDayZEventXmlFragment {
        param(
            [Parameter(Mandatory)][System.Xml.XmlWriter]$XmlWriter,
            [Parameter()][string]$RawXml
        )

        if ([string]::IsNullOrWhiteSpace($RawXml)) { return }

        try {
            $doc = New-Object System.Xml.XmlDocument
            $doc.PreserveWhitespace = $false
            $doc.LoadXml(('<__ugsm_fragment__>' + $RawXml + '</__ugsm_fragment__>'))

            foreach ($node in @($doc.DocumentElement.ChildNodes)) {
                Write-UGSMGameDayZEventXmlNode -XmlWriter $XmlWriter -Node $node
            }
        }
        catch {
            # Fallback preserves data even if a custom fragment cannot be parsed.
            $XmlWriter.WriteRaw($RawXml)
        }
    }

    try {
        $writer.WriteStartDocument()
        $writer.WriteStartElement('events')

        foreach ($row in @($Rows)) {
            $writer.WriteStartElement('event')
            $writer.WriteAttributeString('name', [string]$row.Name)

            foreach ($pair in @(
                    @{ N = 'nominal'; V = $row.Nominal }
                    @{ N = 'min'; V = $row.Min }
                    @{ N = 'max'; V = $row.Max }
                    @{ N = 'lifetime'; V = $row.Lifetime }
                    @{ N = 'restock'; V = $row.Restock }
                    @{ N = 'saferadius'; V = $row.SafeRadius }
                    @{ N = 'distanceradius'; V = $row.DistanceRadius }
                    @{ N = 'cleanupradius'; V = $row.CleanupRadius }
                    @{ N = 'secondary'; V = $null }
                    @{ N = 'flags'; V = $null }
                    @{ N = 'position'; V = $row.Position }
                    @{ N = 'limit'; V = $row.Limit }
                    @{ N = 'active'; V = $row.Active }
                )) {
                if ($pair.N -eq 'secondary') {
                    if (-not [string]::IsNullOrWhiteSpace([string]$row.SecondaryOuterXml)) {
                        Write-UGSMGameDayZEventXmlFragment -XmlWriter $writer -RawXml ([string]$row.SecondaryOuterXml)
                    }
                }
                elseif ($pair.N -eq 'flags') {
                    $writer.WriteStartElement('flags')
                    $writer.WriteAttributeString('deletable', [string]$row.FlagsDeletable)
                    $writer.WriteAttributeString('init_random', [string]$row.FlagsInitRandom)
                    $writer.WriteAttributeString('remove_damaged', [string]$row.FlagsRemoveDamaged)
                    $writer.WriteEndElement()
                }
                else {
                    $writer.WriteElementString($pair.N, [string]$pair.V)
                }
            }

            if (-not [string]::IsNullOrWhiteSpace([string]$row.ChildrenOuterXml)) {
                Write-UGSMGameDayZEventXmlFragment -XmlWriter $writer -RawXml ([string]$row.ChildrenOuterXml)
            }

            if (-not [string]::IsNullOrWhiteSpace([string]$row.SecondaryNodesOuterXml)) {
                Write-UGSMGameDayZEventXmlFragment -XmlWriter $writer -RawXml ([string]$row.SecondaryNodesOuterXml)
            }

            $writer.WriteEndElement()
        }

        $writer.WriteEndElement()
        $writer.WriteEndDocument()
    }
    finally {
        $writer.Flush()
        $writer.Dispose()
    }

    return $Path
}

function Get-UGSMGameDayZEditorSchema {
    [CmdletBinding()]
    param()

    $actions = @{
        OpenServerSettings   = { param($Instance, $Paths, $StatusLabel) Invoke-UGSMGameDayZEditorAction -Instance $Instance -Paths $Paths -Target 'ServerSettings'   -EnsureFile   -StatusLabel $StatusLabel -OpenedMessage 'Opened ServerSettings.ini.' }
        OpenAdminUsers       = { param($Instance, $Paths, $StatusLabel) Invoke-UGSMGameDayZEditorAction -Instance $Instance -Paths $Paths -Target 'AdminUsers'       -EnsureFile   -StatusLabel $StatusLabel -OpenedMessage 'Opened AdminUsers.ini.' }
        OpenExclusiveUsers   = { param($Instance, $Paths, $StatusLabel) Invoke-UGSMGameDayZEditorAction -Instance $Instance -Paths $Paths -Target 'ExclusiveUsers'   -EnsureFile   -StatusLabel $StatusLabel -OpenedMessage 'Opened ExclusiveUsers.ini.' }
        OpenWhitelistedUsers = { param($Instance, $Paths, $StatusLabel) Invoke-UGSMGameDayZEditorAction -Instance $Instance -Paths $Paths -Target 'WhitelistedUsers' -EnsureFile   -StatusLabel $StatusLabel -OpenedMessage 'Opened WhitelistedUsers.ini.' }
        OpenRaidTimes        = { param($Instance, $Paths, $StatusLabel) Invoke-UGSMGameDayZEditorAction -Instance $Instance -Paths $Paths -Target 'RaidTimes'        -EnsureFile   -StatusLabel $StatusLabel -OpenedMessage 'Opened RaidTimes.json.' }
        OpenEconomy          = { param($Instance, $Paths, $StatusLabel) Invoke-UGSMGameDayZEditorAction -Instance $Instance -Paths $Paths -Target 'EconomyOverride'  -EnsureFile   -StatusLabel $StatusLabel -OpenedMessage 'Opened EconomyOverride.json.' }
        OpenProfileFolder    = { param($Instance, $Paths, $StatusLabel) Invoke-UGSMGameDayZEditorAction -Instance $Instance -Paths $Paths -Target 'ProfileFolder'    -EnsureFolder -StatusLabel $StatusLabel -OpenedMessage 'Opened the DayZ profile folder.' }
    }

    $samplePaths = [pscustomobject]@{
        AdminUsersPath       = 'AdminUsers.ini'
        ExclusiveUsersPath   = 'ExclusiveUsers.ini'
        WhitelistedUsersPath = 'WhitelistedUsers.ini'
        BannedUsersPath      = 'BannedUsers.ini'
        SilencedUsersPath    = 'SilencedUsers.ini'
    }

    return [pscustomobject]@{
        Tabs = @(
            [pscustomobject]@{
                Title   = 'serverDZ.cfg'
                SubTabs = @(
                    [pscustomobject]@{ Title = 'Identity'; Description = 'Server Setup'; Fields = @(
                            @{ Id = 'HostName'; Type = 'Text'; File = 'serverDZ.cfg'; Format = 'Cfg'; Key = 'hostname'; Label = 'Host Name'; DefaultValue = 'DayZ Server'; Hint = 'The public server name shown in the browser.' }
                            @{ Id = 'Password'; Type = 'Text'; File = 'serverDZ.cfg'; Format = 'Cfg'; Key = 'password'; Label = 'Password'; DefaultValue = ''; Hint = 'Leave blank to keep the server public.' }
                            @{ Id = 'ShardId'; Type = 'Text'; File = 'serverDZ.cfg'; Format = 'Cfg'; Key = 'shardId'; Label = 'Shard ID'; DefaultValue = '123abc'; Hint = 'Six alphanumeric characters for a private server.' }
                            @{ Id = 'InstanceId'; Type = 'Number'; File = 'serverDZ.cfg'; Format = 'Cfg'; Key = 'instanceId'; Label = 'Instance ID'; DefaultValue = 1; Min = 1; Max = 1000; Increment = 1; Hint = 'Identifies the server instance and its persistence storage.' }
                            
                        )
                    }

                    [pscustomobject]@{ Title = 'Players'; Description = ''; Fields = @(
                            @{ Id = 'MaxPlayers'; Type = 'Number'; File = 'serverDZ.cfg'; Format = 'Cfg'; Key = 'maxPlayers'; Label = 'Max Players'; DefaultValue = 60; Min = 1; Max = 120; Increment = 1; Hint = 'Maximum simultaneous players allowed on the server.' }
                           
                            @{ Id = 'LoginQueueConcurrentPlayers'; Type = 'Number'; File = 'serverDZ.cfg'; Format = 'Cfg'; Key = 'loginQueueConcurrentPlayers'; Label = 'Login Queue Concurrent Players'; DefaultValue = 5; Min = 1; Max = 100; Increment = 1; Hint = 'Number of players processed at the same time during login.' }
                            @{ Id = 'LoginQueueMaxPlayers'; Type = 'Number'; File = 'serverDZ.cfg'; Format = 'Cfg'; Key = 'loginQueueMaxPlayers'; Label = 'Login Queue Max Players'; DefaultValue = 500; Min = 1; Max = 1000; Increment = 1; Hint = 'Maximum number of players allowed to wait in the login queue.' }
                            
                        ) 
                    }

                    [pscustomobject]@{ Title = 'Voice & View'; Description = ''; Fields = @(
                            @{ Id = 'DisableVoN'; Type = 'Boolean'; File = 'serverDZ.cfg'; Format = 'Cfg'; Key = 'disableVoN'; Label = 'Disable VoN'; DefaultValue = $false; Hint = 'Disable voice over network.' }
                            @{ Id = 'VoNCodecQuality'; Type = 'Number'; File = 'serverDZ.cfg'; Format = 'Cfg'; Key = 'vonCodecQuality'; Label = 'VoN Codec Quality'; DefaultValue = 20; Min = 0; Max = 30; Increment = 1; Hint = 'Voice over network codec quality. Higher is better.' }
                            @{ Id = 'Disable3rdPerson'; Type = 'Boolean'; File = 'serverDZ.cfg'; Format = 'Cfg'; Key = 'disable3rdPerson'; Label = 'Disable 3rd Person'; DefaultValue = $false; Hint = 'Disable third-person camera.' }
                            @{ Id = 'DisableCrosshair'; Type = 'Boolean'; File = 'serverDZ.cfg'; Format = 'Cfg'; Key = 'disableCrosshair'; Label = 'Disable Crosshair'; DefaultValue = $false; Hint = 'Disable crosshair.' }
                            @{ Id = 'DisablePersonalLight'; Type = 'Boolean'; File = 'serverDZ.cfg'; Format = 'Cfg'; Key = 'disablePersonalLight'; Label = 'Disable Personal Light'; DefaultValue = $true; Hint = 'Disable personal light for all connected clients.' }
                            
                        ) 
                    }

                    [pscustomobject]@{ Title = 'Time'; Description = ''; Fields = @(
                            @{ Id = 'LightingConfig'; Type = 'Number'; File = 'serverDZ.cfg'; Format = 'Cfg'; Key = 'lightingConfig'; Label = 'Lighting Config'; DefaultValue = 0; Min = 0; Max = 1; Increment = 1; Hint = '0 = brighter nights, 1 = darker nights.' }
                            @{ Id = 'ServerTime'; Type = 'Text'; File = 'serverDZ.cfg'; Format = 'Cfg'; Key = 'serverTime'; Label = 'Server Time'; DefaultValue = 'SystemTime'; Hint = 'Initial in-game time. Use SystemTime or a value like YYYY/MM/DD/HH/MM.' }
                            @{ Id = 'ServerTimeAcceleration'; Type = 'Number'; File = 'serverDZ.cfg'; Format = 'Cfg'; Key = 'serverTimeAcceleration'; Label = 'Time Acceleration'; DefaultValue = 12; Min = 0; Max = 24; Increment = 1; Hint = 'Multiplier for daytime progression.' }
                            @{ Id = 'ServerNightTimeAcceleration'; Type = 'Decimal'; File = 'serverDZ.cfg'; Format = 'Cfg'; Key = 'serverNightTimeAcceleration'; Label = 'Night Time Acceleration'; DefaultValue = 1; Min = 0.1; Max = 64; Increment = 0.1; Hint = 'Multiplier for nighttime progression.' }
                            @{ Id = 'ServerTimePersistent'; Type = 'Boolean'; File = 'serverDZ.cfg'; Format = 'Cfg'; Key = 'serverTimePersistent'; Label = 'Persistent Time'; DefaultValue = $false; Hint = 'Save and reuse the current world time between restarts.' }
                            
                        ) 
                    }

                    [pscustomobject]@{ Title = 'System'; Description = ''; Fields = @(
                            @{ Id = 'VerifySignatures'; Type = 'Boolean'; File = 'serverDZ.cfg'; Format = 'Cfg'; Key = 'verifySignatures'; Label = 'Verify Signatures'; DefaultValue = $true; Hint = 'Require client signatures to match approved server content.' }
                            @{ Id = 'GuaranteedUpdates'; Type = 'Number'; File = 'serverDZ.cfg'; Format = 'Cfg'; Key = 'guaranteedUpdates'; Label = 'Guaranteed Updates'; DefaultValue = 1; Min = 1; Max = 1; Increment = 1; Hint = 'Communication protocol setting. Leave at 1.' }
                           
                            @{ Id = 'StorageAutoFix'; Type = 'Boolean'; File = 'serverDZ.cfg'; Format = 'Cfg'; Key = 'storageAutoFix'; Label = 'Storage Auto Fix'; DefaultValue = $true; Hint = 'Replace corrupted persistence files with empty ones.' }
                           
                        ) 
                    }

                    #[pscustomobject]@{ Title = 'Mission'; Description = ''; Fields = @(
                    #        @{ Id = 'HostName'; Type = 'Text'; File = 'serverDZ.cfg'; Format = 'Cfg'; SubTab = 'Identity'; Key = 'hostname'; Label = 'Host Name'; DefaultValue = 'DayZ Server'; Hint = 'The public server name shown in the browser.'}
                            
                    #    ) 
                    #}
                    [pscustomobject]@{
                        Title       = 'Discord'
                        Description = 'Per-server Discord override settings. Leave the webhook blank to fall back to the global webhook configured in Settings.'
                        Fields      = @(
                            @{ Id = 'DiscordWebhookUrl'; Type = 'InstanceText'; Model = 'Discord'; Property = 'WebhookUrl'; Label = 'Discord Webhook URL'; DefaultValue = ''; Hint = 'Optional per-server webhook override. Blank uses the global webhook.' }
                            @{ Id = 'DiscordNotifyStart'; Type = 'InstanceBoolean'; Model = 'Discord'; Property = 'NotifyOnStart'; Label = 'Notify On Start'; DefaultValue = $false; Hint = 'Send a Discord notification when this server starts.' }
                            @{ Id = 'DiscordNotifyStop'; Type = 'InstanceBoolean'; Model = 'Discord'; Property = 'NotifyOnStop'; Label = 'Notify On Stop'; DefaultValue = $false; Hint = 'Send a Discord notification when this server stops.' }
                            @{ Id = 'DiscordVisible'; Type = 'InstanceBoolean'; Model = 'Discord'; Property = 'ShowInDashboard'; Label = 'Show In Dashboard'; DefaultValue = $false; Hint = 'Marks this server as visible for Discord/dashboard status integrations.' }

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

                                        $result = Test-UGSMDiscordWebhook -WebhookUrl $discordModel.EffectiveWebhookUrl -Label ("DayZ " + [string]$Instance.Name)

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
        )
    }
}
