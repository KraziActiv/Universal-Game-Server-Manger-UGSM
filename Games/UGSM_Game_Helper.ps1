# UGSM shared game-module helpers
# Common helpers for future game modules. Keep this file game-agnostic.

function ConvertTo-UGSMGameHelperSafeLogText {
    [CmdletBinding()]
    param([AllowNull()][object]$Value)

    if ($null -eq $Value) { return '' }
    $text = [string]$Value
    if ([string]::IsNullOrWhiteSpace($text)) { return $text }

    try {
        if (Get-Command -Name ConvertTo-UGSMDisplayPath -ErrorAction SilentlyContinue) {
            $text = ConvertTo-UGSMDisplayPath -Path $text
        }

        $localAppData = [Environment]::GetFolderPath('LocalApplicationData')
        if (-not [string]::IsNullOrWhiteSpace($localAppData)) {
            $text = [regex]::Replace($text, [regex]::Escape($localAppData.TrimEnd('\')), '%LOCALAPPDATA%', 'IgnoreCase')
        }

        if (-not [string]::IsNullOrWhiteSpace($env:USERPROFILE)) {
            $text = [regex]::Replace($text, [regex]::Escape($env:USERPROFILE.TrimEnd('\')), '%USERPROFILE%', 'IgnoreCase')
        }

        foreach ($entry in @(
            @{ Names = @('UGSM_SteamRoot','UGSM_SteamCMDRoot','UGSM_SteamInstallRoot'); Token = '%UGSM_STEAM%' },
            @{ Names = @('UGSM_ProfileRoot','UGSM_ProfilesRoot','UGSM_ProfileStoreRoot'); Token = '%UGSM_PROFILES%' },
            @{ Names = @('UGSM_AppRoot','UGSM_Root','UGSM_SourceRoot'); Token = '%UGSM_ROOT%' }
        )) {
            foreach ($name in $entry.Names) {
                $rootValue = $null
                $scriptVar = Get-Variable -Name $name -Scope Script -ErrorAction SilentlyContinue
                if ($scriptVar -and $scriptVar.Value) { $rootValue = [string]$scriptVar.Value }
                if ([string]::IsNullOrWhiteSpace($rootValue)) {
                    $globalVar = Get-Variable -Name $name -Scope Global -ErrorAction SilentlyContinue
                    if ($globalVar -and $globalVar.Value) { $rootValue = [string]$globalVar.Value }
                }
                if (-not [string]::IsNullOrWhiteSpace($rootValue)) {
                    $text = [regex]::Replace($text, [regex]::Escape($rootValue.TrimEnd('\')), [string]$entry.Token, 'IgnoreCase')
                }
            }
        }

        $text = [regex]::Replace($text, '(?i)https://(?:canary\.|ptb\.)?discord(?:app)?\.com/api/webhooks/[^\s''"<>]+', '<redacted-discord-webhook>')
        $text = [regex]::Replace($text, '(?i)(\+login\s+)(?!anonymous\b)\S+(\s+)\S+', '$1<redacted>$2<redacted>')
        $text = [regex]::Replace(
            $text,
            '(?i)\b(password|passwd|pass|token|api[_-]?key|apikey|secret|gslt|login[_-]?token|private[_-]?token|webhook(?:url)?)\b\s*[:=]\s*("[^"]*"|''[^'']*''|[^\s;,]+)',
            '$1=<redacted>'
        )
    }
    catch {
    }

    return $text
}

function Write-UGSMGameHelperLog {
    [CmdletBinding()]
    param(
        [ValidateSet('TRACE','DEBUG','INFO','WARN','ERROR')][string]$Level = 'DEBUG',
        [string]$Category = 'Mods',
        [Parameter(Mandatory)][string]$Message,
        [System.Exception]$Exception
    )

    $safeMessage = ConvertTo-UGSMGameHelperSafeLogText -Value $Message
    if ($Exception) {
        $exceptionType = $Exception.GetType().Name
        $exceptionMessage = ConvertTo-UGSMGameHelperSafeLogText -Value $Exception.Message
        $safeMessage = "$safeMessage Exception=$exceptionType`: $exceptionMessage"
    }

    if (Get-Command -Name Write-UGSMLog -ErrorAction SilentlyContinue) {
        Write-UGSMLog -Level $Level -Category $Category -Message $safeMessage
    }
}

function New-UGSMDefaultModsDefinition {
    [CmdletBinding()]
    param(
        [string]$GameId = '',
        [string]$DisplayName = 'Mods',
        [bool]$Supported = $false
    )

    return [pscustomobject]@{
        Supported   = [bool]$Supported
        DisplayName = $DisplayName
        Version     = 1
        Capabilities = [pscustomobject]@{
            SteamWorkshop   = $false
            ArchiveImport   = $false
            FolderImport    = $false
            FrameworkInstall = $false
            PluginManager   = $false
            MapList         = $false
            ConfigMerge     = $false
            LoadOrder       = $false
            UrlDownload     = $false
        }
        Providers = @()
        Archive = [pscustomobject]@{
            AllowedExtensions = @('.zip', '.rar')
            InstallFolderRelative = 'Mods'
            RequireSafetyNotice = $true
        }
        Workshop = [pscustomobject]@{
            IdField = 'WorkshopItemIds'
            SupportsCollections = $true
            ConfigStrategy = 'GameSpecific'
        }
        Framework = [pscustomobject]@{
            Id = ''
            Label = ''
            OfficialSourceOnly = $true
            RequiresConfirmation = $true
        }
        Paths = [pscustomobject]@{
            ModsFolderRelative = 'Mods'
            ManifestFileName = $null
        }
        StoragePolicy = [pscustomobject]@{
            Mode = 'InstanceJson'
            KeepWorkshopModsShared = $true
            CopyFullModsToProfile = $false
            CopyOnlyRequiredFilesToProfile = $true
            RuntimeMode = 'SharedWorkshopCache'
            SummaryFileName = $null
        }
        InstanceStorage = [pscustomobject]@{
            ModsProperty = 'Mods'
            ModStatesProperty = 'ModStates'
        }
        Safety = [pscustomobject]@{
            ShowThirdPartyNotice = $false
            RequireConfirmation = $false
            NoticeKind = 'GenericMods'
        }
        Hooks = [pscustomobject]@{
            Refresh = ''
            Save    = ''
            Install = ''
            Remove  = ''
            Validate = ''
            BuildCustomTab = ''
        }
        GameId = $GameId
    }
}

function Test-UGSMGameModsSupported {
    [CmdletBinding()]
    param([AllowNull()][object]$ModsDefinition)

    if ($null -eq $ModsDefinition) { return $false }
    if ($ModsDefinition.PSObject.Properties['Supported']) { return [bool]$ModsDefinition.Supported }
    return $false
}

function Get-UGSMModSafetyNoticeText {
    [CmdletBinding()]
    param([AllowNull()][object]$ModsDefinition)

    if (-not (Test-UGSMGameModsSupported -ModsDefinition $ModsDefinition)) { return '' }

    $cap = $ModsDefinition.Capabilities
    $parts = New-Object System.Collections.Generic.List[string]

    if ($cap -and $cap.PSObject.Properties['ArchiveImport'] -and [bool]$cap.ArchiveImport) {
        [void]$parts.Add('Archive mods: UGSM can install ZIP/RAR files you provide, but it cannot verify third-party mod safety or compatibility. Only use files from trusted sources. UGSM is not responsible for malware, damage, data loss, crashes, broken saves, or issues caused by third-party mod files.')
    }
    if ($cap -and $cap.PSObject.Properties['FrameworkInstall'] -and [bool]$cap.FrameworkInstall) {
        [void]$parts.Add('Framework installs: installing a mod framework can modify server files. Continue only if you understand that frameworks and plugins can affect stability, security, saves, and gameplay.')
    }
    if ($cap -and $cap.PSObject.Properties['PluginManager'] -and [bool]$cap.PluginManager) {
        [void]$parts.Add('Plugins: third-party plugins can change server behavior and may cause crashes or save issues. Use plugins only from trusted sources.')
    }
    if ($cap -and $cap.PSObject.Properties['SteamWorkshop'] -and [bool]$cap.SteamWorkshop) {
        [void]$parts.Add('Steam Workshop: Workshop items are third-party content. UGSM can help configure/download them, but compatibility and safety remain the server owner''s responsibility.')
    }
    if ($cap -and $cap.PSObject.Properties['UrlDownload'] -and [bool]$cap.UrlDownload) {
        [void]$parts.Add('URL downloads: only download files from trusted official sources. Avoid random mirrors and bundled installers.')
    }

    if ($parts.Count -eq 0) {
        [void]$parts.Add('Mods are third-party content. UGSM can help manage supported mod workflows, but compatibility, safety, and server stability remain the server owner''s responsibility.')
    }

    return ($parts -join "`r`n`r`n")
}


function Test-UGSMModsUseInstanceJson {
    [CmdletBinding()]
    param([AllowNull()][object]$ModsDefinition)

    if ($ModsDefinition) {
        foreach ($propName in @('ModStateStorage','StorageMode')) {
            if ($ModsDefinition.PSObject.Properties[$propName] -and [string]$ModsDefinition.$propName -eq 'InstanceJson') { return $true }
        }
        if ($ModsDefinition.PSObject.Properties['StoragePolicy'] -and $ModsDefinition.StoragePolicy) {
            foreach ($propName in @('Mode','StorageMode','ModStateStorage')) {
                if ($ModsDefinition.StoragePolicy.PSObject.Properties[$propName] -and [string]$ModsDefinition.StoragePolicy.$propName -eq 'InstanceJson') { return $true }
            }
        }
    }

    return $true
}

function Get-UGSMModsInstancePropertyNames {
    [CmdletBinding()]
    param([AllowNull()][object]$ModsDefinition)

    $modsProperty = 'Mods'
    $statesProperty = 'ModStates'

    if ($ModsDefinition) {
        foreach ($propName in @('InstanceModsProperty','ModsProperty')) {
            if ($ModsDefinition.PSObject.Properties[$propName] -and -not [string]::IsNullOrWhiteSpace([string]$ModsDefinition.$propName)) { $modsProperty = [string]$ModsDefinition.$propName }
        }
        foreach ($propName in @('InstanceModStatesProperty','ModStatesProperty')) {
            if ($ModsDefinition.PSObject.Properties[$propName] -and -not [string]::IsNullOrWhiteSpace([string]$ModsDefinition.$propName)) { $statesProperty = [string]$ModsDefinition.$propName }
        }
        if ($ModsDefinition.PSObject.Properties['InstanceStorage'] -and $ModsDefinition.InstanceStorage) {
            if ($ModsDefinition.InstanceStorage.PSObject.Properties['ModsProperty'] -and -not [string]::IsNullOrWhiteSpace([string]$ModsDefinition.InstanceStorage.ModsProperty)) { $modsProperty = [string]$ModsDefinition.InstanceStorage.ModsProperty }
            if ($ModsDefinition.InstanceStorage.PSObject.Properties['ModStatesProperty'] -and -not [string]::IsNullOrWhiteSpace([string]$ModsDefinition.InstanceStorage.ModStatesProperty)) { $statesProperty = [string]$ModsDefinition.InstanceStorage.ModStatesProperty }
        }
    }

    return [pscustomobject]@{ Mods = $modsProperty; States = $statesProperty }
}

function Ensure-UGSMModsInstanceCollections {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$Instance,
        [AllowNull()][object]$ModsDefinition
    )

    $names = Get-UGSMModsInstancePropertyNames -ModsDefinition $ModsDefinition
    if (-not $Instance.PSObject.Properties[$names.Mods]) { Add-Member -InputObject $Instance -MemberType NoteProperty -Name $names.Mods -Value @() -Force }
    if (-not $Instance.PSObject.Properties[$names.States]) { Add-Member -InputObject $Instance -MemberType NoteProperty -Name $names.States -Value @() -Force }
    return $names
}

function Get-UGSMModsInstanceDefinitionPath {
    [CmdletBinding()]
    param([Parameter(Mandatory)][object]$Instance)

    if ($Instance.PSObject.Properties['DefinitionPath'] -and -not [string]::IsNullOrWhiteSpace([string]$Instance.DefinitionPath)) { return [string]$Instance.DefinitionPath }

    $gameId = if ($Instance.PSObject.Properties['GameId']) { [string]$Instance.GameId } else { '' }
    if ($gameId -eq 'ProjectZomboid' -and (Get-Command -Name Get-UGSMGameProjectZomboidInstanceDefinitionPath -ErrorAction SilentlyContinue)) {
        try { return [string](Get-UGSMGameProjectZomboidInstanceDefinitionPath -Instance $Instance) } catch { }
    }
    if ($gameId -eq 'DayZ' -and (Get-Command -Name Get-UGSMGameDayZInstanceDefinitionPath -ErrorAction SilentlyContinue)) {
        try { return [string](Get-UGSMGameDayZInstanceDefinitionPath -Instance $Instance) } catch { }
    }
    if (Get-Command -Name Get-UGSMInstanceDefinitionFilePath -ErrorAction SilentlyContinue) {
        try { return [string](Get-UGSMInstanceDefinitionFilePath -Instance $Instance -Create) } catch { }
    }
    if ($Instance.PSObject.Properties['ProfilePath'] -and -not [string]::IsNullOrWhiteSpace([string]$Instance.ProfilePath)) { return (Join-Path ([string]$Instance.ProfilePath) 'instance.json') }
    return ''
}

function Save-UGSMModsInstanceDefinition {
    [CmdletBinding()]
    param([Parameter(Mandatory)][object]$Instance)

    $gameId = if ($Instance.PSObject.Properties['GameId']) { [string]$Instance.GameId } else { '' }
    $commands = New-Object System.Collections.Generic.List[string]
    if (-not [string]::IsNullOrWhiteSpace($gameId)) { [void]$commands.Add(('Save-UGSMGame' + $gameId + 'InstanceDefinition')) }
    foreach ($cmd in @('Save-UGSMGameProjectZomboidInstanceDefinition','Save-UGSMGameDayZInstanceDefinition','Save-UGSMInstance','Update-UGSMInstance','Set-UGSMInstance')) { [void]$commands.Add($cmd) }

    foreach ($cmd in @($commands | Select-Object -Unique)) {
        if (Get-Command -Name $cmd -ErrorAction SilentlyContinue) {
            try { & $cmd -Instance $Instance | Out-Null; return $true } catch { }
        }
    }

    $path = Get-UGSMModsInstanceDefinitionPath -Instance $Instance
    if ([string]::IsNullOrWhiteSpace($path)) { return $false }
    try {
        $parent = Split-Path -Parent $path
        if (-not [string]::IsNullOrWhiteSpace($parent) -and -not (Test-Path -LiteralPath $parent -PathType Container)) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
        $Instance | ConvertTo-Json -Depth 16 | Set-Content -LiteralPath $path -Encoding UTF8 -ErrorAction Stop
        return $true
    }
    catch {
        Write-UGSMGameHelperLog -Level 'WARN' -Category 'Mods' -Message ('Failed to save instance mod state. Path=' + $path) -Exception $_.Exception
        return $false
    }
}

function Resolve-UGSMModsManifestPath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$Instance,
        [AllowNull()][object]$ModsDefinition
    )

    if (Test-UGSMModsUseInstanceJson -ModsDefinition $ModsDefinition) {
        return (Get-UGSMModsInstanceDefinitionPath -Instance $Instance)
    }

    $profilePath = ''
    if ($Instance.PSObject.Properties['ProfilePath']) { $profilePath = [string]$Instance.ProfilePath }
    if ([string]::IsNullOrWhiteSpace($profilePath)) { return '' }

    $fileName = ''
    if ($ModsDefinition -and $ModsDefinition.PSObject.Properties['Paths'] -and $ModsDefinition.Paths -and $ModsDefinition.Paths.PSObject.Properties['ManifestFileName']) {
        $candidate = [string]$ModsDefinition.Paths.ManifestFileName
        if (-not [string]::IsNullOrWhiteSpace($candidate)) { $fileName = $candidate }
    }
    if ([string]::IsNullOrWhiteSpace($fileName)) { return (Get-UGSMModsInstanceDefinitionPath -Instance $Instance) }

    return (Join-Path $profilePath $fileName)
}


function Read-UGSMModsManifest {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$Instance,
        [AllowNull()][object]$ModsDefinition
    )

    if (Test-UGSMModsUseInstanceJson -ModsDefinition $ModsDefinition) {
        $names = Ensure-UGSMModsInstanceCollections -Instance $Instance -ModsDefinition $ModsDefinition
        $mods = @()
        $modsProp = $Instance.PSObject.Properties[$names.Mods]
        if ($modsProp -and $modsProp.Value) { $mods = @($modsProp.Value) }
        return [pscustomobject]@{
            Version = 1
            GameId = if ($Instance.PSObject.Properties['GameId']) { [string]$Instance.GameId } else { '' }
            Storage = 'InstanceJson'
            Mods = @($mods)
        }
    }

    $path = Resolve-UGSMModsManifestPath -Instance $Instance -ModsDefinition $ModsDefinition
    if ([string]::IsNullOrWhiteSpace($path) -or -not (Test-Path -LiteralPath $path -PathType Leaf)) {
        return [pscustomobject]@{ Version = 1; GameId = [string]$Instance.GameId; Mods = @() }
    }

    try {
        return (Get-Content -LiteralPath $path -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop)
    }
    catch {
        Write-UGSMGameHelperLog -Level 'WARN' -Category 'Mods' -Message ('Failed to read mod manifest. Path=' + $path) -Exception $_.Exception
        return [pscustomobject]@{ Version = 1; GameId = [string]$Instance.GameId; Mods = @() }
    }
}


function Save-UGSMModsManifest {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$Instance,
        [Parameter(Mandatory)][object]$Manifest,
        [AllowNull()][object]$ModsDefinition
    )

    $manifest = Normalize-UGSMModsManifest -Manifest $Manifest -Instance $Instance -ModsDefinition $ModsDefinition

    if (Test-UGSMModsUseInstanceJson -ModsDefinition $ModsDefinition) {
        $names = Ensure-UGSMModsInstanceCollections -Instance $Instance -ModsDefinition $ModsDefinition
        $mods = @($manifest.Mods)
        $Instance.PSObject.Properties[$names.Mods].Value = @($mods)

        $states = @()
        foreach ($mod in @($mods)) {
            if (-not $mod) { continue }
            $id = ''
            if ($mod.PSObject.Properties['WorkshopId']) { $id = [string]$mod.WorkshopId }
            elseif ($mod.PSObject.Properties['Id']) { $id = [string]$mod.Id }
            $states += [pscustomobject]@{
                Id = $id
                Enabled = if ($mod.PSObject.Properties['Enabled']) { [bool]$mod.Enabled } else { $true }
                LoadOrder = if ($mod.PSObject.Properties['LoadOrder']) { [int]$mod.LoadOrder } else { 0 }
            }
        }
        $Instance.PSObject.Properties[$names.States].Value = @($states)
        [void](Save-UGSMModsInstanceDefinition -Instance $Instance)
        Write-UGSMGameHelperLog -Level 'DEBUG' -Category 'Mods' -Message 'Saved mod state into instance.json.'
        return $true
    }

    $path = Resolve-UGSMModsManifestPath -Instance $Instance -ModsDefinition $ModsDefinition
    if ([string]::IsNullOrWhiteSpace($path)) { throw 'Mods manifest path could not be resolved.' }

    $parent = Split-Path -Parent $path
    if (-not (Test-Path -LiteralPath $parent -PathType Container)) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }

    $manifest | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $path -Encoding UTF8
    Write-UGSMGameHelperLog -Level 'DEBUG' -Category 'Mods' -Message ('Saved mod manifest. Path=' + $path)
    return $true
}


function Get-UGSMModsSummaryPath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$Instance,
        [AllowNull()][object]$ModsDefinition
    )

    if (Test-UGSMModsUseInstanceJson -ModsDefinition $ModsDefinition) { return '' }

    $summaryFileName = ''
    if ($ModsDefinition -and $ModsDefinition.PSObject.Properties['StoragePolicy'] -and $ModsDefinition.StoragePolicy -and $ModsDefinition.StoragePolicy.PSObject.Properties['SummaryFileName']) {
        $candidate = [string]$ModsDefinition.StoragePolicy.SummaryFileName
        if (-not [string]::IsNullOrWhiteSpace($candidate)) { $summaryFileName = $candidate }
    }
    if ([string]::IsNullOrWhiteSpace($summaryFileName)) { return '' }

    $manifestPath = Resolve-UGSMModsManifestPath -Instance $Instance -ModsDefinition $ModsDefinition
    if ([string]::IsNullOrWhiteSpace($manifestPath)) { return '' }
    return (Join-Path (Split-Path -Parent $manifestPath) $summaryFileName)
}


function Get-UGSMModsSummaryLines {
    [CmdletBinding()]
    param([AllowNull()][object]$Manifest)

    $lines = New-Object System.Collections.Generic.List[string]
    if (-not $Manifest -or -not $Manifest.PSObject.Properties['Mods'] -or @($Manifest.Mods).Count -eq 0) {
        [void]$lines.Add('No active mods are configured for this server profile yet.')
        return $lines.ToArray()
    }

    $index = 1
    foreach ($mod in @($Manifest.Mods | Sort-Object LoadOrder)) {
        if (-not $mod) { continue }
        $enabled = if ($mod.PSObject.Properties['Enabled'] -and [bool]$mod.Enabled) { 'Enabled' } elseif (-not $mod.PSObject.Properties['Enabled']) { 'Enabled' } else { 'Disabled' }
        $source = if ($mod.PSObject.Properties['SourceType']) { [string]$mod.SourceType } else { 'SteamWorkshop' }
        $name = if ($mod.PSObject.Properties['Name'] -and -not [string]::IsNullOrWhiteSpace([string]$mod.Name)) { [string]$mod.Name } else { 'Workshop ' + [string]$mod.WorkshopId }
        $id = if ($mod.PSObject.Properties['WorkshopId']) { [string]$mod.WorkshopId } elseif ($mod.PSObject.Properties['Id']) { [string]$mod.Id } else { '' }
        $modIds = ''
        if ($mod.PSObject.Properties['ModIds'] -and @($mod.ModIds).Count -gt 0) { $modIds = ' | Mods=' + ((@($mod.ModIds) | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) }) -join ',') }
        elseif ($mod.PSObject.Properties['ModId'] -and -not [string]::IsNullOrWhiteSpace([string]$mod.ModId)) { $modIds = ' | Mods=' + [string]$mod.ModId }
        $maps = ''
        if ($mod.PSObject.Properties['MapFolders'] -and @($mod.MapFolders).Count -gt 0) { $maps = ' | Maps=' + ((@($mod.MapFolders) | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) }) -join ',') }
        [void]$lines.Add(('{0}. [{1}] {2} - {3} ({4}){5}{6}' -f $index, $enabled, $source, $name, $id, $modIds, $maps))
        $index++
    }

    if ($lines.Count -eq 0) { [void]$lines.Add('No active mods are configured for this server profile yet.') }
    return $lines.ToArray()
}

function Get-UGSMModsActiveSummaryText {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$Instance,
        [AllowNull()][object]$ModsDefinition
    )

    $manifest = Normalize-UGSMModsManifest -Manifest (Read-UGSMModsManifest -Instance $Instance -ModsDefinition $ModsDefinition) -Instance $Instance -ModsDefinition $ModsDefinition
    return [string]::Join([Environment]::NewLine, @(Get-UGSMModsSummaryLines -Manifest $manifest))
}

function Update-UGSMModsActiveListControls {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$Instance,
        [AllowNull()][object]$ModsDefinition,
        [AllowNull()][object]$StatusLabel
    )

    $summaryText = Get-UGSMModsActiveSummaryText -Instance $Instance -ModsDefinition $ModsDefinition

    try {
        $form = $null
        if ($StatusLabel) { $form = $StatusLabel.FindForm() }
        if ($null -eq $form) { return $summaryText }

        $controls = $form.Controls.Find('UGSMModsActiveListView', $true)
        foreach ($control in @($controls)) {
            if ($control -and $control.PSObject.Properties['Text']) { $control.Text = $summaryText }
        }
    }
    catch {
        # UI refresh is best-effort; the summary file has already been written.
    }

    return $summaryText
}


function Normalize-UGSMModsManifest {
    [CmdletBinding()]
    param(
        [AllowNull()][object]$Manifest,
        [Parameter(Mandatory)][object]$Instance,
        [AllowNull()][object]$ModsDefinition
    )

    $mods = @()
    if ($Manifest -and $Manifest.PSObject.Properties['Mods'] -and $Manifest.Mods) { $mods = @($Manifest.Mods) }

    $normalized = New-Object System.Collections.Generic.List[object]
    $index = 0
    foreach ($mod in @($mods)) {
        if (-not $mod) { continue }

        $sourceType = 'SteamWorkshop'
        if ($mod.PSObject.Properties['SourceType'] -and -not [string]::IsNullOrWhiteSpace([string]$mod.SourceType)) { $sourceType = [string]$mod.SourceType }
        elseif ($mod.PSObject.Properties['Type'] -and -not [string]::IsNullOrWhiteSpace([string]$mod.Type)) { $sourceType = [string]$mod.Type }

        $loadOrder = $index
        if ($mod.PSObject.Properties['LoadOrder']) { try { $loadOrder = [int]$mod.LoadOrder } catch { $loadOrder = $index } }
        $enabled = $true
        if ($mod.PSObject.Properties['Enabled']) { $enabled = [bool]$mod.Enabled }

        if ([string]$sourceType -eq 'SteamWorkshop') {
            $workshopId = ''
            foreach ($propName in @('WorkshopId','Id')) {
                if ($mod.PSObject.Properties[$propName] -and [string]$mod.$propName -match '\d+') { $workshopId = ([regex]::Match([string]$mod.$propName, '\d+')).Value; break }
            }
            if ([string]::IsNullOrWhiteSpace($workshopId)) { continue }

            $modId = ''
            foreach ($propName in @('ModId','ModID','PZModId')) {
                if ($mod.PSObject.Properties[$propName] -and -not [string]::IsNullOrWhiteSpace([string]$mod.$propName)) { $modId = [string]$mod.$propName; break }
            }
            $modIds = @()
            if ($mod.PSObject.Properties['ModIds']) { $modIds = @($mod.ModIds | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) }) }
            elseif (-not [string]::IsNullOrWhiteSpace($modId)) { $modIds = @($modId) }

            $maps = @()
            if ($mod.PSObject.Properties['MapFolders']) { $maps = @($mod.MapFolders | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) }) }
            elseif ($mod.PSObject.Properties['MapFolder'] -and -not [string]::IsNullOrWhiteSpace([string]$mod.MapFolder)) { $maps = @([string]$mod.MapFolder) }

            $name = if ($mod.PSObject.Properties['Name'] -and -not [string]::IsNullOrWhiteSpace([string]$mod.Name)) { [string]$mod.Name } else { 'Workshop ' + $workshopId }
            [void]$normalized.Add([pscustomobject]@{
                Id = $workshopId
                Name = $name
                SourceType = 'SteamWorkshop'
                WorkshopId = $workshopId
                Enabled = $enabled
                LoadOrder = $loadOrder
                RuntimeMode = 'SharedWorkshopCache'
                SharedContentPath = if ($mod.PSObject.Properties['SharedContentPath']) { [string]$mod.SharedContentPath } else { '' }
                ModId = $modId
                ModIds = @($modIds)
                MapFolders = @($maps)
                Notes = if ($mod.PSObject.Properties['Notes']) { [string]$mod.Notes } else { '' }
            })
        }
        else {
            $id = ''
            foreach ($propName in @('Id','Name','FolderName')) {
                if ($mod.PSObject.Properties[$propName] -and -not [string]::IsNullOrWhiteSpace([string]$mod.$propName)) { $id = [string]$mod.$propName; break }
            }
            if ([string]::IsNullOrWhiteSpace($id)) { continue }

            $name = if ($mod.PSObject.Properties['Name'] -and -not [string]::IsNullOrWhiteSpace([string]$mod.Name)) { [string]$mod.Name } else { $id }
            [void]$normalized.Add([pscustomobject]@{
                Id = $id
                Name = $name
                SourceType = $sourceType
                Enabled = $enabled
                LoadOrder = $loadOrder
                RuntimeMode = if ($mod.PSObject.Properties['RuntimeMode'] -and -not [string]::IsNullOrWhiteSpace([string]$mod.RuntimeMode)) { [string]$mod.RuntimeMode } else { 'SharedArchiveMods' }
                SharedContentPath = if ($mod.PSObject.Properties['SharedContentPath']) { [string]$mod.SharedContentPath } elseif ($mod.PSObject.Properties['InstalledPath']) { [string]$mod.InstalledPath } else { '' }
                InstalledPath = if ($mod.PSObject.Properties['InstalledPath']) { [string]$mod.InstalledPath } elseif ($mod.PSObject.Properties['SharedContentPath']) { [string]$mod.SharedContentPath } else { '' }
                SourceArchive = if ($mod.PSObject.Properties['SourceArchive']) { [string]$mod.SourceArchive } else { '' }
                FolderName = if ($mod.PSObject.Properties['FolderName']) { [string]$mod.FolderName } else { $name }
                Notes = if ($mod.PSObject.Properties['Notes']) { [string]$mod.Notes } else { '' }
            })
        }
        $index++
    }

    $storagePolicy = [pscustomobject]@{
        KeepWorkshopModsShared = $true
        CopyFullModsToProfile = $false
        CopyOnlyRequiredFilesToProfile = $true
        RuntimeMode = 'SharedWorkshopCache'
        Mode = 'InstanceJson'
        SummaryFileName = $null
    }
    if ($ModsDefinition -and $ModsDefinition.PSObject.Properties['StoragePolicy'] -and $ModsDefinition.StoragePolicy) { $storagePolicy = $ModsDefinition.StoragePolicy }

    return [pscustomobject]@{
        Version = 1
        GameId = if ($Instance.PSObject.Properties['GameId']) { [string]$Instance.GameId } else { '' }
        Storage = if (Test-UGSMModsUseInstanceJson -ModsDefinition $ModsDefinition) { 'InstanceJson' } else { 'ManifestFile' }
        Mods = @($normalized.ToArray())
        UpdatedAtUtc = [DateTime]::UtcNow.ToString('o')
        StoragePolicy = $storagePolicy
    }
}

function Get-UGSMWorkshopIdFromInput {
    [CmdletBinding()]
    param([AllowNull()][string]$InputText)

    if ([string]::IsNullOrWhiteSpace($InputText)) { return '' }
    $text = $InputText.Trim()

    if ($text -match '(?i)[?&]id=(\d+)') { return [string]$matches[1] }
    if ($text -match '(?i)/sharedfiles/filedetails/\?id=(\d+)') { return [string]$matches[1] }
    if ($text -match '^\d+$') { return $text }

    $m = [regex]::Match($text, '\d{6,}')
    if ($m.Success) { return $m.Value }

    return ''
}


function Add-UGSMSteamWorkshopModToManifest {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$Instance,
        [Parameter(Mandatory)][string]$WorkshopInput,
        [AllowNull()][object]$ModsDefinition,
        [string]$ModId = '',
        [string[]]$MapFolders = @(),
        [string]$Notes = ''
    )

    $workshopId = Get-UGSMWorkshopIdFromInput -InputText $WorkshopInput
    if ([string]::IsNullOrWhiteSpace($workshopId)) { throw 'No Steam Workshop ID was found in the input.' }

    $manifest = Normalize-UGSMModsManifest -Manifest (Read-UGSMModsManifest -Instance $Instance -ModsDefinition $ModsDefinition) -Instance $Instance -ModsDefinition $ModsDefinition
    $mods = New-Object System.Collections.Generic.List[object]
    $exists = $false

    foreach ($mod in @($manifest.Mods | Sort-Object LoadOrder)) {
        if (-not $mod) { continue }
        if ($mod.PSObject.Properties['WorkshopId'] -and [string]$mod.WorkshopId -eq $workshopId) {
            $exists = $true
            if (-not [string]::IsNullOrWhiteSpace($ModId)) {
                $mod.ModId = $ModId
                $mod.ModIds = @($ModId)
            }
            if ($MapFolders -and @($MapFolders).Count -gt 0) { $mod.MapFolders = @($MapFolders | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) }) }
            if (-not [string]::IsNullOrWhiteSpace($Notes)) { $mod.Notes = $Notes }
            $mod.Enabled = $true
        }
        [void]$mods.Add($mod)
    }

    if (-not $exists) {
        $cleanMaps = @($MapFolders | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) })
        $newMod = [pscustomobject]@{
            Id = $workshopId
            Name = 'Workshop ' + $workshopId
            SourceType = 'SteamWorkshop'
            WorkshopId = $workshopId
            Enabled = $true
            LoadOrder = $mods.Count
            RuntimeMode = 'SharedWorkshopCache'
            SharedContentPath = ''
            ModId = $ModId
            ModIds = @(if (-not [string]::IsNullOrWhiteSpace($ModId)) { $ModId })
            MapFolders = @($cleanMaps)
            Notes = $Notes
        }
        [void]$mods.Add($newMod)
    }

    $manifest.Mods = $mods.ToArray()
    $manifest.UpdatedAtUtc = [DateTime]::UtcNow.ToString('o')
    Save-UGSMModsManifest -Instance $Instance -Manifest $manifest -ModsDefinition $ModsDefinition | Out-Null
    Invoke-UGSMGameHelperHook -ModsDefinition $ModsDefinition -HookName 'AfterModsChanged' -Instance $Instance -Manifest $manifest -WorkshopId $workshopId | Out-Null

    return [pscustomobject]@{
        Success = $true
        WorkshopId = $workshopId
        Manifest = $manifest
        SummaryPath = ''
        Message = $(if ($exists) { 'Updated Workshop mod ' + $workshopId + ' in instance mod list.' } else { 'Added Workshop mod ' + $workshopId + ' to instance mod list.' })
    }
}


function Remove-UGSMSteamWorkshopModFromManifest {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$Instance,
        [Parameter(Mandatory)][string]$WorkshopInput,
        [AllowNull()][object]$ModsDefinition
    )

    $workshopId = Get-UGSMWorkshopIdFromInput -InputText $WorkshopInput
    if ([string]::IsNullOrWhiteSpace($workshopId)) { throw 'No Steam Workshop ID was found in the input.' }

    $manifest = Normalize-UGSMModsManifest -Manifest (Read-UGSMModsManifest -Instance $Instance -ModsDefinition $ModsDefinition) -Instance $Instance -ModsDefinition $ModsDefinition
    $mods = New-Object System.Collections.Generic.List[object]

    foreach ($mod in @($manifest.Mods | Sort-Object LoadOrder)) {
        if (-not $mod) { continue }
        if ($mod.PSObject.Properties['WorkshopId'] -and [string]$mod.WorkshopId -eq $workshopId) { continue }
        $mod.LoadOrder = $mods.Count
        [void]$mods.Add($mod)
    }

    $manifest.Mods = $mods.ToArray()
    $manifest.UpdatedAtUtc = [DateTime]::UtcNow.ToString('o')
    Save-UGSMModsManifest -Instance $Instance -Manifest $manifest -ModsDefinition $ModsDefinition | Out-Null
    Invoke-UGSMGameHelperHook -ModsDefinition $ModsDefinition -HookName 'AfterModsChanged' -Instance $Instance -Manifest $manifest -WorkshopId $workshopId | Out-Null

    return [pscustomobject]@{
        Success = $true
        WorkshopId = $workshopId
        Manifest = $manifest
        SummaryPath = ''
        Message = 'Removed Workshop mod ' + $workshopId + ' from instance mod list.'
    }
}

function Get-UGSMModsSteamAppId {
    [CmdletBinding()]
    param(
        [AllowNull()][object]$ModsDefinition,
        [string]$FallbackAppId = ''
    )

    $candidates = New-Object System.Collections.Generic.List[string]

    if ($ModsDefinition) {
        if ($ModsDefinition.PSObject.Properties['Workshop'] -and $ModsDefinition.Workshop) {
            foreach ($name in @('AppId','WorkshopAppId','SteamWorkshopAppId','SteamAppId','ClientAppId')) {
                if ($ModsDefinition.Workshop.PSObject.Properties[$name]) { [void]$candidates.Add([string]$ModsDefinition.Workshop.$name) }
            }
        }

        foreach ($name in @('WorkshopAppId','SteamWorkshopAppId','SteamStoreAppId','StoreAppId','ClientAppId','SteamAppId')) {
            if ($ModsDefinition.PSObject.Properties[$name]) { [void]$candidates.Add([string]$ModsDefinition.$name) }
        }
    }

    if (-not [string]::IsNullOrWhiteSpace($FallbackAppId)) { [void]$candidates.Add($FallbackAppId) }

    foreach ($candidate in $candidates.ToArray()) {
        if (-not [string]::IsNullOrWhiteSpace($candidate) -and $candidate.Trim() -ne '000000') { return $candidate.Trim() }
    }

    if ($ModsDefinition -and $ModsDefinition.PSObject.Properties['GameId'] -and [string]$ModsDefinition.GameId -in @('PZTest','ProjectZomboid')) { return '108600' }
    return ''
}

function Get-UGSMWorkshopSharedContentPath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$AppId,
        [Parameter(Mandatory)][string]$WorkshopId,
        [AllowNull()][object]$Instance = $null
    )

    $steamCmdPath = $null
    try { $steamCmdPath = Get-UGSMGameHelperSteamCmdExecutablePath -Instance $Instance } catch { $steamCmdPath = $null }
    try {
        foreach ($root in @(Get-UGSMGameHelperWorkshopContentRoots -Instance $Instance -AppId $AppId -SteamCmdPath $steamCmdPath)) {
            $candidate = Join-Path $root ([string]$WorkshopId)
            if (Test-Path -LiteralPath $candidate -PathType Container) { return [string]$candidate }
        }
    } catch { }

    if (-not [string]::IsNullOrWhiteSpace([string]$steamCmdPath)) {
        return (Join-Path (Split-Path -Parent $steamCmdPath) ('steamapps\workshop\content\' + $AppId + '\' + $WorkshopId))
    }
    return ''
}






function Get-UGSMGameHelperSteamCmdExecutablePath {
    [CmdletBinding()]
    param([AllowNull()][object]$Instance)

    # Generic copy of the working DayZ SteamCMD resolver. Keep this path simple:
    # resolve steamcmd.exe and let Start-Process run SteamCMD visibly.
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
    if (-not $settings -and (Get-Command -Name Get-UGSMSettings -ErrorAction SilentlyContinue)) {
        try { $settings = Get-UGSMSettings } catch { $settings = $null }
    }
    if (-not $settings -and (Get-Command -Name Get-UGSMGlobalSettingsModel -ErrorAction SilentlyContinue)) {
        try { $settings = Get-UGSMGlobalSettingsModel } catch { $settings = $null }
    }

    if ($settings) {
        foreach ($propertyName in @('SteamCMDPath', 'SteamCmdPath', 'SteamCmdExePath')) {
            if ($settings.PSObject.Properties.Name -contains $propertyName) {
                $value = [string]$settings.$propertyName
                if (-not [string]::IsNullOrWhiteSpace([string]$value)) { $candidates += $value }
            }
        }
        foreach ($propertyName in @('SteamCmdRoot', 'SteamRoot', 'SteamPath', 'InstallRoot', 'SteamLibraryRoot', 'SteamInstallPath')) {
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

    foreach ($varName in @('UGSM_SteamCMDRoot','UGSM_STEAMCMD','UGSM_STEAM')) {
        try {
            $value = [Environment]::GetEnvironmentVariable($varName)
            if (-not [string]::IsNullOrWhiteSpace([string]$value)) {
                $candidates += (Join-Path $value 'steamcmd.exe')
                $candidates += (Join-Path $value 'SteamCMD\steamcmd.exe')
            }
        } catch { }
    }

    foreach ($candidate in @($candidates | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) } | Select-Object -Unique)) {
        $path = [string]$candidate
        if ((Split-Path -Leaf $path) -ine 'steamcmd.exe') { $path = Join-Path $path 'steamcmd.exe' }
        if (Test-Path -LiteralPath $path -PathType Leaf) { return [string]$path }
    }
    throw 'Workshop mod download failed: SteamCMD executable could not be resolved from the current settings.'
}

function Get-UGSMGameHelperSteamLoginArguments {
    [CmdletBinding()]
    param([string]$LoginMode = 'Anonymous')

    # Project Zomboid supports anonymous Workshop downloads. This mirrors DayZ's
    # argument-array style while allowing anonymous games to skip stored credentials.
    if ([string]::IsNullOrWhiteSpace($LoginMode) -or $LoginMode -eq 'Anonymous') {
        return @('+login', 'anonymous')
    }

    $settings = $null
    if (Get-Command -Name Get-UGSMGlobalSettings -ErrorAction SilentlyContinue) {
        try { $settings = Get-UGSMGlobalSettings -CreateIfMissing } catch { $settings = $null }
    }
    if (-not $settings -and (Get-Command -Name Get-UGSMSettings -ErrorAction SilentlyContinue)) {
        try { $settings = Get-UGSMSettings } catch { $settings = $null }
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
        throw 'Workshop mod download requires Steam credentials for this game. Set your Steam username in settings.'
    }

    if ([string]::IsNullOrWhiteSpace($steamPass)) {
        return @('+login', $steamUser)
    }

    return @('+login', $steamUser, $steamPass)
}

function Get-UGSMGameHelperWorkshopContentRoots {
    [CmdletBinding()]
    param(
        [AllowNull()][object]$Instance,
        [Parameter(Mandatory)][string]$AppId,
        [AllowNull()][string]$SteamCmdPath
    )

    # Generic version of DayZ's Workshop content root resolver. SteamCMD normally
    # places downloads under its own steamapps folder, not necessarily the game
    # install Steam library the user is looking at.
    $roots = @()
    $installPath = ''
    try {
        if ($Instance -and $Instance.PSObject.Properties.Name -contains 'InstallPath') { $installPath = [string]$Instance.InstallPath }
    } catch { $installPath = '' }

    if (-not [string]::IsNullOrWhiteSpace([string]$installPath)) {
        $installPathText = [string]$installPath
        $marker = '\steamapps\common\'
        $markerIndex = $installPathText.IndexOf($marker, [System.StringComparison]::OrdinalIgnoreCase)
        if ($markerIndex -ge 0) {
            $libraryRoot = $installPathText.Substring(0, $markerIndex)
            if (-not [string]::IsNullOrWhiteSpace([string]$libraryRoot)) {
                $roots += (Join-Path $libraryRoot ('steamapps\workshop\content\' + [string]$AppId))
            }
        }
        $installParent = Split-Path -Parent $installPathText
        if (-not [string]::IsNullOrWhiteSpace([string]$installParent)) { $roots += (Join-Path $installParent ('steamapps\workshop\content\' + [string]$AppId)) }
        $roots += (Join-Path $installPathText ('steamapps\workshop\content\' + [string]$AppId))
    }

    if (-not [string]::IsNullOrWhiteSpace([string]$SteamCmdPath)) {
        $steamCmdRoot = Split-Path -Parent $SteamCmdPath
        if (-not [string]::IsNullOrWhiteSpace([string]$steamCmdRoot)) {
            $roots += (Join-Path $steamCmdRoot ('steamapps\workshop\content\' + [string]$AppId))
            $steamCmdParent = Split-Path -Parent $steamCmdRoot
            if (-not [string]::IsNullOrWhiteSpace([string]$steamCmdParent)) { $roots += (Join-Path $steamCmdParent ('steamapps\workshop\content\' + [string]$AppId)) }
        }
    }

    $settings = $null
    if (Get-Command -Name Get-UGSMGlobalSettings -ErrorAction SilentlyContinue) {
        try { $settings = Get-UGSMGlobalSettings -CreateIfMissing } catch { $settings = $null }
    }
    if (-not $settings -and (Get-Command -Name Get-UGSMSettings -ErrorAction SilentlyContinue)) {
        try { $settings = Get-UGSMSettings } catch { $settings = $null }
    }
    if ($settings) {
        foreach ($propertyName in @('SteamCmdRoot', 'SteamRoot', 'SteamPath', 'InstallRoot', 'SteamLibraryRoot', 'SteamInstallPath')) {
            if ($settings.PSObject.Properties.Name -contains $propertyName) {
                $candidateRoot = [string]$settings.$propertyName
                if (-not [string]::IsNullOrWhiteSpace([string]$candidateRoot)) {
                    $roots += (Join-Path $candidateRoot ('steamapps\workshop\content\' + [string]$AppId))
                    $roots += (Join-Path $candidateRoot ('servers\steamapps\workshop\content\' + [string]$AppId))
                    $roots += (Join-Path $candidateRoot ('SteamCMD\steamapps\workshop\content\' + [string]$AppId))
                }
            }
        }
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

function Invoke-UGSMWorkshopSteamCMDDownload {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$AppId,
        [Parameter(Mandatory)][string]$WorkshopId,
        [int]$TimeoutSeconds = 7200,
        [string]$LoginMode = 'Anonymous',
        [AllowNull()][object]$Instance = $null
    )

    # Exact DayZ-style workflow: resolve steamcmd.exe, build args, Start-Process
    # with -PassThru -Wait, then check ExitCode. This intentionally avoids the
    # UGSM process service and keeps the SteamCMD console visible to the user.
    $steamCmdPath = Get-UGSMGameHelperSteamCmdExecutablePath -Instance $Instance
    $steamCmdRoot = Split-Path -Parent $steamCmdPath

    $argumentParts = @()
    $argumentParts += @(Get-UGSMGameHelperSteamLoginArguments -LoginMode $LoginMode)
    $argumentParts += @('+workshop_download_item', [string]$AppId, [string]$WorkshopId)
    $argumentParts += '+quit'

    $argumentString = ($argumentParts | ForEach-Object {
            $part = [string]$_
            if ($part -match '\s') { '"{0}"' -f $part.Replace('"', '"') } else { $part }
        }) -join ' '

    Write-UGSMGameHelperLog -Category 'Mods' -Message ('Starting Workshop download with DayZ SteamCMD workflow. SteamCMD=' + $steamCmdPath + '; AppId=' + $AppId + '; WorkshopId=' + $WorkshopId + '.') -Level 'Info'
    Write-UGSMGameHelperLog -Category 'Mods' -Message ('SteamCMD should be visible while this runs. UGSM may appear not responding until SteamCMD exits.') -Level 'Info'

    $process = Start-Process -FilePath $steamCmdPath -WorkingDirectory $steamCmdRoot -ArgumentList $argumentString -PassThru -Wait
    if ($null -eq $process) { throw 'Workshop mod download failed: SteamCMD process did not start.' }
    if ([int]$process.ExitCode -ne 0) { throw ('Workshop mod download failed: SteamCMD exited with code {0}.' -f [int]$process.ExitCode) }

    $missingItems = @()
    $itemPath = ''
    $contentRoots = @(Get-UGSMGameHelperWorkshopContentRoots -Instance $Instance -AppId $AppId -SteamCmdPath $steamCmdPath)
    foreach ($root in $contentRoots) {
        $candidate = Join-Path $root ([string]$WorkshopId)
        if (Test-Path -LiteralPath $candidate -PathType Container) {
            $itemPath = $candidate
            break
        }
    }
    if ([string]::IsNullOrWhiteSpace([string]$itemPath)) { $missingItems += [string]$WorkshopId }

    Write-UGSMGameHelperLog -Category 'Mods' -Message ('Workshop download completed with DayZ SteamCMD workflow. AppId=' + $AppId + '; WorkshopId=' + $WorkshopId + '; ExitCode=' + [string][int]$process.ExitCode + '; ContentPath=' + [string]$itemPath + '.') -Level 'Info'

    return [pscustomobject]@{
        Success      = $true
        AppId        = [string]$AppId
        WorkshopId   = [string]$WorkshopId
        SteamCmdPath = $steamCmdPath
        SteamCmdRoot = $steamCmdRoot
        ItemPath     = $itemPath
        MissingItems = @($missingItems)
        ExitCode     = [int]$process.ExitCode
        Message      = 'SteamCMD Workshop download completed.'
    }
}


function Invoke-UGSMGameHelperHook {
    [CmdletBinding()]
    param(
        [AllowNull()][object]$ModsDefinition,
        [Parameter(Mandatory)][string]$HookName,
        [Parameter(Mandatory)][object]$Instance,
        [Parameter(Mandatory)][object]$Manifest,
        [string]$WorkshopId = '',
        [string]$SharedContentPath = '',
        [string]$ArchivePath = '',
        [string]$ModName = ''
    )

    if (-not $ModsDefinition -or -not $ModsDefinition.PSObject.Properties['Hooks'] -or -not $ModsDefinition.Hooks) { return $null }
    if (-not $ModsDefinition.Hooks.PSObject.Properties[$HookName]) { return $null }

    $commandName = [string]$ModsDefinition.Hooks.$HookName
    if ([string]::IsNullOrWhiteSpace($commandName)) { return $null }

    $command = Get-Command -Name $commandName -ErrorAction SilentlyContinue
    if (-not $command) { return $null }

    # Different games can expose different hook signatures. Do not pass helper-only
    # parameters unless the hook explicitly accepts them; otherwise strict-mode
    # turns a valid Add/Download action into a UI-visible parameter error.
    $args = @{}
    $params = $command.Parameters

    if ($params.ContainsKey('Instance'))          { $args['Instance'] = $Instance }
    if ($params.ContainsKey('Manifest'))          { $args['Manifest'] = $Manifest }
    if ($params.ContainsKey('ModsDefinition'))    { $args['ModsDefinition'] = $ModsDefinition }
    if ($params.ContainsKey('WorkshopId'))        { $args['WorkshopId'] = $WorkshopId }
    if ($params.ContainsKey('WorkshopID'))        { $args['WorkshopID'] = $WorkshopId }
    if ($params.ContainsKey('SharedContentPath')) { $args['SharedContentPath'] = $SharedContentPath }
    if ($params.ContainsKey('ArchivePath'))       { $args['ArchivePath'] = $ArchivePath }
    if ($params.ContainsKey('ModName'))           { $args['ModName'] = $ModName }

    return (& $commandName @args)
}



function Get-UGSMProjectZomboidWorkshopMetadata {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$WorkshopItemPath
    )

    $modIds = [System.Collections.Generic.List[string]]::new()
    $mapFolders = [System.Collections.Generic.List[string]]::new()
    $names = [System.Collections.Generic.List[string]]::new()

    if ([string]::IsNullOrWhiteSpace($WorkshopItemPath) -or -not (Test-Path -LiteralPath $WorkshopItemPath -PathType Container)) {
        return [pscustomobject]@{ ModIds = @(); MapFolders = @(); Name = '' }
    }

    try {
        $modInfoFiles = @(Get-ChildItem -LiteralPath $WorkshopItemPath -Filter 'mod.info' -Recurse -File -ErrorAction SilentlyContinue)
        foreach ($info in $modInfoFiles) {
            $modFolder = Split-Path -Parent $info.FullName
            try {
                foreach ($line in @(Get-Content -LiteralPath $info.FullName -ErrorAction Stop)) {
                    $text = [string]$line
                    if ($text -match '^\s*id\s*=\s*(.+?)\s*$') {
                        $id = [string]$matches[1]
                        if (-not [string]::IsNullOrWhiteSpace($id) -and -not $modIds.Contains($id)) { [void]$modIds.Add($id) }
                    }
                    elseif ($text -match '^\s*name\s*=\s*(.+?)\s*$') {
                        $name = [string]$matches[1]
                        if (-not [string]::IsNullOrWhiteSpace($name) -and -not $names.Contains($name)) { [void]$names.Add($name) }
                    }
                }
            }
            catch {
                Write-UGSMGameHelperLog -Category 'Mods' -Level 'WARN' -Message ('Failed to read Project Zomboid mod.info. File=' + [string]$info.FullName) -Exception $_.Exception
            }

            $mapsRoot = Join-Path $modFolder 'media\maps'
            if (Test-Path -LiteralPath $mapsRoot -PathType Container) {
                foreach ($mapDir in @(Get-ChildItem -LiteralPath $mapsRoot -Directory -ErrorAction SilentlyContinue)) {
                    $mapName = [string]$mapDir.Name
                    if (-not [string]::IsNullOrWhiteSpace($mapName) -and -not $mapFolders.Contains($mapName)) { [void]$mapFolders.Add($mapName) }
                }
            }
        }
    }
    catch {
        Write-UGSMGameHelperLog -Category 'Mods' -Level 'WARN' -Message ('Failed to inspect Project Zomboid Workshop item metadata. Path=' + [string]$WorkshopItemPath) -Exception $_.Exception
    }

    $displayName = ''
    if ($names.Count -gt 0) { $displayName = [string]$names[0] }

    return [pscustomobject]@{
        ModIds = @($modIds.ToArray())
        MapFolders = @($mapFolders.ToArray())
        Name = $displayName
    }
}


function Get-UGSMProjectZomboidInstanceSafeNameForHelper {
    [CmdletBinding()]
    param([Parameter(Mandatory)][object]$Instance)

    $name = ''
    foreach ($prop in @('Name','Id','InstanceName','ProfileName')) {
        if ($Instance.PSObject.Properties[$prop] -and -not [string]::IsNullOrWhiteSpace([string]$Instance.$prop)) { $name = [string]$Instance.$prop; break }
    }
    if ([string]::IsNullOrWhiteSpace($name)) { $name = 'server' }
    $safe = [regex]::Replace($name, '[^A-Za-z0-9_\- ]', '')
    if ([string]::IsNullOrWhiteSpace($safe)) { $safe = 'server' }
    return $safe.Trim()
}

function Resolve-UGSMProjectZomboidServerIniPathForHelper {
    [CmdletBinding()]
    param([Parameter(Mandatory)][object]$Instance)

    try {
        if (Get-Command -Name Get-UGSMGameProjectZomboidProfilePaths -ErrorAction SilentlyContinue) {
            $paths = Get-UGSMGameProjectZomboidProfilePaths -Instance $Instance
            if ($paths -and $paths.PSObject.Properties['ServerSettingsPath'] -and -not [string]::IsNullOrWhiteSpace([string]$paths.ServerSettingsPath)) { return [string]$paths.ServerSettingsPath }
        }
    }
    catch {}

    $profileRoot = ''
    foreach ($prop in @('ProfilePath','RuntimeRoot','ProfileRoot','RootPath','Path')) {
        if ($Instance.PSObject.Properties[$prop] -and -not [string]::IsNullOrWhiteSpace([string]$Instance.$prop)) { $profileRoot = [string]$Instance.$prop; break }
    }
    if ([string]::IsNullOrWhiteSpace($profileRoot)) { return '' }

    $serverName = Get-UGSMProjectZomboidInstanceSafeNameForHelper -Instance $Instance
    return (Join-Path (Join-Path $profileRoot 'Server') ($serverName + '.ini'))
}

function Write-UGSMGameHelperTextFileNoBom {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Path,
        [AllowNull()][object]$Value
    )

    $folder = Split-Path -Parent $Path
    if (-not [string]::IsNullOrWhiteSpace($folder) -and -not (Test-Path -LiteralPath $folder -PathType Container)) {
        New-Item -ItemType Directory -Path $folder -Force | Out-Null
    }

    $lines = @()
    if ($null -ne $Value) {
        if ($Value -is [string]) {
            $text = [string]$Value
            if ($text.Contains("`r") -or $text.Contains("`n")) {
                $lines = @($text -split "`r?`n", -1)
                if ($lines.Count -gt 0 -and $lines[$lines.Count - 1] -eq '') {
                    if ($lines.Count -eq 1) { $lines = @() } else { $lines = @($lines[0..($lines.Count - 2)]) }
                }
            }
            else {
                $lines = @($text)
            }
        }
        elseif ($Value -is [System.Collections.IEnumerable]) {
            $lines = @($Value | ForEach-Object { [string]$_ })
        }
        else {
            $lines = @([string]$Value)
        }
    }

    if ($lines.Count -gt 0 -and $null -ne $lines[0]) {
        $lines[0] = ([string]$lines[0]).TrimStart([char]0xFEFF)
    }

    $content = [string]::Join("`r`n", $lines)
    if ($lines.Count -gt 0) { $content += "`r`n" }

    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($Path, $content, $utf8NoBom)
}

function Set-UGSMProjectZomboidIniValueForHelper {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Key,
        [AllowNull()][object]$Value
    )

    $folder = Split-Path -Parent $Path
    if (-not [string]::IsNullOrWhiteSpace($folder) -and -not (Test-Path -LiteralPath $folder -PathType Container)) { New-Item -ItemType Directory -Path $folder -Force | Out-Null }

    $lines = @()
    if (Test-Path -LiteralPath $Path -PathType Leaf) { $lines = @(Get-Content -LiteralPath $Path -ErrorAction SilentlyContinue) }
    $valueText = if ($null -eq $Value) { '' } else { [string]$Value }
    $pattern = '^\s*' + [regex]::Escape($Key) + '\s*='
    $newLine = $Key + '=' + $valueText
    $done = $false
    $out = New-Object System.Collections.Generic.List[string]
    foreach ($line in $lines) {
        if (-not $done -and ([string]$line) -match $pattern) {
            [void]$out.Add($newLine)
            $done = $true
        }
        else {
            [void]$out.Add([string]$line)
        }
    }
    if (-not $done) { [void]$out.Add($newLine) }
    Write-UGSMGameHelperTextFileNoBom -Path $Path -Value @($out.ToArray())
}

function Sync-UGSMProjectZomboidModsManifestToIniForHelper {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$Instance,
        [Parameter(Mandatory)][object]$Manifest,
        [AllowNull()][object]$ModsDefinition
    )

    $gameId = ''
    if ($Instance.PSObject.Properties['GameId']) { $gameId = [string]$Instance.GameId }
    if ([string]::IsNullOrWhiteSpace($gameId) -and $ModsDefinition -and $ModsDefinition.PSObject.Properties['GameId']) { $gameId = [string]$ModsDefinition.GameId }
    if ($gameId -notin @('ProjectZomboid','PZTest')) { return $null }

    $iniPath = Resolve-UGSMProjectZomboidServerIniPathForHelper -Instance $Instance
    if ([string]::IsNullOrWhiteSpace($iniPath)) { return $null }

    $workshopIds = [System.Collections.Generic.List[string]]::new()
    $modIds = [System.Collections.Generic.List[string]]::new()
    $mapFolders = [System.Collections.Generic.List[string]]::new()

    foreach ($mod in @($Manifest.Mods)) {
        if (-not $mod) { continue }
        $enabled = $true
        if ($mod.PSObject.Properties['Enabled']) { $enabled = [bool]$mod.Enabled }
        if (-not $enabled) { continue }

        foreach ($prop in @('WorkshopId','Id')) {
            if ($mod.PSObject.Properties[$prop]) {
                $wid = [string]$mod.$prop
                if ($wid -match '^\d+$' -and -not $workshopIds.Contains($wid)) { [void]$workshopIds.Add($wid) }
                break
            }
        }

        if ($mod.PSObject.Properties['ModIds']) {
            foreach ($midObj in @($mod.ModIds)) {
                $mid = [string]$midObj
                if (-not [string]::IsNullOrWhiteSpace($mid) -and $mid -notmatch '^Workshop\s+\d+$' -and -not $modIds.Contains($mid)) { [void]$modIds.Add($mid) }
            }
        }
        foreach ($prop in @('ModId','ModID','PZModId')) {
            if ($mod.PSObject.Properties[$prop]) {
                $mid = [string]$mod.$prop
                if (-not [string]::IsNullOrWhiteSpace($mid) -and $mid -notmatch '^Workshop\s+\d+$' -and -not $modIds.Contains($mid)) { [void]$modIds.Add($mid) }
            }
        }

        foreach ($prop in @('MapFolders','MapFolder','Map')) {
            if ($mod.PSObject.Properties[$prop]) {
                foreach ($mapObj in @($mod.$prop)) {
                    $map = [string]$mapObj
                    if (-not [string]::IsNullOrWhiteSpace($map) -and -not $mapFolders.Contains($map)) { [void]$mapFolders.Add($map) }
                }
            }
        }
    }

    if ($mapFolders.Count -gt 0 -and -not $mapFolders.Contains('Muldraugh, KY')) { [void]$mapFolders.Add('Muldraugh, KY') }

    Set-UGSMProjectZomboidIniValueForHelper -Path $iniPath -Key 'WorkshopItems' -Value (($workshopIds.ToArray()) -join ';')
    Set-UGSMProjectZomboidIniValueForHelper -Path $iniPath -Key 'Mods' -Value (($modIds.ToArray()) -join ';')
    if ($mapFolders.Count -gt 0) { Set-UGSMProjectZomboidIniValueForHelper -Path $iniPath -Key 'Map' -Value (($mapFolders.ToArray()) -join ';') }

    Write-UGSMGameHelperLog -Category 'Mods' -Level 'INFO' -Message ('Synced Project Zomboid Workshop metadata to server INI. WorkshopItems=' + (($workshopIds.ToArray()) -join ';') + '; Mods=' + (($modIds.ToArray()) -join ';') + '; Path=' + $iniPath)
    return [pscustomobject]@{ Success = $true; Path = $iniPath; WorkshopItems = (($workshopIds.ToArray()) -join ';'); Mods = (($modIds.ToArray()) -join ';') }
}

function Update-UGSMProjectZomboidModEntryFromWorkshopContent {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$Mod,
        [Parameter(Mandatory)][string]$WorkshopItemPath
    )

    if (-not $Mod) { return $false }
    if ([string]::IsNullOrWhiteSpace($WorkshopItemPath) -or -not (Test-Path -LiteralPath $WorkshopItemPath -PathType Container)) { return $false }

    $metadata = Get-UGSMProjectZomboidWorkshopMetadata -WorkshopItemPath $WorkshopItemPath
    $changed = $false

    $existingIds = @()
    if ($Mod.PSObject.Properties['ModIds']) { $existingIds = @($Mod.ModIds | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) }) }
    elseif ($Mod.PSObject.Properties['ModId'] -and -not [string]::IsNullOrWhiteSpace([string]$Mod.ModId)) { $existingIds = @([string]$Mod.ModId) }

    $mergedIds = [System.Collections.Generic.List[string]]::new()
    foreach ($id in @($existingIds + @($metadata.ModIds))) {
        $text = [string]$id
        if (-not [string]::IsNullOrWhiteSpace($text) -and -not $mergedIds.Contains($text)) { [void]$mergedIds.Add($text) }
    }
    if ($mergedIds.Count -gt 0) {
        if (-not $Mod.PSObject.Properties['ModIds']) { Add-Member -InputObject $Mod -MemberType NoteProperty -Name ModIds -Value @() -Force }
        $Mod.ModIds = @($mergedIds.ToArray())
        if (-not $Mod.PSObject.Properties['ModId']) { Add-Member -InputObject $Mod -MemberType NoteProperty -Name ModId -Value '' -Force }
        if ([string]::IsNullOrWhiteSpace([string]$Mod.ModId)) { $Mod.ModId = [string]$mergedIds[0] }
        $changed = $true
    }

    $existingMaps = @()
    if ($Mod.PSObject.Properties['MapFolders']) { $existingMaps = @($Mod.MapFolders | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) }) }
    $mergedMaps = [System.Collections.Generic.List[string]]::new()
    foreach ($map in @($existingMaps + @($metadata.MapFolders))) {
        $text = [string]$map
        if (-not [string]::IsNullOrWhiteSpace($text) -and -not $mergedMaps.Contains($text)) { [void]$mergedMaps.Add($text) }
    }
    if ($mergedMaps.Count -gt 0) {
        if (-not $Mod.PSObject.Properties['MapFolders']) { Add-Member -InputObject $Mod -MemberType NoteProperty -Name MapFolders -Value @() -Force }
        $Mod.MapFolders = @($mergedMaps.ToArray())
        $changed = $true
    }

    if ($Mod.PSObject.Properties['Name'] -and ([string]$Mod.Name -match '^Workshop\s+\d+$') -and -not [string]::IsNullOrWhiteSpace([string]$metadata.Name)) {
        $Mod.Name = [string]$metadata.Name
        $changed = $true
    }

    return $changed
}

function Update-UGSMModsSummaryFile {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$Instance,
        [Parameter(Mandatory)][object]$Manifest,
        [AllowNull()][object]$ModsDefinition
    )

    $summaryPath = Get-UGSMModsSummaryPath -Instance $Instance -ModsDefinition $ModsDefinition
    if ([string]::IsNullOrWhiteSpace($summaryPath)) { return '' }

    $folder = Split-Path -Parent $summaryPath
    if (-not (Test-Path -LiteralPath $folder -PathType Container)) { New-Item -ItemType Directory -Path $folder -Force | Out-Null }

    Set-Content -LiteralPath $summaryPath -Value @(Get-UGSMModsSummaryLines -Manifest $Manifest) -Encoding UTF8
    return $summaryPath
}

function Invoke-UGSMDownloadActiveSteamWorkshopMods {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$Instance,
        [AllowNull()][object]$ModsDefinition
    )

    $manifest = Normalize-UGSMModsManifest -Manifest (Read-UGSMModsManifest -Instance $Instance -ModsDefinition $ModsDefinition) -Instance $Instance -ModsDefinition $ModsDefinition
    $appId = Get-UGSMModsSteamAppId -ModsDefinition $ModsDefinition
    if ([string]::IsNullOrWhiteSpace($appId)) { throw 'No Steam App ID is configured for Workshop downloads. Set Mods.Workshop.AppId in the game module before enabling Workshop downloads.' }

    $enabledMods = @($manifest.Mods | Where-Object { $_ -and $_.PSObject.Properties['SourceType'] -and [string]$_.SourceType -eq 'SteamWorkshop' -and (-not $_.PSObject.Properties['Enabled'] -or [bool]$_.Enabled) })
    if ($enabledMods.Count -eq 0) {
        $summaryPath = Update-UGSMModsSummaryFile -Instance $Instance -Manifest $manifest -ModsDefinition $ModsDefinition
        return [pscustomobject]@{ Success = $true; Count = 0; Manifest = $manifest; SummaryPath = $summaryPath; Message = 'No enabled Workshop mods are in this profile manifest.' }
    }

    $successCount = 0
    foreach ($mod in $enabledMods) {
        $workshopId = [string]$mod.WorkshopId
        if ([string]::IsNullOrWhiteSpace($workshopId)) { continue }

        $result = Invoke-UGSMWorkshopSteamCMDDownload -AppId $appId -WorkshopId $workshopId -TimeoutSeconds 7200 -LoginMode 'Anonymous' -Instance $Instance
        $sharedPath = Get-UGSMWorkshopSharedContentPath -AppId $appId -WorkshopId $workshopId -Instance $Instance
        if ($result -and $result.PSObject.Properties['ItemPath'] -and -not [string]::IsNullOrWhiteSpace([string]$result.ItemPath)) { $sharedPath = [string]$result.ItemPath }

        if ($mod.PSObject.Properties['SharedContentPath']) { $mod.SharedContentPath = $sharedPath } else { Add-Member -InputObject $mod -MemberType NoteProperty -Name SharedContentPath -Value $sharedPath -Force }
        if ($mod.PSObject.Properties['DownloadedAtUtc']) { $mod.DownloadedAtUtc = [DateTime]::UtcNow.ToString('o') } else { Add-Member -InputObject $mod -MemberType NoteProperty -Name DownloadedAtUtc -Value ([DateTime]::UtcNow.ToString('o')) -Force }

        if ([string]$appId -eq '108600' -and -not [string]::IsNullOrWhiteSpace([string]$sharedPath) -and (Test-Path -LiteralPath $sharedPath -PathType Container)) {
            $metadataChanged = Update-UGSMProjectZomboidModEntryFromWorkshopContent -Mod $mod -WorkshopItemPath $sharedPath
            if ($metadataChanged) {
                Write-UGSMGameHelperLog -Category 'Mods' -Level 'INFO' -Message ('Detected Project Zomboid mod metadata from Workshop content. WorkshopId=' + $workshopId + '; ModIds=' + ((@($mod.ModIds) | ForEach-Object { [string]$_ }) -join ';') + '; Maps=' + ((@($mod.MapFolders) | ForEach-Object { [string]$_ }) -join ';') + '.')
            }
        }

        Invoke-UGSMGameHelperHook -ModsDefinition $ModsDefinition -HookName 'AfterWorkshopDownload' -Instance $Instance -Manifest $manifest -WorkshopId $workshopId -SharedContentPath $sharedPath | Out-Null
        Invoke-UGSMGameHelperHook -ModsDefinition $ModsDefinition -HookName 'AfterModsChanged' -Instance $Instance -Manifest $manifest -WorkshopId $workshopId -SharedContentPath $sharedPath | Out-Null
        $successCount++
    }

    $manifest.UpdatedAtUtc = [DateTime]::UtcNow.ToString('o')
    Save-UGSMModsManifest -Instance $Instance -Manifest $manifest -ModsDefinition $ModsDefinition
    try { Sync-UGSMProjectZomboidModsManifestToIniForHelper -Instance $Instance -Manifest $manifest -ModsDefinition $ModsDefinition | Out-Null } catch { Write-UGSMGameHelperLog -Category 'Mods' -Level 'WARN' -Message 'Failed to directly sync Project Zomboid mods to server INI after Workshop download.' -Exception $_.Exception }
    $summaryPath = Update-UGSMModsSummaryFile -Instance $Instance -Manifest $manifest -ModsDefinition $ModsDefinition

    return [pscustomobject]@{
        Success = $true
        Count = $successCount
        AppId = $appId
        Manifest = $manifest
        SummaryPath = $summaryPath
        Message = 'Downloaded/updated Workshop mods. Count=' + $successCount + '; AppId=' + $appId + '.'
    }
}

function New-UGSMModsTabSchema {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$ModsDefinition,
        [string]$GameId = ''
    )

    if (-not (Test-UGSMGameModsSupported -ModsDefinition $ModsDefinition)) { return $null }

    $cap = $ModsDefinition.Capabilities
    $fields = New-Object System.Collections.Generic.List[hashtable]

    [void]$fields.Add(@{
        Id = 'UGSMModsActiveListView'
        Type = 'ActiveModsList'
        Label = 'Active Mods On Server'
        ButtonText = ''
        Hint = 'Shows enabled mods/load order stored on this instance. Full Workshop files remain in the shared Steam Workshop cache.'
        ModsDefinition = $ModsDefinition
    })

    $notice = Get-UGSMModSafetyNoticeText -ModsDefinition $ModsDefinition
    if (-not [string]::IsNullOrWhiteSpace($notice)) {
        [void]$fields.Add(@{
            Id = 'UGSMModsSafetyNotice'
            Type = 'ActionButton'
            Label = 'Mod Safety Notice'
            ButtonText = 'Show Notice'
            Hint = $notice
            Action = {
                param($Instance, $Paths, $StatusLabel)
                if ($StatusLabel) { $StatusLabel.Text = 'Review the mod safety notice before installing third-party mods.' }
            }
        })
    }

    if ($cap -and $cap.PSObject.Properties['SteamWorkshop'] -and [bool]$cap.SteamWorkshop) {
        $modsDefForActions = $ModsDefinition
        # Compatibility alias: an older helper build had this variable misspelled in
        # the Workshop action closures. Keep it set so stale generated handlers do
        # not crash under Set-StrictMode before the editor is refreshed.
        $modsDeforActions = $modsDefForActions

        [void]$fields.Add(@{
            Id = 'UGSMModsWorkshopAdd'
            Type = 'ActionButton'
            Label = 'Steam Workshop'
            ButtonText = 'Add Workshop ID / URL'
            Hint = 'Adds a Steam Workshop ID or full Steam Workshop URL to this instance mod list. The full mod stays in the shared Steam Workshop cache; the profile stores only the active mod reference and load order.'
            Action = {
                param($Instance, $Paths, $StatusLabel)
                try {
                    $input = Read-UGSMGameHelperInputBox -Title 'Add Steam Workshop Mod' -Prompt 'Paste a Steam Workshop ID or full Steam Workshop URL:'
                    if ([string]::IsNullOrWhiteSpace($input)) { if ($StatusLabel) { $StatusLabel.Text = 'Add Workshop mod cancelled.' }; return }
                    $modId = ''
                    $mapFolders = @()
                    if ($modsDefForActions -and $modsDefForActions.PSObject.Properties['Workshop'] -and $modsDefForActions.Workshop) {
                        if ($modsDefForActions.Workshop.PSObject.Properties['PromptForModId'] -and [bool]$modsDefForActions.Workshop.PromptForModId) {
                            $modId = Read-UGSMGameHelperInputBox -Title 'Project Zomboid Mod ID' -Prompt 'Optional: enter the Project Zomboid mod ID from mod.info. Leave blank if unknown.'
                        }
                        if ($modsDefForActions.Workshop.PSObject.Properties['PromptForMapFolders'] -and [bool]$modsDefForActions.Workshop.PromptForMapFolders) {
                            $mapInput = Read-UGSMGameHelperInputBox -Title 'Project Zomboid Map Folders' -Prompt 'Optional: enter semicolon-separated map folders. Leave blank for no map folders.'
                            if (-not [string]::IsNullOrWhiteSpace($mapInput)) { $mapFolders = @(([string]$mapInput -split ';') | ForEach-Object { $_.Trim() } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }) }
                        }
                    }
                    $result = Add-UGSMSteamWorkshopModToManifest -Instance $Instance -WorkshopInput $input -ModsDefinition $modsDefForActions -ModId $modId -MapFolders $mapFolders
                    Invoke-UGSMGameHelperHook -ModsDefinition $modsDefForActions -HookName 'AfterWorkshopDownload' -Instance $Instance -Manifest $result.Manifest -WorkshopId $result.WorkshopId | Out-Null
                    Update-UGSMModsActiveListControls -Instance $Instance -ModsDefinition $modsDefForActions -StatusLabel $StatusLabel | Out-Null
                    if ($StatusLabel) { $StatusLabel.Text = $result.Message + ' Active mods list refreshed.' }
                }
                catch { if ($StatusLabel) { $StatusLabel.Text = 'Add Workshop mod failed: ' + $_.Exception.Message } }
            }
        })

        [void]$fields.Add(@{
            Id = 'UGSMModsWorkshopDownload'
            Type = 'ActionButton'
            Label = 'Download / Update'
            ButtonText = 'Download Active Workshop Mods'
            Hint = 'Downloads or updates enabled Steam Workshop mods through SteamCMD into the shared Steam Workshop cache. It does not copy full mods into this profile.'
            Action = {
                param($Instance, $Paths, $StatusLabel)
                try {
                    $result = Invoke-UGSMDownloadActiveSteamWorkshopMods -Instance $Instance -ModsDefinition $modsDefForActions
                    Update-UGSMModsActiveListControls -Instance $Instance -ModsDefinition $modsDefForActions -StatusLabel $StatusLabel | Out-Null
                    if ($StatusLabel) { $StatusLabel.Text = $result.Message + ' Active mods list refreshed.' }
                }
                catch {
                    Write-UGSMGameHelperLog -Category 'Mods' -Message ('Workshop download failed from schema Mods action: ' + $_.Exception.Message) -Level 'Error'
                    if ($StatusLabel) { $StatusLabel.Text = 'Workshop download failed: ' + $_.Exception.Message }
                }
            }
        })

        [void]$fields.Add(@{
            Id = 'UGSMModsWorkshopRemove'
            Type = 'ActionButton'
            Label = 'Remove Active Mod'
            ButtonText = 'Remove Workshop ID'
            Hint = 'Removes the Workshop ID from this profile''s active mod manifest. Shared downloaded Workshop files are left in the Steam cache so other profiles can still use them.'
            Action = {
                param($Instance, $Paths, $StatusLabel)
                try {
                    $input = Read-UGSMGameHelperInputBox -Title 'Remove Steam Workshop Mod' -Prompt 'Enter the Workshop ID or URL to remove from this profile:'
                    if ([string]::IsNullOrWhiteSpace($input)) { if ($StatusLabel) { $StatusLabel.Text = 'Remove Workshop mod cancelled.' }; return }
                    $result = Remove-UGSMSteamWorkshopModFromManifest -Instance $Instance -WorkshopInput $input -ModsDefinition $modsDefForActions
                    Invoke-UGSMGameHelperHook -ModsDefinition $modsDefForActions -HookName 'AfterWorkshopDownload' -Instance $Instance -Manifest $result.Manifest -WorkshopId $result.WorkshopId | Out-Null
                    Update-UGSMModsActiveListControls -Instance $Instance -ModsDefinition $modsDefForActions -StatusLabel $StatusLabel | Out-Null
                    if ($StatusLabel) { $StatusLabel.Text = $result.Message + ' Active mods list refreshed.' }
                }
                catch { if ($StatusLabel) { $StatusLabel.Text = 'Remove Workshop mod failed: ' + $_.Exception.Message } }
            }
        })
    }

    if ($cap -and $cap.PSObject.Properties['ArchiveImport'] -and [bool]$cap.ArchiveImport) {
        $modsDefForArchiveActions = $ModsDefinition
        [void]$fields.Add(@{
            Id = 'UGSMModsArchiveImport'
            Type = 'ActionButton'
            Label = 'Archive Import'
            ButtonText = 'Import ZIP/RAR'
            Hint = 'Installs a user-selected ZIP/RAR mod archive using the game module archive import hook. Only use trusted mod sources. UGSM cannot verify third-party mod safety or compatibility.'
            Action = {
                param($Instance, $Paths, $StatusLabel)
                try {
                    $installHook = ''
                    if ($modsDefForArchiveActions -and $modsDefForArchiveActions.PSObject.Properties['Hooks'] -and $modsDefForArchiveActions.Hooks -and $modsDefForArchiveActions.Hooks.PSObject.Properties['Install']) { $installHook = [string]$modsDefForArchiveActions.Hooks.Install }
                    if ([string]::IsNullOrWhiteSpace($installHook)) { throw 'Archive import is enabled, but this game module did not provide a Mods.Hooks.Install function.' }

                    $allowed = @('.zip','.rar')
                    if ($modsDefForArchiveActions -and $modsDefForArchiveActions.PSObject.Properties['Archive'] -and $modsDefForArchiveActions.Archive -and $modsDefForArchiveActions.Archive.PSObject.Properties['AllowedExtensions']) {
                        $allowed = @($modsDefForArchiveActions.Archive.AllowedExtensions | ForEach-Object { [string]$_ } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
                    }
                    if ($allowed.Count -eq 0) { $allowed = @('.zip','.rar') }

                    Add-Type -AssemblyName System.Windows.Forms -ErrorAction SilentlyContinue | Out-Null
                    $dialog = New-Object System.Windows.Forms.OpenFileDialog
                    $dialog.Title = 'Select mod archive'
                    $dialog.Filter = 'Mod Archives (*.zip;*.rar)|*.zip;*.rar|All Files (*.*)|*.*'
                    $dialog.Multiselect = $false
                    if ($dialog.ShowDialog() -ne [System.Windows.Forms.DialogResult]::OK) { if ($StatusLabel) { $StatusLabel.Text = 'Archive mod import cancelled.' }; return }

                    $ext = [System.IO.Path]::GetExtension($dialog.FileName).ToLowerInvariant()
                    if ($allowed -notcontains $ext) { throw ('Unsupported archive extension: ' + $ext) }

                    $requiresConfirm = $true
                    if ($modsDefForArchiveActions.PSObject.Properties['Archive'] -and $modsDefForArchiveActions.Archive -and $modsDefForArchiveActions.Archive.PSObject.Properties['RequireSafetyNotice']) { $requiresConfirm = [bool]$modsDefForArchiveActions.Archive.RequireSafetyNotice }
                    if ($requiresConfirm) {
                        $notice = Get-UGSMModSafetyNoticeText -ModsDefinition $modsDefForArchiveActions
                        if ([string]::IsNullOrWhiteSpace($notice)) { $notice = 'UGSM can install ZIP/RAR files you provide, but cannot verify third-party mod safety or compatibility. Continue only if this file came from a trusted source.' }
                        $choice = [System.Windows.Forms.MessageBox]::Show($notice + "`r`n`r`nInstall this archive now?", 'UGSM Mod Safety Notice', [System.Windows.Forms.MessageBoxButtons]::YesNo, [System.Windows.Forms.MessageBoxIcon]::Warning)
                        if ($choice -ne [System.Windows.Forms.DialogResult]::Yes) { if ($StatusLabel) { $StatusLabel.Text = 'Archive mod import cancelled.' }; return }
                    }

                    if ($StatusLabel) { $StatusLabel.Text = 'Importing archive mod...' }
                    $manifest = Normalize-UGSMModsManifest -Manifest (Read-UGSMModsManifest -Instance $Instance -ModsDefinition $modsDefForArchiveActions) -Instance $Instance -ModsDefinition $modsDefForArchiveActions
                    $result = Invoke-UGSMGameHelperHook -ModsDefinition $modsDefForArchiveActions -HookName 'Install' -Instance $Instance -Manifest $manifest -ArchivePath $dialog.FileName
                    if ($result -and $result.PSObject.Properties['Manifest'] -and $result.Manifest) { $manifest = $result.Manifest }
                    else { $manifest = Normalize-UGSMModsManifest -Manifest (Read-UGSMModsManifest -Instance $Instance -ModsDefinition $modsDefForArchiveActions) -Instance $Instance -ModsDefinition $modsDefForArchiveActions }
                    $summaryPath = Update-UGSMModsSummaryFile -Instance $Instance -Manifest $manifest -ModsDefinition $modsDefForArchiveActions
                    Update-UGSMModsActiveListControls -Instance $Instance -ModsDefinition $modsDefForArchiveActions -StatusLabel $StatusLabel | Out-Null
                    $count = if ($result -and $result.PSObject.Properties['Imported']) { @($result.Imported).Count } else { 0 }
                    if ($StatusLabel) { $StatusLabel.Text = ('Archive mod import complete. Imported=' + $count + '; File=' + (ConvertTo-UGSMGameHelperSafeLogText -Value $summaryPath)) }
                }
                catch {
                    Write-UGSMGameHelperLog -Category 'Mods' -Level 'ERROR' -Message ('Archive mod import failed from shared Mods tab. Detail=' + $_.Exception.Message + '; Stack=' + ([string]$_.ScriptStackTrace)) -Exception $_.Exception
                    if ($StatusLabel) { $StatusLabel.Text = 'Archive mod import failed: ' + $_.Exception.Message }
                }
            }
        })

        [void]$fields.Add(@{
            Id = 'UGSMModsArchiveRemove'
            Type = 'ActionButton'
            Label = 'Archive Import'
            ButtonText = 'Remove Archive Mod'
            Hint = 'Removes a UGSM-managed archive mod using the game module remove hook. For games with shared mod folders this may affect all instances using the same binaries.'
            Action = {
                param($Instance, $Paths, $StatusLabel)
                try {
                    $removeHook = ''
                    if ($modsDefForArchiveActions -and $modsDefForArchiveActions.PSObject.Properties['Hooks'] -and $modsDefForArchiveActions.Hooks -and $modsDefForArchiveActions.Hooks.PSObject.Properties['Remove']) { $removeHook = [string]$modsDefForArchiveActions.Hooks.Remove }
                    if ([string]::IsNullOrWhiteSpace($removeHook)) { throw 'Archive removal is enabled, but this game module did not provide a Mods.Hooks.Remove function.' }

                    $input = Read-UGSMGameHelperInputBox -Title 'Remove Archive Mod' -Prompt 'Enter the mod folder/name to remove:'
                    if ([string]::IsNullOrWhiteSpace($input)) { if ($StatusLabel) { $StatusLabel.Text = 'Remove archive mod cancelled.' }; return }

                    Add-Type -AssemblyName System.Windows.Forms -ErrorAction SilentlyContinue | Out-Null
                    $choice = [System.Windows.Forms.MessageBox]::Show('Remove this UGSM-managed archive mod? For shared mod folders this may affect every instance using the same game install.' + "`r`n`r`n" + $input, 'Remove Archive Mod', [System.Windows.Forms.MessageBoxButtons]::YesNo, [System.Windows.Forms.MessageBoxIcon]::Warning)
                    if ($choice -ne [System.Windows.Forms.DialogResult]::Yes) { if ($StatusLabel) { $StatusLabel.Text = 'Remove archive mod cancelled.' }; return }

                    $manifest = Normalize-UGSMModsManifest -Manifest (Read-UGSMModsManifest -Instance $Instance -ModsDefinition $modsDefForArchiveActions) -Instance $Instance -ModsDefinition $modsDefForArchiveActions
                    $result = Invoke-UGSMGameHelperHook -ModsDefinition $modsDefForArchiveActions -HookName 'Remove' -Instance $Instance -Manifest $manifest -ModName $input
                    if ($result -and $result.PSObject.Properties['Manifest'] -and $result.Manifest) { $manifest = $result.Manifest }
                    else { $manifest = Normalize-UGSMModsManifest -Manifest (Read-UGSMModsManifest -Instance $Instance -ModsDefinition $modsDefForArchiveActions) -Instance $Instance -ModsDefinition $modsDefForArchiveActions }
                    $summaryPath = Update-UGSMModsSummaryFile -Instance $Instance -Manifest $manifest -ModsDefinition $modsDefForArchiveActions
                    Update-UGSMModsActiveListControls -Instance $Instance -ModsDefinition $modsDefForArchiveActions -StatusLabel $StatusLabel | Out-Null
                    if ($StatusLabel) { $StatusLabel.Text = ('Archive mod removed. File=' + (ConvertTo-UGSMGameHelperSafeLogText -Value $summaryPath)) }
                }
                catch {
                    Write-UGSMGameHelperLog -Category 'Mods' -Level 'ERROR' -Message 'Archive mod remove failed from shared Mods tab.' -Exception $_.Exception
                    if ($StatusLabel) { $StatusLabel.Text = 'Remove archive mod failed: ' + $_.Exception.Message }
                }
            }
        })
    }

    if ($cap -and $cap.PSObject.Properties['FolderImport'] -and [bool]$cap.FolderImport) {
        [void]$fields.Add(@{
            Id = 'UGSMModsFolderPlaceholder'
            Type = 'ActionButton'
            Label = 'Folder Import'
            ButtonText = 'Import Folder'
            Hint = 'Shared helper placeholder for copying a user-selected mod folder into the selected profile/server Mods folder.'
            Action = { param($Instance, $Paths, $StatusLabel) if ($StatusLabel) { $StatusLabel.Text = 'Folder mod import is enabled for this game definition.' } }
        })
    }

    if ($cap -and $cap.PSObject.Properties['FrameworkInstall'] -and [bool]$cap.FrameworkInstall) {
        $frameworkLabel = 'Mod Framework'
        if ($ModsDefinition.PSObject.Properties['Framework'] -and $ModsDefinition.Framework -and $ModsDefinition.Framework.PSObject.Properties['Label'] -and -not [string]::IsNullOrWhiteSpace([string]$ModsDefinition.Framework.Label)) {
            $frameworkLabel = [string]$ModsDefinition.Framework.Label
        }
        [void]$fields.Add(@{
            Id = 'UGSMModsFrameworkPlaceholder'
            Type = 'ActionButton'
            Label = $frameworkLabel
            ButtonText = 'Install / Update Framework'
            Hint = 'Shared helper placeholder. This should require confirmation before downloading or patching server files.'
            Action = { param($Instance, $Paths, $StatusLabel) if ($StatusLabel) { $StatusLabel.Text = 'Framework install workflow is enabled for this game definition.' } }
        })
    }

    $modsDefCommonActions = $ModsDefinition
    [void]$fields.Add(@{
        Id = 'UGSMModsOpenManifest'
        Type = 'ActionButton'
        Label = 'Instance Mod State'
        ButtonText = 'Open Instance Mod State'
        Hint = 'Opens the instance JSON that stores active mod references and load order, not full mod files.'
        Action = {
            param($Instance, $Paths, $StatusLabel)
            try {
                $manifest = Normalize-UGSMModsManifest -Manifest (Read-UGSMModsManifest -Instance $Instance -ModsDefinition $modsDefCommonActions) -Instance $Instance -ModsDefinition $modsDefCommonActions
                Save-UGSMModsManifest -Instance $Instance -Manifest $manifest -ModsDefinition $modsDefCommonActions
                Update-UGSMModsSummaryFile -Instance $Instance -Manifest $manifest -ModsDefinition $modsDefCommonActions | Out-Null
                $path = Resolve-UGSMModsManifestPath -Instance $Instance -ModsDefinition $modsDefCommonActions
                if (-not [string]::IsNullOrWhiteSpace($path)) { Start-Process -FilePath $path | Out-Null }
                if ($StatusLabel) { $StatusLabel.Text = 'Opened instance mod state.' }
            }
            catch { if ($StatusLabel) { $StatusLabel.Text = 'Open mod manifest failed: ' + $_.Exception.Message } }
        }
    })

    [void]$fields.Add(@{
        Id = 'UGSMModsRefreshSummary'
        Type = 'ActionButton'
        Label = 'Active Mods List'
        ButtonText = 'Refresh Active Mods Summary'
        Hint = 'Refreshes the visible active mod list from instance mod state and runs any game-specific sync hook.'
        Action = {
            param($Instance, $Paths, $StatusLabel)
            try {
                $manifest = Normalize-UGSMModsManifest -Manifest (Read-UGSMModsManifest -Instance $Instance -ModsDefinition $modsDefCommonActions) -Instance $Instance -ModsDefinition $modsDefCommonActions
                Invoke-UGSMGameHelperHook -ModsDefinition $modsDefCommonActions -HookName 'AfterWorkshopDownload' -Instance $Instance -Manifest $manifest | Out-Null
                $summaryPath = Update-UGSMModsSummaryFile -Instance $Instance -Manifest $manifest -ModsDefinition $modsDefCommonActions
                Update-UGSMModsActiveListControls -Instance $Instance -ModsDefinition $modsDefCommonActions -StatusLabel $StatusLabel | Out-Null
                $count = @($manifest.Mods).Count
                if ($StatusLabel) { $StatusLabel.Text = ('Active mods summary refreshed. Count=' + $count + '; File=' + (ConvertTo-UGSMGameHelperSafeLogText -Value $summaryPath)) }
            }
            catch { if ($StatusLabel) { $StatusLabel.Text = 'Refresh active mods summary failed: ' + $_.Exception.Message } }
        }
    })

    return [pscustomobject]@{
        Title = $(if (-not [string]::IsNullOrWhiteSpace([string]$ModsDefinition.DisplayName)) { [string]$ModsDefinition.DisplayName } else { 'Mods' })
        Description = 'Shared UGSM mod-management shell. The game definition controls which provider sections appear; game-specific hooks can override install/save behavior.'
        Fields = $fields.ToArray()
    }
}


function Add-UGSMModsTabToSchema {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$Schema,
        [Parameter(Mandatory)][object]$ModsDefinition,
        [string]$GameId = ''
    )

    if (-not (Test-UGSMGameModsSupported -ModsDefinition $ModsDefinition)) { return $Schema }

    $modsTab = New-UGSMModsTabSchema -ModsDefinition $ModsDefinition -GameId $GameId
    if ($null -eq $modsTab) { return $Schema }

    $tabList = New-Object System.Collections.Generic.List[object]
    if ($Schema -and $Schema.PSObject.Properties['Tabs']) {
        foreach ($tab in @($Schema.Tabs)) {
            if ([string]$tab.Title -eq [string]$modsTab.Title) { return $Schema }
            [void]$tabList.Add($tab)
        }
    }

    [void]$tabList.Add($modsTab)

    $version = 1
    if ($Schema -and $Schema.PSObject.Properties['Version']) { $version = $Schema.Version }

    return [pscustomobject]@{
        Version = $version
        Tabs    = $tabList.ToArray()
    }
}




# ============================================================
# Shared Framework / Plugin Mods Editor (Rust uMod/Oxide style)
# ============================================================
function New-UGSMSharedFrameworkPluginModsEditor {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][System.Windows.Forms.Control]$Parent,
        [Parameter(Mandatory)][object]$Instance,
        [AllowNull()][object]$ModsDefinition,
        [AllowNull()][object]$Theme = $null,
        [AllowNull()][object]$StatusLabel = $null
    )

    Add-Type -AssemblyName System.Windows.Forms -ErrorAction SilentlyContinue | Out-Null
    Add-Type -AssemblyName System.Drawing -ErrorAction SilentlyContinue | Out-Null

    $modsDef = $ModsDefinition
    if (-not $modsDef) {
        Set-UGSMGameHelperStatusText -StatusLabel $StatusLabel -Text 'Framework mods tab unavailable: missing mods definition.'
        return $null
    }

    $textColor = Get-UGSMGameHelperThemeValue -Theme $Theme -Name 'Text'
    $mutedColor = Get-UGSMGameHelperThemeValue -Theme $Theme -Name 'Muted'
    $panelColor = Get-UGSMGameHelperThemeValue -Theme $Theme -Name 'Background'
    $surfaceColor = Get-UGSMGameHelperThemeValue -Theme $Theme -Name 'Surface'
    $inputColor = Get-UGSMGameHelperThemeValue -Theme $Theme -Name 'Input'
    $buttonColor = Get-UGSMGameHelperThemeValue -Theme $Theme -Name 'Button'
    $accentColor = Get-UGSMGameHelperThemeValue -Theme $Theme -Name 'Accent'
    $dangerColor = Get-UGSMGameHelperThemeValue -Theme $Theme -Name 'Danger'
    $successColor = Get-UGSMGameHelperThemeValue -Theme $Theme -Name 'Success'

    $framework = Get-UGSMGameHelperObjectValue -Object $modsDef -Name 'Framework'
    $hooks = Get-UGSMGameHelperObjectValue -Object $modsDef -Name 'Hooks'
    $label = [string](Get-UGSMGameHelperObjectValue -Object $framework -Name 'Label' -Default 'uMod / Oxide')
    $pluginFolderRel = [string](Get-UGSMGameHelperObjectValue -Object $framework -Name 'PluginFolderRelative' -Default 'oxide\plugins')

    $statusHook = [string](Get-UGSMGameHelperObjectValue -Object $hooks -Name 'FrameworkStatus' -Default '')
    if ([string]::IsNullOrWhiteSpace($statusHook)) { $statusHook = 'Test-UGSMRustOxideFrameworkInstalled' }
    $installHook = [string](Get-UGSMGameHelperObjectValue -Object $hooks -Name 'FrameworkInstall' -Default '')
    $openHook = [string](Get-UGSMGameHelperObjectValue -Object $hooks -Name 'OpenPlugins' -Default '')
    $addHook = [string](Get-UGSMGameHelperObjectValue -Object $hooks -Name 'AddPlugin' -Default '')
    $removeHook = [string](Get-UGSMGameHelperObjectValue -Object $hooks -Name 'RemovePlugin' -Default '')

    $root = New-Object System.Windows.Forms.Panel
    $root.Dock = 'Fill'
    $root.AutoScroll = $true
    $root.BackColor = $panelColor
    [void]$Parent.Controls.Add($root)

    $description = New-UGSMGameHelperLabel -Text ("Manage $label and server plugins for this profile. Framework files install into the shared game binaries; plugins are kept in the framework plugin folder.") -X 8 -Y 8 -Width 1200 -Height 32 -Color $mutedColor
    [void]$root.Controls.Add($description)

    $source = New-UGSMGameHelperLabel -Text ("Source: $pluginFolderRel") -X 8 -Y 36 -Width 1200 -Height 18 -Color $mutedColor
    [void]$root.Controls.Add($source)

    $leftPanel = New-Object System.Windows.Forms.Panel
    $leftPanel.Left = 8
    $leftPanel.Top = 62
    $leftPanel.Width = 450
    $leftPanel.Height = 610
    $leftPanel.BackColor = $surfaceColor
    [void]$root.Controls.Add($leftPanel)

    $pluginsLabel = New-UGSMGameHelperLabel -Text 'Installed Plugins' -X 8 -Y 8 -Width 260 -Height 22 -Color $textColor -Bold
    [void]$leftPanel.Controls.Add($pluginsLabel)

    $pluginList = New-Object System.Windows.Forms.ListBox
    $pluginList.Left = 8
    $pluginList.Top = 36
    $pluginList.Width = 310
    $pluginList.Height = 468
    $pluginList.BackColor = $inputColor
    $pluginList.ForeColor = $textColor
    $pluginList.HorizontalScrollbar = $true
    [void]$leftPanel.Controls.Add($pluginList)

    $btnRefresh = New-UGSMGameHelperButton -Text 'Refresh' -X 330 -Y 36 -Width 105 -Height 30 -BackColor $buttonColor
    $btnRemove = New-UGSMGameHelperButton -Text 'Remove Plugin' -X 330 -Y 76 -Width 105 -Height 30 -BackColor $dangerColor
    [void]$leftPanel.Controls.Add($btnRefresh)
    [void]$leftPanel.Controls.Add($btnRemove)

    $rightPanel = New-Object System.Windows.Forms.Panel
    $rightPanel.Left = 472
    $rightPanel.Top = 62
    $rightPanel.Width = 760
    $rightPanel.Height = 610
    $rightPanel.BackColor = $surfaceColor
    [void]$root.Controls.Add($rightPanel)

    $statusText = New-UGSMGameHelperLabel -Text "$label status has not been checked yet." -X 12 -Y 12 -Width 720 -Height 28 -Color $mutedColor
    [void]$rightPanel.Controls.Add($statusText)

    $btnInstall = New-UGSMGameHelperButton -Text "Install / Update $label" -X 12 -Y 54 -Width 300 -Height 34 -BackColor $successColor
    $btnOpen = New-UGSMGameHelperButton -Text 'Open Plugins Folder' -X 330 -Y 54 -Width 260 -Height 34 -BackColor $buttonColor
    $btnAdd = New-UGSMGameHelperButton -Text 'Add Plugin .cs' -X 12 -Y 104 -Width 300 -Height 34 -BackColor $successColor
    $btnNotice = New-UGSMGameHelperButton -Text 'Show Mod Safety Notice' -X 330 -Y 104 -Width 260 -Height 34 -BackColor $buttonColor
    [void]$rightPanel.Controls.Add($btnInstall)
    [void]$rightPanel.Controls.Add($btnOpen)
    [void]$rightPanel.Controls.Add($btnAdd)
    [void]$rightPanel.Controls.Add($btnNotice)

    $hint = New-UGSMGameHelperLabel -Text 'Framework installs modify shared server binaries. Plugins are third-party .cs files and can affect stability, security, saves, and gameplay.' -X 12 -Y 154 -Width 720 -Height 44 -Color $mutedColor
    [void]$rightPanel.Controls.Add($hint)

    $refreshPlugins = {
        try {
            $pluginList.Items.Clear()
            $folder = $null

            # Prefer the framework status hook because it is the owner for this
            # framework's plugin folder and may return a pre-built plugin list.
            $statusResult = $null
            if (-not [string]::IsNullOrWhiteSpace($statusHook)) {
                $statusCmd = Get-Command -Name $statusHook -CommandType Function -ErrorAction SilentlyContinue
                if ($statusCmd) {
                    $statusResult = & $statusCmd.Name -Instance $Instance -ModsDefinition $modsDef -Manifest $null
                    if ($statusResult -and $statusResult.PSObject.Properties['PluginFolder']) {
                        $folder = [string]$statusResult.PluginFolder
                    }
                    if ($statusResult -and $statusResult.PSObject.Properties['Plugins'] -and $statusResult.Plugins) {
                        foreach ($pluginName in @($statusResult.Plugins)) {
                            if (-not [string]::IsNullOrWhiteSpace([string]$pluginName)) {
                                [void]$pluginList.Items.Add([string]$pluginName)
                            }
                        }
                        if ($pluginList.Items.Count -gt 0) { return }
                    }
                }
            }

            # Rust/uMod fallback for the current framework owner.
            if ([string]::IsNullOrWhiteSpace($folder) -and (Get-Command -Name Get-UGSMRustOxidePaths -CommandType Function -ErrorAction SilentlyContinue)) {
                $paths = Get-UGSMRustOxidePaths -Instance $Instance -ModsDefinition $modsDef
                if ($paths -and $paths.PSObject.Properties['PluginFolder']) {
                    $folder = [string]$paths.PluginFolder
                }
            }

            if ($folder -and (Test-Path -LiteralPath $folder -PathType Container)) {
                $files = @(Get-ChildItem -LiteralPath $folder -Filter '*.cs' -File -ErrorAction SilentlyContinue | Sort-Object Name)
                foreach ($file in $files) { [void]$pluginList.Items.Add($file.Name) }
                if ($files.Count -eq 0) { [void]$pluginList.Items.Add('No .cs plugins installed.') }
            }
            else {
                [void]$pluginList.Items.Add('Plugins folder not created yet.')
            }
        }
        catch {
            $pluginList.Items.Clear()
            [void]$pluginList.Items.Add('Plugin list unavailable.')
            Set-UGSMGameHelperStatusText -StatusLabel $StatusLabel -Text ('Plugin refresh failed: ' + $_.Exception.Message)
        }
    }.GetNewClosure()

    $refreshStatus = {
        try {
            $message = "$label is not installed yet."
            $installed = $false
            $cmd = $null
            if (-not [string]::IsNullOrWhiteSpace($statusHook)) {
                $cmd = Get-Command -Name $statusHook -CommandType Function -ErrorAction SilentlyContinue
            }
            if ($cmd) {
                $result = & $cmd.Name -Instance $Instance -ModsDefinition $modsDef
                if ($result) {
                    if ($result.PSObject.Properties['Installed']) { $installed = [bool]$result.Installed }
                    if ($result.PSObject.Properties['Message'] -and -not [string]::IsNullOrWhiteSpace([string]$result.Message)) { $message = [string]$result.Message }
                    elseif ($result.PSObject.Properties['StatusText'] -and -not [string]::IsNullOrWhiteSpace([string]$result.StatusText)) { $message = [string]$result.StatusText }
                }
            }
            $statusText.Text = $message
            $btnInstall.Text = $(if ($installed) { "Update $label" } else { "Install $label" })
        }
        catch {
            $statusText.Text = "$label status check failed."
            Set-UGSMGameHelperStatusText -StatusLabel $StatusLabel -Text ('Framework status failed: ' + $_.Exception.Message)
        }
    }.GetNewClosure()

    $btnRefresh.Add_Click({ & $refreshPlugins; & $refreshStatus }.GetNewClosure())

    $btnNotice.Add_Click({
        [System.Windows.Forms.MessageBox]::Show('Third-party server frameworks and plugins can affect stability, security, saves, and gameplay. Only install plugins from trusted sources and keep backups before changing a live server.', 'UGSM Mod Safety Notice', [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Warning) | Out-Null
    }.GetNewClosure())

    $btnOpen.Add_Click({
        try {
            if ([string]::IsNullOrWhiteSpace($openHook)) { throw "This game module did not provide an Open Plugins hook." }
            $cmd = Get-Command -Name $openHook -CommandType Function -ErrorAction SilentlyContinue
            if (-not $cmd) { throw "Open Plugins hook '$openHook' was not found." }
            $result = & $cmd.Name -Instance $Instance -ModsDefinition $modsDef -Manifest $null
            if ($result -and $result.PSObject.Properties['Message']) { Set-UGSMGameHelperStatusText -StatusLabel $StatusLabel -Text ([string]$result.Message) }
        }
        catch {
            Set-UGSMGameHelperStatusText -StatusLabel $StatusLabel -Text ('Open plugins folder failed: ' + $_.Exception.Message)
            Write-UGSMGameHelperLog -Category 'Mods' -Level 'ERROR' -Message 'Open plugins folder failed.' -Exception $_.Exception
        }
    }.GetNewClosure())

    $btnInstall.Add_Click({
        try {
            if ([string]::IsNullOrWhiteSpace($installHook)) { throw "This game module did not provide a $label install hook." }
            $cmd = Get-Command -Name $installHook -CommandType Function -ErrorAction SilentlyContinue
            if (-not $cmd) { throw "$label install hook '$installHook' was not found." }
            $result = & $cmd.Name -Instance $Instance -ModsDefinition $modsDef -Manifest $null
            if ($result -and $result.PSObject.Properties['Message']) { Set-UGSMGameHelperStatusText -StatusLabel $StatusLabel -Text ([string]$result.Message) }
            else { Set-UGSMGameHelperStatusText -StatusLabel $StatusLabel -Text "$label install/update completed." }
            & $refreshStatus
            & $refreshPlugins
        }
        catch {
            Set-UGSMGameHelperStatusText -StatusLabel $StatusLabel -Text ("$label install/update failed: " + $_.Exception.Message)
            Write-UGSMGameHelperLog -Category 'Mods' -Level 'ERROR' -Message "$label install/update failed." -Exception $_.Exception
        }
    }.GetNewClosure())

    $btnAdd.Add_Click({
        try {
            if ([string]::IsNullOrWhiteSpace($addHook)) { throw "This game module did not provide a PluginAdd hook." }
            $cmd = Get-Command -Name $addHook -CommandType Function -ErrorAction SilentlyContinue
            if (-not $cmd) { throw "PluginAdd hook '$addHook' was not found." }

            $dialog = New-Object System.Windows.Forms.OpenFileDialog
            $dialog.Title = 'Select Oxide/uMod plugin .cs file'
            $dialog.Filter = 'C# plugin files (*.cs)|*.cs'
            $dialog.Multiselect = $false
            if ($dialog.ShowDialog() -ne [System.Windows.Forms.DialogResult]::OK) { return }

            $result = & $cmd.Name -Instance $Instance -ModsDefinition $modsDef -Manifest $null -ArchivePath $dialog.FileName
            if ($result -and $result.PSObject.Properties['Message']) { Set-UGSMGameHelperStatusText -StatusLabel $StatusLabel -Text ([string]$result.Message) }
            else { Set-UGSMGameHelperStatusText -StatusLabel $StatusLabel -Text 'Plugin added.' }
            & $refreshPlugins
        }
        catch {
            Set-UGSMGameHelperStatusText -StatusLabel $StatusLabel -Text ('Add plugin failed: ' + $_.Exception.Message)
            Write-UGSMGameHelperLog -Category 'Mods' -Level 'ERROR' -Message 'Add plugin failed.' -Exception $_.Exception
        }
    }.GetNewClosure())

    $btnRemove.Add_Click({
        try {
            if ([string]::IsNullOrWhiteSpace($removeHook)) { throw "This game module did not provide a PluginRemove hook." }
            $selected = $pluginList.SelectedItem
            if (-not $selected -or [string]$selected -match '^No |^Plugins folder') { throw 'Select an installed plugin first.' }
            $cmd = Get-Command -Name $removeHook -CommandType Function -ErrorAction SilentlyContinue
            if (-not $cmd) { throw "PluginRemove hook '$removeHook' was not found." }
            $result = & $cmd.Name -Instance $Instance -ModsDefinition $modsDef -Manifest $null -ModName ([string]$selected)
            if ($result -and $result.PSObject.Properties['Message']) { Set-UGSMGameHelperStatusText -StatusLabel $StatusLabel -Text ([string]$result.Message) }
            else { Set-UGSMGameHelperStatusText -StatusLabel $StatusLabel -Text 'Plugin removed.' }
            & $refreshPlugins
        }
        catch {
            Set-UGSMGameHelperStatusText -StatusLabel $StatusLabel -Text ('Remove plugin failed: ' + $_.Exception.Message)
            Write-UGSMGameHelperLog -Category 'Mods' -Level 'ERROR' -Message 'Remove plugin failed.' -Exception $_.Exception
        }
    }.GetNewClosure())

    & $refreshStatus
    & $refreshPlugins

    return $root
}

# ============================================================
# Shared Steam Workshop Mods Editor (DayZ-style)
# ============================================================
function Read-UGSMGameHelperInputBox {
    [CmdletBinding()]
    param(
        [string]$Title = 'UGSM Input',
        [string]$Prompt = 'Enter value:',
        [string]$DefaultValue = ''
    )

    Add-Type -AssemblyName System.Windows.Forms -ErrorAction SilentlyContinue | Out-Null
    Add-Type -AssemblyName System.Drawing -ErrorAction SilentlyContinue | Out-Null

    $form = New-Object System.Windows.Forms.Form
    $form.Text = $Title
    $form.StartPosition = 'CenterParent'
    $form.Width = 520
    $form.Height = 170
    $form.FormBorderStyle = 'FixedDialog'
    $form.MaximizeBox = $false
    $form.MinimizeBox = $false
    $form.ShowInTaskbar = $false

    $label = New-Object System.Windows.Forms.Label
    $label.Text = $Prompt
    $label.Left = 12
    $label.Top = 12
    $label.Width = 480
    $label.Height = 36
    $form.Controls.Add($label)

    $textbox = New-Object System.Windows.Forms.TextBox
    $textbox.Left = 12
    $textbox.Top = 54
    $textbox.Width = 480
    $textbox.Text = $DefaultValue
    $form.Controls.Add($textbox)

    $ok = New-Object System.Windows.Forms.Button
    $ok.Text = 'OK'
    $ok.Left = 316
    $ok.Top = 88
    $ok.Width = 84
    $ok.DialogResult = [System.Windows.Forms.DialogResult]::OK
    $form.AcceptButton = $ok
    $form.Controls.Add($ok)

    $cancel = New-Object System.Windows.Forms.Button
    $cancel.Text = 'Cancel'
    $cancel.Left = 408
    $cancel.Top = 88
    $cancel.Width = 84
    $cancel.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
    $form.CancelButton = $cancel
    $form.Controls.Add($cancel)

    $result = $form.ShowDialog()
    if ($result -eq [System.Windows.Forms.DialogResult]::OK) { return [string]$textbox.Text }
    return ''
}





function Get-UGSMGameHelperModDisplayText {
    [CmdletBinding()]
    param([AllowNull()][object]$Mod)

    if (-not $Mod) { return '' }

    $name = ''
    $workshopId = ''
    $modId = ''

    if ($Mod.PSObject.Properties['Name']) { $name = [string]$Mod.Name }
    if ($Mod.PSObject.Properties['WorkshopId']) { $workshopId = [string]$Mod.WorkshopId }
    if ($Mod.PSObject.Properties['ModId']) { $modId = [string]$Mod.ModId }

    if ([string]::IsNullOrWhiteSpace($name)) {
        if (-not [string]::IsNullOrWhiteSpace($modId)) { $name = $modId }
        elseif (-not [string]::IsNullOrWhiteSpace($workshopId)) { $name = 'Workshop ' + $workshopId }
        else { $name = 'Workshop Mod' }
    }

    if (-not [string]::IsNullOrWhiteSpace($modId) -and $name -ne $modId) {
        return ('{0} ({1}) [{2}]' -f $name, $workshopId, $modId)
    }
    if (-not [string]::IsNullOrWhiteSpace($workshopId)) {
        return ('{0} ({1})' -f $name, $workshopId)
    }
    return $name
}

function Get-UGSMGameHelperColor {
    [CmdletBinding()]
    param(
        [AllowNull()][object]$Value = $null,
        [ValidateSet('Background','Surface','Input','Text','Muted','Accent','Button','Danger','Success')]
        [string]$Name = 'Background'
    )

    Add-Type -AssemblyName System.Drawing -ErrorAction SilentlyContinue | Out-Null

    if ($Value -is [System.Drawing.Color]) { return [System.Drawing.Color]$Value }

    $fallback = switch ($Name) {
        'Background' { $global:UGSM_ColorBackground }
        'Surface'    { $global:UGSM_ColorSurface }
        'Input'      { $global:UGSM_ColorInputBackground }
        'Text'       { $global:UGSM_ColorText }
        'Muted'      { $global:UGSM_ColorMutedText }
        'Accent'     { $global:UGSM_ColorAccent }
        'Button'     { $global:UGSM_ColorNeutral }
        'Danger'     { $global:UGSM_ColorDanger }
        'Success'    { $global:UGSM_ColorSuccess }
        default      { $global:UGSM_ColorBackground }
    }

    if (Get-Command -Name ConvertTo-UGSMSafeColor -CommandType Function -ErrorAction SilentlyContinue) {
        try { return (ConvertTo-UGSMSafeColor -Color $Value -Fallback $fallback) } catch {}
        try { return (ConvertTo-UGSMSafeColor -Color $fallback -Fallback ([System.Drawing.SystemColors]::Control)) } catch {}
    }

    if ($fallback -is [System.Drawing.Color]) { return [System.Drawing.Color]$fallback }

    switch ($Name) {
        'Text'       { return [System.Drawing.SystemColors]::WindowText }
        'Muted'      { return [System.Drawing.SystemColors]::GrayText }
        'Input'      { return [System.Drawing.SystemColors]::Window }
        'Accent'     { return [System.Drawing.SystemColors]::Highlight }
        'Success'    { return [System.Drawing.SystemColors]::Highlight }
        'Danger'     { return [System.Drawing.SystemColors]::ControlDark }
        'Button'     { return [System.Drawing.SystemColors]::ControlDark }
        'Surface'    { return [System.Drawing.SystemColors]::Control }
        default      { return [System.Drawing.SystemColors]::Control }
    }
}

function Get-UGSMGameHelperThemeValue {
    [CmdletBinding()]
    param(
        [AllowNull()][object]$Theme,
        [ValidateSet('Background','Surface','Input','Text','Muted','Accent','Button','Danger','Success')]
        [string]$Name
    )

    try {
        if ($Theme) {
            if ($Theme -is [hashtable] -and $Theme.ContainsKey($Name)) {
                return (Get-UGSMGameHelperColor -Value $Theme[$Name] -Name $Name)
            }
            if ($Theme.PSObject.Properties[$Name]) {
                return (Get-UGSMGameHelperColor -Value $Theme.$Name -Name $Name)
            }
        }
    }
    catch {}

    return (Get-UGSMGameHelperColor -Name $Name)
}

function Get-UGSMGameHelperObjectValue {
    [CmdletBinding()]
    param(
        [AllowNull()][object]$Object,
        [Parameter(Mandatory)][string]$Name,
        [AllowNull()][object]$Default = $null
    )

    if ($null -eq $Object) { return $Default }

    try {
        if ($Object -is [hashtable] -and $Object.ContainsKey($Name)) { return $Object[$Name] }
        $prop = $Object.PSObject.Properties[$Name]
        if ($prop) { return $prop.Value }
    }
    catch {}

    return $Default
}

function Set-UGSMGameHelperStatusText {
    [CmdletBinding()]
    param(
        [AllowNull()][object]$StatusLabel,
        [AllowNull()][string]$Text
    )

    try {
        if ($StatusLabel) { $StatusLabel.Text = [string]$Text }
    }
    catch {}
}


function New-UGSMGameHelperLabel {
    [CmdletBinding()]
    param(
        [string]$Text,
        [int]$X,
        [int]$Y,
        [int]$Width = 160,
        [int]$Height = 20,
        [AllowNull()][object]$Color = $null,
        [switch]$Bold
    )

    $label = New-Object System.Windows.Forms.Label
    $label.Text = $Text
    $label.Left = $X
    $label.Top = $Y
    $label.Width = $Width
    $label.Height = $Height
    $label.ForeColor = Get-UGSMGameHelperColor -Value $Color -Name 'Text'
    $label.BackColor = [System.Drawing.Color]::Transparent
    if ($Bold) { $label.Font = New-Object System.Drawing.Font($label.Font, [System.Drawing.FontStyle]::Bold) }
    return $label
}

function New-UGSMGameHelperButton {
    [CmdletBinding()]
    param(
        [string]$Text,
        [int]$X,
        [int]$Y,
        [int]$Width = 120,
        [int]$Height = 30,
        [AllowNull()][object]$BackColor = $null,
        [AllowNull()][object]$ForeColor = $null
    )

    $button = New-Object System.Windows.Forms.Button
    $button.Text = $Text
    $button.Left = $X
    $button.Top = $Y
    $button.Width = $Width
    $button.Height = $Height
    $button.FlatStyle = 'Flat'
    $button.BackColor = Get-UGSMGameHelperColor -Value $BackColor -Name 'Button'
    $button.ForeColor = Get-UGSMGameHelperColor -Value $ForeColor -Name 'Text'
    return $button
}

function New-UGSMSharedSteamWorkshopModsEditor {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][System.Windows.Forms.Control]$Parent,
        [Parameter(Mandatory)][object]$Instance,
        [AllowNull()][object]$ModsDefinition,
        [AllowNull()][object]$Theme = $null,
        [AllowNull()][object]$StatusLabel = $null
    )

    Add-Type -AssemblyName System.Windows.Forms -ErrorAction SilentlyContinue | Out-Null
    Add-Type -AssemblyName System.Drawing -ErrorAction SilentlyContinue | Out-Null

    $statusControl = $StatusLabel
    $modsDef = $ModsDefinition
    # Compatibility aliases for older action closures and strict-mode safety.
    $modsDefForActions = $modsDef
    $modsDeforActions = $modsDef
    $textColor = Get-UGSMGameHelperThemeValue -Theme $Theme -Name 'Text'
    $mutedColor = Get-UGSMGameHelperThemeValue -Theme $Theme -Name 'Muted'
    $panelColor = Get-UGSMGameHelperThemeValue -Theme $Theme -Name 'Background'
    $surfaceColor = Get-UGSMGameHelperThemeValue -Theme $Theme -Name 'Surface'
    $buttonColor = Get-UGSMGameHelperThemeValue -Theme $Theme -Name 'Button'
    $accentColor = Get-UGSMGameHelperThemeValue -Theme $Theme -Name 'Accent'
    $dangerColor = Get-UGSMGameHelperThemeValue -Theme $Theme -Name 'Danger'
    $successColor = Get-UGSMGameHelperThemeValue -Theme $Theme -Name 'Success'

    if (-not $modsDef) {
        if ($statusControl) { $statusControl.Text = 'Mods tab unavailable: missing mods definition.' }
        return $null
    }

    $modTabMode = [string](Get-UGSMGameHelperObjectValue -Object $modsDef -Name 'ModTabMode' -Default '')
    if ($modTabMode -eq 'FrameworkPlugin') {
        if (Get-Command -Name New-UGSMSharedFrameworkPluginModsEditor -CommandType Function -ErrorAction SilentlyContinue) {
            return (New-UGSMSharedFrameworkPluginModsEditor -Parent $Parent -Instance $Instance -ModsDefinition $modsDef -Theme $Theme -StatusLabel $StatusLabel)
        }
        Set-UGSMGameHelperStatusText -StatusLabel $StatusLabel -Text 'Framework/plugin mods renderer is not loaded.'
        return $null
    }

    $cap = $null
    if ($modsDef.PSObject.Properties['Capabilities']) { $cap = $modsDef.Capabilities }
    $hasSteamWorkshop = [bool]($cap -and $cap.PSObject.Properties['SteamWorkshop'] -and [bool]$cap.SteamWorkshop)
    $hasArchiveImport = [bool]($cap -and $cap.PSObject.Properties['ArchiveImport'] -and [bool]$cap.ArchiveImport)
    $hasLoadOrder = [bool]($cap -and $cap.PSObject.Properties['LoadOrder'] -and [bool]$cap.LoadOrder)
    $canDownload = $hasSteamWorkshop
    $canOpenManifest = [bool]($cap -and $cap.PSObject.Properties['OpenManifest'] -and [bool]$cap.OpenManifest)
    $canRefresh = [bool]($cap -and $cap.PSObject.Properties['RefreshSummary'] -and [bool]$cap.RefreshSummary)

    $frameworkMode = $false
    try {
        $frameworkMode = ([string]$modsDef.ModTabMode -eq 'FrameworkPlugin') -or [bool]($cap -and $cap.PSObject.Properties['FrameworkInstall'] -and [bool]$cap.FrameworkInstall) -or [bool]($cap -and $cap.PSObject.Properties['PluginManager'] -and [bool]$cap.PluginManager)
    } catch { $frameworkMode = $false }
    if ($frameworkMode -and (Get-Command -Name New-UGSMSharedFrameworkPluginModsEditor -CommandType Function -ErrorAction SilentlyContinue)) {
        return (New-UGSMSharedFrameworkPluginModsEditor -Parent $Parent -Instance $Instance -ModsDefinition $modsDef -Theme $Theme -StatusLabel $StatusLabel)
    }

    $promptModId = $false
    $promptMapFolders = $false
    if ($modsDef.PSObject.Properties['Workshop'] -and $modsDef.Workshop) {
        if ($modsDef.Workshop.PSObject.Properties['PromptForModId']) { $promptModId = [bool]$modsDef.Workshop.PromptForModId }
        if ($modsDef.Workshop.PSObject.Properties['PromptForMapFolders']) { $promptMapFolders = [bool]$modsDef.Workshop.PromptForMapFolders }
    }

    $root = New-Object System.Windows.Forms.Panel
    $root.Dock = 'Fill'
    $root.BackColor = $panelColor
    $Parent.Controls.Add($root)

    $descriptionText = $(if ($hasArchiveImport -and -not $hasSteamWorkshop) { 'Manage ZIP/RAR archive mods for this game. For 7D2D these install into the shared Steam install Mods folder and affect all instances using those binaries.' } else { 'Manage Steam Workshop mods for this profile. Mods are stored on the instance and synced into the game config when changed.' })
    $description = New-UGSMGameHelperLabel -Text $descriptionText -X 8 -Y 8 -Width 1150 -Height 32 -Color $mutedColor
    $root.Controls.Add($description)

    $sourceText = $(if ($hasArchiveImport -and -not $hasSteamWorkshop) { 'Source: Shared Archive Mods Folder' } else { 'Source: Steam Workshop Cache' })
    try {
        if ($Instance -and $Instance.PSObject.Properties['ProfileRoot']) {
            $sourceText += '   Runtime: ' + [string]$Instance.ProfileRoot
        }
    } catch {}
    $source = New-UGSMGameHelperLabel -Text $sourceText -X 8 -Y 34 -Width 1150 -Height 18 -Color $mutedColor
    $root.Controls.Add($source)

    $leftPanel = New-Object System.Windows.Forms.Panel
    $leftPanel.Left = 8
    $leftPanel.Top = 62
    $leftPanel.Width = 470
    $leftPanel.Height = 610
    $leftPanel.BackColor = $surfaceColor
    $root.Controls.Add($leftPanel)

    $activeLabel = New-UGSMGameHelperLabel -Text 'Active Mods [Load Order]' -X 8 -Y 6 -Width 260 -Height 22 -Color $textColor -Bold
    $leftPanel.Controls.Add($activeLabel)

    $list = New-Object System.Windows.Forms.ListBox
    $list.Left = 8
    $list.Top = 34
    $list.Width = 315
    $list.Height = 468
    $list.HorizontalScrollbar = $true
    $leftPanel.Controls.Add($list)

    $btnUp = New-UGSMGameHelperButton -Text 'Move Up' -X 342 -Y 34 -Width 118 -Height 30
    $btnDown = New-UGSMGameHelperButton -Text 'Move Down' -X 342 -Y 76 -Width 118 -Height 30
    $btnRemove = New-UGSMGameHelperButton -Text 'Remove' -X 342 -Y 126 -Width 118 -Height 30 -BackColor $dangerColor
    $leftPanel.Controls.Add($btnUp)
    $leftPanel.Controls.Add($btnDown)
    $leftPanel.Controls.Add($btnRemove)

    if (-not $hasLoadOrder) {
        $btnUp.Enabled = $false
        $btnDown.Enabled = $false
    }

    $rightPanel = New-Object System.Windows.Forms.Panel
    $rightPanel.Left = 492
    $rightPanel.Top = 62
    $rightPanel.Width = 720
    $rightPanel.Height = 610
    $rightPanel.BackColor = $surfaceColor
    $root.Controls.Add($rightPanel)

    $addTitle = New-UGSMGameHelperLabel -Text 'Add New Mod' -X 12 -Y 8 -Width 220 -Height 22 -Color $textColor -Bold
    $rightPanel.Controls.Add($addTitle)

    $workshopLabel = New-UGSMGameHelperLabel -Text $(if ($hasArchiveImport -and -not $hasSteamWorkshop) { 'ZIP/RAR Archive:' } else { 'Workshop ID / URL:' }) -X 12 -Y 42 -Width 180 -Height 20 -Color $textColor
    $rightPanel.Controls.Add($workshopLabel)

    $txtWorkshop = New-Object System.Windows.Forms.TextBox
    $txtWorkshop.Left = 12
    $txtWorkshop.Top = 66
    $txtWorkshop.Width = 318
    $rightPanel.Controls.Add($txtWorkshop)

    $btnAdd = New-UGSMGameHelperButton -Text $(if ($hasArchiveImport -and -not $hasSteamWorkshop) { 'Import ZIP/RAR Mod' } else { 'Add' }) -X 350 -Y 64 -Width $(if ($hasArchiveImport -and -not $hasSteamWorkshop) { 170 } else { 100 }) -Height 30 -BackColor $successColor
    $rightPanel.Controls.Add($btnAdd)
    if ($hasArchiveImport -and -not $hasSteamWorkshop) { $txtWorkshop.Visible = $false }

    $nextY = 102
    $txtModId = $null
    if ($promptModId) {
        $modLabel = New-UGSMGameHelperLabel -Text 'Project Zomboid Mod ID:' -X 12 -Y $nextY -Width 220 -Height 20 -Color $textColor
        $rightPanel.Controls.Add($modLabel)
        $txtModId = New-Object System.Windows.Forms.TextBox
        $txtModId.Left = 12
        $txtModId.Top = ($nextY + 24)
        $txtModId.Width = 318
        $rightPanel.Controls.Add($txtModId)
        $nextY += 62
    }

    $txtMaps = $null
    if ($promptMapFolders) {
        $mapLabel = New-UGSMGameHelperLabel -Text 'Map folders, semicolon separated:' -X 12 -Y $nextY -Width 260 -Height 20 -Color $textColor
        $rightPanel.Controls.Add($mapLabel)
        $txtMaps = New-Object System.Windows.Forms.TextBox
        $txtMaps.Left = 12
        $txtMaps.Top = ($nextY + 24)
        $txtMaps.Width = 438
        $rightPanel.Controls.Add($txtMaps)
        $nextY += 62
    }

    $serverSide = New-Object System.Windows.Forms.CheckBox
    $serverSide.Text = 'Server-Side Mod (copy PBOs to Root)'
    $serverSide.Left = 12
    $serverSide.Top = $nextY
    $serverSide.Width = 320
    $serverSide.ForeColor = $textColor
    $serverSide.BackColor = [System.Drawing.Color]::Transparent
    $serverSide.Enabled = $false
    $rightPanel.Controls.Add($serverSide)

    $utilityTop = $nextY + 46
    $utilityTitle = New-UGSMGameHelperLabel -Text 'Utility Actions' -X 12 -Y $utilityTop -Width 220 -Height 22 -Color $textColor -Bold
    $rightPanel.Controls.Add($utilityTitle)

    $btnDownload = New-UGSMGameHelperButton -Text 'Download / Update All Mods' -X 12 -Y ($utilityTop + 34) -Width 360 -Height 34 -BackColor $successColor
    $btnRefresh = New-UGSMGameHelperButton -Text 'Refresh Active Mod Summary' -X 12 -Y ($utilityTop + 78) -Width 360 -Height 34 -BackColor $buttonColor
    $btnOpenState = New-UGSMGameHelperButton -Text 'Open Instance Mod State' -X 392 -Y ($utilityTop + 34) -Width 260 -Height 34 -BackColor $buttonColor
    $btnNotice = New-UGSMGameHelperButton -Text 'Show Mod Safety Notice' -X 392 -Y ($utilityTop + 78) -Width 260 -Height 34 -BackColor $buttonColor

    $btnDownload.Enabled = $canDownload
    $btnRefresh.Enabled = $canRefresh
    $btnOpenState.Enabled = $canOpenManifest

    $rightPanel.Controls.Add($btnDownload)
    $rightPanel.Controls.Add($btnRefresh)
    $rightPanel.Controls.Add($btnOpenState)
    $rightPanel.Controls.Add($btnNotice)

    $hintText = $(if ($hasArchiveImport -and -not $hasSteamWorkshop) { 'Archive mods are third-party files. For shared mod folders, installing or removing a mod affects every instance that uses the same game binaries.' } else { 'Workshop files stay in the shared Steam Workshop cache. The instance stores only active references, load order, and game-specific mod metadata.' })
    $hint = New-UGSMGameHelperLabel -Text $hintText -X 12 -Y ($utilityTop + 126) -Width 660 -Height 44 -Color $mutedColor
    $rightPanel.Controls.Add($hint)

    $script:UGSM_SharedMods_LastManifest = $null

    $refreshList = {
        param([int]$SelectIndex = -1)
        try {
            $manifest = Normalize-UGSMModsManifest -Manifest (Read-UGSMModsManifest -Instance $Instance -ModsDefinition $modsDef) -Instance $Instance -ModsDefinition $modsDef
            $script:UGSM_SharedMods_LastManifest = $manifest
            $list.Items.Clear()
            $active = @($manifest.Mods | Where-Object { $_ -and (-not $_.PSObject.Properties['Enabled'] -or [bool]$_.Enabled) } | Sort-Object LoadOrder)
            foreach ($mod in $active) {
                [void]$list.Items.Add((Get-UGSMGameHelperModDisplayText -Mod $mod))
            }
            if ($list.Items.Count -eq 0) {
                [void]$list.Items.Add('No active mods are configured for this server profile yet.')
            }
            if ($SelectIndex -ge 0 -and $SelectIndex -lt $list.Items.Count) { $list.SelectedIndex = $SelectIndex }
            if ($statusControl) { $statusControl.Text = 'Active mod list refreshed.' }
        }
        catch {
            if ($statusControl) { $statusControl.Text = 'Failed to refresh mod list: ' + $_.Exception.Message }
        }
    }.GetNewClosure()

    $getSelectedActiveMod = {
        try {
            if ($list.SelectedIndex -lt 0) { return $null }
            $manifest = Normalize-UGSMModsManifest -Manifest (Read-UGSMModsManifest -Instance $Instance -ModsDefinition $modsDef) -Instance $Instance -ModsDefinition $modsDef
            $active = @($manifest.Mods | Where-Object { $_ -and (-not $_.PSObject.Properties['Enabled'] -or [bool]$_.Enabled) } | Sort-Object LoadOrder)
            if ($list.SelectedIndex -ge $active.Count) { return $null }
            return $active[$list.SelectedIndex]
        }
        catch { return $null }
    }.GetNewClosure()

    $moveSelected = {
        param([int]$Delta)
        try {
            if (-not $hasLoadOrder) { return }
            $selectedIndex = $list.SelectedIndex
            if ($selectedIndex -lt 0) { if ($statusControl) { $statusControl.Text = 'Select a mod first.' }; return }

            $manifest = Normalize-UGSMModsManifest -Manifest (Read-UGSMModsManifest -Instance $Instance -ModsDefinition $modsDef) -Instance $Instance -ModsDefinition $modsDef
            $active = @($manifest.Mods | Where-Object { $_ -and (-not $_.PSObject.Properties['Enabled'] -or [bool]$_.Enabled) } | Sort-Object LoadOrder)
            if ($selectedIndex -ge $active.Count) { return }

            $targetIndex = $selectedIndex + $Delta
            if ($targetIndex -lt 0 -or $targetIndex -ge $active.Count) { return }

            $a = $active[$selectedIndex]
            $b = $active[$targetIndex]
            $oldA = [int]$a.LoadOrder
            $a.LoadOrder = [int]$b.LoadOrder
            $b.LoadOrder = $oldA

            $manifest.Mods = @($manifest.Mods | Sort-Object LoadOrder)
            $manifest.UpdatedAtUtc = [DateTime]::UtcNow.ToString('o')
            Save-UGSMModsManifest -Instance $Instance -Manifest $manifest -ModsDefinition $modsDef | Out-Null
            Invoke-UGSMGameHelperHook -ModsDefinition $modsDef -HookName 'AfterModsChanged' -Instance $Instance -Manifest $manifest | Out-Null
            & $refreshList $targetIndex
            if ($statusControl) { $statusControl.Text = 'Mod load order updated.' }
        }
        catch {
            if ($statusControl) { $statusControl.Text = 'Move mod failed: ' + $_.Exception.Message }
        }
    }.GetNewClosure()

    $btnAdd.Add_Click({
        try {
            if ($hasArchiveImport -and -not $hasSteamWorkshop) {
                $installHook = ''
                if ($modsDef -and $modsDef.PSObject.Properties['Hooks'] -and $modsDef.Hooks -and $modsDef.Hooks.PSObject.Properties['Install']) { $installHook = [string]$modsDef.Hooks.Install }
                if ([string]::IsNullOrWhiteSpace($installHook)) { throw 'Archive import is enabled, but this game module did not provide a Mods.Hooks.Install function.' }

                $dialog = New-Object System.Windows.Forms.OpenFileDialog
                $dialog.Title = 'Select ZIP/RAR mod archive'
                $dialog.Filter = 'Mod Archives (*.zip;*.rar)|*.zip;*.rar|All Files (*.*)|*.*'
                $dialog.Multiselect = $false
                if ($dialog.ShowDialog() -ne [System.Windows.Forms.DialogResult]::OK) { if ($statusControl) { $statusControl.Text = 'Archive mod import cancelled.' }; return }

                $ext = [System.IO.Path]::GetExtension($dialog.FileName).ToLowerInvariant()
                if ($ext -notin @('.zip','.rar')) { throw ('Unsupported archive extension: ' + $ext) }

                $notice = Get-UGSMModSafetyNoticeText -ModsDefinition $modsDef
                if ([string]::IsNullOrWhiteSpace($notice)) { $notice = 'UGSM can install ZIP/RAR files you provide, but cannot verify third-party mod safety or compatibility. Continue only if this file came from a trusted source.' }
                $choice = [System.Windows.Forms.MessageBox]::Show($notice + "`r`n`r`nInstall this archive now?", 'UGSM Mod Safety Notice', [System.Windows.Forms.MessageBoxButtons]::YesNo, [System.Windows.Forms.MessageBoxIcon]::Warning)
                if ($choice -ne [System.Windows.Forms.DialogResult]::Yes) { if ($statusControl) { $statusControl.Text = 'Archive mod import cancelled.' }; return }

                if ($statusControl) { $statusControl.Text = 'Importing archive mod...' }
                $manifest = Normalize-UGSMModsManifest -Manifest (Read-UGSMModsManifest -Instance $Instance -ModsDefinition $modsDef) -Instance $Instance -ModsDefinition $modsDef
                $result = Invoke-UGSMGameHelperHook -ModsDefinition $modsDef -HookName 'Install' -Instance $Instance -Manifest $manifest -ArchivePath $dialog.FileName
                if ($result -and $result.PSObject.Properties['Manifest'] -and $result.Manifest) {
                    Save-UGSMModsManifest -Instance $Instance -Manifest $result.Manifest -ModsDefinition $modsDef | Out-Null
                }
                & $refreshList -1
                $count = if ($result -and $result.PSObject.Properties['Imported']) { @($result.Imported).Count } else { 0 }
                if ($statusControl) { $statusControl.Text = 'Archive mod import complete. Imported=' + $count + '.' }
                return
            }

            if (-not $hasSteamWorkshop) {
                if ($statusControl) { $statusControl.Text = 'Steam Workshop support is disabled for this game.' }
                return
            }

            $input = [string]$txtWorkshop.Text
            if ([string]::IsNullOrWhiteSpace($input)) {
                if ($statusControl) { $statusControl.Text = 'Enter a Workshop ID or URL first.' }
                return
            }

            $modId = ''
            if ($txtModId) { $modId = [string]$txtModId.Text }

            $mapFolders = @()
            if ($txtMaps -and -not [string]::IsNullOrWhiteSpace([string]$txtMaps.Text)) {
                $mapFolders = @(([string]$txtMaps.Text -split ';') | ForEach-Object { $_.Trim() } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
            }

            $result = Add-UGSMSteamWorkshopModToManifest -Instance $Instance -WorkshopInput $input -ModsDefinition $modsDef -ModId $modId -MapFolders $mapFolders
            $txtWorkshop.Text = ''
            if ($txtModId) { $txtModId.Text = '' }
            if ($txtMaps) { $txtMaps.Text = '' }

            & $refreshList -1
            if ($statusControl) { $statusControl.Text = [string]$result.Message }
        }
        catch {
            $prefix = if ($hasArchiveImport -and -not $hasSteamWorkshop) { 'Archive mod import failed: ' } else { 'Add Workshop mod failed: ' }
            Write-UGSMGameHelperLog -Category 'Mods' -Level 'ERROR' -Message $prefix -Exception $_.Exception
            if ($statusControl) { $statusControl.Text = $prefix + $_.Exception.Message }
        }
    }.GetNewClosure())

    $btnRemove.Add_Click({
        try {
            $selected = & $getSelectedActiveMod
            if (-not $selected) { if ($statusControl) { $statusControl.Text = 'Select a mod to remove.' }; return }
            $sourceType = if ($selected.PSObject.Properties['SourceType']) { [string]$selected.SourceType } else { 'SteamWorkshop' }
            if ($sourceType -ne 'SteamWorkshop') {
                $removeHook = ''
                if ($modsDef -and $modsDef.PSObject.Properties['Hooks'] -and $modsDef.Hooks -and $modsDef.Hooks.PSObject.Properties['Remove']) { $removeHook = [string]$modsDef.Hooks.Remove }
                if ([string]::IsNullOrWhiteSpace($removeHook)) { throw 'Archive removal is enabled, but this game module did not provide a Mods.Hooks.Remove function.' }
                $name = if ($selected.PSObject.Properties['FolderName'] -and -not [string]::IsNullOrWhiteSpace([string]$selected.FolderName)) { [string]$selected.FolderName } elseif ($selected.PSObject.Properties['Name']) { [string]$selected.Name } else { [string]$selected.Id }
                $choice = [System.Windows.Forms.MessageBox]::Show('Remove this UGSM-managed archive mod? For shared mod folders this may affect every instance using the same game install.' + "`r`n`r`n" + $name, 'Remove Archive Mod', [System.Windows.Forms.MessageBoxButtons]::YesNo, [System.Windows.Forms.MessageBoxIcon]::Warning)
                if ($choice -ne [System.Windows.Forms.DialogResult]::Yes) { if ($statusControl) { $statusControl.Text = 'Remove archive mod cancelled.' }; return }
                $manifest = Normalize-UGSMModsManifest -Manifest (Read-UGSMModsManifest -Instance $Instance -ModsDefinition $modsDef) -Instance $Instance -ModsDefinition $modsDef
                $result = Invoke-UGSMGameHelperHook -ModsDefinition $modsDef -HookName 'Remove' -Instance $Instance -Manifest $manifest -ModName $name
                & $refreshList -1
                if ($statusControl) { $statusControl.Text = 'Archive mod removed: ' + $name }
                return
            }

            $workshopId = ''
            if ($selected.PSObject.Properties['WorkshopId']) { $workshopId = [string]$selected.WorkshopId }
            if ([string]::IsNullOrWhiteSpace($workshopId)) { if ($statusControl) { $statusControl.Text = 'Selected mod has no Workshop ID.' }; return }

            $result = Remove-UGSMSteamWorkshopModFromManifest -Instance $Instance -WorkshopInput $workshopId -ModsDefinition $modsDef
            & $refreshList -1
            if ($statusControl) { $statusControl.Text = [string]$result.Message }
        }
        catch {
            if ($statusControl) { $statusControl.Text = 'Remove Workshop mod failed: ' + $_.Exception.Message }
        }
    }.GetNewClosure())

    $btnUp.Add_Click({ & $moveSelected -1 }.GetNewClosure())
    $btnDown.Add_Click({ & $moveSelected 1 }.GetNewClosure())

    $btnDownload.Add_Click({
        try {
            $result = Invoke-UGSMDownloadActiveSteamWorkshopMods -Instance $Instance -ModsDefinition $modsDef
            & $refreshList -1
            if ($statusControl) { $statusControl.Text = [string]$result.Message }
        }
        catch {
            Write-UGSMGameHelperLog -Category 'Mods' -Message ('Workshop download failed from shared Mods tab: ' + $_.Exception.Message) -Level 'Error'
            if ($statusControl) { $statusControl.Text = 'Workshop download failed: ' + $_.Exception.Message }
        }
    }.GetNewClosure())

    $btnRefresh.Add_Click({
        try {
            $manifest = Normalize-UGSMModsManifest -Manifest (Read-UGSMModsManifest -Instance $Instance -ModsDefinition $modsDef) -Instance $Instance -ModsDefinition $modsDef
            Invoke-UGSMGameHelperHook -ModsDefinition $modsDef -HookName 'AfterModsChanged' -Instance $Instance -Manifest $manifest | Out-Null
            & $refreshList -1
            if ($statusControl) { $statusControl.Text = 'Active mod summary refreshed and game sync hook ran.' }
        }
        catch {
            if ($statusControl) { $statusControl.Text = 'Refresh mod summary failed: ' + $_.Exception.Message }
        }
    }.GetNewClosure())

    $btnOpenState.Add_Click({
        try {
            $path = Resolve-UGSMModsManifestPath -Instance $Instance -ModsDefinition $modsDef
            if (-not [string]::IsNullOrWhiteSpace([string]$path)) {
                if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
                    $manifest = Normalize-UGSMModsManifest -Manifest (Read-UGSMModsManifest -Instance $Instance -ModsDefinition $modsDef) -Instance $Instance -ModsDefinition $modsDef
                    Save-UGSMModsManifest -Instance $Instance -Manifest $manifest -ModsDefinition $modsDef | Out-Null
                }
                Invoke-Item -LiteralPath $path
                if ($statusControl) { $statusControl.Text = 'Opened instance mod state.' }
            }
        }
        catch {
            if ($statusControl) { $statusControl.Text = 'Open mod state failed: ' + $_.Exception.Message }
        }
    }.GetNewClosure())

    $btnNotice.Add_Click({
        try {
            $notice = Get-UGSMModSafetyNoticeText -ModsDefinition $modsDef
            if ([string]::IsNullOrWhiteSpace($notice)) { $notice = 'Steam Workshop mods are third-party content. UGSM can configure/download them, but compatibility and safety depend on the source mod.' }
            [System.Windows.Forms.MessageBox]::Show($notice, 'UGSM Mod Safety Notice', [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information) | Out-Null
            if ($statusControl) { $statusControl.Text = 'Displayed mod safety notice.' }
        }
        catch {
            if ($statusControl) { $statusControl.Text = 'Show notice failed: ' + $_.Exception.Message }
        }
    }.GetNewClosure())

    & $refreshList -1
    return $root
}



# ============================================================
# Shared editor JSON helpers
# Reusable by game modules that expose schema fields with JsonPath.
# ============================================================
function Read-UGSMGameJsonFile {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Path,
        [AllowNull()][object]$DefaultValue = $null
    )

    if ([string]::IsNullOrWhiteSpace($Path) -or -not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        if ($PSBoundParameters.ContainsKey('DefaultValue')) { return $DefaultValue }
        return [pscustomobject]@{}
    }

    $raw = Get-Content -LiteralPath $Path -Raw -ErrorAction Stop
    if ([string]::IsNullOrWhiteSpace($raw)) {
        if ($PSBoundParameters.ContainsKey('DefaultValue')) { return $DefaultValue }
        return [pscustomobject]@{}
    }

    return ($raw | ConvertFrom-Json -ErrorAction Stop)
}

function Write-UGSMGameJsonFile {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][AllowNull()][object]$Value,
        [int]$Depth = 32
    )

    $dir = Split-Path -Parent $Path
    if (-not [string]::IsNullOrWhiteSpace($dir) -and -not (Test-Path -LiteralPath $dir -PathType Container)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }

    $json = $Value | ConvertTo-Json -Depth $Depth
    Set-Content -LiteralPath $Path -Value $json -Encoding UTF8
}

function Split-UGSMGameJsonPath {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$JsonPath)

    if ([string]::IsNullOrWhiteSpace($JsonPath)) { return @() }
    return @($JsonPath -split '\.' | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) })
}

function Get-UGSMGameJsonPathValue {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][AllowNull()][object]$Root,
        [Parameter(Mandatory)][string]$JsonPath,
        [AllowNull()][object]$DefaultValue = $null
    )

    if ($null -eq $Root) { return $DefaultValue }
    $current = $Root
    foreach ($segment in @(Split-UGSMGameJsonPath -JsonPath $JsonPath)) {
        if ($null -eq $current) { return $DefaultValue }
        if ($current -is [System.Collections.IDictionary]) {
            if (-not $current.Contains($segment)) { return $DefaultValue }
            $current = $current[$segment]
            continue
        }
        if (-not $current.PSObject.Properties[$segment]) { return $DefaultValue }
        $current = $current.$segment
    }
    if ($null -eq $current -and $PSBoundParameters.ContainsKey('DefaultValue')) { return $DefaultValue }
    return $current
}

function Set-UGSMGameJsonPathValue {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$Root,
        [Parameter(Mandatory)][string]$JsonPath,
        [AllowNull()][object]$Value
    )

    $segments = @(Split-UGSMGameJsonPath -JsonPath $JsonPath)
    if ($segments.Count -eq 0) { return $Root }

    $current = $Root
    for ($i = 0; $i -lt ($segments.Count - 1); $i++) {
        $segment = [string]$segments[$i]
        if ($current -is [System.Collections.IDictionary]) {
            if (-not $current.Contains($segment) -or $null -eq $current[$segment]) { $current[$segment] = [pscustomobject]@{} }
            $current = $current[$segment]
            continue
        }
        if (-not $current.PSObject.Properties[$segment] -or $null -eq $current.$segment) {
            Add-Member -InputObject $current -MemberType NoteProperty -Name $segment -Value ([pscustomobject]@{}) -Force
        }
        $current = $current.$segment
    }

    $leaf = [string]$segments[-1]
    if ($current -is [System.Collections.IDictionary]) { $current[$leaf] = $Value }
    elseif ($current.PSObject.Properties[$leaf]) { $current.$leaf = $Value }
    else { Add-Member -InputObject $current -MemberType NoteProperty -Name $leaf -Value $Value -Force }
    return $Root
}

function Set-UGSMGameJsonFilePathValue {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$JsonPath,
        [AllowNull()][object]$Value,
        [int]$Depth = 32
    )

    $root = Read-UGSMGameJsonFile -Path $Path
    $root = Set-UGSMGameJsonPathValue -Root $root -JsonPath $JsonPath -Value $Value
    Write-UGSMGameJsonFile -Path $Path -Value $root -Depth $Depth
    return $root
}

# ============================================================
# Rust uMod / Oxide helpers
# ============================================================
function Get-UGSMRustOxidePaths {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$Instance,
        [AllowNull()][object]$ModsDefinition = $null
    )

    $installPath = ''
    if ($Instance.PSObject.Properties['InstallPath']) { $installPath = [string]$Instance.InstallPath }
    if ([string]::IsNullOrWhiteSpace($installPath)) { throw 'Rust install path is missing from the selected instance.' }

    $pluginRelative = 'oxide\plugins'
    if ($ModsDefinition -and $ModsDefinition.PSObject.Properties['Framework'] -and $ModsDefinition.Framework -and $ModsDefinition.Framework.PSObject.Properties['PluginFolderRelative'] -and -not [string]::IsNullOrWhiteSpace([string]$ModsDefinition.Framework.PluginFolderRelative)) {
        $pluginRelative = [string]$ModsDefinition.Framework.PluginFolderRelative
    }

    $pluginFolder = Join-Path $installPath $pluginRelative
    $managedFolder = Join-Path $installPath 'RustDedicated_Data\Managed'
    return [pscustomobject]@{
        InstallPath   = $installPath
        ManagedFolder = $managedFolder
        PluginFolder  = $pluginFolder
        OxideRoot     = Join-Path $installPath 'oxide'
        MarkerDll     = Join-Path $managedFolder 'Oxide.Rust.dll'
    }
}

function Test-UGSMRustOxideFrameworkInstalled {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$Instance,
        [AllowNull()][object]$ModsDefinition = $null,
        [AllowNull()][object]$Manifest = $null
    )

    $paths = Get-UGSMRustOxidePaths -Instance $Instance -ModsDefinition $ModsDefinition
    $installed = ((Test-Path -LiteralPath $paths.MarkerDll -PathType Leaf) -or (Test-Path -LiteralPath $paths.OxideRoot -PathType Container))
    $plugins = @()
    if (Test-Path -LiteralPath $paths.PluginFolder -PathType Container) {
        $plugins = @(Get-ChildItem -LiteralPath $paths.PluginFolder -Filter '*.cs' -File -ErrorAction SilentlyContinue | Sort-Object Name | ForEach-Object { $_.Name })
    }
    return [pscustomobject]@{
        Installed    = [bool]$installed
        PluginFolder = [string]$paths.PluginFolder
        Plugins      = $plugins
        StatusText   = $(if ($installed) { 'uMod / Oxide is installed.' } else { 'uMod / Oxide is not installed yet.' })
    }
}

function Install-UGSMRustOxideFramework {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$Instance,
        [AllowNull()][object]$ModsDefinition = $null,
        [AllowNull()][object]$Manifest = $null
    )

    Add-Type -AssemblyName System.Windows.Forms -ErrorAction SilentlyContinue | Out-Null
    $choice = [System.Windows.Forms.MessageBox]::Show('Install or update uMod / Oxide for Rust? This modifies the shared Rust server binaries. Third-party frameworks and plugins can affect stability, security, saves, and gameplay.', 'Install uMod / Oxide', [System.Windows.Forms.MessageBoxButtons]::YesNo, [System.Windows.Forms.MessageBoxIcon]::Warning)
    if ($choice -ne [System.Windows.Forms.DialogResult]::Yes) { return [pscustomobject]@{ Cancelled=$true } }

    $paths = Get-UGSMRustOxidePaths -Instance $Instance -ModsDefinition $ModsDefinition
    if (-not (Test-Path -LiteralPath $paths.InstallPath -PathType Container)) { throw 'Rust install folder does not exist.' }

    $url = 'https://umod.org/games/rust/download/develop'
    if ($ModsDefinition -and $ModsDefinition.PSObject.Properties['Framework'] -and $ModsDefinition.Framework -and $ModsDefinition.Framework.PSObject.Properties['DownloadUrl'] -and -not [string]::IsNullOrWhiteSpace([string]$ModsDefinition.Framework.DownloadUrl)) {
        $url = [string]$ModsDefinition.Framework.DownloadUrl
    }

    $tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('UGSM_Rust_Oxide_' + [Guid]::NewGuid().ToString('N'))
    $zipPath = Join-Path $tempRoot 'oxide-rust.zip'
    $extractPath = Join-Path $tempRoot 'extract'
    New-Item -ItemType Directory -Force -Path $tempRoot, $extractPath | Out-Null
    try {
        Invoke-WebRequest -Uri $url -OutFile $zipPath -UseBasicParsing -ErrorAction Stop
        Expand-Archive -LiteralPath $zipPath -DestinationPath $extractPath -Force
        Copy-Item -LiteralPath (Join-Path $extractPath '*') -Destination $paths.InstallPath -Recurse -Force
        New-Item -ItemType Directory -Force -Path $paths.PluginFolder | Out-Null
        if (Get-Command -Name Write-UGSMLog -ErrorAction SilentlyContinue) { Write-UGSMLog -Message 'Rust uMod/Oxide framework installed or updated.' -Level 'Info' }
        return (Test-UGSMRustOxideFrameworkInstalled -Instance $Instance -ModsDefinition $ModsDefinition)
    }
    finally {
        Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}

function Open-UGSMRustOxidePluginsFolder {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$Instance,
        [AllowNull()][object]$ModsDefinition = $null,
        [AllowNull()][object]$Manifest = $null
    )

    $paths = Get-UGSMRustOxidePaths -Instance $Instance -ModsDefinition $ModsDefinition
    New-Item -ItemType Directory -Force -Path $paths.PluginFolder | Out-Null
    Start-Process -FilePath explorer.exe -ArgumentList ('"{0}"' -f $paths.PluginFolder) | Out-Null
    return [pscustomobject]@{ PluginFolder = [string]$paths.PluginFolder }
}

function Add-UGSMRustOxidePlugin {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$Instance,
        [AllowNull()][object]$ModsDefinition = $null,
        [AllowNull()][object]$Manifest = $null,
        [string]$ArchivePath = ''
    )

    if ([string]::IsNullOrWhiteSpace($ArchivePath) -or -not (Test-Path -LiteralPath $ArchivePath -PathType Leaf)) { throw 'Plugin file was not found.' }
    if ([System.IO.Path]::GetExtension($ArchivePath).ToLowerInvariant() -ne '.cs') { throw 'Rust Oxide plugins must be .cs files.' }
    Add-Type -AssemblyName System.Windows.Forms -ErrorAction SilentlyContinue | Out-Null
    $choice = [System.Windows.Forms.MessageBox]::Show('Add this third-party Rust plugin? Plugins can affect stability, security, saves, and gameplay. Only install plugins from trusted sources.', 'Add Rust Plugin', [System.Windows.Forms.MessageBoxButtons]::YesNo, [System.Windows.Forms.MessageBoxIcon]::Warning)
    if ($choice -ne [System.Windows.Forms.DialogResult]::Yes) { return [pscustomobject]@{ Cancelled=$true } }

    $paths = Get-UGSMRustOxidePaths -Instance $Instance -ModsDefinition $ModsDefinition
    New-Item -ItemType Directory -Force -Path $paths.PluginFolder | Out-Null
    $dest = Join-Path $paths.PluginFolder ([System.IO.Path]::GetFileName($ArchivePath))
    Copy-Item -LiteralPath $ArchivePath -Destination $dest -Force
    if (Get-Command -Name Write-UGSMLog -ErrorAction SilentlyContinue) { Write-UGSMLog -Message 'Rust Oxide plugin added.' -Level 'Info' }
    return (Test-UGSMRustOxideFrameworkInstalled -Instance $Instance -ModsDefinition $ModsDefinition)
}

function Remove-UGSMRustOxidePlugin {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$Instance,
        [AllowNull()][object]$ModsDefinition = $null,
        [AllowNull()][object]$Manifest = $null,
        [string]$ModName = ''
    )

    if ([string]::IsNullOrWhiteSpace($ModName)) { throw 'Plugin name is required.' }
    $safeName = [System.IO.Path]::GetFileName($ModName)
    if ([System.IO.Path]::GetExtension($safeName).ToLowerInvariant() -ne '.cs') { throw 'Only .cs plugin files can be removed from this panel.' }
    $paths = Get-UGSMRustOxidePaths -Instance $Instance -ModsDefinition $ModsDefinition
    $target = Join-Path $paths.PluginFolder $safeName
    if (Test-Path -LiteralPath $target -PathType Leaf) { Remove-Item -LiteralPath $target -Force }
    if (Get-Command -Name Write-UGSMLog -ErrorAction SilentlyContinue) { Write-UGSMLog -Message 'Rust Oxide plugin removed.' -Level 'Info' }
    return (Test-UGSMRustOxideFrameworkInstalled -Instance $Instance -ModsDefinition $ModsDefinition)
}


