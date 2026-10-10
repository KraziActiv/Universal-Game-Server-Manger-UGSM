# ============================================================
# UGSM DayZ File / Instance Storage Service
# Shared DayZ file path, instance storage, backup, and cache helpers.
# Keep DayZ UI tabs thin; put shared file responsibilities here.
# ============================================================

function Get-UGSMDayZAppDataRoot {
    [CmdletBinding()]
    param()

    if (Get-Command -Name Get-UGSMAppDataRoot -ErrorAction SilentlyContinue) {
        try {
            $root = [string](Get-UGSMAppDataRoot)
            if (-not [string]::IsNullOrWhiteSpace($root)) { return $root }
        }
        catch { }
    }

    return (Join-Path $env:LOCALAPPDATA 'UGSM')
}

function Get-UGSMDayZInstancesRoot {
    [CmdletBinding()]
    param()

    return (Join-Path (Join-Path (Get-UGSMDayZAppDataRoot) 'Instances') 'DayZ')
}

function ConvertTo-UGSMDayZSafePathName {
    [CmdletBinding()]
    param(
        [AllowNull()][string]$Name,
        [string]$Fallback = 'Instance'
    )

    $value = [string]$Name
    if ([string]::IsNullOrWhiteSpace($value)) { $value = [string]$Fallback }

    foreach ($ch in [System.IO.Path]::GetInvalidFileNameChars()) {
        $value = $value.Replace([string]$ch, '_')
    }

    $value = $value.Trim()
    if ([string]::IsNullOrWhiteSpace($value)) { $value = [string]$Fallback }
    return $value
}

function Get-UGSMDayZInstanceIdentity {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$Instance
    )

    $id = ''
    $name = ''

    if ($Instance.PSObject.Properties.Name -contains 'Id') { $id = [string]$Instance.Id }
    if ($Instance.PSObject.Properties.Name -contains 'Name') { $name = [string]$Instance.Name }

    if ([string]::IsNullOrWhiteSpace($id)) { $id = $name }
    if ([string]::IsNullOrWhiteSpace($name)) { $name = $id }

    $folderName = ConvertTo-UGSMDayZSafePathName -Name $name -Fallback $id

    return [pscustomobject]@{
        Id         = $id
        Name       = $name
        FolderName = $folderName
    }
}

function Get-UGSMDayZInstanceFolderPath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$Instance
    )

    $identity = Get-UGSMDayZInstanceIdentity -Instance $Instance
    return (Join-Path (Get-UGSMDayZInstancesRoot) $identity.FolderName)
}

function Get-UGSMDayZInstanceJsonPath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$Instance
    )

    return (Join-Path (Get-UGSMDayZInstanceFolderPath -Instance $Instance) 'instance.json')
}

function Get-UGSMDayZLegacyInstanceJsonPath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$Instance
    )

    $identity = Get-UGSMDayZInstanceIdentity -Instance $Instance
    $root = Get-UGSMDayZInstancesRoot

    $candidates = @()
    if (-not [string]::IsNullOrWhiteSpace($identity.Id)) {
        $candidates += (Join-Path $root (('{0}.json' -f (ConvertTo-UGSMDayZSafePathName -Name $identity.Id -Fallback $identity.FolderName))))
    }
    if (-not [string]::IsNullOrWhiteSpace($identity.Name)) {
        $candidates += (Join-Path $root (('{0}.json' -f (ConvertTo-UGSMDayZSafePathName -Name $identity.Name -Fallback $identity.FolderName))))
    }

    foreach ($propertyName in @('DefinitionPath', 'JsonPath', 'ConfigPath', 'InstancePath', 'Path', 'FilePath')) {
        if ($Instance.PSObject.Properties.Name -contains $propertyName) {
            $value = [string]$Instance.$propertyName
            if (-not [string]::IsNullOrWhiteSpace($value) -and $value -like '*.json') {
                $candidates += $value
            }
        }
    }

    foreach ($candidate in @($candidates | Select-Object -Unique)) {
        if (-not [string]::IsNullOrWhiteSpace($candidate) -and (Test-Path -LiteralPath $candidate -PathType Leaf)) {
            return [string]$candidate
        }
    }

    return $null
}

function Set-UGSMDayZInstanceDefinitionPathProperties {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$Instance,
        [Parameter(Mandatory)][string]$Path
    )

    # DefinitionPath and JsonPath point to the JSON definition file.
    # InstancePath points to the instance folder that owns cache/backups/generated/logs.
    $definitionPath = [string]$Path
    $folderPath = Split-Path -Parent $definitionPath

    $values = @{
        DefinitionPath = $definitionPath
        JsonPath       = $definitionPath
        InstancePath   = [string]$folderPath
    }

    foreach ($entry in $values.GetEnumerator()) {
        $propertyName = [string]$entry.Key
        $propertyValue = [string]$entry.Value
        if ($Instance.PSObject.Properties.Name -contains $propertyName) {
            $Instance.$propertyName = $propertyValue
        }
        else {
            try { $Instance | Add-Member -NotePropertyName $propertyName -NotePropertyValue $propertyValue -Force } catch { }
        }
    }
}

function Initialize-UGSMDayZInstanceStorage {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$Instance,
        [switch]$MigrateLegacyJson
    )

    $folder = Get-UGSMDayZInstanceFolderPath -Instance $Instance
    $paths = [ordered]@{
        InstanceFolder       = $folder
        InstanceJsonPath     = (Join-Path $folder 'instance.json')
        CacheFolder          = (Join-Path $folder 'cache')
        BackupsFolder        = (Join-Path $folder 'backups')
        GeneratedFolder      = (Join-Path $folder 'generated')
        LogsFolder           = (Join-Path $folder 'logs')
        ClassNamesCachePath  = (Join-Path (Join-Path $folder 'cache') 'classnames.json')
        ActiveModsCachePath  = (Join-Path (Join-Path $folder 'cache') 'active-mods.json')
        FilesIndexPath       = (Join-Path (Join-Path $folder 'cache') 'files-index.json')
        MergePlanPath        = (Join-Path (Join-Path $folder 'cache') 'merge-plan.json')
        ContributionsPath    = (Join-Path (Join-Path $folder 'cache') 'mod-contributions.json')
    }

    foreach ($key in @('InstanceFolder', 'CacheFolder', 'BackupsFolder', 'GeneratedFolder', 'LogsFolder')) {
        $dir = [string]$paths[$key]
        if (-not (Test-Path -LiteralPath $dir -PathType Container)) {
            New-Item -ItemType Directory -Path $dir -Force | Out-Null
        }
    }

    if ($MigrateLegacyJson -and -not (Test-Path -LiteralPath $paths.InstanceJsonPath -PathType Leaf)) {
        $legacyPath = Get-UGSMDayZLegacyInstanceJsonPath -Instance $Instance
        if (-not [string]::IsNullOrWhiteSpace($legacyPath) -and (Test-Path -LiteralPath $legacyPath -PathType Leaf)) {
            Copy-Item -LiteralPath $legacyPath -Destination $paths.InstanceJsonPath -Force
            try {
                $notePath = Join-Path $paths.LogsFolder 'migration.log'
                $line = '[{0}] Copied legacy instance JSON from {1} to {2}' -f (Get-Date).ToString('s'), $legacyPath, $paths.InstanceJsonPath
                Add-Content -LiteralPath $notePath -Value $line -Encoding UTF8
            }
            catch { }
        }
    }

    Set-UGSMDayZInstanceDefinitionPathProperties -Instance $Instance -Path ([string]$paths.InstanceJsonPath)

    return [pscustomobject]$paths
}

function Get-UGSMDayZInstanceStoragePaths {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$Instance,
        [switch]$Create
    )

    if ($Create) {
        return (Initialize-UGSMDayZInstanceStorage -Instance $Instance -MigrateLegacyJson)
    }

    $folder = Get-UGSMDayZInstanceFolderPath -Instance $Instance
    return [pscustomobject]@{
        InstanceFolder       = $folder
        InstanceJsonPath     = (Join-Path $folder 'instance.json')
        CacheFolder          = (Join-Path $folder 'cache')
        BackupsFolder        = (Join-Path $folder 'backups')
        GeneratedFolder      = (Join-Path $folder 'generated')
        LogsFolder           = (Join-Path $folder 'logs')
        ClassNamesCachePath  = (Join-Path (Join-Path $folder 'cache') 'classnames.json')
        ActiveModsCachePath  = (Join-Path (Join-Path $folder 'cache') 'active-mods.json')
        FilesIndexPath       = (Join-Path (Join-Path $folder 'cache') 'files-index.json')
        MergePlanPath        = (Join-Path (Join-Path $folder 'cache') 'merge-plan.json')
        ContributionsPath    = (Join-Path (Join-Path $folder 'cache') 'mod-contributions.json')
    }
}

function Get-UGSMDayZInstanceDefinitionPath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$Instance,
        [switch]$Create
    )

    $paths = Get-UGSMDayZInstanceStoragePaths -Instance $Instance -Create:$Create
    if ($Create) { return [string]$paths.InstanceJsonPath }
    if (Test-Path -LiteralPath $paths.InstanceJsonPath -PathType Leaf) { return [string]$paths.InstanceJsonPath }

    $legacyPath = Get-UGSMDayZLegacyInstanceJsonPath -Instance $Instance
    if (-not [string]::IsNullOrWhiteSpace($legacyPath)) { return [string]$legacyPath }

    return [string]$paths.InstanceJsonPath
}

function Save-UGSMDayZInstanceJson {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$Instance
    )

    $paths = Initialize-UGSMDayZInstanceStorage -Instance $Instance -MigrateLegacyJson
    $json = $Instance | ConvertTo-Json -Depth 32
    Set-Content -LiteralPath $paths.InstanceJsonPath -Value $json -Encoding UTF8 -ErrorAction Stop
    return [string]$paths.InstanceJsonPath
}

function Get-UGSMDayZLiveJsonFiles {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Path,
        [switch]$Recurse
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Container)) { return @() }

    return @(
        Get-ChildItem -LiteralPath $Path -File -Filter '*.json' -Recurse:$Recurse -ErrorAction SilentlyContinue |
            Where-Object {
                $_.Name -notmatch '(?i)\.bak(\.|$)' -and
                $_.FullName -notmatch '(?i)[\\/]backups[\\/]'
            }
    )
}

function Backup-UGSMDayZLiveFileOnce {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$Instance,
        [Parameter(Mandatory)][string]$Path,
        [switch]$Overwrite
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $null }

    $paths = Initialize-UGSMDayZInstanceStorage -Instance $Instance -MigrateLegacyJson
    $safeLeaf = ConvertTo-UGSMDayZSafePathName -Name (Split-Path -Leaf $Path) -Fallback 'file'
    $backupPath = Join-Path $paths.BackupsFolder ($safeLeaf + '.bak')

    if ($Overwrite -or -not (Test-Path -LiteralPath $backupPath -PathType Leaf)) {
        Copy-Item -LiteralPath $Path -Destination $backupPath -Force
    }

    return [string]$backupPath
}

# ============================================================
# DayZ Instance Scanner / Cache Builder
# First pass: read-only scan. Builds cache files only; does not merge or modify live server files.
# ============================================================

function Write-UGSMDayZCacheJson {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][object]$Data,
        [int]$Depth = 48
    )

    $parent = Split-Path -Parent $Path
    if (-not [string]::IsNullOrWhiteSpace($parent) -and -not (Test-Path -LiteralPath $parent -PathType Container)) {
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
    }

    $json = $Data | ConvertTo-Json -Depth $Depth
    Set-Content -LiteralPath $Path -Value $json -Encoding UTF8 -ErrorAction Stop
    return [string]$Path
}

function Get-UGSMDayZEnabledMods {
    [CmdletBinding()]
    param([Parameter(Mandatory)][object]$Instance)

    $mods = @()
    if ($Instance.PSObject.Properties.Name -contains 'Mods' -and $Instance.Mods) { $mods = @($Instance.Mods) }

    $stateById = @{}
    if ($Instance.PSObject.Properties.Name -contains 'ModStates' -and $Instance.ModStates) {
        foreach ($state in @($Instance.ModStates)) {
            $stateId = if ($state.PSObject.Properties.Name -contains 'Id') { [string]$state.Id } else { '' }
            if (-not [string]::IsNullOrWhiteSpace($stateId)) { $stateById[$stateId] = $state }
        }
    }

    $enabled = New-Object System.Collections.Generic.List[object]
    foreach ($mod in $mods) {
        $id = if ($mod.PSObject.Properties.Name -contains 'Id') { [string]$mod.Id } else { '' }
        $isEnabled = $true
        if ($mod.PSObject.Properties.Name -contains 'Enabled') { try { $isEnabled = [bool]$mod.Enabled } catch { $isEnabled = $true } }
        if (-not [string]::IsNullOrWhiteSpace($id) -and $stateById.ContainsKey($id)) {
            $state = $stateById[$id]
            if ($state.PSObject.Properties.Name -contains 'Enabled') { try { $isEnabled = [bool]$state.Enabled } catch { } }
        }
        if ($isEnabled) { [void]$enabled.Add($mod) }
    }
    return @($enabled)
}

function Get-UGSMDayZModSourcePathCandidates {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$Instance,
        [Parameter(Mandatory)][object]$Mod
    )

    $candidates = New-Object System.Collections.Generic.List[string]
    foreach ($propertyName in @('SourcePath', 'Path', 'InstallPath')) {
        if ($Mod.PSObject.Properties.Name -contains $propertyName) {
            $value = [string]$Mod.$propertyName
            if (-not [string]::IsNullOrWhiteSpace($value)) { [void]$candidates.Add($value) }
        }
    }

    $folderName = if ($Mod.PSObject.Properties.Name -contains 'FolderName') { [string]$Mod.FolderName } else { '' }
    $id = if ($Mod.PSObject.Properties.Name -contains 'Id') { [string]$Mod.Id } else { '' }

    if ($Instance.PSObject.Properties.Name -contains 'InstallPath' -and -not [string]::IsNullOrWhiteSpace([string]$Instance.InstallPath)) {
        $installPath = [string]$Instance.InstallPath
        $serverRoot = Split-Path -Parent $installPath
        if (-not [string]::IsNullOrWhiteSpace($folderName)) {
            [void]$candidates.Add((Join-Path $installPath $folderName))
            if (-not [string]::IsNullOrWhiteSpace($serverRoot)) { [void]$candidates.Add((Join-Path $serverRoot $folderName)) }
        }
        if (-not [string]::IsNullOrWhiteSpace($id)) {
            $steamapps = $null
            $cursor = $installPath
            for ($i = 0; $i -lt 8 -and -not [string]::IsNullOrWhiteSpace($cursor); $i++) {
                if ((Split-Path -Leaf $cursor) -ieq 'steamapps') { $steamapps = $cursor; break }
                $cursor = Split-Path -Parent $cursor
            }
            if (-not [string]::IsNullOrWhiteSpace($steamapps)) {
                [void]$candidates.Add((Join-Path (Join-Path (Join-Path $steamapps 'workshop') 'content') (Join-Path '221100' $id)))
            }
        }
    }

    return @($candidates | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -Unique)
}

function Find-UGSMDayZModConfigFiles {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$Instance,
        [Parameter(Mandatory)][object]$Mod
    )

    $id = if ($Mod.PSObject.Properties.Name -contains 'Id') { [string]$Mod.Id } else { '' }
    $name = if ($Mod.PSObject.Properties.Name -contains 'Name') { [string]$Mod.Name } else { $id }
    $folderName = if ($Mod.PSObject.Properties.Name -contains 'FolderName') { [string]$Mod.FolderName } else { '' }
    $loadOrder = if ($Mod.PSObject.Properties.Name -contains 'LoadOrder') { $Mod.LoadOrder } else { $null }

    $sourcePath = $null
    foreach ($candidate in Get-UGSMDayZModSourcePathCandidates -Instance $Instance -Mod $Mod) {
        if (Test-Path -LiteralPath $candidate -PathType Container) { $sourcePath = [string]$candidate; break }
    }

    $warnings = New-Object System.Collections.Generic.List[string]
    $files = New-Object System.Collections.Generic.List[object]

    if ([string]::IsNullOrWhiteSpace($sourcePath)) {
        [void]$warnings.Add(('SourcePath missing or not found for mod {0} ({1}).' -f $name, $id))
    }
    else {
        $wantedNames = @('types.xml','events.xml','cfgspawnabletypes.xml','cfgeventspawns.xml','cfgvehicles.xml')
        try {
            $xmlFiles = Get-ChildItem -LiteralPath $sourcePath -Recurse -File -ErrorAction SilentlyContinue |
                Where-Object { $wantedNames -contains $_.Name.ToLowerInvariant() }
            foreach ($file in @($xmlFiles)) {
                $fileNameLower = $file.Name.ToLowerInvariant()
                $kind = if ($fileNameLower -eq 'types.xml') { 'types' }
                        elseif ($fileNameLower -eq 'events.xml') { 'events' }
                        elseif ($fileNameLower -eq 'cfgspawnabletypes.xml') { 'cfgspawnabletypes' }
                        elseif ($fileNameLower -eq 'cfgeventspawns.xml') { 'cfgeventspawns' }
                        elseif ($fileNameLower -eq 'cfgeventgroups.xml') { 'cfgeventgroups' }
                        elseif ($fileNameLower -eq 'cfgvehicles.xml') { 'cfgvehicles' }
                        else { 'xml' }
                [void]$files.Add([pscustomobject]@{
                    ModId = $id; ModName = $name; FolderName = $folderName; LoadOrder = $loadOrder
                    Kind = $kind; FileName = $file.Name; Path = $file.FullName
                    RelativePath = $file.FullName.Substring($sourcePath.Length).TrimStart('\','/')
                    Length = $file.Length; LastWriteTime = $file.LastWriteTime.ToString('s')
                })
            }
        }
        catch { [void]$warnings.Add(('Failed scanning files for mod {0}: {1}' -f $name, [string]$_.Exception.Message)) }
    }

    return [pscustomobject]@{ Id = $id; Name = $name; FolderName = $folderName; SourcePath = [string]$sourcePath; LoadOrder = $loadOrder; Enabled = $true; Files = @($files); Warnings = @($warnings) }
}

function Add-UGSMDayZClassNameResult {
    [CmdletBinding()]
    param(
        [object]$List,
        [hashtable]$Seen,
        [AllowEmptyString()][string]$ClassName = '',
        [Parameter(Mandatory)][string]$Kind,
        [Parameter(Mandatory)][object]$FileRecord,
        [Parameter(Mandatory)][string]$SourceField
    )

    if ($null -eq $List) { return }
    if ($null -eq $Seen) { $Seen = @{} }
    if ([string]::IsNullOrWhiteSpace($ClassName)) { return }

    $clean = ([string]$ClassName).Trim()
    if ([string]::IsNullOrWhiteSpace($clean)) { return }

    # Avoid bad dropdown entries from generic config values.
    if ($clean -match '^[-+]?\d+(\.\d+)?$') { return }
    if ($clean.Length -lt 2) { return }

    $modId = ''
    $modName = ''
    $fileName = ''
    $filePath = ''
    $loadOrder = 0
    try { if ($FileRecord.PSObject.Properties.Name -contains 'ModId') { $modId = [string]$FileRecord.ModId } } catch { }
    try { if ($FileRecord.PSObject.Properties.Name -contains 'ModName') { $modName = [string]$FileRecord.ModName } } catch { }
    try { if ($FileRecord.PSObject.Properties.Name -contains 'FileName') { $fileName = [string]$FileRecord.FileName } } catch { }
    try { if ($FileRecord.PSObject.Properties.Name -contains 'Path') { $filePath = [string]$FileRecord.Path } } catch { }
    try { if ($FileRecord.PSObject.Properties.Name -contains 'LoadOrder') { $loadOrder = $FileRecord.LoadOrder } } catch { }

    $key = ('{0}|{1}|{2}' -f $clean.ToLowerInvariant(), [string]$Kind, $modId)
    if ($Seen.ContainsKey($key)) { return }
    $Seen[$key] = $true

    [void]$List.Add([pscustomobject]@{
        ClassName     = $clean
        Kind          = [string]$Kind
        Source        = 'Mod'
        SourceModId   = $modId
        SourceModName = $modName
        SourceFile    = $fileName
        SourcePath    = $filePath
        SourceField   = [string]$SourceField
        LoadOrder     = $loadOrder
    })
}
function Get-UGSMDayZClassNamesFromXmlFile {
    [CmdletBinding()]
    param([Parameter(Mandatory)][object]$FileRecord)

    $classNames = New-Object System.Collections.ArrayList
    $seen = @{}
    if (-not (Test-Path -LiteralPath ([string]$FileRecord.Path) -PathType Leaf)) { return @() }

    try { [xml]$xml = Get-Content -LiteralPath ([string]$FileRecord.Path) -Raw -ErrorAction Stop }
    catch {
        return @([pscustomobject]@{ ClassName=''; Kind='ParseError'; Source='Mod'; SourceModId=[string]$FileRecord.ModId; SourceModName=[string]$FileRecord.ModName; SourceFile=[string]$FileRecord.FileName; SourcePath=[string]$FileRecord.Path; SourceField='xml'; Error=[string]$_.Exception.Message })
    }

    $kind = [string]$FileRecord.Kind
    if ($kind -eq 'types') {
        foreach ($node in @($xml.SelectNodes('//type[@name]'))) { Add-UGSMDayZClassNameResult -List $classNames -Seen $seen -ClassName ([string]$node.name) -Kind 'Item' -FileRecord $FileRecord -SourceField 'type.name' }
    }
    elseif ($kind -eq 'cfgspawnabletypes') {
        foreach ($node in @($xml.SelectNodes('//type[@name]'))) { Add-UGSMDayZClassNameResult -List $classNames -Seen $seen -ClassName ([string]$node.name) -Kind 'SpawnableType' -FileRecord $FileRecord -SourceField 'type.name' }
        foreach ($node in @($xml.SelectNodes('//item[@name]'))) { Add-UGSMDayZClassNameResult -List $classNames -Seen $seen -ClassName ([string]$node.name) -Kind 'SpawnableItem' -FileRecord $FileRecord -SourceField 'item.name' }
    }
    elseif ($kind -eq 'events') {
        foreach ($node in @($xml.SelectNodes('//event[@name]'))) { Add-UGSMDayZClassNameResult -List $classNames -Seen $seen -ClassName ([string]$node.name) -Kind 'Event' -FileRecord $FileRecord -SourceField 'event.name' }
        foreach ($node in @($xml.SelectNodes('//child[@type]'))) { Add-UGSMDayZClassNameResult -List $classNames -Seen $seen -ClassName ([string]$node.type) -Kind 'EventChild' -FileRecord $FileRecord -SourceField 'child.type' }
    }
    elseif ($kind -eq 'cfgeventspawns') {
        foreach ($node in @($xml.SelectNodes('//*[@name]'))) { Add-UGSMDayZClassNameResult -List $classNames -Seen $seen -ClassName ([string]$node.name) -Kind 'EventSpawn' -FileRecord $FileRecord -SourceField ($node.Name + '.name') }
    }
    else {
        foreach ($node in @($xml.SelectNodes('//*[@name]'))) { Add-UGSMDayZClassNameResult -List $classNames -Seen $seen -ClassName ([string]$node.name) -Kind 'XmlName' -FileRecord $FileRecord -SourceField ($node.Name + '.name') }
        foreach ($node in @($xml.SelectNodes('//*[@type]'))) { Add-UGSMDayZClassNameResult -List $classNames -Seen $seen -ClassName ([string]$node.type) -Kind 'XmlType' -FileRecord $FileRecord -SourceField ($node.Name + '.type') }
    }
    return @($classNames)
}

function Invoke-UGSMDayZInstanceIndexScan_CoreV3 {
    [CmdletBinding()]
    param([Parameter(Mandatory)][object]$Instance)

    $started = Get-Date
    $paths = Initialize-UGSMDayZInstanceStorage -Instance $Instance -MigrateLegacyJson
    $enabledMods = @(Get-UGSMDayZEnabledMods -Instance $Instance)

    $modReports = New-Object System.Collections.Generic.List[object]
    $fileRecords = New-Object System.Collections.Generic.List[object]
    $classRecords = New-Object System.Collections.Generic.List[object]
    $warnings = New-Object System.Collections.Generic.List[string]

    foreach ($mod in $enabledMods | Sort-Object @{Expression={ if ($_.PSObject.Properties.Name -contains 'LoadOrder') { $_.LoadOrder } else { 999999 } }}, @{Expression={ if ($_.PSObject.Properties.Name -contains 'Name') { $_.Name } else { $_.Id } }}) {
        $report = Find-UGSMDayZModConfigFiles -Instance $Instance -Mod $mod
        [void]$modReports.Add([pscustomobject]@{ Id=$report.Id; Name=$report.Name; FolderName=$report.FolderName; SourcePath=$report.SourcePath; LoadOrder=$report.LoadOrder; Enabled=$true; FileCount=@($report.Files).Count; Warnings=@($report.Warnings) })
        foreach ($warning in @($report.Warnings)) { [void]$warnings.Add($warning) }
        foreach ($file in @($report.Files)) {
            [void]$fileRecords.Add($file)
            foreach ($classRecord in @(Get-UGSMDayZClassNamesFromXmlFile -FileRecord $file)) {
                if ($classRecord.Kind -eq 'ParseError') { [void]$warnings.Add(('Failed parsing {0}: {1}' -f $classRecord.SourcePath, $classRecord.Error)) }
                elseif (-not [string]::IsNullOrWhiteSpace([string]$classRecord.ClassName)) { [void]$classRecords.Add($classRecord) }
            }
        }
    }

    $classRecordsSorted = @($classRecords | Sort-Object ClassName, Kind, SourceModName -Unique)
    $finished = Get-Date

    $activeModsCache = [pscustomobject]@{ GeneratedAt=$finished.ToString('s'); InstanceId=[string]$Instance.Id; InstanceName=[string]$Instance.Name; Count=@($modReports).Count; Mods=@($modReports) }
    $filesIndex = [pscustomobject]@{ GeneratedAt=$finished.ToString('s'); InstanceId=[string]$Instance.Id; InstanceName=[string]$Instance.Name; Count=@($fileRecords).Count; Files=@($fileRecords | Sort-Object LoadOrder, ModName, Kind, Path) }
    $classnames = [pscustomobject]@{ GeneratedAt=$finished.ToString('s'); InstanceId=[string]$Instance.Id; InstanceName=[string]$Instance.Name; Count=@($classRecordsSorted).Count; Items=@($classRecordsSorted) }
    $scanReport = [pscustomobject]@{ StartedAt=$started.ToString('s'); FinishedAt=$finished.ToString('s'); DurationSeconds=[math]::Round(($finished - $started).TotalSeconds, 2); InstanceId=[string]$Instance.Id; InstanceName=[string]$Instance.Name; ActiveModCount=@($modReports).Count; FileCount=@($fileRecords).Count; ClassNameCount=@($classRecordsSorted).Count; WarningCount=@($warnings).Count; Warnings=@($warnings) }

    Write-UGSMDayZCacheJson -Path $paths.ActiveModsCachePath -Data $activeModsCache | Out-Null
    Write-UGSMDayZCacheJson -Path $paths.FilesIndexPath -Data $filesIndex | Out-Null
    Write-UGSMDayZCacheJson -Path $paths.ClassNamesCachePath -Data $classnames | Out-Null
    Write-UGSMDayZCacheJson -Path (Join-Path $paths.CacheFolder 'scan-report.json') -Data $scanReport | Out-Null

    try {
        $logLine = '[{0}] Scanned {1} active mods, {2} files, {3} classnames, {4} warnings.' -f $finished.ToString('s'), @($modReports).Count, @($fileRecords).Count, @($classRecordsSorted).Count, @($warnings).Count
        Add-Content -LiteralPath (Join-Path $paths.LogsFolder 'scan.log') -Value $logLine -Encoding UTF8
    } catch { }

    return $scanReport
}

function Get-UGSMDayZCachedClassNames {
    [CmdletBinding()]
    param([Parameter(Mandatory)][object]$Instance)

    $paths = Get-UGSMDayZInstanceStoragePaths -Instance $Instance -Create
    if (-not (Test-Path -LiteralPath $paths.ClassNamesCachePath -PathType Leaf)) { return @() }
    try {
        $data = Get-Content -LiteralPath $paths.ClassNamesCachePath -Raw -ErrorAction Stop | ConvertFrom-Json
        if ($data.PSObject.Properties.Name -contains 'Items') { return @($data.Items) }
    } catch { }
    return @()
}

# ============================================================
# UGSM DayZ Index Scanner v4 overrides
# Fixes strict argument/type errors from the first scanner pass by
# avoiding typed .NET lists in the scan path and adding safer path handling.
# ============================================================

function Get-UGSMDayZObjectValue {
    [CmdletBinding()]
    param(
        [AllowNull()][object]$Object,
        [Parameter(Mandatory)][string]$Name,
        [AllowNull()][object]$Default = $null
    )

    if ($null -eq $Object) { return $Default }
    try {
        if ($Object -is [hashtable] -and $Object.ContainsKey($Name)) { return $Object[$Name] }
        if ($Object.PSObject.Properties.Name -contains $Name) { return $Object.$Name }
    } catch { }
    return $Default
}

function Write-UGSMDayZCacheJson {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Path,
        [AllowNull()][object]$Data,
        [int]$Depth = 64
    )

    $parent = Split-Path -Parent $Path
    if (-not [string]::IsNullOrWhiteSpace($parent) -and -not (Test-Path -LiteralPath $parent -PathType Container)) {
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
    }

    $json = $Data | ConvertTo-Json -Depth $Depth
    if ($null -eq $json) { $json = 'null' }
    [System.IO.File]::WriteAllText($Path, [string]$json, [System.Text.UTF8Encoding]::new($false))
    return [string]$Path
}

function Get-UGSMDayZEnabledMods {
    [CmdletBinding()]
    param([Parameter(Mandatory)][object]$Instance)

    $mods = @(Get-UGSMDayZObjectValue -Object $Instance -Name 'Mods' -Default @())
    $states = @(Get-UGSMDayZObjectValue -Object $Instance -Name 'ModStates' -Default @())
    $stateById = @{}

    foreach ($state in $states) {
        $stateId = [string](Get-UGSMDayZObjectValue -Object $state -Name 'Id' -Default '')
        if (-not [string]::IsNullOrWhiteSpace($stateId)) { $stateById[$stateId] = $state }
    }

    $enabled = @()
    foreach ($mod in $mods) {
        $id = [string](Get-UGSMDayZObjectValue -Object $mod -Name 'Id' -Default '')
        $isEnabled = $true

        $enabledValue = Get-UGSMDayZObjectValue -Object $mod -Name 'Enabled' -Default $null
        if ($null -ne $enabledValue) { try { $isEnabled = [bool]$enabledValue } catch { $isEnabled = $true } }

        if (-not [string]::IsNullOrWhiteSpace($id) -and $stateById.ContainsKey($id)) {
            $stateEnabled = Get-UGSMDayZObjectValue -Object $stateById[$id] -Name 'Enabled' -Default $null
            if ($null -ne $stateEnabled) { try { $isEnabled = [bool]$stateEnabled } catch { } }
        }

        if ($isEnabled) { $enabled += $mod }
    }

    return @($enabled)
}

function Get-UGSMDayZModSourcePathCandidates {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$Instance,
        [Parameter(Mandatory)][object]$Mod
    )

    $candidates = @()
    foreach ($propertyName in @('SourcePath', 'Path', 'InstallPath')) {
        $value = [string](Get-UGSMDayZObjectValue -Object $Mod -Name $propertyName -Default '')
        if (-not [string]::IsNullOrWhiteSpace($value)) { $candidates += $value }
    }

    $folderName = [string](Get-UGSMDayZObjectValue -Object $Mod -Name 'FolderName' -Default '')
    $id = [string](Get-UGSMDayZObjectValue -Object $Mod -Name 'Id' -Default '')
    $installPath = [string](Get-UGSMDayZObjectValue -Object $Instance -Name 'InstallPath' -Default '')

    if (-not [string]::IsNullOrWhiteSpace($installPath)) {
        $serverRoot = Split-Path -Parent $installPath
        if (-not [string]::IsNullOrWhiteSpace($folderName)) {
            $candidates += (Join-Path $installPath $folderName)
            if (-not [string]::IsNullOrWhiteSpace($serverRoot)) { $candidates += (Join-Path $serverRoot $folderName) }
        }
        if (-not [string]::IsNullOrWhiteSpace($id)) {
            $steamapps = $null
            $cursor = $installPath
            for ($i = 0; $i -lt 8 -and -not [string]::IsNullOrWhiteSpace($cursor); $i++) {
                if ((Split-Path -Leaf $cursor) -ieq 'steamapps') { $steamapps = $cursor; break }
                $cursor = Split-Path -Parent $cursor
            }
            if (-not [string]::IsNullOrWhiteSpace($steamapps)) {
                $candidates += (Join-Path (Join-Path (Join-Path $steamapps 'workshop') 'content') (Join-Path '221100' $id))
            }
        }
    }

    return @($candidates | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -Unique)
}

function Find-UGSMDayZModConfigFiles {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$Instance,
        [Parameter(Mandatory)][object]$Mod
    )

    $id = [string](Get-UGSMDayZObjectValue -Object $Mod -Name 'Id' -Default '')
    $name = [string](Get-UGSMDayZObjectValue -Object $Mod -Name 'Name' -Default $id)
    $folderName = [string](Get-UGSMDayZObjectValue -Object $Mod -Name 'FolderName' -Default '')
    $loadOrder = Get-UGSMDayZObjectValue -Object $Mod -Name 'LoadOrder' -Default 999999

    $sourcePath = $null
    foreach ($candidate in @(Get-UGSMDayZModSourcePathCandidates -Instance $Instance -Mod $Mod)) {
        if (Test-Path -LiteralPath $candidate -PathType Container) { $sourcePath = [string]$candidate; break }
    }

    $warnings = @()
    $files = @()

    if ([string]::IsNullOrWhiteSpace($sourcePath)) {
        $warnings += ('SourcePath missing or not found for mod {0} ({1}).' -f $name, $id)
    }
    else {
        $wantedNames = @('types.xml','events.xml','cfgspawnabletypes.xml','cfgeventspawns.xml','cfgvehicles.xml')
        try {
            $xmlFiles = @(Get-ChildItem -LiteralPath $sourcePath -Recurse -File -ErrorAction SilentlyContinue | Where-Object { $wantedNames -contains $_.Name.ToLowerInvariant() })
            foreach ($file in $xmlFiles) {
                $fileNameLower = $file.Name.ToLowerInvariant()
                $kind = if ($fileNameLower -eq 'types.xml') { 'types' }
                        elseif ($fileNameLower -eq 'events.xml') { 'events' }
                        elseif ($fileNameLower -eq 'cfgspawnabletypes.xml') { 'cfgspawnabletypes' }
                        elseif ($fileNameLower -eq 'cfgeventspawns.xml') { 'cfgeventspawns' }
                        elseif ($fileNameLower -eq 'cfgeventgroups.xml') { 'cfgeventgroups' }
                        elseif ($fileNameLower -eq 'cfgvehicles.xml') { 'cfgvehicles' }
                        else { 'xml' }

                $relative = [string]$file.FullName
                if ($relative.StartsWith($sourcePath, [System.StringComparison]::OrdinalIgnoreCase)) {
                    $relative = $relative.Substring($sourcePath.Length) -replace '^[\\/]+', ''
                }

                $files += [pscustomobject]@{
                    ModId = $id; ModName = $name; FolderName = $folderName; LoadOrder = $loadOrder
                    Kind = $kind; FileName = $file.Name; Path = $file.FullName; RelativePath = $relative
                    Length = $file.Length; LastWriteTime = $file.LastWriteTime.ToString('s')
                }
            }
        }
        catch { $warnings += ('Failed scanning files for mod {0}: {1}' -f $name, [string]$_.Exception.Message) }
    }

    return [pscustomobject]@{ Id = $id; Name = $name; FolderName = $folderName; SourcePath = [string]$sourcePath; LoadOrder = $loadOrder; Enabled = $true; Files = @($files); Warnings = @($warnings) }
}

function Invoke-UGSMDayZInstanceIndexScan_CoreV3 {
    [CmdletBinding()]
    param([Parameter(Mandatory)][object]$Instance)

    $started = Get-Date
    $paths = Initialize-UGSMDayZInstanceStorage -Instance $Instance -MigrateLegacyJson
    $enabledMods = @(Get-UGSMDayZEnabledMods -Instance $Instance)

    $modReports = @()
    $fileRecords = @()
    $classRecords = @()
    $warnings = @()

    $sortedMods = @($enabledMods | Sort-Object `
        @{ Expression = { Get-UGSMDayZObjectValue -Object $_ -Name 'LoadOrder' -Default 999999 } },
        @{ Expression = { [string](Get-UGSMDayZObjectValue -Object $_ -Name 'Name' -Default (Get-UGSMDayZObjectValue -Object $_ -Name 'Id' -Default '')) } })

    foreach ($mod in $sortedMods) {
        $report = Find-UGSMDayZModConfigFiles -Instance $Instance -Mod $mod
        $modReports += [pscustomobject]@{
            Id=$report.Id; Name=$report.Name; FolderName=$report.FolderName; SourcePath=$report.SourcePath
            LoadOrder=$report.LoadOrder; Enabled=$true; FileCount=@($report.Files).Count; Warnings=@($report.Warnings)
        }
        foreach ($warning in @($report.Warnings)) { $warnings += [string]$warning }
        foreach ($file in @($report.Files)) {
            $fileRecords += $file
            foreach ($classRecord in @(Get-UGSMDayZClassNamesFromXmlFile -FileRecord $file)) {
                if ([string]$classRecord.Kind -eq 'ParseError') { $warnings += ('Failed parsing {0}: {1}' -f $classRecord.SourcePath, $classRecord.Error) }
                elseif (-not [string]::IsNullOrWhiteSpace([string]$classRecord.ClassName)) { $classRecords += $classRecord }
            }
        }
    }

    $classRecordsSorted = @($classRecords | Sort-Object ClassName, Kind, SourceModName -Unique)
    $finished = Get-Date

    $instanceId = [string](Get-UGSMDayZObjectValue -Object $Instance -Name 'Id' -Default '')
    $instanceName = [string](Get-UGSMDayZObjectValue -Object $Instance -Name 'Name' -Default $instanceId)

    $activeModsCache = [pscustomobject]@{ GeneratedAt=$finished.ToString('s'); InstanceId=$instanceId; InstanceName=$instanceName; Count=@($modReports).Count; Mods=@($modReports) }
    $filesIndex = [pscustomobject]@{ GeneratedAt=$finished.ToString('s'); InstanceId=$instanceId; InstanceName=$instanceName; Count=@($fileRecords).Count; Files=@($fileRecords | Sort-Object LoadOrder, ModName, Kind, Path) }
    $classnames = [pscustomobject]@{ GeneratedAt=$finished.ToString('s'); InstanceId=$instanceId; InstanceName=$instanceName; Count=@($classRecordsSorted).Count; Items=@($classRecordsSorted) }
    $scanReport = [pscustomobject]@{
        StartedAt=$started.ToString('s'); FinishedAt=$finished.ToString('s'); DurationSeconds=[math]::Round(($finished - $started).TotalSeconds, 2)
        InstanceId=$instanceId; InstanceName=$instanceName; ActiveModCount=@($modReports).Count; FileCount=@($fileRecords).Count
        ClassNameCount=@($classRecordsSorted).Count; WarningCount=@($warnings).Count; Warnings=@($warnings)
    }

    Write-UGSMDayZCacheJson -Path $paths.ActiveModsCachePath -Data $activeModsCache | Out-Null
    Write-UGSMDayZCacheJson -Path $paths.FilesIndexPath -Data $filesIndex | Out-Null
    Write-UGSMDayZCacheJson -Path $paths.ClassNamesCachePath -Data $classnames | Out-Null
    Write-UGSMDayZCacheJson -Path (Join-Path $paths.CacheFolder 'scan-report.json') -Data $scanReport | Out-Null

    try {
        $logLine = '[{0}] Scanned {1} active mods, {2} files, {3} classnames, {4} warnings.' -f $finished.ToString('s'), @($modReports).Count, @($fileRecords).Count, @($classRecordsSorted).Count, @($warnings).Count
        Add-Content -LiteralPath (Join-Path $paths.LogsFolder 'scan.log') -Value $logLine -Encoding UTF8
    } catch { }

    return $scanReport
}
# ============================================================
# UGSM DayZ Index Scanner v5 overrides
# Adds live profile/vanilla mission file scanning before active mod scanning.
# This keeps AppData as the instance library while reading the live ProfilePath files.
# ============================================================

function Get-UGSMDayZProfilePath {
    [CmdletBinding()]
    param([Parameter(Mandatory)][object]$Instance)

    $profilePath = [string](Get-UGSMDayZObjectValue -Object $Instance -Name 'ProfilePath' -Default '')
    if (-not [string]::IsNullOrWhiteSpace($profilePath)) { return $profilePath }

    foreach ($propertyName in @('ServerProfilePath','RuntimePath','RuntimeProfilePath')) {
        $value = [string](Get-UGSMDayZObjectValue -Object $Instance -Name $propertyName -Default '')
        if (-not [string]::IsNullOrWhiteSpace($value)) { return $value }
    }

    return ''
}

function Get-UGSMDayZProfileMissionFolders {
    [CmdletBinding()]
    param([Parameter(Mandatory)][object]$Instance)

    $profilePath = Get-UGSMDayZProfilePath -Instance $Instance
    if ([string]::IsNullOrWhiteSpace($profilePath) -or -not (Test-Path -LiteralPath $profilePath -PathType Container)) { return @() }

    $mpmissions = Join-Path $profilePath 'mpmissions'
    if (-not (Test-Path -LiteralPath $mpmissions -PathType Container)) { return @() }

    $folders = @()
    try {
        $folders = @(Get-ChildItem -LiteralPath $mpmissions -ErrorAction SilentlyContinue | Where-Object { $_.PSIsContainer })
    } catch { $folders = @() }

    return @($folders)
}

function Get-UGSMDayZProfileConfigFiles {
    [CmdletBinding()]
    param([Parameter(Mandatory)][object]$Instance)

    $profilePath = Get-UGSMDayZProfilePath -Instance $Instance
    $warnings = @()
    $files = @()

    if ([string]::IsNullOrWhiteSpace($profilePath)) {
        $warnings += 'ProfilePath is empty. Vanilla/profile file scan skipped.'
        return [pscustomobject]@{ Files=@(); Warnings=@($warnings) }
    }
    if (-not (Test-Path -LiteralPath $profilePath -PathType Container)) {
        $warnings += ('ProfilePath not found. Vanilla/profile file scan skipped: {0}' -f $profilePath)
        return [pscustomobject]@{ Files=@(); Warnings=@($warnings) }
    }

    $missionFolders = @(Get-UGSMDayZProfileMissionFolders -Instance $Instance)
    if (@($missionFolders).Count -eq 0) {
        $warnings += ('No mpmissions folders found under ProfilePath: {0}' -f $profilePath)
        return [pscustomobject]@{ Files=@(); Warnings=@($warnings) }
    }

    $wantedNames = @(
        'types.xml',
        'events.xml',
        'cfgspawnabletypes.xml',
        'cfgeventspawns.xml',
        'cfgvehicles.xml',
        'cfgrandompresets.xml',
        'cfgplayerspawnpoints.xml',
        'cfgenvironment.xml',
        'cfgeconomycore.xml',
        'cfgeventgroups.xml',
        'cfglimitsdefinition.xml',
        'cfglimitsdefinitionuser.xml',
        'globals.xml',
        'economy.xml'
    )

    foreach ($mission in $missionFolders) {
        try {
            $xmlFiles = @(Get-ChildItem -LiteralPath $mission.FullName -Recurse -File -ErrorAction SilentlyContinue | Where-Object {
                $nameLower = $_.Name.ToLowerInvariant()
                ($wantedNames -contains $nameLower) -or ($nameLower -like '*_territories.xml')
            })

            foreach ($file in $xmlFiles) {
                $fileNameLower = $file.Name.ToLowerInvariant()
                $kind = if ($fileNameLower -eq 'types.xml') { 'types' }
                        elseif ($fileNameLower -eq 'events.xml') { 'events' }
                        elseif ($fileNameLower -eq 'cfgspawnabletypes.xml') { 'cfgspawnabletypes' }
                        elseif ($fileNameLower -eq 'cfgeventspawns.xml') { 'cfgeventspawns' }
                        elseif ($fileNameLower -eq 'cfgeventgroups.xml') { 'cfgeventgroups' }
                        elseif ($fileNameLower -eq 'cfgvehicles.xml') { 'cfgvehicles' }
                        elseif ($fileNameLower -eq 'cfgrandompresets.xml') { 'cfgrandompresets' }
                        elseif ($fileNameLower -eq 'cfgplayerspawnpoints.xml') { 'cfgplayerspawnpoints' }
                        elseif ($fileNameLower -like '*_territories.xml') { 'territories' }
                        else { 'profilexml' }

                $relative = [string]$file.FullName
                if ($relative.StartsWith($profilePath, [System.StringComparison]::OrdinalIgnoreCase)) {
                    $relative = $relative.Substring($profilePath.Length) -replace '^[\\/]+', ''
                }

                $files += [pscustomobject]@{
                    ModId = ''
                    ModName = 'DayZ Profile / Vanilla'
                    FolderName = ''
                    LoadOrder = -100000
                    Source = 'Profile'
                    SourceType = 'Profile'
                    Kind = $kind
                    FileName = $file.Name
                    Path = $file.FullName
                    RelativePath = $relative
                    MissionName = $mission.Name
                    Length = $file.Length
                    LastWriteTime = $file.LastWriteTime.ToString('s')
                }
            }
        }
        catch {
            $warnings += ('Failed scanning profile mission folder {0}: {1}' -f $mission.FullName, [string]$_.Exception.Message)
        }
    }

    return [pscustomobject]@{ Files=@($files); Warnings=@($warnings) }
}

function ConvertTo-UGSMDayZProfileClassRecord {
    [CmdletBinding()]
    param([Parameter(Mandatory)][object]$ClassRecord)

    try {
        if ($ClassRecord.PSObject.Properties.Name -contains 'Source') { $ClassRecord.Source = 'Profile' }
        else { $ClassRecord | Add-Member -NotePropertyName 'Source' -NotePropertyValue 'Profile' -Force }

        if ($ClassRecord.PSObject.Properties.Name -contains 'SourceModId') { $ClassRecord.SourceModId = '' }
        else { $ClassRecord | Add-Member -NotePropertyName 'SourceModId' -NotePropertyValue '' -Force }

        if ($ClassRecord.PSObject.Properties.Name -contains 'SourceModName') { $ClassRecord.SourceModName = 'DayZ Profile / Vanilla' }
        else { $ClassRecord | Add-Member -NotePropertyName 'SourceModName' -NotePropertyValue 'DayZ Profile / Vanilla' -Force }
    } catch { }

    return $ClassRecord
}

function Invoke-UGSMDayZInstanceIndexScan_CoreV3 {
    [CmdletBinding()]
    param([Parameter(Mandatory)][object]$Instance)

    $started = Get-Date
    $paths = Initialize-UGSMDayZInstanceStorage -Instance $Instance -MigrateLegacyJson
    $enabledMods = @(Get-UGSMDayZEnabledMods -Instance $Instance)

    $modReports = @()
    $fileRecords = @()
    $classRecords = @()
    $warnings = @()

    # First scan the live profile/mission files. These are the vanilla/live files the server can already run with.
    $profileReport = Get-UGSMDayZProfileConfigFiles -Instance $Instance
    foreach ($warning in @($profileReport.Warnings)) { $warnings += [string]$warning }
    foreach ($file in @($profileReport.Files)) {
        $fileRecords += $file
        foreach ($classRecord in @(Get-UGSMDayZClassNamesFromXmlFile -FileRecord $file)) {
            if ([string]$classRecord.Kind -eq 'ParseError') {
                $warnings += ('Failed parsing {0}: {1}' -f $classRecord.SourcePath, $classRecord.Error)
            }
            elseif (-not [string]::IsNullOrWhiteSpace([string]$classRecord.ClassName)) {
                $classRecords += (ConvertTo-UGSMDayZProfileClassRecord -ClassRecord $classRecord)
            }
        }
    }

    # Then scan enabled mods. These append mod classnames and mod config files into the same cache library.
    $sortedMods = @($enabledMods | Sort-Object `
        @{ Expression = { Get-UGSMDayZObjectValue -Object $_ -Name 'LoadOrder' -Default 999999 } },
        @{ Expression = { [string](Get-UGSMDayZObjectValue -Object $_ -Name 'Name' -Default (Get-UGSMDayZObjectValue -Object $_ -Name 'Id' -Default '')) } })

    foreach ($mod in $sortedMods) {
        $report = Find-UGSMDayZModConfigFiles -Instance $Instance -Mod $mod
        $modReports += [pscustomobject]@{
            Id=$report.Id; Name=$report.Name; FolderName=$report.FolderName; SourcePath=$report.SourcePath
            LoadOrder=$report.LoadOrder; Enabled=$true; FileCount=@($report.Files).Count; Warnings=@($report.Warnings)
        }
        foreach ($warning in @($report.Warnings)) { $warnings += [string]$warning }
        foreach ($file in @($report.Files)) {
            $fileRecords += $file
            foreach ($classRecord in @(Get-UGSMDayZClassNamesFromXmlFile -FileRecord $file)) {
                if ([string]$classRecord.Kind -eq 'ParseError') { $warnings += ('Failed parsing {0}: {1}' -f $classRecord.SourcePath, $classRecord.Error) }
                elseif (-not [string]::IsNullOrWhiteSpace([string]$classRecord.ClassName)) { $classRecords += $classRecord }
            }
        }
    }

    $classRecordsSorted = @($classRecords | Sort-Object ClassName, Kind, Source, SourceModName -Unique)
    $finished = Get-Date

    $instanceId = [string](Get-UGSMDayZObjectValue -Object $Instance -Name 'Id' -Default '')
    $instanceName = [string](Get-UGSMDayZObjectValue -Object $Instance -Name 'Name' -Default $instanceId)

    $profileFileCount = @($profileReport.Files).Count
    $activeModsCache = [pscustomobject]@{ GeneratedAt=$finished.ToString('s'); InstanceId=$instanceId; InstanceName=$instanceName; Count=@($modReports).Count; Mods=@($modReports) }
    $filesIndex = [pscustomobject]@{ GeneratedAt=$finished.ToString('s'); InstanceId=$instanceId; InstanceName=$instanceName; Count=@($fileRecords).Count; ProfileFileCount=$profileFileCount; ModFileCount=(@($fileRecords).Count - $profileFileCount); Files=@($fileRecords | Sort-Object LoadOrder, ModName, Kind, Path) }
    $classnames = [pscustomobject]@{ GeneratedAt=$finished.ToString('s'); InstanceId=$instanceId; InstanceName=$instanceName; Count=@($classRecordsSorted).Count; ProfileFileCount=$profileFileCount; Items=@($classRecordsSorted) }
    $scanReport = [pscustomobject]@{
        StartedAt=$started.ToString('s'); FinishedAt=$finished.ToString('s'); DurationSeconds=[math]::Round(($finished - $started).TotalSeconds, 2)
        InstanceId=$instanceId; InstanceName=$instanceName
        ProfileFileCount=$profileFileCount
        ActiveModCount=@($modReports).Count
        FileCount=@($fileRecords).Count
        ClassNameCount=@($classRecordsSorted).Count
        WarningCount=@($warnings).Count
        Warnings=@($warnings)
    }

    Write-UGSMDayZCacheJson -Path $paths.ActiveModsCachePath -Data $activeModsCache | Out-Null
    Write-UGSMDayZCacheJson -Path $paths.FilesIndexPath -Data $filesIndex | Out-Null
    Write-UGSMDayZCacheJson -Path $paths.ClassNamesCachePath -Data $classnames | Out-Null
    Write-UGSMDayZCacheJson -Path (Join-Path $paths.CacheFolder 'scan-report.json') -Data $scanReport | Out-Null

    try {
        $logLine = '[{0}] Scanned {1} profile files, {2} active mods, {3} total files, {4} classnames, {5} warnings.' -f $finished.ToString('s'), $profileFileCount, @($modReports).Count, @($fileRecords).Count, @($classRecordsSorted).Count, @($warnings).Count
        Add-Content -LiteralPath (Join-Path $paths.LogsFolder 'scan.log') -Value $logLine -Encoding UTF8
    } catch { }

    return $scanReport
}
# ============================================================
# UGSM DayZ Index Scanner v7 overrides
# - Rebuilds cache from scratch each scan
# - Scans the selected/live mission first instead of every map folder
# - Keeps classnames.json as a unique dropdown-friendly library
# - Writes classnames-full.json as the detailed source ledger
# ============================================================

function Get-UGSMDayZSelectedMissionName {
    [CmdletBinding()]
    param([Parameter(Mandatory)][object]$Instance)

    $map = [string](Get-UGSMDayZObjectValue -Object $Instance -Name 'Map' -Default '')
    if (-not [string]::IsNullOrWhiteSpace($map)) {
        $map = $map.Trim()
        if ($map -like 'dayzOffline.*') { return $map }
        return ('dayzOffline.{0}' -f $map)
    }

    $profilePath = Get-UGSMDayZProfilePath -Instance $Instance
    if (-not [string]::IsNullOrWhiteSpace($profilePath)) {
        $serverCfg = Join-Path $profilePath 'serverDZ.cfg'
        if (Test-Path -LiteralPath $serverCfg -PathType Leaf) {
            try {
                $raw = Get-Content -LiteralPath $serverCfg -Raw -ErrorAction Stop
                $match = [regex]::Match($raw, '(?im)^\s*template\s*=\s*"?([^";\r\n]+)"?\s*;?')
                if ($match.Success) {
                    $template = $match.Groups[1].Value.Trim()
                    if (-not [string]::IsNullOrWhiteSpace($template)) { return $template }
                }
            } catch { }
        }
    }

    return 'dayzOffline.chernarusplus'
}

function Get-UGSMDayZProfileMissionFolders {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$Instance,
        [switch]$AllMissions
    )

    $profilePath = Get-UGSMDayZProfilePath -Instance $Instance
    if ([string]::IsNullOrWhiteSpace($profilePath) -or -not (Test-Path -LiteralPath $profilePath -PathType Container)) { return @() }

    $mpmissions = Join-Path $profilePath 'mpmissions'
    if (-not (Test-Path -LiteralPath $mpmissions -PathType Container)) { return @() }

    $folders = @()
    try { $folders = @(Get-ChildItem -LiteralPath $mpmissions -ErrorAction SilentlyContinue | Where-Object { $_.PSIsContainer }) } catch { $folders = @() }
    if ($AllMissions) { return @($folders) }

    $selected = Get-UGSMDayZSelectedMissionName -Instance $Instance
    $match = @($folders | Where-Object { $_.Name -ieq $selected })
    if (@($match).Count -gt 0) { return @($match) }

    $chernarus = @($folders | Where-Object { $_.Name -ieq 'dayzOffline.chernarusplus' })
    if (@($chernarus).Count -gt 0) { return @($chernarus) }

    return @($folders | Select-Object -First 1)
}

function Get-UGSMDayZProfileConfigFiles {
    [CmdletBinding()]
    param([Parameter(Mandatory)][object]$Instance)

    $profilePath = Get-UGSMDayZProfilePath -Instance $Instance
    $warnings = @()
    $files = @()

    if ([string]::IsNullOrWhiteSpace($profilePath)) {
        $warnings += 'ProfilePath is empty. Vanilla/profile file scan skipped.'
        return [pscustomobject]@{ Files=@(); Warnings=@($warnings); SelectedMission='' }
    }
    if (-not (Test-Path -LiteralPath $profilePath -PathType Container)) {
        $warnings += ('ProfilePath not found. Vanilla/profile file scan skipped: {0}' -f $profilePath)
        return [pscustomobject]@{ Files=@(); Warnings=@($warnings); SelectedMission='' }
    }

    $missionFolders = @(Get-UGSMDayZProfileMissionFolders -Instance $Instance)
    $selectedMission = if (@($missionFolders).Count -gt 0) { [string]$missionFolders[0].Name } else { '' }
    if (@($missionFolders).Count -eq 0) {
        $warnings += ('No selected mpmissions folder found under ProfilePath: {0}' -f $profilePath)
        return [pscustomobject]@{ Files=@(); Warnings=@($warnings); SelectedMission='' }
    }

    # Keep this list focused on files that provide item/entity names useful to editors.
    $wantedNames = @('types.xml','cfgspawnabletypes.xml','events.xml','cfgeventspawns.xml','cfgvehicles.xml')

    foreach ($mission in $missionFolders) {
        try {
            $xmlFiles = @(Get-ChildItem -LiteralPath $mission.FullName -Recurse -File -ErrorAction SilentlyContinue | Where-Object {
                $wantedNames -contains $_.Name.ToLowerInvariant()
            })

            foreach ($file in $xmlFiles) {
                $fileNameLower = $file.Name.ToLowerInvariant()
                $kind = if ($fileNameLower -eq 'types.xml') { 'types' }
                        elseif ($fileNameLower -eq 'events.xml') { 'events' }
                        elseif ($fileNameLower -eq 'cfgspawnabletypes.xml') { 'cfgspawnabletypes' }
                        elseif ($fileNameLower -eq 'cfgeventspawns.xml') { 'cfgeventspawns' }
                        elseif ($fileNameLower -eq 'cfgeventgroups.xml') { 'cfgeventgroups' }
                        elseif ($fileNameLower -eq 'cfgvehicles.xml') { 'cfgvehicles' }
                        else { 'profilexml' }

                $relative = [string]$file.FullName
                if ($relative.StartsWith($profilePath, [System.StringComparison]::OrdinalIgnoreCase)) {
                    $relative = $relative.Substring($profilePath.Length) -replace '^[\\/]+', ''
                }

                $files += [pscustomobject]@{
                    ModId = ''
                    ModName = 'DayZ Profile / Vanilla'
                    FolderName = ''
                    LoadOrder = -100000
                    Source = 'Profile'
                    SourceType = 'Profile'
                    Kind = $kind
                    FileName = $file.Name
                    Path = $file.FullName
                    RelativePath = $relative
                    MissionName = $mission.Name
                    Length = $file.Length
                    LastWriteTime = $file.LastWriteTime.ToString('s')
                }
            }
        }
        catch {
            $warnings += ('Failed scanning profile mission folder {0}: {1}' -f $mission.FullName, [string]$_.Exception.Message)
        }
    }

    return [pscustomobject]@{ Files=@($files); Warnings=@($warnings); SelectedMission=$selectedMission }
}

function Add-UGSMDayZClassNameResult {
    [CmdletBinding()]
    param(
        [object]$List,
        [hashtable]$Seen,
        [AllowEmptyString()][string]$ClassName = '',
        [Parameter(Mandatory)][string]$Kind,
        [Parameter(Mandatory)][object]$FileRecord,
        [Parameter(Mandatory)][string]$SourceField
    )

    if ($null -eq $List) { return }
    if ($null -eq $Seen) { $Seen = @{} }
    if ([string]::IsNullOrWhiteSpace($ClassName)) { return }

    $clean = ([string]$ClassName).Trim()
    if ([string]::IsNullOrWhiteSpace($clean)) { return }

    # Avoid bad dropdown entries from generic config values.
    if ($clean -match '^[-+]?\d+(\.\d+)?$') { return }
    if ($clean.Length -lt 2) { return }

    $modId = ''
    $modName = ''
    $fileName = ''
    $filePath = ''
    $loadOrder = 0
    $source = 'Mod'
    try { if ($FileRecord.PSObject.Properties.Name -contains 'ModId') { $modId = [string]$FileRecord.ModId } } catch { }
    try { if ($FileRecord.PSObject.Properties.Name -contains 'ModName') { $modName = [string]$FileRecord.ModName } } catch { }
    try { if ($FileRecord.PSObject.Properties.Name -contains 'FileName') { $fileName = [string]$FileRecord.FileName } } catch { }
    try { if ($FileRecord.PSObject.Properties.Name -contains 'Path') { $filePath = [string]$FileRecord.Path } } catch { }
    try { if ($FileRecord.PSObject.Properties.Name -contains 'LoadOrder') { $loadOrder = $FileRecord.LoadOrder } } catch { }
    try { if ($FileRecord.PSObject.Properties.Name -contains 'Source') { $source = [string]$FileRecord.Source } } catch { }
    if ([string]::IsNullOrWhiteSpace($modName) -and $source -eq 'Profile') { $modName = 'DayZ Profile / Vanilla' }

    $key = ('{0}|{1}|{2}|{3}|{4}' -f $clean.ToLowerInvariant(), [string]$Kind, $source, $modId, $filePath.ToLowerInvariant())
    if ($Seen.ContainsKey($key)) { return }
    $Seen[$key] = $true

    [void]$List.Add([pscustomobject]@{
        ClassName     = $clean
        Kind          = [string]$Kind
        Source        = $source
        SourceModId   = $modId
        SourceModName = $modName
        SourceFile    = $fileName
        SourcePath    = $filePath
        SourceField   = [string]$SourceField
        LoadOrder     = $loadOrder
    })
}

function Get-UGSMDayZClassNamesFromXmlFile {
    [CmdletBinding()]
    param([Parameter(Mandatory)][object]$FileRecord)

    $classNames = New-Object System.Collections.ArrayList
    $seen = @{}
    if (-not (Test-Path -LiteralPath ([string]$FileRecord.Path) -PathType Leaf)) { return @() }

    try { [xml]$xml = Get-Content -LiteralPath ([string]$FileRecord.Path) -Raw -ErrorAction Stop }
    catch {
        return @([pscustomobject]@{ ClassName=''; Kind='ParseError'; Source='Mod'; SourceModId=[string]$FileRecord.ModId; SourceModName=[string]$FileRecord.ModName; SourceFile=[string]$FileRecord.FileName; SourcePath=[string]$FileRecord.Path; SourceField='xml'; Error=[string]$_.Exception.Message })
    }

    $kind = [string]$FileRecord.Kind
    if ($kind -eq 'types') {
        foreach ($node in @($xml.SelectNodes('//type[@name]'))) { Add-UGSMDayZClassNameResult -List $classNames -Seen $seen -ClassName ([string]$node.name) -Kind 'Item' -FileRecord $FileRecord -SourceField 'type.name' }
    }
    elseif ($kind -eq 'cfgspawnabletypes') {
        foreach ($node in @($xml.SelectNodes('//type[@name]'))) { Add-UGSMDayZClassNameResult -List $classNames -Seen $seen -ClassName ([string]$node.name) -Kind 'SpawnableType' -FileRecord $FileRecord -SourceField 'type.name' }
        foreach ($node in @($xml.SelectNodes('//item[@name]'))) { Add-UGSMDayZClassNameResult -List $classNames -Seen $seen -ClassName ([string]$node.name) -Kind 'SpawnableItem' -FileRecord $FileRecord -SourceField 'item.name' }
    }
    elseif ($kind -eq 'events') {
        # Events themselves are not item classnames. Child type values are useful for animals/zombies/etc.
        foreach ($node in @($xml.SelectNodes('//child[@type]'))) { Add-UGSMDayZClassNameResult -List $classNames -Seen $seen -ClassName ([string]$node.type) -Kind 'EventChild' -FileRecord $FileRecord -SourceField 'child.type' }
    }
    elseif ($kind -eq 'cfgvehicles') {
        foreach ($node in @($xml.SelectNodes('//type[@name]'))) { Add-UGSMDayZClassNameResult -List $classNames -Seen $seen -ClassName ([string]$node.name) -Kind 'Vehicle' -FileRecord $FileRecord -SourceField 'type.name' }
    }

    return @($classNames)
}

function ConvertTo-UGSMDayZUniqueClassNameLibrary {
    [CmdletBinding()]
    param([object[]]$Records)

    $byName = @{}
    foreach ($record in @($Records)) {
        $name = [string](Get-UGSMDayZObjectValue -Object $record -Name 'ClassName' -Default '')
        if ([string]::IsNullOrWhiteSpace($name)) { continue }
        $key = $name.ToLowerInvariant()
        if (-not $byName.ContainsKey($key)) {
            $byName[$key] = [ordered]@{
                ClassName = $name
                Kind = [string](Get-UGSMDayZObjectValue -Object $record -Name 'Kind' -Default '')
                Source = [string](Get-UGSMDayZObjectValue -Object $record -Name 'Source' -Default '')
                SourceModId = [string](Get-UGSMDayZObjectValue -Object $record -Name 'SourceModId' -Default '')
                SourceModName = [string](Get-UGSMDayZObjectValue -Object $record -Name 'SourceModName' -Default '')
                Kinds = New-Object System.Collections.Generic.List[string]
                Sources = New-Object System.Collections.Generic.List[string]
                SourceMods = New-Object System.Collections.Generic.List[object]
                SourceFiles = New-Object System.Collections.Generic.List[string]
            }
        }

        $entry = $byName[$key]
        $kind = [string](Get-UGSMDayZObjectValue -Object $record -Name 'Kind' -Default '')
        $source = [string](Get-UGSMDayZObjectValue -Object $record -Name 'Source' -Default '')
        $modId = [string](Get-UGSMDayZObjectValue -Object $record -Name 'SourceModId' -Default '')
        $modName = [string](Get-UGSMDayZObjectValue -Object $record -Name 'SourceModName' -Default '')
        $sourceFile = [string](Get-UGSMDayZObjectValue -Object $record -Name 'SourceFile' -Default '')

        if (-not [string]::IsNullOrWhiteSpace($kind) -and -not $entry.Kinds.Contains($kind)) { [void]$entry.Kinds.Add($kind) }
        if (-not [string]::IsNullOrWhiteSpace($source) -and -not $entry.Sources.Contains($source)) { [void]$entry.Sources.Add($source) }
        if (-not [string]::IsNullOrWhiteSpace($sourceFile) -and -not $entry.SourceFiles.Contains($sourceFile)) { [void]$entry.SourceFiles.Add($sourceFile) }

        $sourceModKey = if ([string]::IsNullOrWhiteSpace($modId)) { ('Profile|{0}' -f $modName) } else { ('Mod|{0}' -f $modId) }
        $already = $false
        foreach ($m in @($entry.SourceMods)) {
            $existingKey = if ([string]::IsNullOrWhiteSpace([string]$m.Id)) { ('Profile|{0}' -f [string]$m.Name) } else { ('Mod|{0}' -f [string]$m.Id) }
            if ($existingKey -eq $sourceModKey) { $already = $true; break }
        }
        if (-not $already) { [void]$entry.SourceMods.Add([pscustomobject]@{ Id=$modId; Name=$modName; Source=$source }) }

        # Prefer Item as the compatibility Kind shown to existing UI code.
        if ($entry.Kind -ne 'Item' -and $kind -eq 'Item') { $entry.Kind = 'Item' }
        if ($entry.Source -ne 'Mod' -and $source -eq 'Mod') {
            $entry.Source = 'Mod'
            $entry.SourceModId = $modId
            $entry.SourceModName = $modName
        }
    }

    $items = foreach ($entry in $byName.Values) {
        [pscustomobject]@{
            ClassName = [string]$entry.ClassName
            Kind = [string]$entry.Kind
            Source = [string]$entry.Source
            SourceModId = [string]$entry.SourceModId
            SourceModName = [string]$entry.SourceModName
            Kinds = @($entry.Kinds | Sort-Object -Unique)
            Sources = @($entry.Sources | Sort-Object -Unique)
            SourceMods = @($entry.SourceMods)
            SourceFiles = @($entry.SourceFiles | Sort-Object -Unique)
        }
    }

    return @($items | Sort-Object ClassName)
}

function Invoke-UGSMDayZInstanceIndexScan_CoreV3 {
    [CmdletBinding()]
    param([Parameter(Mandatory)][object]$Instance)

    $started = Get-Date
    $paths = Initialize-UGSMDayZInstanceStorage -Instance $Instance -MigrateLegacyJson
    $enabledMods = @(Get-UGSMDayZEnabledMods -Instance $Instance)

    $modReports = @()
    $fileRecords = @()
    $classRecords = @()
    $warnings = @()

    $profileReport = Get-UGSMDayZProfileConfigFiles -Instance $Instance
    foreach ($warning in @($profileReport.Warnings)) { $warnings += [string]$warning }
    foreach ($file in @($profileReport.Files)) {
        $fileRecords += $file
        foreach ($classRecord in @(Get-UGSMDayZClassNamesFromXmlFile -FileRecord $file)) {
            if ([string]$classRecord.Kind -eq 'ParseError') { $warnings += ('Failed parsing {0}: {1}' -f $classRecord.SourcePath, $classRecord.Error) }
            elseif (-not [string]::IsNullOrWhiteSpace([string]$classRecord.ClassName)) { $classRecords += (ConvertTo-UGSMDayZProfileClassRecord -ClassRecord $classRecord) }
        }
    }

    $sortedMods = @($enabledMods | Sort-Object `
        @{ Expression = { Get-UGSMDayZObjectValue -Object $_ -Name 'LoadOrder' -Default 999999 } },
        @{ Expression = { [string](Get-UGSMDayZObjectValue -Object $_ -Name 'Name' -Default (Get-UGSMDayZObjectValue -Object $_ -Name 'Id' -Default '')) } })

    foreach ($mod in $sortedMods) {
        $report = Find-UGSMDayZModConfigFiles -Instance $Instance -Mod $mod
        $modReports += [pscustomobject]@{
            Id=$report.Id; Name=$report.Name; FolderName=$report.FolderName; SourcePath=$report.SourcePath
            LoadOrder=$report.LoadOrder; Enabled=$true; FileCount=@($report.Files).Count; Warnings=@($report.Warnings)
        }
        foreach ($warning in @($report.Warnings)) { $warnings += [string]$warning }
        foreach ($file in @($report.Files)) {
            $fileRecords += $file
            foreach ($classRecord in @(Get-UGSMDayZClassNamesFromXmlFile -FileRecord $file)) {
                if ([string]$classRecord.Kind -eq 'ParseError') { $warnings += ('Failed parsing {0}: {1}' -f $classRecord.SourcePath, $classRecord.Error) }
                elseif (-not [string]::IsNullOrWhiteSpace([string]$classRecord.ClassName)) { $classRecords += $classRecord }
            }
        }
    }

    $fullClassRecords = @($classRecords | Sort-Object ClassName, Kind, Source, SourceModName, SourcePath -Unique)
    $uniqueClassNames = @(ConvertTo-UGSMDayZUniqueClassNameLibrary -Records $fullClassRecords)
    $finished = Get-Date

    $instanceId = [string](Get-UGSMDayZObjectValue -Object $Instance -Name 'Id' -Default '')
    $instanceName = [string](Get-UGSMDayZObjectValue -Object $Instance -Name 'Name' -Default $instanceId)
    $profileFileCount = @($profileReport.Files).Count

    $activeModsCache = [pscustomobject]@{ GeneratedAt=$finished.ToString('s'); InstanceId=$instanceId; InstanceName=$instanceName; Count=@($modReports).Count; Mods=@($modReports) }
    $filesIndex = [pscustomobject]@{ GeneratedAt=$finished.ToString('s'); InstanceId=$instanceId; InstanceName=$instanceName; SelectedMission=$profileReport.SelectedMission; Count=@($fileRecords).Count; ProfileFileCount=$profileFileCount; ModFileCount=(@($fileRecords).Count - $profileFileCount); Files=@($fileRecords | Sort-Object LoadOrder, ModName, Kind, Path) }
    $classnames = [pscustomobject]@{ GeneratedAt=$finished.ToString('s'); InstanceId=$instanceId; InstanceName=$instanceName; SelectedMission=$profileReport.SelectedMission; Count=@($uniqueClassNames).Count; FullRecordCount=@($fullClassRecords).Count; Items=@($uniqueClassNames) }
    $classnamesFull = [pscustomobject]@{ GeneratedAt=$finished.ToString('s'); InstanceId=$instanceId; InstanceName=$instanceName; SelectedMission=$profileReport.SelectedMission; Count=@($fullClassRecords).Count; Items=@($fullClassRecords) }
    $scanReport = [pscustomobject]@{
        StartedAt=$started.ToString('s'); FinishedAt=$finished.ToString('s'); DurationSeconds=[math]::Round(($finished - $started).TotalSeconds, 2)
        InstanceId=$instanceId; InstanceName=$instanceName; SelectedMission=$profileReport.SelectedMission
        ProfileFileCount=$profileFileCount; ActiveModCount=@($modReports).Count; FileCount=@($fileRecords).Count
        ClassNameCount=@($uniqueClassNames).Count; FullClassRecordCount=@($fullClassRecords).Count
        WarningCount=@($warnings).Count; Warnings=@($warnings)
    }

    Write-UGSMDayZCacheJson -Path $paths.ActiveModsCachePath -Data $activeModsCache | Out-Null
    Write-UGSMDayZCacheJson -Path $paths.FilesIndexPath -Data $filesIndex | Out-Null
    Write-UGSMDayZCacheJson -Path $paths.ClassNamesCachePath -Data $classnames | Out-Null
    Write-UGSMDayZCacheJson -Path (Join-Path $paths.CacheFolder 'classnames-full.json') -Data $classnamesFull | Out-Null
    Write-UGSMDayZCacheJson -Path (Join-Path $paths.CacheFolder 'scan-report.json') -Data $scanReport | Out-Null

    try {
        $logLine = '[{0}] Scanned mission {1}, {2} profile files, {3} active mods, {4} total files, {5} unique classnames ({6} records), {7} warnings.' -f $finished.ToString('s'), $profileReport.SelectedMission, $profileFileCount, @($modReports).Count, @($fileRecords).Count, @($uniqueClassNames).Count, @($fullClassRecords).Count, @($warnings).Count
        Add-Content -LiteralPath (Join-Path $paths.LogsFolder 'scan.log') -Value $logLine -Encoding UTF8
    } catch { }

    return $scanReport
}

# ============================================================
# v8 override: avoid Generic.List containers in the unique classname
# library builder. Some WinPS/PowerShell event paths can throw
# "Argument types do not match" when generic list properties are
# later serialized or added to from mixed object sources.
# ============================================================
function ConvertTo-UGSMDayZUniqueClassNameLibrary {
    [CmdletBinding()]
    param([object[]]$Records)

    $byName = @{}

    foreach ($record in @($Records)) {
        $name = [string](Get-UGSMDayZObjectValue -Object $record -Name 'ClassName' -Default '')
        if ([string]::IsNullOrWhiteSpace($name)) { continue }

        $name = $name.Trim()
        if ([string]::IsNullOrWhiteSpace($name)) { continue }
        if ($name -match '^[-+]?\d+(\.\d+)?$') { continue }
        if ($name.Length -lt 2) { continue }

        $key = $name.ToLowerInvariant()
        if (-not $byName.ContainsKey($key)) {
            $byName[$key] = [ordered]@{
                ClassName = $name
                Kind = ''
                Source = ''
                SourceModId = ''
                SourceModName = ''
                Kinds = @{}
                Sources = @{}
                SourceFiles = @{}
                SourceMods = @{}
            }
        }

        $entry = $byName[$key]
        $kind = [string](Get-UGSMDayZObjectValue -Object $record -Name 'Kind' -Default '')
        $source = [string](Get-UGSMDayZObjectValue -Object $record -Name 'Source' -Default '')
        $modId = [string](Get-UGSMDayZObjectValue -Object $record -Name 'SourceModId' -Default '')
        $modName = [string](Get-UGSMDayZObjectValue -Object $record -Name 'SourceModName' -Default '')
        $sourceFile = [string](Get-UGSMDayZObjectValue -Object $record -Name 'SourceFile' -Default '')

        if ([string]::IsNullOrWhiteSpace([string]$entry.Kind)) { $entry.Kind = $kind }
        if ([string]::IsNullOrWhiteSpace([string]$entry.Source)) { $entry.Source = $source }
        if ([string]::IsNullOrWhiteSpace([string]$entry.SourceModId)) { $entry.SourceModId = $modId }
        if ([string]::IsNullOrWhiteSpace([string]$entry.SourceModName)) { $entry.SourceModName = $modName }

        if (-not [string]::IsNullOrWhiteSpace($kind)) { $entry.Kinds[$kind] = $true }
        if (-not [string]::IsNullOrWhiteSpace($source)) { $entry.Sources[$source] = $true }
        if (-not [string]::IsNullOrWhiteSpace($sourceFile)) { $entry.SourceFiles[$sourceFile] = $true }

        $sourceModKey = if ([string]::IsNullOrWhiteSpace($modId)) { ('Profile|{0}' -f $modName) } else { ('Mod|{0}' -f $modId) }
        if (-not $entry.SourceMods.ContainsKey($sourceModKey)) {
            $entry.SourceMods[$sourceModKey] = [pscustomobject]@{ Id=$modId; Name=$modName; Source=$source }
        }

        # Prefer Item as the compatibility Kind shown to existing UI code.
        if ([string]$entry.Kind -ne 'Item' -and $kind -eq 'Item') { $entry.Kind = 'Item' }

        # Prefer Mod as the main source when the classname exists in both profile and mod sources.
        if ([string]$entry.Source -ne 'Mod' -and $source -eq 'Mod') {
            $entry.Source = 'Mod'
            $entry.SourceModId = $modId
            $entry.SourceModName = $modName
        }
    }

    $items = @()
    foreach ($entry in $byName.Values) {
        $items += [pscustomobject]@{
            ClassName = [string]$entry.ClassName
            Kind = [string]$entry.Kind
            Source = [string]$entry.Source
            SourceModId = [string]$entry.SourceModId
            SourceModName = [string]$entry.SourceModName
            Kinds = @($entry.Kinds.Keys | Sort-Object -Unique)
            Sources = @($entry.Sources.Keys | Sort-Object -Unique)
            SourceMods = @($entry.SourceMods.Values)
            SourceFiles = @($entry.SourceFiles.Keys | Sort-Object -Unique)
        }
    }

    return @($items | Sort-Object ClassName)
}


# ============================================================
# v9 override: flexible mod config/classname scanning
# - Mod folders can use names like FOG_Types.xml, FOG_spawnabletypes.xml
# - Mod folders can include one-classname-per-line TXT files like ALL_CLASSNAMES.txt
# - Profile/vanilla scan remains strict/selective from the active mission only
# ============================================================

function Get-UGSMDayZModConfigKindFromFileName {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$FileName)

    $name = ([string]$FileName).ToLowerInvariant()

    if ($name -match 'spawnabletypes' -or $name -match 'cfgspawnabletypes') { return 'cfgspawnabletypes' }
    if ($name -match 'eventgroups' -or $name -match 'cfgeventgroups') { return 'cfgeventgroups' }
    if ($name -match 'eventspawns' -or $name -match 'cfgeventspawns') { return 'cfgeventspawns' }
    if ($name -match 'events') { return 'events' }
    if ($name -match 'cfgvehicles') { return 'cfgvehicles' }
    if ($name -match 'types') { return 'types' }
    if ($name -match 'class[_\-\s]*names' -or $name -match 'classnames') { return 'classnames_txt' }

    return ''
}

function Test-UGSMDayZUsefulModConfigFile {
    [CmdletBinding()]
    param([Parameter(Mandatory)][System.IO.FileInfo]$File)

    $name = $File.Name.ToLowerInvariant()
    $ext = $File.Extension.ToLowerInvariant()

    if ($ext -eq '.xml') {
        if ($name -match 'spawnabletypes') { return $true }
        if ($name -match 'eventgroups') { return $true }
        if ($name -match 'eventspawns') { return $true }
        if ($name -match 'events') { return $true }
        if ($name -match 'cfgvehicles') { return $true }
        if ($name -match 'types') { return $true }
        return $false
    }

    if ($ext -eq '.txt') {
        if ($name -match 'class[_\-\s]*names' -or $name -match 'classnames') { return $true }
        return $false
    }

    return $false
}

function Find-UGSMDayZModConfigFiles {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$Instance,
        [Parameter(Mandatory)][object]$Mod
    )

    $id = [string](Get-UGSMDayZObjectValue -Object $Mod -Name 'Id' -Default '')
    $name = [string](Get-UGSMDayZObjectValue -Object $Mod -Name 'Name' -Default $id)
    $folderName = [string](Get-UGSMDayZObjectValue -Object $Mod -Name 'FolderName' -Default '')
    $loadOrder = Get-UGSMDayZObjectValue -Object $Mod -Name 'LoadOrder' -Default 999999

    $sourcePath = $null
    foreach ($candidate in @(Get-UGSMDayZModSourcePathCandidates -Instance $Instance -Mod $Mod)) {
        if (Test-Path -LiteralPath $candidate -PathType Container) {
            $sourcePath = [string]$candidate
            break
        }
    }

    $warnings = @()
    $files = @()

    if ([string]::IsNullOrWhiteSpace($sourcePath)) {
        $warnings += ('SourcePath missing or not found for mod {0} ({1}).' -f $name, $id)
    }
    else {
        try {
            $candidateFiles = @(Get-ChildItem -LiteralPath $sourcePath -Recurse -File -ErrorAction SilentlyContinue | Where-Object {
                Test-UGSMDayZUsefulModConfigFile -File $_
            })

            foreach ($file in $candidateFiles) {
                $kind = Get-UGSMDayZModConfigKindFromFileName -FileName $file.Name
                if ([string]::IsNullOrWhiteSpace($kind)) { continue }

                $relative = [string]$file.FullName
                if ($relative.StartsWith($sourcePath, [System.StringComparison]::OrdinalIgnoreCase)) {
                    $relative = $relative.Substring($sourcePath.Length) -replace '^[\\/]+', ''
                }

                $files += [pscustomobject]@{
                    ModId = $id
                    ModName = $name
                    FolderName = $folderName
                    LoadOrder = $loadOrder
                    Source = 'Mod'
                    SourceType = 'Mod'
                    Kind = $kind
                    FileName = $file.Name
                    Path = $file.FullName
                    RelativePath = $relative
                    Length = $file.Length
                    LastWriteTime = $file.LastWriteTime.ToString('s')
                }
            }
        }
        catch {
            $warnings += ('Failed scanning files for mod {0}: {1}' -f $name, [string]$_.Exception.Message)
        }
    }

    return [pscustomobject]@{
        Id = $id
        Name = $name
        FolderName = $folderName
        SourcePath = [string]$sourcePath
        LoadOrder = $loadOrder
        Enabled = $true
        Files = @($files)
        Warnings = @($warnings)
    }
}

function Get-UGSMDayZClassNamesFromTextFile {
    [CmdletBinding()]
    param([Parameter(Mandatory)][object]$FileRecord)

    $classNames = New-Object System.Collections.ArrayList
    $seen = @{}
    $path = [string](Get-UGSMDayZObjectValue -Object $FileRecord -Name 'Path' -Default '')
    if ([string]::IsNullOrWhiteSpace($path) -or -not (Test-Path -LiteralPath $path -PathType Leaf)) { return @() }

    $inUnusedBlock = $false

    try {
        $lines = @(Get-Content -LiteralPath $path -ErrorAction Stop)
        foreach ($rawLine in $lines) {
            $line = ([string]$rawLine).Trim()

            if ([string]::IsNullOrWhiteSpace($line)) { continue }

            # FOG's ALL_CLASSNAMES.txt has an UNUSED block with old names and replacement notes.
            if ($line -match '^\s*<--\s*UNUSED CLASSNAMES\s*-->\s*$') {
                $inUnusedBlock = $true
                continue
            }
            if ($line -match '^\s*<--\s*UNUSED CLASSNAMES END\s*-->\s*$') {
                $inUnusedBlock = $false
                continue
            }
            if ($inUnusedBlock) { continue }

            # Section headers/comments are not classnames.
            if ($line -match '^\s*<--.*-->\s*$') { continue }
            if ($line.StartsWith('#') -or $line.StartsWith('//') -or $line.StartsWith(';')) { continue }
            if ($line.StartsWith('(')) { continue }

            # Drop inline comments. Classnames should not contain spaces.
            $line = ($line -replace '\s+//.*$', '').Trim()
            $line = ($line -replace '\s+#.*$', '').Trim()

            # Replacement/documentation lines are not direct classnames.
            if ($line -match '\s+>\s+' -or $line -match '\s+replace\s+with\s+') { continue }

            # Keep simple DayZ classname tokens only.
            if ($line -notmatch '^[A-Za-z_][A-Za-z0-9_]*$') { continue }

            Add-UGSMDayZClassNameResult `
                -List $classNames `
                -Seen $seen `
                -ClassName $line `
                -Kind 'ClassNameList' `
                -FileRecord $FileRecord `
                -SourceField 'txt.line'
        }
    }
    catch {
        return @([pscustomobject]@{
            ClassName=''
            Kind='ParseError'
            Source='Mod'
            SourceModId=[string](Get-UGSMDayZObjectValue -Object $FileRecord -Name 'ModId' -Default '')
            SourceModName=[string](Get-UGSMDayZObjectValue -Object $FileRecord -Name 'ModName' -Default '')
            SourceFile=[string](Get-UGSMDayZObjectValue -Object $FileRecord -Name 'FileName' -Default '')
            SourcePath=$path
            SourceField='txt'
            Error=[string]$_.Exception.Message
        })
    }

    return @($classNames)
}

function Get-UGSMDayZClassNamesFromXmlFile {
    [CmdletBinding()]
    param([Parameter(Mandatory)][object]$FileRecord)

    $kind = [string](Get-UGSMDayZObjectValue -Object $FileRecord -Name 'Kind' -Default '')
    $path = [string](Get-UGSMDayZObjectValue -Object $FileRecord -Name 'Path' -Default '')

    if ($kind -eq 'classnames_txt' -or ([System.IO.Path]::GetExtension($path) -ieq '.txt')) {
        return @(Get-UGSMDayZClassNamesFromTextFile -FileRecord $FileRecord)
    }

    $classNames = New-Object System.Collections.ArrayList
    $seen = @{}
    if ([string]::IsNullOrWhiteSpace($path) -or -not (Test-Path -LiteralPath $path -PathType Leaf)) { return @() }

    try {
        [xml]$xml = Get-Content -LiteralPath $path -Raw -ErrorAction Stop
    }
    catch {
        return @([pscustomobject]@{
            ClassName=''
            Kind='ParseError'
            Source=[string](Get-UGSMDayZObjectValue -Object $FileRecord -Name 'Source' -Default 'Mod')
            SourceModId=[string](Get-UGSMDayZObjectValue -Object $FileRecord -Name 'ModId' -Default '')
            SourceModName=[string](Get-UGSMDayZObjectValue -Object $FileRecord -Name 'ModName' -Default '')
            SourceFile=[string](Get-UGSMDayZObjectValue -Object $FileRecord -Name 'FileName' -Default '')
            SourcePath=$path
            SourceField='xml'
            Error=[string]$_.Exception.Message
        })
    }

    if ($kind -eq 'types') {
        foreach ($node in @($xml.SelectNodes('//type[@name]'))) {
            Add-UGSMDayZClassNameResult -List $classNames -Seen $seen -ClassName ([string]$node.name) -Kind 'Item' -FileRecord $FileRecord -SourceField 'type.name'
        }
    }
    elseif ($kind -eq 'cfgspawnabletypes') {
        foreach ($node in @($xml.SelectNodes('//type[@name]'))) {
            Add-UGSMDayZClassNameResult -List $classNames -Seen $seen -ClassName ([string]$node.name) -Kind 'SpawnableType' -FileRecord $FileRecord -SourceField 'type.name'
        }
        foreach ($node in @($xml.SelectNodes('//item[@name]'))) {
            Add-UGSMDayZClassNameResult -List $classNames -Seen $seen -ClassName ([string]$node.name) -Kind 'SpawnableItem' -FileRecord $FileRecord -SourceField 'item.name'
        }
    }
    elseif ($kind -eq 'events') {
        foreach ($node in @($xml.SelectNodes('//child[@type]'))) {
            Add-UGSMDayZClassNameResult -List $classNames -Seen $seen -ClassName ([string]$node.type) -Kind 'EventChild' -FileRecord $FileRecord -SourceField 'child.type'
        }
    }
    elseif ($kind -eq 'cfgvehicles') {
        foreach ($node in @($xml.SelectNodes('//*[@name]'))) {
            Add-UGSMDayZClassNameResult -List $classNames -Seen $seen -ClassName ([string]$node.name) -Kind 'VehicleConfig' -FileRecord $FileRecord -SourceField 'node.name'
        }
        foreach ($node in @($xml.SelectNodes('//*[@type]'))) {
            Add-UGSMDayZClassNameResult -List $classNames -Seen $seen -ClassName ([string]$node.type) -Kind 'VehicleConfig' -FileRecord $FileRecord -SourceField 'node.type'
        }
    }
    else {
        # Conservative fallback for mod-named XML files. This catches useful class names
        # without scanning generic numeric config values.
        foreach ($node in @($xml.SelectNodes('//type[@name]'))) {
            Add-UGSMDayZClassNameResult -List $classNames -Seen $seen -ClassName ([string]$node.name) -Kind 'Item' -FileRecord $FileRecord -SourceField 'type.name'
        }
        foreach ($node in @($xml.SelectNodes('//item[@name]'))) {
            Add-UGSMDayZClassNameResult -List $classNames -Seen $seen -ClassName ([string]$node.name) -Kind 'SpawnableItem' -FileRecord $FileRecord -SourceField 'item.name'
        }
        foreach ($node in @($xml.SelectNodes('//child[@type]'))) {
            Add-UGSMDayZClassNameResult -List $classNames -Seen $seen -ClassName ([string]$node.type) -Kind 'EventChild' -FileRecord $FileRecord -SourceField 'child.type'
        }
    }

    return @($classNames)
}

# ============================================================
# v10: DayZ live db\types.xml merge helpers
# Scanner stays read-only. These functions are explicit merge/apply actions.
# ============================================================

function Get-UGSMDayZLiveTypesXmlPath {
    [CmdletBinding()]
    param([Parameter(Mandatory)][object]$Instance)

    $profilePath = Get-UGSMDayZProfilePath -Instance $Instance
    if ([string]::IsNullOrWhiteSpace($profilePath)) { return '' }

    $missionName = Get-UGSMDayZSelectedMissionName -Instance $Instance
    return (Join-Path $profilePath (Join-Path (Join-Path 'mpmissions' $missionName) (Join-Path 'db' 'types.xml')))
}

function Read-UGSMDayZJsonFileSafe {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Path,
        [object]$Default = $null
    )

    if ([string]::IsNullOrWhiteSpace($Path) -or -not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        return $Default
    }

    try {
        return (Get-Content -LiteralPath $Path -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop)
    }
    catch {
        return $Default
    }
}

function Get-UGSMDayZCachedFileIndex {
    [CmdletBinding()]
    param([Parameter(Mandatory)][object]$Instance)

    $paths = Get-UGSMDayZInstanceStoragePaths -Instance $Instance -Create
    $data = Read-UGSMDayZJsonFileSafe -Path $paths.FilesIndexPath -Default $null
    if ($null -eq $data) { return @() }
    return @($data.Files)
}

function Get-UGSMDayZCachedModTypeFileRecords {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$Instance,
        [string]$ModId = ''
    )

    $files = @(Get-UGSMDayZCachedFileIndex -Instance $Instance)
    $records = @()

    foreach ($file in $files) {
        $source = [string](Get-UGSMDayZObjectValue -Object $file -Name 'Source' -Default '')
        $kind = [string](Get-UGSMDayZObjectValue -Object $file -Name 'Kind' -Default '')
        $fileModId = [string](Get-UGSMDayZObjectValue -Object $file -Name 'ModId' -Default '')

        if ($source -ne 'Mod') { continue }
        if ($kind -ne 'types') { continue }
        if (-not [string]::IsNullOrWhiteSpace($ModId) -and $fileModId -ne $ModId) { continue }

        $path = [string](Get-UGSMDayZObjectValue -Object $file -Name 'Path' -Default '')
        if ([string]::IsNullOrWhiteSpace($path) -or -not (Test-Path -LiteralPath $path -PathType Leaf)) { continue }

        $records += $file
    }

    return @($records)
}

function Get-UGSMDayZTypeNodesFromFileRecord {
    [CmdletBinding()]
    param([Parameter(Mandatory)][object]$FileRecord)

    $path = [string](Get-UGSMDayZObjectValue -Object $FileRecord -Name 'Path' -Default '')
    if ([string]::IsNullOrWhiteSpace($path) -or -not (Test-Path -LiteralPath $path -PathType Leaf)) { return @() }

    try {
        [xml]$xml = Get-Content -LiteralPath $path -Raw -ErrorAction Stop
        return @($xml.SelectNodes('//type[@name]'))
    }
    catch {
        return @()
    }
}

function Get-UGSMDayZExistingTypeNameSet {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$TypesXmlPath)

    $set = @{}
    if ([string]::IsNullOrWhiteSpace($TypesXmlPath) -or -not (Test-Path -LiteralPath $TypesXmlPath -PathType Leaf)) { return $set }

    try {
        [xml]$xml = Get-Content -LiteralPath $TypesXmlPath -Raw -ErrorAction Stop
        foreach ($node in @($xml.SelectNodes('//type[@name]'))) {
            $name = [string]$node.GetAttribute('name')
            if (-not [string]::IsNullOrWhiteSpace($name)) {
                $set[$name.ToLowerInvariant()] = $true
            }
        }
    }
    catch { }

    return $set
}

function New-UGSMDayZTypesMergePlan {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$Instance,
        [string]$ModId = '',
        [switch]$WritePlan
    )

    $paths = Get-UGSMDayZInstanceStoragePaths -Instance $Instance -Create
    $typesPath = Get-UGSMDayZLiveTypesXmlPath -Instance $Instance
    if ([string]::IsNullOrWhiteSpace($typesPath)) {
        throw 'Could not resolve live DayZ db\types.xml path for this instance.'
    }
    if (-not (Test-Path -LiteralPath $typesPath -PathType Leaf)) {
        throw ('Live DayZ db\types.xml was not found: {0}' -f $typesPath)
    }

    $existing = Get-UGSMDayZExistingTypeNameSet -TypesXmlPath $typesPath
    $modTypeFiles = @(Get-UGSMDayZCachedModTypeFileRecords -Instance $Instance -ModId $ModId)

    $seenIncoming = @{}
    $entries = @()
    $addCount = 0
    $skipExistingCount = 0
    $skipDuplicateIncomingCount = 0

    foreach ($file in $modTypeFiles) {
        $fileModId = [string](Get-UGSMDayZObjectValue -Object $file -Name 'ModId' -Default '')
        $fileModName = [string](Get-UGSMDayZObjectValue -Object $file -Name 'ModName' -Default $fileModId)
        $sourceFile = [string](Get-UGSMDayZObjectValue -Object $file -Name 'FileName' -Default '')
        $sourcePath = [string](Get-UGSMDayZObjectValue -Object $file -Name 'Path' -Default '')

        foreach ($node in @(Get-UGSMDayZTypeNodesFromFileRecord -FileRecord $file)) {
            $name = [string]$node.GetAttribute('name')
            if ([string]::IsNullOrWhiteSpace($name)) { continue }

            $key = $name.ToLowerInvariant()
            $action = 'Add'
            $reason = ''

            if ($existing.ContainsKey($key)) {
                $action = 'Skip'
                $reason = 'AlreadyExistsInLiveTypes'
                $skipExistingCount++
            }
            elseif ($seenIncoming.ContainsKey($key)) {
                $action = 'Skip'
                $reason = 'DuplicateIncomingType'
                $skipDuplicateIncomingCount++
            }
            else {
                $seenIncoming[$key] = $true
                $addCount++
            }

            $entries += [pscustomobject]@{
                ClassName = $name
                Action = $action
                Reason = $reason
                SourceModId = $fileModId
                SourceModName = $fileModName
                SourceFile = $sourceFile
                SourcePath = $sourcePath
            }
        }
    }

    $plan = [pscustomobject]@{
        GeneratedAt = (Get-Date).ToString('s')
        InstanceId = [string](Get-UGSMDayZObjectValue -Object $Instance -Name 'Id' -Default '')
        InstanceName = [string](Get-UGSMDayZObjectValue -Object $Instance -Name 'Name' -Default '')
        SelectedMission = Get-UGSMDayZSelectedMissionName -Instance $Instance
        LiveTypesPath = $typesPath
        RequestedModId = $ModId
        ModTypeFileCount = @($modTypeFiles).Count
        TotalIncomingTypeCount = @($entries).Count
        AddCount = $addCount
        SkipExistingCount = $skipExistingCount
        SkipDuplicateIncomingCount = $skipDuplicateIncomingCount
        Entries = @($entries)
    }

    if ($WritePlan) {
        $planPath = Join-Path $paths.GeneratedFolder 'types-merge-plan.json'
        Write-UGSMDayZCacheJson -Path $planPath -Data $plan -Depth 64 | Out-Null
    }

    return $plan
}

function Save-UGSMDayZXmlDocumentUtf8 {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][xml]$Xml,
        [Parameter(Mandatory)][string]$Path
    )

    $settings = New-Object System.Xml.XmlWriterSettings
    $settings.Indent = $true
    $settings.IndentChars = '    '
    $settings.NewLineChars = "`r`n"
    $settings.NewLineHandling = [System.Xml.NewLineHandling]::Replace
    $settings.Encoding = New-Object System.Text.UTF8Encoding($false)

    $writer = [System.Xml.XmlWriter]::Create($Path, $settings)
    try {
        $Xml.Save($writer)
    }
    finally {
        if ($writer) { $writer.Close() }
    }
}


function ConvertTo-UGSMDayZXPathLiteral {
    [CmdletBinding()]
    param([AllowNull()][string]$Value)

    $text = [string]$Value
    if (-not $text.Contains("'")) { return ("'{0}'" -f $text) }
    if (-not $text.Contains('"')) { return ('"{0}"' -f $text) }

    $parts = @()
    foreach ($part in $text.Split("'")) {
        if ($part.Length -gt 0) { $parts += ("'{0}'" -f $part) }
        $parts += '"''"'
    }

    if ($parts.Count -gt 0 -and $parts[-1] -eq '"''"') {
        $parts = @($parts | Select-Object -First ($parts.Count - 1))
    }

    return ('concat({0})' -f ($parts -join ','))
}


function Ensure-UGSMDayZTypeNodeHasDefaultFlags {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][xml]$Xml,
        [Parameter(Mandatory)][System.Xml.XmlElement]$TypeNode
    )

    if ($null -eq $Xml -or $null -eq $TypeNode) { return @() }

    $changes = @()
    $flags = $TypeNode.SelectSingleNode('./flags')
    if ($null -eq $flags) {
        $flags = $Xml.CreateElement('flags')
        [void]$flags.SetAttribute('count_in_cargo', '0')
        [void]$flags.SetAttribute('count_in_hoarder', '0')
        [void]$flags.SetAttribute('count_in_map', '1')
        [void]$flags.SetAttribute('count_in_player', '0')
        [void]$flags.SetAttribute('crafted', '0')
        [void]$flags.SetAttribute('deloot', '0')

        $insertBefore = $null
        foreach ($laterName in @('category','usage','value','tag')) {
            $laterNode = $TypeNode.SelectSingleNode('./' + $laterName)
            if ($null -ne $laterNode) { $insertBefore = $laterNode; break }
        }

        if ($null -ne $insertBefore) { [void]$TypeNode.InsertBefore($flags, $insertBefore) }
        else { [void]$TypeNode.AppendChild($flags) }

        $changes += 'AddedElement:flags(default)'
    }

    foreach ($pair in @(
        @{ N='count_in_cargo'; V='0' },
        @{ N='count_in_hoarder'; V='0' },
        @{ N='count_in_map'; V='1' },
        @{ N='count_in_player'; V='0' },
        @{ N='crafted'; V='0' },
        @{ N='deloot'; V='0' }
    )) {
        if (-not $flags.HasAttribute([string]$pair.N)) {
            [void]$flags.SetAttribute([string]$pair.N, [string]$pair.V)
            $changes += ('AddedFlagAttribute:{0}(default)' -f [string]$pair.N)
        }
    }

    return @($changes)
}

function Merge-UGSMDayZMissingTypeNodeContent {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][xml]$LiveXml,
        [Parameter(Mandatory)][System.Xml.XmlElement]$LiveTypeNode,
        [Parameter(Mandatory)][System.Xml.XmlElement]$IncomingTypeNode
    )

    $changes = @()

    # Only fill missing economy child elements. Do not overwrite live/user-tuned values.
    $orderedChildren = @('nominal','lifetime','restock','min','max','quantmin','quantmax','cost')

    foreach ($childName in $orderedChildren) {
        $incomingChild = $IncomingTypeNode.SelectSingleNode('./' + $childName)
        if ($null -eq $incomingChild) { continue }

        $liveChild = $LiveTypeNode.SelectSingleNode('./' + $childName)
        if ($null -ne $liveChild) { continue }

        $importedChild = $LiveXml.ImportNode($incomingChild, $true)

        $insertBefore = $null
        $currentIndex = [array]::IndexOf($orderedChildren, $childName)
        foreach ($laterName in @($orderedChildren | Select-Object -Skip ($currentIndex + 1))) {
            $laterNode = $LiveTypeNode.SelectSingleNode('./' + $laterName)
            if ($null -ne $laterNode) {
                $insertBefore = $laterNode
                break
            }
        }

        if ($null -ne $insertBefore) {
            [void]$LiveTypeNode.InsertBefore($importedChild, $insertBefore)
        }
        else {
            [void]$LiveTypeNode.AppendChild($importedChild)
        }

        $changes += ('AddedElement:{0}' -f $childName)
    }

    # Fill missing flags/flag attributes from the mod type block. This preserves edited live values.
    $incomingFlags = $IncomingTypeNode.SelectSingleNode('./flags')
    if ($null -ne $incomingFlags) {
        $liveFlags = $LiveTypeNode.SelectSingleNode('./flags')

        if ($null -eq $liveFlags) {
            $importedFlags = $LiveXml.ImportNode($incomingFlags, $true)

            $insertBefore = $null
            foreach ($laterName in @('category','usage','value','tag')) {
                $laterNode = $LiveTypeNode.SelectSingleNode('./' + $laterName)
                if ($null -ne $laterNode) {
                    $insertBefore = $laterNode
                    break
                }
            }

            if ($null -ne $insertBefore) {
                [void]$LiveTypeNode.InsertBefore($importedFlags, $insertBefore)
            }
            else {
                [void]$LiveTypeNode.AppendChild($importedFlags)
            }

            $changes += 'AddedElement:flags'
        }
        else {
            foreach ($attr in @($incomingFlags.Attributes)) {
                if ($null -eq $attr) { continue }
                $attrName = [string]$attr.Name
                if ([string]::IsNullOrWhiteSpace($attrName)) { continue }

                if (-not $liveFlags.HasAttribute($attrName)) {
                    [void]$liveFlags.SetAttribute($attrName, [string]$attr.Value)
                    $changes += ('AddedFlagAttribute:{0}' -f $attrName)
                }
            }
        }
    }

    if (@($changes).Count -eq 0) {
        $defaultChanges = @(Ensure-UGSMDayZTypeNodeHasDefaultFlags -Xml $LiveXml -TypeNode $LiveTypeNode)
        if (@($defaultChanges).Count -gt 0) { $changes += $defaultChanges }
    }

    return @($changes)
}

function Add-UGSMDayZTypeNodesToLiveTypes {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$Instance,
        [string]$ModId = ''
    )

    $paths = Get-UGSMDayZInstanceStoragePaths -Instance $Instance -Create
    $typesPath = Get-UGSMDayZLiveTypesXmlPath -Instance $Instance
    if ([string]::IsNullOrWhiteSpace($typesPath) -or -not (Test-Path -LiteralPath $typesPath -PathType Leaf)) {
        throw ('Live DayZ db\types.xml was not found: {0}' -f $typesPath)
    }

    $plan = New-UGSMDayZTypesMergePlan -Instance $Instance -ModId $ModId -WritePlan

    $entriesToAdd = @(
        $plan.Entries | Where-Object {
            [string]$_.Action -eq 'Add'
        }
    )

    # Reconcile ownership even when an entry already exists in live types.xml.
    # This is the critical fix for mods whose items already exist in types.xml
    # but no longer have a live AddType entry in mod-contributions.json.
    $entriesToOwn = @(
        $plan.Entries | Where-Object {
            ([string]$_.Action -eq 'Add') -or
            (
                ([string]$_.Action -eq 'Skip') -and
                ([string]$_.Reason -eq 'AlreadyExistsInLiveTypes')
            )
        }
    )

    $backupPath = ''
    $liveXml = $null
    $root = $null

    if (@($entriesToOwn).Count -gt 0) {
        $backupPath = Backup-UGSMDayZLiveFileOnce -Instance $Instance -Path $typesPath

        [xml]$liveXml = Get-Content -LiteralPath $typesPath -Raw -ErrorAction Stop
        $root = $liveXml.DocumentElement
        if ($null -eq $root -or $root.Name -ne 'types') {
            throw 'Live types.xml root node is not <types>.'
        }
    }

    $entriesByKey = @{}
    foreach ($entry in $entriesToAdd) {
        $entriesByKey[[string]$entry.ClassName] = $entry
    }

    $added = @()
    $addedKeys = @{}

    if (@($entriesToAdd).Count -gt 0) {
        $modTypeFiles = @(Get-UGSMDayZCachedModTypeFileRecords -Instance $Instance -ModId $ModId)
        foreach ($file in $modTypeFiles) {
            foreach ($node in @(Get-UGSMDayZTypeNodesFromFileRecord -FileRecord $file)) {
                $name = [string]$node.GetAttribute('name')
                if ([string]::IsNullOrWhiteSpace($name)) { continue }
                if (-not $entriesByKey.ContainsKey($name)) { continue }

                $nameKey = $name.ToLowerInvariant()
                if ($addedKeys.ContainsKey($nameKey)) { continue }

                $imported = $liveXml.ImportNode($node, $true)
                [void](Ensure-UGSMDayZTypeNodeHasDefaultFlags -Xml $liveXml -TypeNode ([System.Xml.XmlElement]$imported))
                [void]$root.AppendChild($liveXml.CreateWhitespace("`r`n    "))
                [void]$root.AppendChild($imported)

                $entry = $entriesByKey[$name]
                $added += [pscustomobject]@{
                    ClassName     = $name
                    SourceModId   = [string]$entry.SourceModId
                    SourceModName = [string]$entry.SourceModName
                    SourceFile    = [string]$entry.SourceFile
                    SourcePath    = [string]$entry.SourcePath
                    LiveFile      = $typesPath
                    Operation     = 'AddType'
                    AppliedAt     = (Get-Date).ToString('s')
                    BackupPath    = $backupPath
                }

                $addedKeys[$nameKey] = $true
            }
        }

    }

    $mergedExisting = @()
    if (@($entriesToOwn).Count -gt 0 -and $null -ne $liveXml -and $null -ne $root) {
        $entriesToMergeByKey = @{}
        foreach ($entry in $entriesToOwn) {
            if ($null -eq $entry) { continue }
            $className = [string]$entry.ClassName
            if (-not [string]::IsNullOrWhiteSpace($className)) {
                $entriesToMergeByKey[$className.ToLowerInvariant()] = $entry
            }
        }

        $modTypeFiles = @(Get-UGSMDayZCachedModTypeFileRecords -Instance $Instance -ModId $ModId)
        foreach ($file in $modTypeFiles) {
            foreach ($incomingNode in @(Get-UGSMDayZTypeNodesFromFileRecord -FileRecord $file)) {
                $name = [string]$incomingNode.GetAttribute('name')
                if ([string]::IsNullOrWhiteSpace($name)) { continue }

                $nameKey = $name.ToLowerInvariant()
                if (-not $entriesToMergeByKey.ContainsKey($nameKey)) { continue }

                $liveNode = $root.SelectSingleNode(('./type[@name={0}]' -f (ConvertTo-UGSMDayZXPathLiteral -Value $name)))
                if ($null -eq $liveNode) { continue }

                $changes = @(Merge-UGSMDayZMissingTypeNodeContent -LiveXml $liveXml -LiveTypeNode ([System.Xml.XmlElement]$liveNode) -IncomingTypeNode ([System.Xml.XmlElement]$incomingNode))
                if (@($changes).Count -le 0) { continue }

                $entry = $entriesToMergeByKey[$nameKey]
                $mergedExisting += [pscustomobject]@{
                    ClassName     = $name
                    SourceModId   = [string]$entry.SourceModId
                    SourceModName = [string]$entry.SourceModName
                    SourceFile    = [string]$entry.SourceFile
                    SourcePath    = [string]$entry.SourcePath
                    LiveFile      = $typesPath
                    Operation     = 'MergeMissingTypeContent'
                    Changes       = @($changes)
                    AppliedAt     = (Get-Date).ToString('s')
                    BackupPath    = $backupPath
                }
            }
        }
    }

    if (((@($added).Count + @($mergedExisting).Count) -gt 0) -and $null -ne $liveXml) {
        [void]$root.AppendChild($liveXml.CreateWhitespace("`r`n"))
        Save-UGSMDayZXmlDocumentUtf8 -Xml $liveXml -Path $typesPath
    }

    $existingContrib = Read-UGSMDayZJsonFileSafe -Path $paths.ContributionsPath -Default $null

    $oldEntries = @()
    $removedEntries = @()

    if ($null -ne $existingContrib) {
        if ($existingContrib.PSObject.Properties.Name -contains 'Entries') {
            $oldEntries = @($existingContrib.Entries)
        }
        if ($existingContrib.PSObject.Properties.Name -contains 'RemovedEntries') {
            $removedEntries = @($existingContrib.RemovedEntries)
        }
    }

    # Build lookup of existing live AddType ownership records so we can avoid duplicates
    # and reattach ownership for Skip/AlreadyExistsInLiveTypes rows.
    $existingLedgerKeys = @{}
    foreach ($existing in $oldEntries) {
        if ($null -eq $existing) { continue }

        $existingClassName = [string](Get-UGSMDayZObjectValue -Object $existing -Name 'ClassName' -Default '')
        $existingSourceModId = [string](Get-UGSMDayZObjectValue -Object $existing -Name 'SourceModId' -Default '')
        $existingOperation = [string](Get-UGSMDayZObjectValue -Object $existing -Name 'Operation' -Default '')
        $existingLiveFile = [string](Get-UGSMDayZObjectValue -Object $existing -Name 'LiveFile' -Default '')

        if ([string]::IsNullOrWhiteSpace($existingClassName)) { continue }
        if (-not ($existingOperation -eq 'AddType')) { continue }
        if ([string]::IsNullOrWhiteSpace($existingLiveFile)) { continue }

        $existingKey = '{0}|{1}|{2}|{3}' -f `
            $existingClassName.ToLowerInvariant(), `
            $existingSourceModId.ToLowerInvariant(), `
            'addtype', `
            $existingLiveFile.ToLowerInvariant()

        $existingLedgerKeys[$existingKey] = $true
    }

    $reconciledOwnership = @()
    foreach ($entry in $entriesToOwn) {
        if ($null -eq $entry) { continue }

        $className = [string]$entry.ClassName
        $sourceModId = [string]$entry.SourceModId
        $sourceModName = [string]$entry.SourceModName
        $sourceFile = [string]$entry.SourceFile
        $sourcePath = [string]$entry.SourcePath

        if ([string]::IsNullOrWhiteSpace($className)) { continue }

        $ledgerKey = '{0}|{1}|{2}|{3}' -f `
            $className.ToLowerInvariant(), `
            $sourceModId.ToLowerInvariant(), `
            'addtype', `
            $typesPath.ToLowerInvariant()

        if ($existingLedgerKeys.ContainsKey($ledgerKey)) {
            continue
        }

        $reconciledOwnership += [pscustomobject]@{
            ClassName     = $className
            SourceModId   = $sourceModId
            SourceModName = $sourceModName
            SourceFile    = $sourceFile
            SourcePath    = $sourcePath
            LiveFile      = $typesPath
            Operation     = 'AddType'
            AppliedAt     = (Get-Date).ToString('s')
            BackupPath    = $backupPath
        }

        $existingLedgerKeys[$ledgerKey] = $true
    }

    $contrib = [pscustomobject]@{
        GeneratedAt      = (Get-Date).ToString('s')
        InstanceId       = $plan.InstanceId
        InstanceName     = $plan.InstanceName
        SelectedMission  = $plan.SelectedMission
        Entries          = @($oldEntries + $reconciledOwnership)
        RemovedEntries   = @($removedEntries)
    }
    Write-UGSMDayZCacheJson -Path $paths.ContributionsPath -Data $contrib -Depth 64 | Out-Null

    $resultMessage =
        if (@($added).Count -gt 0) {
            'Added {0} type entries to live types.xml.' -f @($added).Count
        }
        elseif (@($mergedExisting).Count -gt 0) {
            'No new type entries were added, but missing content was merged into {0} existing live types.xml entries.' -f @($mergedExisting).Count
        }
        elseif (@($reconciledOwnership).Count -gt 0) {
            'No new type entries were added, but ownership was reconciled for {0} existing live types.xml entries.' -f @($reconciledOwnership).Count
        }
        else {
            'No new type entries needed to be added.'
        }

    $result = [pscustomobject]@{
        AppliedAt               = (Get-Date).ToString('s')
        InstanceId              = $plan.InstanceId
        InstanceName            = $plan.InstanceName
        LiveTypesPath           = $typesPath
        RequestedModId          = $ModId
        AddedCount              = @($added).Count
        MergedExistingCount      = @($mergedExisting).Count
        ReconciledOwnershipCount = @($reconciledOwnership).Count
        SkippedCount            = ([int]$plan.SkipExistingCount + [int]$plan.SkipDuplicateIncomingCount)
        BackupPath              = $backupPath
        ContributionsPath       = $paths.ContributionsPath
        Message                 = $resultMessage
        Added                   = @($added)
        MergedExisting          = @($mergedExisting)
        ReconciledOwnership     = @($reconciledOwnership)
        Plan                    = $plan
    }

    $resultPath = Join-Path $paths.GeneratedFolder 'types-merge-result.json'
    Write-UGSMDayZCacheJson -Path $resultPath -Data $result -Depth 64 | Out-Null

    return $result
}

function Invoke-UGSMDayZPreviewSelectedModTypesMerge {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$Instance,
        [Parameter(Mandatory)][string]$ModId
    )

    return (New-UGSMDayZTypesMergePlan -Instance $Instance -ModId $ModId -WritePlan)
}

function Invoke-UGSMDayZApplySelectedModTypesMerge {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$Instance,
        [Parameter(Mandatory)][string]$ModId
    )

    return (Add-UGSMDayZTypeNodesToLiveTypes -Instance $Instance -ModId $ModId)
}

# ============================================================
# v12: Hard pretty-format fix for DayZ db\types.xml
# XmlDocument can preserve compact imported XML. This formatter rebuilds
# whitespace nodes inside the XML tree before saving, so compact mod
# <type> entries become readable multi-line blocks.
# ============================================================

function Get-UGSMDayZIndentString {
    [CmdletBinding()]
    param([int]$Depth = 0)

    if ($Depth -le 0) { return '' }
    return ('    ' * $Depth)
}

function Format-UGSMDayZXmlElementWhitespace {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][System.Xml.XmlElement]$Element,
        [int]$Depth = 0
    )

    $elementChildren = @($Element.ChildNodes | Where-Object { $_.NodeType -eq [System.Xml.XmlNodeType]::Element })
    if (@($elementChildren).Count -eq 0) {
        return
    }

    # Remove existing whitespace-only text nodes so the formatter can rebuild a clean layout.
    foreach ($node in @($Element.ChildNodes)) {
        if ($node.NodeType -eq [System.Xml.XmlNodeType]::Whitespace) {
            [void]$Element.RemoveChild($node)
        }
        elseif ($node.NodeType -eq [System.Xml.XmlNodeType]::Text -and [string]::IsNullOrWhiteSpace([string]$node.Value)) {
            [void]$Element.RemoveChild($node)
        }
    }

    # Format child elements first.
    foreach ($child in @($Element.ChildNodes)) {
        if ($child.NodeType -eq [System.Xml.XmlNodeType]::Element) {
            Format-UGSMDayZXmlElementWhitespace -Element ([System.Xml.XmlElement]$child) -Depth ($Depth + 1)
        }
    }

    # Insert indentation before each child element.
    foreach ($child in @($Element.ChildNodes)) {
        if ($child.NodeType -eq [System.Xml.XmlNodeType]::Element) {
            $ws = $Element.OwnerDocument.CreateWhitespace("`r`n" + (Get-UGSMDayZIndentString -Depth ($Depth + 1)))
            [void]$Element.InsertBefore($ws, $child)
        }
    }

    # Indent the closing tag for this element.
    $endWs = $Element.OwnerDocument.CreateWhitespace("`r`n" + (Get-UGSMDayZIndentString -Depth $Depth))
    [void]$Element.AppendChild($endWs)
}

function Save-UGSMDayZXmlDocumentUtf8 {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][xml]$Xml,
        [Parameter(Mandatory)][string]$Path
    )

    if ($Xml -and $Xml.DocumentElement) {
        Format-UGSMDayZXmlElementWhitespace -Element $Xml.DocumentElement -Depth 0
    }

    $settings = New-Object System.Xml.XmlWriterSettings
    $settings.Indent = $false
    $settings.NewLineChars = "`r`n"
    $settings.NewLineHandling = [System.Xml.NewLineHandling]::Replace
    $settings.Encoding = New-Object System.Text.UTF8Encoding($false)

    $writer = [System.Xml.XmlWriter]::Create($Path, $settings)
    try {
        $Xml.Save($writer)
    }
    finally {
        if ($writer) { $writer.Close() }
    }
}

function Format-UGSMDayZLiveTypesXml {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$Instance,
        [switch]$Backup
    )

    $typesPath = Get-UGSMDayZLiveTypesXmlPath -Instance $Instance
    if ([string]::IsNullOrWhiteSpace($typesPath) -or -not (Test-Path -LiteralPath $typesPath -PathType Leaf)) {
        throw ('Live DayZ db\types.xml was not found: {0}' -f $typesPath)
    }

    $backupPath = ''
    if ($Backup) {
        $backupPath = [string](Backup-UGSMDayZLiveFileOnce -Instance $Instance -Path $typesPath)
    }

    [xml]$xml = Get-Content -LiteralPath $typesPath -Raw -ErrorAction Stop
    Save-UGSMDayZXmlDocumentUtf8 -Xml $xml -Path $typesPath

    return [pscustomobject]@{
        FormattedAt = (Get-Date).ToString('s')
        LiveTypesPath = $typesPath
        BackupPath = $backupPath
        Message = 'Live db\types.xml formatted.'
    }
}

function Invoke-UGSMDayZApplySelectedModTypesMerge {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$Instance,
        [Parameter(Mandatory)][string]$ModId
    )

    $result = Add-UGSMDayZTypeNodesToLiveTypes -Instance $Instance -ModId $ModId

    # Also format when AddedCount is 0. This fixes an already-merged file that
    # was created before the pretty-format fix.
    try {
        [void](Format-UGSMDayZLiveTypesXml -Instance $Instance -Backup)
    }
    catch { }

    return $result
}

# ============================================================
# v13: Preview/apply cleanup for removed/disabled mod db\types.xml entries
# Uses cache\mod-contributions.json as the ownership ledger.
# Removes only UGSM-owned type entries whose SourceModId is no longer active.
# ============================================================

function Get-UGSMDayZActiveModIdSet {
    [CmdletBinding()]
    param([Parameter(Mandatory)][object]$Instance)

    $set = @{}
    foreach ($mod in @(Get-UGSMDayZEnabledMods -Instance $Instance)) {
        $id = [string](Get-UGSMDayZObjectValue -Object $mod -Name 'Id' -Default '')
        if (-not [string]::IsNullOrWhiteSpace($id)) {
            $set[$id] = $true
        }
    }

    return $set
}

function Get-UGSMDayZLiveTypeNameSet {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$TypesXmlPath)

    $set = @{}
    if ([string]::IsNullOrWhiteSpace($TypesXmlPath) -or -not (Test-Path -LiteralPath $TypesXmlPath -PathType Leaf)) {
        return $set
    }

    try {
        [xml]$xml = Get-Content -LiteralPath $TypesXmlPath -Raw -ErrorAction Stop
        foreach ($node in @($xml.SelectNodes('/types/type[@name]'))) {
            $name = [string]$node.GetAttribute('name')
            if (-not [string]::IsNullOrWhiteSpace($name)) {
                $set[$name.ToLowerInvariant()] = $name
            }
        }
    }
    catch { }

    return $set
}

function New-UGSMDayZRemovedModTypesCleanupPlan {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$Instance,
        [switch]$WritePlan
    )

    $paths = Get-UGSMDayZInstanceStoragePaths -Instance $Instance -Create
    $typesPath = Get-UGSMDayZLiveTypesXmlPath -Instance $Instance

    if ([string]::IsNullOrWhiteSpace($typesPath) -or -not (Test-Path -LiteralPath $typesPath -PathType Leaf)) {
        throw ('Live DayZ db\types.xml was not found: {0}' -f $typesPath)
    }

    $contrib = Read-UGSMDayZJsonFileSafe -Path $paths.ContributionsPath -Default $null
    $contribEntries = @()
    if ($null -ne $contrib -and $contrib.PSObject.Properties.Name -contains 'Entries') {
        $contribEntries = @($contrib.Entries)
    }

    $activeSet = Get-UGSMDayZActiveModIdSet -Instance $Instance
    $liveSet = Get-UGSMDayZLiveTypeNameSet -TypesXmlPath $typesPath

    $seen = @{}
    $entries = @()
    $removeCount = 0
    $skipActiveCount = 0
    $skipMissingLiveCount = 0
    $skipDuplicateLedgerCount = 0
    $skipInvalidCount = 0

    foreach ($entry in $contribEntries) {
        $className = [string](Get-UGSMDayZObjectValue -Object $entry -Name 'ClassName' -Default '')
        $sourceModId = [string](Get-UGSMDayZObjectValue -Object $entry -Name 'SourceModId' -Default '')
        $operation = [string](Get-UGSMDayZObjectValue -Object $entry -Name 'Operation' -Default 'AddType')
        $liveFile = [string](Get-UGSMDayZObjectValue -Object $entry -Name 'LiveFile' -Default '')

        if ([string]::IsNullOrWhiteSpace($className) -or [string]::IsNullOrWhiteSpace($sourceModId)) {
            $skipInvalidCount++
            continue
        }

        if ($operation -ne 'AddType') {
            $skipInvalidCount++
            continue
        }

        # Only clean the current selected mission's live db\types.xml.
        if (-not [string]::IsNullOrWhiteSpace($liveFile) -and ($liveFile -ne $typesPath)) {
            $skipInvalidCount++
            continue
        }

        if ($activeSet.ContainsKey($sourceModId)) {
            $skipActiveCount++
            continue
        }

        $key = $className.ToLowerInvariant()
        if ($seen.ContainsKey($key)) {
            $skipDuplicateLedgerCount++
            continue
        }
        $seen[$key] = $true

        $existsInLive = $liveSet.ContainsKey($key)

        $action = 'Remove'
        $reason = ''
        if (-not $existsInLive) {
            $action = 'Skip'
            $reason = 'MissingFromLiveTypes'
            $skipMissingLiveCount++
        }
        else {
            $removeCount++
        }

        $entries += [pscustomobject]@{
            ClassName = $className
            Action = $action
            Reason = $reason
            SourceModId = $sourceModId
            SourceModName = [string](Get-UGSMDayZObjectValue -Object $entry -Name 'SourceModName' -Default $sourceModId)
            SourceFile = [string](Get-UGSMDayZObjectValue -Object $entry -Name 'SourceFile' -Default '')
            SourcePath = [string](Get-UGSMDayZObjectValue -Object $entry -Name 'SourcePath' -Default '')
            LiveFile = $typesPath
            BackupPath = [string](Get-UGSMDayZObjectValue -Object $entry -Name 'BackupPath' -Default '')
        }
    }

    $inactiveModIds = @($entries | Where-Object { $_.Action -eq 'Remove' } | ForEach-Object { [string]$_.SourceModId } | Sort-Object -Unique)

    $plan = [pscustomobject]@{
        GeneratedAt = (Get-Date).ToString('s')
        InstanceId = [string](Get-UGSMDayZObjectValue -Object $Instance -Name 'Id' -Default '')
        InstanceName = [string](Get-UGSMDayZObjectValue -Object $Instance -Name 'Name' -Default '')
        SelectedMission = Get-UGSMDayZSelectedMissionName -Instance $Instance
        LiveTypesPath = $typesPath
        ContributionsPath = $paths.ContributionsPath
        ActiveModCount = $activeSet.Count
        LedgerEntryCount = @($contribEntries).Count
        InactiveModIds = @($inactiveModIds)
        CleanupCandidateCount = @($entries).Count
        RemoveCount = $removeCount
        SkipActiveCount = $skipActiveCount
        SkipMissingLiveCount = $skipMissingLiveCount
        SkipDuplicateLedgerCount = $skipDuplicateLedgerCount
        SkipInvalidCount = $skipInvalidCount
        Entries = @($entries)
    }

    if ($WritePlan) {
        $planPath = Join-Path $paths.GeneratedFolder 'types-cleanup-plan.json'
        Write-UGSMDayZCacheJson -Path $planPath -Data $plan -Depth 64 | Out-Null
    }

    return $plan
}

function Remove-UGSMDayZRemovedModTypeNodes {
    [CmdletBinding()]
    param([Parameter(Mandatory)][object]$Instance)

    $paths = Get-UGSMDayZInstanceStoragePaths -Instance $Instance -Create
    $typesPath = Get-UGSMDayZLiveTypesXmlPath -Instance $Instance
    if ([string]::IsNullOrWhiteSpace($typesPath) -or -not (Test-Path -LiteralPath $typesPath -PathType Leaf)) {
        throw ('Live DayZ db\types.xml was not found: {0}' -f $typesPath)
    }

    $plan = New-UGSMDayZRemovedModTypesCleanupPlan -Instance $Instance -WritePlan
    $entriesToRemove = @($plan.Entries | Where-Object { [string]$_.Action -eq 'Remove' })

    if (@($entriesToRemove).Count -eq 0) {
        return [pscustomobject]@{
            AppliedAt = (Get-Date).ToString('s')
            InstanceId = $plan.InstanceId
            InstanceName = $plan.InstanceName
            LiveTypesPath = $typesPath
            RemovedCount = 0
            SkippedCount = ([int]$plan.SkipActiveCount + [int]$plan.SkipMissingLiveCount + [int]$plan.SkipDuplicateLedgerCount + [int]$plan.SkipInvalidCount)
            InactiveModIds = @($plan.InactiveModIds)
            BackupPath = ''
            ContributionsPath = $paths.ContributionsPath
            Message = 'No removed/disabled mod type entries needed cleanup.'
            Plan = $plan
        }
    }

    $backupPath = Backup-UGSMDayZLiveFileOnce -Instance $Instance -Path $typesPath

    $removeSet = @{}
    foreach ($entry in $entriesToRemove) {
        $name = [string]$entry.ClassName
        if (-not [string]::IsNullOrWhiteSpace($name)) {
            $removeSet[$name.ToLowerInvariant()] = $entry
        }
    }

    [xml]$xml = Get-Content -LiteralPath $typesPath -Raw -ErrorAction Stop
    $removed = @()

    foreach ($node in @($xml.SelectNodes('/types/type[@name]'))) {
        $name = [string]$node.GetAttribute('name')
        if ([string]::IsNullOrWhiteSpace($name)) { continue }

        $key = $name.ToLowerInvariant()
        if (-not $removeSet.ContainsKey($key)) { continue }

        $entry = $removeSet[$key]
        [void]$node.ParentNode.RemoveChild($node)

        $removed += [pscustomobject]@{
            ClassName = $name
            SourceModId = [string]$entry.SourceModId
            SourceModName = [string]$entry.SourceModName
            SourceFile = [string]$entry.SourceFile
            SourcePath = [string]$entry.SourcePath
            LiveFile = $typesPath
            Operation = 'RemoveType'
            RemovedAt = (Get-Date).ToString('s')
            BackupPath = $backupPath
        }
    }

    Save-UGSMDayZXmlDocumentUtf8 -Xml $xml -Path $typesPath

    # Update ledger: keep entries whose classnames were not removed, and keep removal history separately.
    $contrib = Read-UGSMDayZJsonFileSafe -Path $paths.ContributionsPath -Default $null
    $oldEntries = @()
    $oldRemoved = @()

    if ($null -ne $contrib -and $contrib.PSObject.Properties.Name -contains 'Entries') {
        $oldEntries = @($contrib.Entries)
    }
    if ($null -ne $contrib -and $contrib.PSObject.Properties.Name -contains 'RemovedEntries') {
        $oldRemoved = @($contrib.RemovedEntries)
    }

    $removedSet = @{}
    foreach ($r in $removed) {
        $removedSet[[string]$r.SourceModId + '|' + ([string]$r.ClassName).ToLowerInvariant()] = $true
    }

    $remainingEntries = @()
    foreach ($e in $oldEntries) {
        $eMod = [string](Get-UGSMDayZObjectValue -Object $e -Name 'SourceModId' -Default '')
        $eName = [string](Get-UGSMDayZObjectValue -Object $e -Name 'ClassName' -Default '')
        $eKey = $eMod + '|' + $eName.ToLowerInvariant()
        if (-not $removedSet.ContainsKey($eKey)) {
            $remainingEntries += $e
        }
    }

    $newContrib = [pscustomobject]@{
        GeneratedAt = (Get-Date).ToString('s')
        InstanceId = $plan.InstanceId
        InstanceName = $plan.InstanceName
        SelectedMission = $plan.SelectedMission
        Entries = @($remainingEntries)
        RemovedEntries = @($oldRemoved + $removed)
    }

    Write-UGSMDayZCacheJson -Path $paths.ContributionsPath -Data $newContrib -Depth 64 | Out-Null

    $result = [pscustomobject]@{
        AppliedAt = (Get-Date).ToString('s')
        InstanceId = $plan.InstanceId
        InstanceName = $plan.InstanceName
        LiveTypesPath = $typesPath
        RemovedCount = @($removed).Count
        SkippedCount = ([int]$plan.SkipActiveCount + [int]$plan.SkipMissingLiveCount + [int]$plan.SkipDuplicateLedgerCount + [int]$plan.SkipInvalidCount)
        InactiveModIds = @($plan.InactiveModIds)
        BackupPath = $backupPath
        ContributionsPath = $paths.ContributionsPath
        Message = ('Removed {0} UGSM-owned type entries for removed/disabled mods.' -f @($removed).Count)
        Removed = @($removed)
        Plan = $plan
    }

    $resultPath = Join-Path $paths.GeneratedFolder 'types-cleanup-result.json'
    Write-UGSMDayZCacheJson -Path $resultPath -Data $result -Depth 64 | Out-Null

    return $result
}

function Invoke-UGSMDayZPreviewRemovedModTypesCleanup {
    [CmdletBinding()]
    param([Parameter(Mandatory)][object]$Instance)

    return (New-UGSMDayZRemovedModTypesCleanupPlan -Instance $Instance -WritePlan)
}

function Invoke-UGSMDayZApplyRemovedModTypesCleanup {
    [CmdletBinding()]
    param([Parameter(Mandatory)][object]$Instance)

    return (Remove-UGSMDayZRemovedModTypeNodes -Instance $Instance)
}

# ============================================================
# v14: Contribution ledger normalization/dedupe
# Keeps cache\mod-contributions.json from inflating after repeated tests.
# This is automatic during add preview/apply and removed-mod cleanup.
# ============================================================

function Get-UGSMDayZContributionEntryKey {
    [CmdletBinding()]
    param([Parameter(Mandatory)][object]$Entry)

    $sourceModId = [string](Get-UGSMDayZObjectValue -Object $Entry -Name 'SourceModId' -Default '')
    $className = [string](Get-UGSMDayZObjectValue -Object $Entry -Name 'ClassName' -Default '')
    $liveFile = [string](Get-UGSMDayZObjectValue -Object $Entry -Name 'LiveFile' -Default '')
    $operation = [string](Get-UGSMDayZObjectValue -Object $Entry -Name 'Operation' -Default 'AddType')

    return ('{0}|{1}|{2}|{3}' -f $sourceModId, $operation, $liveFile.ToLowerInvariant(), $className.ToLowerInvariant())
}

function Select-UGSMDayZUniqueContributionEntries {
    [CmdletBinding()]
    param([object[]]$Entries)

    $map = [ordered]@{}

    foreach ($entry in @($Entries)) {
        if ($null -eq $entry) { continue }

        $sourceModId = [string](Get-UGSMDayZObjectValue -Object $entry -Name 'SourceModId' -Default '')
        $className = [string](Get-UGSMDayZObjectValue -Object $entry -Name 'ClassName' -Default '')

        if ([string]::IsNullOrWhiteSpace($sourceModId) -or [string]::IsNullOrWhiteSpace($className)) {
            continue
        }

        $key = Get-UGSMDayZContributionEntryKey -Entry $entry

        # Keep the latest occurrence for a repeated contribution key.
        # This preserves the latest backup/applied timestamp after repeated tests.
        $map[$key] = $entry
    }

    return @($map.Values)
}

function Normalize-UGSMDayZModContributions {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$Instance,
        [switch]$Write
    )

    $paths = Get-UGSMDayZInstanceStoragePaths -Instance $Instance -Create
    $contrib = Read-UGSMDayZJsonFileSafe -Path $paths.ContributionsPath -Default $null

    $entries = @()
    $removedEntries = @()

    if ($null -ne $contrib -and $contrib.PSObject.Properties.Name -contains 'Entries') {
        $entries = @($contrib.Entries)
    }
    if ($null -ne $contrib -and $contrib.PSObject.Properties.Name -contains 'RemovedEntries') {
        $removedEntries = @($contrib.RemovedEntries)
    }

    $uniqueEntries = @(Select-UGSMDayZUniqueContributionEntries -Entries $entries)
    $uniqueRemoved = @(Select-UGSMDayZUniqueContributionEntries -Entries $removedEntries)

    $normalized = [pscustomobject]@{
        GeneratedAt = (Get-Date).ToString('s')
        InstanceId = [string](Get-UGSMDayZObjectValue -Object $Instance -Name 'Id' -Default '')
        InstanceName = [string](Get-UGSMDayZObjectValue -Object $Instance -Name 'Name' -Default '')
        SelectedMission = Get-UGSMDayZSelectedMissionName -Instance $Instance
        Entries = @($uniqueEntries)
        RemovedEntries = @($uniqueRemoved)
        LedgerStats = [pscustomobject]@{
            OriginalEntryCount = @($entries).Count
            EntryCount = @($uniqueEntries).Count
            RemovedDuplicateEntries = (@($entries).Count - @($uniqueEntries).Count)
            OriginalRemovedEntryCount = @($removedEntries).Count
            RemovedEntryCount = @($uniqueRemoved).Count
            RemovedDuplicateRemovedEntries = (@($removedEntries).Count - @($uniqueRemoved).Count)
        }
    }

    if ($Write) {
        Write-UGSMDayZCacheJson -Path $paths.ContributionsPath -Data $normalized -Depth 64 | Out-Null
    }

    return $normalized
}

function Invoke-UGSMDayZNormalizeTypeContributionLedger {
    [CmdletBinding()]
    param([Parameter(Mandatory)][object]$Instance)

    return (Normalize-UGSMDayZModContributions -Instance $Instance -Write)
}

function Invoke-UGSMDayZApplySelectedModTypesMerge {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$Instance,
        [Parameter(Mandatory)][string]$ModId
    )

    $result = Add-UGSMDayZTypeNodesToLiveTypes -Instance $Instance -ModId $ModId

    # Format even when AddedCount is 0. This also repairs already-merged files.
    try {
        [void](Format-UGSMDayZLiveTypesXml -Instance $Instance -Backup)
    }
    catch { }

    try {
        $normalized = Normalize-UGSMDayZModContributions -Instance $Instance -Write
        $result | Add-Member -NotePropertyName LedgerEntryCount -NotePropertyValue @($normalized.Entries).Count -Force
        $result | Add-Member -NotePropertyName LedgerDuplicateEntriesRemoved -NotePropertyValue ([int]$normalized.LedgerStats.RemovedDuplicateEntries) -Force
    }
    catch { }

    return $result
}

function Invoke-UGSMDayZPreviewRemovedModTypesCleanup {
    [CmdletBinding()]
    param([Parameter(Mandatory)][object]$Instance)

    [void](Normalize-UGSMDayZModContributions -Instance $Instance -Write)
    return (New-UGSMDayZRemovedModTypesCleanupPlan -Instance $Instance -WritePlan)
}

function Invoke-UGSMDayZApplyRemovedModTypesCleanup {
    [CmdletBinding()]
    param([Parameter(Mandatory)][object]$Instance)

    [void](Normalize-UGSMDayZModContributions -Instance $Instance -Write)
    $result = Remove-UGSMDayZRemovedModTypeNodes -Instance $Instance
    [void](Normalize-UGSMDayZModContributions -Instance $Instance -Write)
    return $result
}

# ============================================================
# v15: cfgspawnabletypes.xml selected-mod apply/removed-mod cleanup
# First pass is intentionally conservative:
# - Adds whole missing <type name="..."> blocks only
# - Skips existing live spawnable type names
# - Removes only UGSM-owned AddSpawnableType ledger entries for inactive mods
# ============================================================

function Get-UGSMDayZLiveSpawnableTypesXmlPath {
    [CmdletBinding()]
    param([Parameter(Mandatory)][object]$Instance)

    $profilePath = Get-UGSMDayZProfilePath -Instance $Instance
    if ([string]::IsNullOrWhiteSpace($profilePath)) { return '' }

    $missionName = Get-UGSMDayZSelectedMissionName -Instance $Instance
    return (Join-Path $profilePath (Join-Path (Join-Path 'mpmissions' $missionName) 'cfgspawnabletypes.xml'))
}

function Get-UGSMDayZCachedModSpawnableTypeFileRecords {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$Instance,
        [string]$ModId = ''
    )

    $files = @(Get-UGSMDayZCachedFileIndex -Instance $Instance)
    $records = @()

    foreach ($file in $files) {
        $source = [string](Get-UGSMDayZObjectValue -Object $file -Name 'Source' -Default '')
        $kind = [string](Get-UGSMDayZObjectValue -Object $file -Name 'Kind' -Default '')
        $fileModId = [string](Get-UGSMDayZObjectValue -Object $file -Name 'ModId' -Default '')

        if ($source -ne 'Mod') { continue }
        if ($kind -ne 'cfgspawnabletypes') { continue }
        if (-not [string]::IsNullOrWhiteSpace($ModId) -and $fileModId -ne $ModId) { continue }

        $path = [string](Get-UGSMDayZObjectValue -Object $file -Name 'Path' -Default '')
        if ([string]::IsNullOrWhiteSpace($path) -or -not (Test-Path -LiteralPath $path -PathType Leaf)) { continue }

        $records += $file
    }

    return @($records)
}

function Get-UGSMDayZSpawnableTypeNodesFromFileRecord {
    [CmdletBinding()]
    param([Parameter(Mandatory)][object]$FileRecord)

    $path = [string](Get-UGSMDayZObjectValue -Object $FileRecord -Name 'Path' -Default '')
    if ([string]::IsNullOrWhiteSpace($path) -or -not (Test-Path -LiteralPath $path -PathType Leaf)) { return @() }

    try {
        [xml]$xml = Get-Content -LiteralPath $path -Raw -ErrorAction Stop
        return @($xml.SelectNodes('/spawnabletypes/type[@name]'))
    }
    catch {
        return @()
    }
}

function Get-UGSMDayZExistingSpawnableTypeNameSet {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$SpawnableTypesXmlPath)

    $set = @{}
    if ([string]::IsNullOrWhiteSpace($SpawnableTypesXmlPath) -or -not (Test-Path -LiteralPath $SpawnableTypesXmlPath -PathType Leaf)) {
        return $set
    }

    try {
        [xml]$xml = Get-Content -LiteralPath $SpawnableTypesXmlPath -Raw -ErrorAction Stop
        foreach ($node in @($xml.SelectNodes('/spawnabletypes/type[@name]'))) {
            $name = [string]$node.GetAttribute('name')
            if (-not [string]::IsNullOrWhiteSpace($name)) {
                $set[$name.ToLowerInvariant()] = $name
            }
        }
    }
    catch { }

    return $set
}

function New-UGSMDayZSpawnableTypesMergePlan {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$Instance,
        [string]$ModId = '',
        [switch]$WritePlan
    )

    $paths = Get-UGSMDayZInstanceStoragePaths -Instance $Instance -Create
    $livePath = Get-UGSMDayZLiveSpawnableTypesXmlPath -Instance $Instance
    if ([string]::IsNullOrWhiteSpace($livePath)) {
        throw 'Could not resolve live DayZ cfgspawnabletypes.xml path for this instance.'
    }
    if (-not (Test-Path -LiteralPath $livePath -PathType Leaf)) {
        throw ('Live DayZ cfgspawnabletypes.xml was not found: {0}' -f $livePath)
    }

    $existing = Get-UGSMDayZExistingSpawnableTypeNameSet -SpawnableTypesXmlPath $livePath
    $modFiles = @(Get-UGSMDayZCachedModSpawnableTypeFileRecords -Instance $Instance -ModId $ModId)

    $seenIncoming = @{}
    $entries = @()
    $addCount = 0
    $skipExistingCount = 0
    $skipDuplicateIncomingCount = 0

    foreach ($file in $modFiles) {
        $fileModId = [string](Get-UGSMDayZObjectValue -Object $file -Name 'ModId' -Default '')
        $fileModName = [string](Get-UGSMDayZObjectValue -Object $file -Name 'ModName' -Default $fileModId)
        $sourceFile = [string](Get-UGSMDayZObjectValue -Object $file -Name 'FileName' -Default '')
        $sourcePath = [string](Get-UGSMDayZObjectValue -Object $file -Name 'Path' -Default '')

        foreach ($node in @(Get-UGSMDayZSpawnableTypeNodesFromFileRecord -FileRecord $file)) {
            $name = [string]$node.GetAttribute('name')
            if ([string]::IsNullOrWhiteSpace($name)) { continue }

            $key = $name.ToLowerInvariant()
            $action = 'Add'
            $reason = ''

            if ($existing.ContainsKey($key)) {
                $action = 'Skip'
                $reason = 'AlreadyExistsInLiveSpawnableTypes'
                $skipExistingCount++
            }
            elseif ($seenIncoming.ContainsKey($key)) {
                $action = 'Skip'
                $reason = 'DuplicateIncomingSpawnableType'
                $skipDuplicateIncomingCount++
            }
            else {
                $seenIncoming[$key] = $true
                $addCount++
            }

            $entries += [pscustomobject]@{
                ClassName = $name
                Action = $action
                Reason = $reason
                SourceModId = $fileModId
                SourceModName = $fileModName
                SourceFile = $sourceFile
                SourcePath = $sourcePath
            }
        }
    }

    $plan = [pscustomobject]@{
        GeneratedAt = (Get-Date).ToString('s')
        InstanceId = [string](Get-UGSMDayZObjectValue -Object $Instance -Name 'Id' -Default '')
        InstanceName = [string](Get-UGSMDayZObjectValue -Object $Instance -Name 'Name' -Default '')
        SelectedMission = Get-UGSMDayZSelectedMissionName -Instance $Instance
        LiveSpawnableTypesPath = $livePath
        RequestedModId = $ModId
        ModSpawnableTypeFileCount = @($modFiles).Count
        TotalIncomingSpawnableTypeCount = @($entries).Count
        AddCount = $addCount
        SkipExistingCount = $skipExistingCount
        SkipDuplicateIncomingCount = $skipDuplicateIncomingCount
        Entries = @($entries)
    }

    if ($WritePlan) {
        $planPath = Join-Path $paths.GeneratedFolder 'spawnabletypes-merge-plan.json'
        Write-UGSMDayZCacheJson -Path $planPath -Data $plan -Depth 64 | Out-Null
    }

    return $plan
}

function Add-UGSMDayZSpawnableTypeNodesToLiveSpawnableTypes {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$Instance,
        [string]$ModId = ''
    )

    $paths = Get-UGSMDayZInstanceStoragePaths -Instance $Instance -Create
    $livePath = Get-UGSMDayZLiveSpawnableTypesXmlPath -Instance $Instance
    if ([string]::IsNullOrWhiteSpace($livePath) -or -not (Test-Path -LiteralPath $livePath -PathType Leaf)) {
        throw ('Live DayZ cfgspawnabletypes.xml was not found: {0}' -f $livePath)
    }

    $plan = New-UGSMDayZSpawnableTypesMergePlan -Instance $Instance -ModId $ModId -WritePlan
    $entriesToAdd = @($plan.Entries | Where-Object { [string]$_.Action -eq 'Add' })

    if (@($entriesToAdd).Count -eq 0) {
        return [pscustomobject]@{
            AppliedAt = (Get-Date).ToString('s')
            InstanceId = $plan.InstanceId
            InstanceName = $plan.InstanceName
            LiveSpawnableTypesPath = $livePath
            RequestedModId = $ModId
            AddedCount = 0
            SkippedCount = @($plan.Entries).Count
            BackupPath = ''
            ContributionsPath = $paths.ContributionsPath
            Message = 'No new spawnable type entries needed to be added.'
            Plan = $plan
        }
    }

    $backupPath = Backup-UGSMDayZLiveFileOnce -Instance $Instance -Path $livePath

    [xml]$liveXml = Get-Content -LiteralPath $livePath -Raw -ErrorAction Stop
    $root = $liveXml.DocumentElement
    if ($null -eq $root -or $root.Name -ne 'spawnabletypes') {
        throw 'Live cfgspawnabletypes.xml root node is not <spawnabletypes>.'
    }

    $entriesByKey = @{}
    foreach ($entry in $entriesToAdd) {
        $entriesByKey[[string]$entry.ClassName] = $entry
    }

    $added = @()
    $addedKeys = @{}

    $modFiles = @(Get-UGSMDayZCachedModSpawnableTypeFileRecords -Instance $Instance -ModId $ModId)
    foreach ($file in $modFiles) {
        foreach ($node in @(Get-UGSMDayZSpawnableTypeNodesFromFileRecord -FileRecord $file)) {
            $name = [string]$node.GetAttribute('name')
            if ([string]::IsNullOrWhiteSpace($name)) { continue }
            if (-not $entriesByKey.ContainsKey($name)) { continue }
            if ($addedKeys.ContainsKey($name.ToLowerInvariant())) { continue }

            $imported = $liveXml.ImportNode($node, $true)
            [void]$root.AppendChild($liveXml.CreateWhitespace("`r`n    "))
            [void]$root.AppendChild($imported)

            $entry = $entriesByKey[$name]
            $added += [pscustomobject]@{
                ClassName = $name
                SourceModId = [string]$entry.SourceModId
                SourceModName = [string]$entry.SourceModName
                SourceFile = [string]$entry.SourceFile
                SourcePath = [string]$entry.SourcePath
                LiveFile = $livePath
                Operation = 'AddSpawnableType'
                AppliedAt = (Get-Date).ToString('s')
                BackupPath = $backupPath
            }
            $addedKeys[$name.ToLowerInvariant()] = $true
        }
    }

    [void]$root.AppendChild($liveXml.CreateWhitespace("`r`n"))
    Save-UGSMDayZXmlDocumentUtf8 -Xml $liveXml -Path $livePath

    $existingContrib = Read-UGSMDayZJsonFileSafe -Path $paths.ContributionsPath -Default $null
    $oldEntries = @()
    $oldRemoved = @()
    if ($null -ne $existingContrib -and $existingContrib.PSObject.Properties.Name -contains 'Entries') {
        $oldEntries = @($existingContrib.Entries)
    }
    if ($null -ne $existingContrib -and $existingContrib.PSObject.Properties.Name -contains 'RemovedEntries') {
        $oldRemoved = @($existingContrib.RemovedEntries)
    }

    $contrib = [pscustomobject]@{
        GeneratedAt = (Get-Date).ToString('s')
        InstanceId = $plan.InstanceId
        InstanceName = $plan.InstanceName
        SelectedMission = $plan.SelectedMission
        Entries = @($oldEntries + $added)
        RemovedEntries = @($oldRemoved)
    }
    Write-UGSMDayZCacheJson -Path $paths.ContributionsPath -Data $contrib -Depth 64 | Out-Null
    try { [void](Normalize-UGSMDayZModContributions -Instance $Instance -Write) } catch { }

    $result = [pscustomobject]@{
        AppliedAt = (Get-Date).ToString('s')
        InstanceId = $plan.InstanceId
        InstanceName = $plan.InstanceName
        LiveSpawnableTypesPath = $livePath
        RequestedModId = $ModId
        AddedCount = @($added).Count
        SkippedCount = ([int]$plan.SkipExistingCount + [int]$plan.SkipDuplicateIncomingCount)
        BackupPath = $backupPath
        ContributionsPath = $paths.ContributionsPath
        Message = ('Added {0} spawnable type entries to live cfgspawnabletypes.xml.' -f @($added).Count)
        Added = @($added)
        Plan = $plan
    }

    $resultPath = Join-Path $paths.GeneratedFolder 'spawnabletypes-merge-result.json'
    Write-UGSMDayZCacheJson -Path $resultPath -Data $result -Depth 64 | Out-Null

    return $result
}

function New-UGSMDayZRemovedModSpawnableTypesCleanupPlan {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$Instance,
        [switch]$WritePlan
    )

    $paths = Get-UGSMDayZInstanceStoragePaths -Instance $Instance -Create
    $livePath = Get-UGSMDayZLiveSpawnableTypesXmlPath -Instance $Instance

    if ([string]::IsNullOrWhiteSpace($livePath) -or -not (Test-Path -LiteralPath $livePath -PathType Leaf)) {
        throw ('Live DayZ cfgspawnabletypes.xml was not found: {0}' -f $livePath)
    }

    [void](Normalize-UGSMDayZModContributions -Instance $Instance -Write)

    $contrib = Read-UGSMDayZJsonFileSafe -Path $paths.ContributionsPath -Default $null
    $contribEntries = @()
    if ($null -ne $contrib -and $contrib.PSObject.Properties.Name -contains 'Entries') {
        $contribEntries = @($contrib.Entries)
    }

    $activeSet = Get-UGSMDayZActiveModIdSet -Instance $Instance
    $liveSet = Get-UGSMDayZExistingSpawnableTypeNameSet -SpawnableTypesXmlPath $livePath

    $seen = @{}
    $entries = @()
    $removeCount = 0
    $skipActiveCount = 0
    $skipMissingLiveCount = 0
    $skipDuplicateLedgerCount = 0
    $skipInvalidCount = 0

    foreach ($entry in $contribEntries) {
        $className = [string](Get-UGSMDayZObjectValue -Object $entry -Name 'ClassName' -Default '')
        $sourceModId = [string](Get-UGSMDayZObjectValue -Object $entry -Name 'SourceModId' -Default '')
        $operation = [string](Get-UGSMDayZObjectValue -Object $entry -Name 'Operation' -Default '')
        $liveFile = [string](Get-UGSMDayZObjectValue -Object $entry -Name 'LiveFile' -Default '')

        if ([string]::IsNullOrWhiteSpace($className) -or [string]::IsNullOrWhiteSpace($sourceModId)) {
            $skipInvalidCount++
            continue
        }

        if ($operation -ne 'AddSpawnableType') {
            $skipInvalidCount++
            continue
        }

        if (-not [string]::IsNullOrWhiteSpace($liveFile) -and ($liveFile -ne $livePath)) {
            $skipInvalidCount++
            continue
        }

        if ($activeSet.ContainsKey($sourceModId)) {
            $skipActiveCount++
            continue
        }

        $key = $className.ToLowerInvariant()
        if ($seen.ContainsKey($key)) {
            $skipDuplicateLedgerCount++
            continue
        }
        $seen[$key] = $true

        $existsInLive = $liveSet.ContainsKey($key)

        $action = 'Remove'
        $reason = ''
        if (-not $existsInLive) {
            $action = 'Skip'
            $reason = 'MissingFromLiveSpawnableTypes'
            $skipMissingLiveCount++
        }
        else {
            $removeCount++
        }

        $entries += [pscustomobject]@{
            ClassName = $className
            Action = $action
            Reason = $reason
            SourceModId = $sourceModId
            SourceModName = [string](Get-UGSMDayZObjectValue -Object $entry -Name 'SourceModName' -Default $sourceModId)
            SourceFile = [string](Get-UGSMDayZObjectValue -Object $entry -Name 'SourceFile' -Default '')
            SourcePath = [string](Get-UGSMDayZObjectValue -Object $entry -Name 'SourcePath' -Default '')
            LiveFile = $livePath
            BackupPath = [string](Get-UGSMDayZObjectValue -Object $entry -Name 'BackupPath' -Default '')
        }
    }

    $inactiveModIds = @($entries | Where-Object { $_.Action -eq 'Remove' } | ForEach-Object { [string]$_.SourceModId } | Sort-Object -Unique)

    $plan = [pscustomobject]@{
        GeneratedAt = (Get-Date).ToString('s')
        InstanceId = [string](Get-UGSMDayZObjectValue -Object $Instance -Name 'Id' -Default '')
        InstanceName = [string](Get-UGSMDayZObjectValue -Object $Instance -Name 'Name' -Default '')
        SelectedMission = Get-UGSMDayZSelectedMissionName -Instance $Instance
        LiveSpawnableTypesPath = $livePath
        ContributionsPath = $paths.ContributionsPath
        ActiveModCount = $activeSet.Count
        LedgerEntryCount = @($contribEntries).Count
        InactiveModIds = @($inactiveModIds)
        CleanupCandidateCount = @($entries).Count
        RemoveCount = $removeCount
        SkipActiveCount = $skipActiveCount
        SkipMissingLiveCount = $skipMissingLiveCount
        SkipDuplicateLedgerCount = $skipDuplicateLedgerCount
        SkipInvalidCount = $skipInvalidCount
        Entries = @($entries)
    }

    if ($WritePlan) {
        $planPath = Join-Path $paths.GeneratedFolder 'spawnabletypes-cleanup-plan.json'
        Write-UGSMDayZCacheJson -Path $planPath -Data $plan -Depth 64 | Out-Null
    }

    return $plan
}

function Remove-UGSMDayZRemovedModSpawnableTypeNodes {
    [CmdletBinding()]
    param([Parameter(Mandatory)][object]$Instance)

    $paths = Get-UGSMDayZInstanceStoragePaths -Instance $Instance -Create
    $livePath = Get-UGSMDayZLiveSpawnableTypesXmlPath -Instance $Instance
    if ([string]::IsNullOrWhiteSpace($livePath) -or -not (Test-Path -LiteralPath $livePath -PathType Leaf)) {
        throw ('Live DayZ cfgspawnabletypes.xml was not found: {0}' -f $livePath)
    }

    $plan = New-UGSMDayZRemovedModSpawnableTypesCleanupPlan -Instance $Instance -WritePlan
    $entriesToRemove = @($plan.Entries | Where-Object { [string]$_.Action -eq 'Remove' })

    if (@($entriesToRemove).Count -eq 0) {
        return [pscustomobject]@{
            AppliedAt = (Get-Date).ToString('s')
            InstanceId = $plan.InstanceId
            InstanceName = $plan.InstanceName
            LiveSpawnableTypesPath = $livePath
            RemovedCount = 0
            SkippedCount = ([int]$plan.SkipActiveCount + [int]$plan.SkipMissingLiveCount + [int]$plan.SkipDuplicateLedgerCount + [int]$plan.SkipInvalidCount)
            InactiveModIds = @($plan.InactiveModIds)
            BackupPath = ''
            ContributionsPath = $paths.ContributionsPath
            Message = 'No removed/disabled mod spawnable type entries needed cleanup.'
            Plan = $plan
        }
    }

    $backupPath = Backup-UGSMDayZLiveFileOnce -Instance $Instance -Path $livePath

    $removeSet = @{}
    foreach ($entry in $entriesToRemove) {
        $name = [string]$entry.ClassName
        if (-not [string]::IsNullOrWhiteSpace($name)) {
            $removeSet[$name.ToLowerInvariant()] = $entry
        }
    }

    [xml]$xml = Get-Content -LiteralPath $livePath -Raw -ErrorAction Stop
    $removed = @()

    foreach ($node in @($xml.SelectNodes('/spawnabletypes/type[@name]'))) {
        $name = [string]$node.GetAttribute('name')
        if ([string]::IsNullOrWhiteSpace($name)) { continue }

        $key = $name.ToLowerInvariant()
        if (-not $removeSet.ContainsKey($key)) { continue }

        $entry = $removeSet[$key]
        [void]$node.ParentNode.RemoveChild($node)

        $removed += [pscustomobject]@{
            ClassName = $name
            SourceModId = [string]$entry.SourceModId
            SourceModName = [string]$entry.SourceModName
            SourceFile = [string]$entry.SourceFile
            SourcePath = [string]$entry.SourcePath
            LiveFile = $livePath
            Operation = 'RemoveSpawnableType'
            RemovedAt = (Get-Date).ToString('s')
            BackupPath = $backupPath
        }
    }

    Save-UGSMDayZXmlDocumentUtf8 -Xml $xml -Path $livePath

    $contrib = Read-UGSMDayZJsonFileSafe -Path $paths.ContributionsPath -Default $null
    $oldEntries = @()
    $oldRemoved = @()

    if ($null -ne $contrib -and $contrib.PSObject.Properties.Name -contains 'Entries') {
        $oldEntries = @($contrib.Entries)
    }
    if ($null -ne $contrib -and $contrib.PSObject.Properties.Name -contains 'RemovedEntries') {
        $oldRemoved = @($contrib.RemovedEntries)
    }

    $removedSet = @{}
    foreach ($r in $removed) {
        $removedSet[[string]$r.SourceModId + '|AddSpawnableType|' + ([string]$r.ClassName).ToLowerInvariant()] = $true
    }

    $remainingEntries = @()
    foreach ($e in $oldEntries) {
        $eMod = [string](Get-UGSMDayZObjectValue -Object $e -Name 'SourceModId' -Default '')
        $eName = [string](Get-UGSMDayZObjectValue -Object $e -Name 'ClassName' -Default '')
        $eOperation = [string](Get-UGSMDayZObjectValue -Object $e -Name 'Operation' -Default '')
        $eKey = $eMod + '|' + $eOperation + '|' + $eName.ToLowerInvariant()
        if (-not $removedSet.ContainsKey($eKey)) {
            $remainingEntries += $e
        }
    }

    $newContrib = [pscustomobject]@{
        GeneratedAt = (Get-Date).ToString('s')
        InstanceId = $plan.InstanceId
        InstanceName = $plan.InstanceName
        SelectedMission = $plan.SelectedMission
        Entries = @($remainingEntries)
        RemovedEntries = @($oldRemoved + $removed)
    }

    Write-UGSMDayZCacheJson -Path $paths.ContributionsPath -Data $newContrib -Depth 64 | Out-Null
    try { [void](Normalize-UGSMDayZModContributions -Instance $Instance -Write) } catch { }

    $result = [pscustomobject]@{
        AppliedAt = (Get-Date).ToString('s')
        InstanceId = $plan.InstanceId
        InstanceName = $plan.InstanceName
        LiveSpawnableTypesPath = $livePath
        RemovedCount = @($removed).Count
        SkippedCount = ([int]$plan.SkipActiveCount + [int]$plan.SkipMissingLiveCount + [int]$plan.SkipDuplicateLedgerCount + [int]$plan.SkipInvalidCount)
        InactiveModIds = @($plan.InactiveModIds)
        BackupPath = $backupPath
        ContributionsPath = $paths.ContributionsPath
        Message = ('Removed {0} UGSM-owned spawnable type entries for removed/disabled mods.' -f @($removed).Count)
        Removed = @($removed)
        Plan = $plan
    }

    $resultPath = Join-Path $paths.GeneratedFolder 'spawnabletypes-cleanup-result.json'
    Write-UGSMDayZCacheJson -Path $resultPath -Data $result -Depth 64 | Out-Null

    return $result
}

function Invoke-UGSMDayZPreviewSelectedModSpawnableTypesMerge {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$Instance,
        [Parameter(Mandatory)][string]$ModId
    )

    return (New-UGSMDayZSpawnableTypesMergePlan -Instance $Instance -ModId $ModId -WritePlan)
}

function Invoke-UGSMDayZApplySelectedModSpawnableTypesMerge {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$Instance,
        [Parameter(Mandatory)][string]$ModId
    )

    $result = Add-UGSMDayZSpawnableTypeNodesToLiveSpawnableTypes -Instance $Instance -ModId $ModId
    try {
        $normalized = Normalize-UGSMDayZModContributions -Instance $Instance -Write
        $result | Add-Member -NotePropertyName LedgerEntryCount -NotePropertyValue @($normalized.Entries).Count -Force
        $result | Add-Member -NotePropertyName LedgerDuplicateEntriesRemoved -NotePropertyValue ([int]$normalized.LedgerStats.RemovedDuplicateEntries) -Force
    }
    catch { }

    return $result
}

function Invoke-UGSMDayZPreviewRemovedModSpawnableTypesCleanup {
    [CmdletBinding()]
    param([Parameter(Mandatory)][object]$Instance)

    [void](Normalize-UGSMDayZModContributions -Instance $Instance -Write)
    return (New-UGSMDayZRemovedModSpawnableTypesCleanupPlan -Instance $Instance -WritePlan)
}

function Invoke-UGSMDayZApplyRemovedModSpawnableTypesCleanup {
    [CmdletBinding()]
    param([Parameter(Mandatory)][object]$Instance)

    [void](Normalize-UGSMDayZModContributions -Instance $Instance -Write)
    $result = Remove-UGSMDayZRemovedModSpawnableTypeNodes -Instance $Instance
    [void](Normalize-UGSMDayZModContributions -Instance $Instance -Write)
    return $result
}

# ============================================================
# v16: events.xml selected-mod apply/removed-mod cleanup
# First pass is conservative:
# - Adds whole missing <event name="..."> blocks only
# - Skips existing live event names
# - Removes only UGSM-owned AddEvent ledger entries for inactive mods
# ============================================================

function Get-UGSMDayZLiveEventsXmlPath {
    [CmdletBinding()]
    param([Parameter(Mandatory)][object]$Instance)

    $profilePath = Get-UGSMDayZProfilePath -Instance $Instance
    if ([string]::IsNullOrWhiteSpace($profilePath)) { return '' }

    $missionName = Get-UGSMDayZSelectedMissionName -Instance $Instance
    return (Join-Path $profilePath (Join-Path (Join-Path 'mpmissions' $missionName) (Join-Path 'db' 'events.xml')))
}

function Get-UGSMDayZCachedModEventFileRecords {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$Instance,
        [string]$ModId = ''
    )

    $files = @(Get-UGSMDayZCachedFileIndex -Instance $Instance)
    $records = @()

    foreach ($file in $files) {
        $source = [string](Get-UGSMDayZObjectValue -Object $file -Name 'Source' -Default '')
        $kind = [string](Get-UGSMDayZObjectValue -Object $file -Name 'Kind' -Default '')
        $fileModId = [string](Get-UGSMDayZObjectValue -Object $file -Name 'ModId' -Default '')

        if ($source -ne 'Mod') { continue }
        if ($kind -ne 'events') { continue }
        if (-not [string]::IsNullOrWhiteSpace($ModId) -and $fileModId -ne $ModId) { continue }

        $path = [string](Get-UGSMDayZObjectValue -Object $file -Name 'Path' -Default '')
        if ([string]::IsNullOrWhiteSpace($path) -or -not (Test-Path -LiteralPath $path -PathType Leaf)) { continue }

        $records += $file
    }

    return @($records)
}

function Get-UGSMDayZEventNodesFromFileRecord {
    [CmdletBinding()]
    param([Parameter(Mandatory)][object]$FileRecord)

    $path = [string](Get-UGSMDayZObjectValue -Object $FileRecord -Name 'Path' -Default '')
    if ([string]::IsNullOrWhiteSpace($path) -or -not (Test-Path -LiteralPath $path -PathType Leaf)) { return @() }

    try {
        [xml]$xml = Get-Content -LiteralPath $path -Raw -ErrorAction Stop
        return @($xml.SelectNodes('/events/event[@name]'))
    }
    catch {
        return @()
    }
}

function Get-UGSMDayZExistingEventNameSet {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$EventsXmlPath)

    $set = @{}
    if ([string]::IsNullOrWhiteSpace($EventsXmlPath) -or -not (Test-Path -LiteralPath $EventsXmlPath -PathType Leaf)) {
        return $set
    }

    try {
        [xml]$xml = Get-Content -LiteralPath $EventsXmlPath -Raw -ErrorAction Stop
        foreach ($node in @($xml.SelectNodes('/events/event[@name]'))) {
            $name = [string]$node.GetAttribute('name')
            if (-not [string]::IsNullOrWhiteSpace($name)) {
                $set[$name.ToLowerInvariant()] = $name
            }
        }
    }
    catch { }

    return $set
}

function New-UGSMDayZEventsMergePlan {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$Instance,
        [string]$ModId = '',
        [switch]$WritePlan
    )

    $paths = Get-UGSMDayZInstanceStoragePaths -Instance $Instance -Create
    $livePath = Get-UGSMDayZLiveEventsXmlPath -Instance $Instance
    if ([string]::IsNullOrWhiteSpace($livePath)) {
        throw 'Could not resolve live DayZ db\events.xml path for this instance.'
    }
    if (-not (Test-Path -LiteralPath $livePath -PathType Leaf)) {
        throw ('Live DayZ db\events.xml was not found: {0}' -f $livePath)
    }

    $existing = Get-UGSMDayZExistingEventNameSet -EventsXmlPath $livePath
    $modFiles = @(Get-UGSMDayZCachedModEventFileRecords -Instance $Instance -ModId $ModId)

    $seenIncoming = @{}
    $entries = @()
    $addCount = 0
    $skipExistingCount = 0
    $skipDuplicateIncomingCount = 0

    foreach ($file in $modFiles) {
        $fileModId = [string](Get-UGSMDayZObjectValue -Object $file -Name 'ModId' -Default '')
        $fileModName = [string](Get-UGSMDayZObjectValue -Object $file -Name 'ModName' -Default $fileModId)
        $sourceFile = [string](Get-UGSMDayZObjectValue -Object $file -Name 'FileName' -Default '')
        $sourcePath = [string](Get-UGSMDayZObjectValue -Object $file -Name 'Path' -Default '')

        foreach ($node in @(Get-UGSMDayZEventNodesFromFileRecord -FileRecord $file)) {
            $name = [string]$node.GetAttribute('name')
            if ([string]::IsNullOrWhiteSpace($name)) { continue }

            $key = $name.ToLowerInvariant()
            $action = 'Add'
            $reason = ''

            if ($existing.ContainsKey($key)) {
                $action = 'Skip'
                $reason = 'AlreadyExistsInLiveEvents'
                $skipExistingCount++
            }
            elseif ($seenIncoming.ContainsKey($key)) {
                $action = 'Skip'
                $reason = 'DuplicateIncomingEvent'
                $skipDuplicateIncomingCount++
            }
            else {
                $seenIncoming[$key] = $true
                $addCount++
            }

            $entries += [pscustomobject]@{
                ClassName = $name
                Action = $action
                Reason = $reason
                SourceModId = $fileModId
                SourceModName = $fileModName
                SourceFile = $sourceFile
                SourcePath = $sourcePath
            }
        }
    }

    $plan = [pscustomobject]@{
        GeneratedAt = (Get-Date).ToString('s')
        InstanceId = [string](Get-UGSMDayZObjectValue -Object $Instance -Name 'Id' -Default '')
        InstanceName = [string](Get-UGSMDayZObjectValue -Object $Instance -Name 'Name' -Default '')
        SelectedMission = Get-UGSMDayZSelectedMissionName -Instance $Instance
        LiveEventsPath = $livePath
        RequestedModId = $ModId
        ModEventFileCount = @($modFiles).Count
        TotalIncomingEventCount = @($entries).Count
        AddCount = $addCount
        SkipExistingCount = $skipExistingCount
        SkipDuplicateIncomingCount = $skipDuplicateIncomingCount
        Entries = @($entries)
    }

    if ($WritePlan) {
        $planPath = Join-Path $paths.GeneratedFolder 'events-merge-plan.json'
        Write-UGSMDayZCacheJson -Path $planPath -Data $plan -Depth 64 | Out-Null
    }

    return $plan
}

function Add-UGSMDayZEventNodesToLiveEvents {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$Instance,
        [string]$ModId = ''
    )

    $paths = Get-UGSMDayZInstanceStoragePaths -Instance $Instance -Create
    $livePath = Get-UGSMDayZLiveEventsXmlPath -Instance $Instance
    if ([string]::IsNullOrWhiteSpace($livePath) -or -not (Test-Path -LiteralPath $livePath -PathType Leaf)) {
        throw ('Live DayZ db\events.xml was not found: {0}' -f $livePath)
    }

    $plan = New-UGSMDayZEventsMergePlan -Instance $Instance -ModId $ModId -WritePlan
    $entriesToAdd = @($plan.Entries | Where-Object { [string]$_.Action -eq 'Add' })

    if (@($entriesToAdd).Count -eq 0) {
        return [pscustomobject]@{
            AppliedAt = (Get-Date).ToString('s')
            InstanceId = $plan.InstanceId
            InstanceName = $plan.InstanceName
            LiveEventsPath = $livePath
            RequestedModId = $ModId
            AddedCount = 0
            SkippedCount = @($plan.Entries).Count
            BackupPath = ''
            ContributionsPath = $paths.ContributionsPath
            Message = 'No new event entries needed to be added.'
            Plan = $plan
        }
    }

    $backupPath = Backup-UGSMDayZLiveFileOnce -Instance $Instance -Path $livePath

    [xml]$liveXml = Get-Content -LiteralPath $livePath -Raw -ErrorAction Stop
    $root = $liveXml.DocumentElement
    if ($null -eq $root -or $root.Name -ne 'events') {
        throw 'Live events.xml root node is not <events>.'
    }

    $entriesByKey = @{}
    foreach ($entry in $entriesToAdd) {
        $entriesByKey[[string]$entry.ClassName] = $entry
    }

    $added = @()
    $addedKeys = @{}

    $modFiles = @(Get-UGSMDayZCachedModEventFileRecords -Instance $Instance -ModId $ModId)
    foreach ($file in $modFiles) {
        foreach ($node in @(Get-UGSMDayZEventNodesFromFileRecord -FileRecord $file)) {
            $name = [string]$node.GetAttribute('name')
            if ([string]::IsNullOrWhiteSpace($name)) { continue }
            if (-not $entriesByKey.ContainsKey($name)) { continue }
            if ($addedKeys.ContainsKey($name.ToLowerInvariant())) { continue }

            $imported = $liveXml.ImportNode($node, $true)
            [void]$root.AppendChild($liveXml.CreateWhitespace("`r`n    "))
            [void]$root.AppendChild($imported)

            $entry = $entriesByKey[$name]
            $added += [pscustomobject]@{
                ClassName = $name
                SourceModId = [string]$entry.SourceModId
                SourceModName = [string]$entry.SourceModName
                SourceFile = [string]$entry.SourceFile
                SourcePath = [string]$entry.SourcePath
                LiveFile = $livePath
                Operation = 'AddEvent'
                AppliedAt = (Get-Date).ToString('s')
                BackupPath = $backupPath
            }
            $addedKeys[$name.ToLowerInvariant()] = $true
        }
    }

    [void]$root.AppendChild($liveXml.CreateWhitespace("`r`n"))
    Save-UGSMDayZXmlDocumentUtf8 -Xml $liveXml -Path $livePath

    $existingContrib = Read-UGSMDayZJsonFileSafe -Path $paths.ContributionsPath -Default $null
    $oldEntries = @()
    $oldRemoved = @()
    if ($null -ne $existingContrib -and $existingContrib.PSObject.Properties.Name -contains 'Entries') {
        $oldEntries = @($existingContrib.Entries)
    }
    if ($null -ne $existingContrib -and $existingContrib.PSObject.Properties.Name -contains 'RemovedEntries') {
        $oldRemoved = @($existingContrib.RemovedEntries)
    }

    $contrib = [pscustomobject]@{
        GeneratedAt = (Get-Date).ToString('s')
        InstanceId = $plan.InstanceId
        InstanceName = $plan.InstanceName
        SelectedMission = $plan.SelectedMission
        Entries = @($oldEntries + $added)
        RemovedEntries = @($oldRemoved)
    }
    Write-UGSMDayZCacheJson -Path $paths.ContributionsPath -Data $contrib -Depth 64 | Out-Null
    try { [void](Normalize-UGSMDayZModContributions -Instance $Instance -Write) } catch { }

    $result = [pscustomobject]@{
        AppliedAt = (Get-Date).ToString('s')
        InstanceId = $plan.InstanceId
        InstanceName = $plan.InstanceName
        LiveEventsPath = $livePath
        RequestedModId = $ModId
        AddedCount = @($added).Count
        SkippedCount = ([int]$plan.SkipExistingCount + [int]$plan.SkipDuplicateIncomingCount)
        BackupPath = $backupPath
        ContributionsPath = $paths.ContributionsPath
        Message = ('Added {0} event entries to live events.xml.' -f @($added).Count)
        Added = @($added)
        Plan = $plan
    }

    $resultPath = Join-Path $paths.GeneratedFolder 'events-merge-result.json'
    Write-UGSMDayZCacheJson -Path $resultPath -Data $result -Depth 64 | Out-Null

    return $result
}

function New-UGSMDayZRemovedModEventsCleanupPlan {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$Instance,
        [switch]$WritePlan
    )

    $paths = Get-UGSMDayZInstanceStoragePaths -Instance $Instance -Create
    $livePath = Get-UGSMDayZLiveEventsXmlPath -Instance $Instance

    if ([string]::IsNullOrWhiteSpace($livePath) -or -not (Test-Path -LiteralPath $livePath -PathType Leaf)) {
        throw ('Live DayZ db\events.xml was not found: {0}' -f $livePath)
    }

    [void](Normalize-UGSMDayZModContributions -Instance $Instance -Write)

    $contrib = Read-UGSMDayZJsonFileSafe -Path $paths.ContributionsPath -Default $null
    $contribEntries = @()
    if ($null -ne $contrib -and $contrib.PSObject.Properties.Name -contains 'Entries') {
        $contribEntries = @($contrib.Entries)
    }

    $activeSet = Get-UGSMDayZActiveModIdSet -Instance $Instance
    $liveSet = Get-UGSMDayZExistingEventNameSet -EventsXmlPath $livePath

    $seen = @{}
    $entries = @()
    $removeCount = 0
    $skipActiveCount = 0
    $skipMissingLiveCount = 0
    $skipDuplicateLedgerCount = 0
    $skipInvalidCount = 0

    foreach ($entry in $contribEntries) {
        $className = [string](Get-UGSMDayZObjectValue -Object $entry -Name 'ClassName' -Default '')
        $sourceModId = [string](Get-UGSMDayZObjectValue -Object $entry -Name 'SourceModId' -Default '')
        $operation = [string](Get-UGSMDayZObjectValue -Object $entry -Name 'Operation' -Default '')
        $liveFile = [string](Get-UGSMDayZObjectValue -Object $entry -Name 'LiveFile' -Default '')

        if ([string]::IsNullOrWhiteSpace($className) -or [string]::IsNullOrWhiteSpace($sourceModId)) {
            $skipInvalidCount++
            continue
        }

        if ($operation -ne 'AddEvent') {
            $skipInvalidCount++
            continue
        }

        if (-not [string]::IsNullOrWhiteSpace($liveFile) -and ($liveFile -ne $livePath)) {
            $skipInvalidCount++
            continue
        }

        if ($activeSet.ContainsKey($sourceModId)) {
            $skipActiveCount++
            continue
        }

        $key = $className.ToLowerInvariant()
        if ($seen.ContainsKey($key)) {
            $skipDuplicateLedgerCount++
            continue
        }
        $seen[$key] = $true

        $existsInLive = $liveSet.ContainsKey($key)

        $action = 'Remove'
        $reason = ''
        if (-not $existsInLive) {
            $action = 'Skip'
            $reason = 'MissingFromLiveEvents'
            $skipMissingLiveCount++
        }
        else {
            $removeCount++
        }

        $entries += [pscustomobject]@{
            ClassName = $className
            Action = $action
            Reason = $reason
            SourceModId = $sourceModId
            SourceModName = [string](Get-UGSMDayZObjectValue -Object $entry -Name 'SourceModName' -Default $sourceModId)
            SourceFile = [string](Get-UGSMDayZObjectValue -Object $entry -Name 'SourceFile' -Default '')
            SourcePath = [string](Get-UGSMDayZObjectValue -Object $entry -Name 'SourcePath' -Default '')
            LiveFile = $livePath
            BackupPath = [string](Get-UGSMDayZObjectValue -Object $entry -Name 'BackupPath' -Default '')
        }
    }

    $inactiveModIds = @($entries | Where-Object { $_.Action -eq 'Remove' } | ForEach-Object { [string]$_.SourceModId } | Sort-Object -Unique)

    $plan = [pscustomobject]@{
        GeneratedAt = (Get-Date).ToString('s')
        InstanceId = [string](Get-UGSMDayZObjectValue -Object $Instance -Name 'Id' -Default '')
        InstanceName = [string](Get-UGSMDayZObjectValue -Object $Instance -Name 'Name' -Default '')
        SelectedMission = Get-UGSMDayZSelectedMissionName -Instance $Instance
        LiveEventsPath = $livePath
        ContributionsPath = $paths.ContributionsPath
        ActiveModCount = $activeSet.Count
        LedgerEntryCount = @($contribEntries).Count
        InactiveModIds = @($inactiveModIds)
        CleanupCandidateCount = @($entries).Count
        RemoveCount = $removeCount
        SkipActiveCount = $skipActiveCount
        SkipMissingLiveCount = $skipMissingLiveCount
        SkipDuplicateLedgerCount = $skipDuplicateLedgerCount
        SkipInvalidCount = $skipInvalidCount
        Entries = @($entries)
    }

    if ($WritePlan) {
        $planPath = Join-Path $paths.GeneratedFolder 'events-cleanup-plan.json'
        Write-UGSMDayZCacheJson -Path $planPath -Data $plan -Depth 64 | Out-Null
    }

    return $plan
}

function Remove-UGSMDayZRemovedModEventNodes {
    [CmdletBinding()]
    param([Parameter(Mandatory)][object]$Instance)

    $paths = Get-UGSMDayZInstanceStoragePaths -Instance $Instance -Create
    $livePath = Get-UGSMDayZLiveEventsXmlPath -Instance $Instance
    if ([string]::IsNullOrWhiteSpace($livePath) -or -not (Test-Path -LiteralPath $livePath -PathType Leaf)) {
        throw ('Live DayZ db\events.xml was not found: {0}' -f $livePath)
    }

    $plan = New-UGSMDayZRemovedModEventsCleanupPlan -Instance $Instance -WritePlan
    $entriesToRemove = @($plan.Entries | Where-Object { [string]$_.Action -eq 'Remove' })

    if (@($entriesToRemove).Count -eq 0) {
        return [pscustomobject]@{
            AppliedAt = (Get-Date).ToString('s')
            InstanceId = $plan.InstanceId
            InstanceName = $plan.InstanceName
            LiveEventsPath = $livePath
            RemovedCount = 0
            SkippedCount = ([int]$plan.SkipActiveCount + [int]$plan.SkipMissingLiveCount + [int]$plan.SkipDuplicateLedgerCount + [int]$plan.SkipInvalidCount)
            InactiveModIds = @($plan.InactiveModIds)
            BackupPath = ''
            ContributionsPath = $paths.ContributionsPath
            Message = 'No removed/disabled mod event entries needed cleanup.'
            Plan = $plan
        }
    }

    $backupPath = Backup-UGSMDayZLiveFileOnce -Instance $Instance -Path $livePath

    $removeSet = @{}
    foreach ($entry in $entriesToRemove) {
        $name = [string]$entry.ClassName
        if (-not [string]::IsNullOrWhiteSpace($name)) {
            $removeSet[$name.ToLowerInvariant()] = $entry
        }
    }

    [xml]$xml = Get-Content -LiteralPath $livePath -Raw -ErrorAction Stop
    $removed = @()

    foreach ($node in @($xml.SelectNodes('/events/event[@name]'))) {
        $name = [string]$node.GetAttribute('name')
        if ([string]::IsNullOrWhiteSpace($name)) { continue }

        $key = $name.ToLowerInvariant()
        if (-not $removeSet.ContainsKey($key)) { continue }

        $entry = $removeSet[$key]
        [void]$node.ParentNode.RemoveChild($node)

        $removed += [pscustomobject]@{
            ClassName = $name
            SourceModId = [string]$entry.SourceModId
            SourceModName = [string]$entry.SourceModName
            SourceFile = [string]$entry.SourceFile
            SourcePath = [string]$entry.SourcePath
            LiveFile = $livePath
            Operation = 'RemoveEvent'
            RemovedAt = (Get-Date).ToString('s')
            BackupPath = $backupPath
        }
    }

    Save-UGSMDayZXmlDocumentUtf8 -Xml $xml -Path $livePath

    $contrib = Read-UGSMDayZJsonFileSafe -Path $paths.ContributionsPath -Default $null
    $oldEntries = @()
    $oldRemoved = @()

    if ($null -ne $contrib -and $contrib.PSObject.Properties.Name -contains 'Entries') {
        $oldEntries = @($contrib.Entries)
    }
    if ($null -ne $contrib -and $contrib.PSObject.Properties.Name -contains 'RemovedEntries') {
        $oldRemoved = @($contrib.RemovedEntries)
    }

    $removedSet = @{}
    foreach ($r in $removed) {
        $removedSet[[string]$r.SourceModId + '|AddEvent|' + ([string]$r.ClassName).ToLowerInvariant()] = $true
    }

    $remainingEntries = @()
    foreach ($e in $oldEntries) {
        $eMod = [string](Get-UGSMDayZObjectValue -Object $e -Name 'SourceModId' -Default '')
        $eName = [string](Get-UGSMDayZObjectValue -Object $e -Name 'ClassName' -Default '')
        $eOperation = [string](Get-UGSMDayZObjectValue -Object $e -Name 'Operation' -Default '')
        $eKey = $eMod + '|' + $eOperation + '|' + $eName.ToLowerInvariant()
        if (-not $removedSet.ContainsKey($eKey)) {
            $remainingEntries += $e
        }
    }

    $newContrib = [pscustomobject]@{
        GeneratedAt = (Get-Date).ToString('s')
        InstanceId = $plan.InstanceId
        InstanceName = $plan.InstanceName
        SelectedMission = $plan.SelectedMission
        Entries = @($remainingEntries)
        RemovedEntries = @($oldRemoved + $removed)
    }

    Write-UGSMDayZCacheJson -Path $paths.ContributionsPath -Data $newContrib -Depth 64 | Out-Null
    try { [void](Normalize-UGSMDayZModContributions -Instance $Instance -Write) } catch { }

    $result = [pscustomobject]@{
        AppliedAt = (Get-Date).ToString('s')
        InstanceId = $plan.InstanceId
        InstanceName = $plan.InstanceName
        LiveEventsPath = $livePath
        RemovedCount = @($removed).Count
        SkippedCount = ([int]$plan.SkipActiveCount + [int]$plan.SkipMissingLiveCount + [int]$plan.SkipDuplicateLedgerCount + [int]$plan.SkipInvalidCount)
        InactiveModIds = @($plan.InactiveModIds)
        BackupPath = $backupPath
        ContributionsPath = $paths.ContributionsPath
        Message = ('Removed {0} UGSM-owned event entries for removed/disabled mods.' -f @($removed).Count)
        Removed = @($removed)
        Plan = $plan
    }

    $resultPath = Join-Path $paths.GeneratedFolder 'events-cleanup-result.json'
    Write-UGSMDayZCacheJson -Path $resultPath -Data $result -Depth 64 | Out-Null

    return $result
}

function Invoke-UGSMDayZPreviewSelectedModEventsMerge {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$Instance,
        [Parameter(Mandatory)][string]$ModId
    )

    return (New-UGSMDayZEventsMergePlan -Instance $Instance -ModId $ModId -WritePlan)
}

function Invoke-UGSMDayZApplySelectedModEventsMerge {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$Instance,
        [Parameter(Mandatory)][string]$ModId
    )

    $result = Add-UGSMDayZEventNodesToLiveEvents -Instance $Instance -ModId $ModId
    try {
        $normalized = Normalize-UGSMDayZModContributions -Instance $Instance -Write
        $result | Add-Member -NotePropertyName LedgerEntryCount -NotePropertyValue @($normalized.Entries).Count -Force
        $result | Add-Member -NotePropertyName LedgerDuplicateEntriesRemoved -NotePropertyValue ([int]$normalized.LedgerStats.RemovedDuplicateEntries) -Force
    }
    catch { }

    return $result
}

function Invoke-UGSMDayZPreviewRemovedModEventsCleanup {
    [CmdletBinding()]
    param([Parameter(Mandatory)][object]$Instance)

    [void](Normalize-UGSMDayZModContributions -Instance $Instance -Write)
    return (New-UGSMDayZRemovedModEventsCleanupPlan -Instance $Instance -WritePlan)
}

function Invoke-UGSMDayZApplyRemovedModEventsCleanup {
    [CmdletBinding()]
    param([Parameter(Mandatory)][object]$Instance)

    [void](Normalize-UGSMDayZModContributions -Instance $Instance -Write)
    $result = Remove-UGSMDayZRemovedModEventNodes -Instance $Instance
    [void](Normalize-UGSMDayZModContributions -Instance $Instance -Write)
    return $result
}


# ============================================================
# v17: cfgeventspawns.xml and cfgeventgroups.xml selected-mod apply/removed-mod cleanup
# ============================================================

function Get-UGSMDayZLiveEventSpawnsXmlPath {
    [CmdletBinding()]
    param([Parameter(Mandatory)][object]$Instance)

    $profilePath = Get-UGSMDayZProfilePath -Instance $Instance
    if ([string]::IsNullOrWhiteSpace($profilePath)) { return '' }

    $missionName = Get-UGSMDayZSelectedMissionName -Instance $Instance
    return (Join-Path $profilePath (Join-Path (Join-Path 'mpmissions' $missionName) 'cfgeventspawns.xml'))
}

function Get-UGSMDayZLiveCfgEventGroupsXmlPath {
    [CmdletBinding()]
    param([Parameter(Mandatory)][object]$Instance)

    $profilePath = Get-UGSMDayZProfilePath -Instance $Instance
    if ([string]::IsNullOrWhiteSpace($profilePath)) { return '' }

    $missionName = Get-UGSMDayZSelectedMissionName -Instance $Instance
    return (Join-Path $profilePath (Join-Path (Join-Path 'mpmissions' $missionName) 'cfgeventgroups.xml'))
}

function Get-UGSMDayZCachedModEventSpawnFileRecords {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$Instance,
        [string]$ModId = ''
    )

    $files = @(Get-UGSMDayZCachedFileIndex -Instance $Instance)
    $records = @()

    foreach ($file in $files) {
        $source = [string](Get-UGSMDayZObjectValue -Object $file -Name 'Source' -Default '')
        $kind = [string](Get-UGSMDayZObjectValue -Object $file -Name 'Kind' -Default '')
        $fileModId = [string](Get-UGSMDayZObjectValue -Object $file -Name 'ModId' -Default '')

        if ($source -ne 'Mod') { continue }
        if ($kind -ne 'cfgeventspawns') { continue }
        if (-not [string]::IsNullOrWhiteSpace($ModId) -and $fileModId -ne $ModId) { continue }

        $path = [string](Get-UGSMDayZObjectValue -Object $file -Name 'Path' -Default '')
        if ([string]::IsNullOrWhiteSpace($path) -or -not (Test-Path -LiteralPath $path -PathType Leaf)) { continue }

        $records += $file
    }

    return @($records)
}

function Get-UGSMDayZCachedModCfgEventGroupFileRecords {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$Instance,
        [string]$ModId = ''
    )

    $files = @(Get-UGSMDayZCachedFileIndex -Instance $Instance)
    $records = @()

    foreach ($file in $files) {
        $source = [string](Get-UGSMDayZObjectValue -Object $file -Name 'Source' -Default '')
        $kind = [string](Get-UGSMDayZObjectValue -Object $file -Name 'Kind' -Default '')
        $fileModId = [string](Get-UGSMDayZObjectValue -Object $file -Name 'ModId' -Default '')

        if ($source -ne 'Mod') { continue }
        if ($kind -ne 'cfgeventgroups') { continue }
        if (-not [string]::IsNullOrWhiteSpace($ModId) -and $fileModId -ne $ModId) { continue }

        $path = [string](Get-UGSMDayZObjectValue -Object $file -Name 'Path' -Default '')
        if ([string]::IsNullOrWhiteSpace($path) -or -not (Test-Path -LiteralPath $path -PathType Leaf)) { continue }

        $records += $file
    }

    return @($records)
}

function Get-UGSMDayZEventSpawnNodesFromFileRecord {
    [CmdletBinding()]
    param([Parameter(Mandatory)][object]$FileRecord)

    $path = [string](Get-UGSMDayZObjectValue -Object $FileRecord -Name 'Path' -Default '')
    if ([string]::IsNullOrWhiteSpace($path) -or -not (Test-Path -LiteralPath $path -PathType Leaf)) { return @() }

    try {
        [xml]$xml = Get-Content -LiteralPath $path -Raw -ErrorAction Stop
        return @($xml.SelectNodes('/eventposdef/event[@name]'))
    }
    catch {
        return @()
    }
}

function Get-UGSMDayZCfgEventGroupNodesFromFileRecord {
    [CmdletBinding()]
    param([Parameter(Mandatory)][object]$FileRecord)

    $path = [string](Get-UGSMDayZObjectValue -Object $FileRecord -Name 'Path' -Default '')
    if ([string]::IsNullOrWhiteSpace($path) -or -not (Test-Path -LiteralPath $path -PathType Leaf)) { return @() }

    try {
        [xml]$xml = Get-Content -LiteralPath $path -Raw -ErrorAction Stop
        return @($xml.SelectNodes('/eventgroupdef/group[@name]'))
    }
    catch {
        return @()
    }
}

function Get-UGSMDayZExistingEventSpawnNameSet {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$EventSpawnsXmlPath)

    $set = @{}
    if ([string]::IsNullOrWhiteSpace($EventSpawnsXmlPath) -or -not (Test-Path -LiteralPath $EventSpawnsXmlPath -PathType Leaf)) {
        return $set
    }

    try {
        [xml]$xml = Get-Content -LiteralPath $EventSpawnsXmlPath -Raw -ErrorAction Stop
        foreach ($node in @($xml.SelectNodes('/eventposdef/event[@name]'))) {
            $name = [string]$node.GetAttribute('name')
            if (-not [string]::IsNullOrWhiteSpace($name)) {
                $set[$name.ToLowerInvariant()] = $name
            }
        }
    }
    catch { }

    return $set
}

function Get-UGSMDayZExistingCfgEventGroupNameSet {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$CfgEventGroupsXmlPath)

    $set = @{}
    if ([string]::IsNullOrWhiteSpace($CfgEventGroupsXmlPath) -or -not (Test-Path -LiteralPath $CfgEventGroupsXmlPath -PathType Leaf)) {
        return $set
    }

    try {
        [xml]$xml = Get-Content -LiteralPath $CfgEventGroupsXmlPath -Raw -ErrorAction Stop
        foreach ($node in @($xml.SelectNodes('/eventgroupdef/group[@name]'))) {
            $name = [string]$node.GetAttribute('name')
            if (-not [string]::IsNullOrWhiteSpace($name)) {
                $set[$name.ToLowerInvariant()] = $name
            }
        }
    }
    catch { }

    return $set
}

function New-UGSMDayZEventSpawnsMergePlan {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$Instance,
        [string]$ModId = '',
        [switch]$WritePlan
    )

    $paths = Get-UGSMDayZInstanceStoragePaths -Instance $Instance -Create
    $livePath = Get-UGSMDayZLiveEventSpawnsXmlPath -Instance $Instance
    if ([string]::IsNullOrWhiteSpace($livePath)) {
        throw 'Could not resolve live DayZ cfgeventspawns.xml path for this instance.'
    }
    if (-not (Test-Path -LiteralPath $livePath -PathType Leaf)) {
        throw ('Live DayZ cfgeventspawns.xml was not found: {0}' -f $livePath)
    }

    $existing = Get-UGSMDayZExistingEventSpawnNameSet -EventSpawnsXmlPath $livePath
    $modFiles = @(Get-UGSMDayZCachedModEventSpawnFileRecords -Instance $Instance -ModId $ModId)

    $seenIncoming = @{}
    $entries = @()
    $addCount = 0
    $skipExistingCount = 0
    $skipDuplicateIncomingCount = 0

    foreach ($file in $modFiles) {
        $fileModId = [string](Get-UGSMDayZObjectValue -Object $file -Name 'ModId' -Default '')
        $fileModName = [string](Get-UGSMDayZObjectValue -Object $file -Name 'ModName' -Default $fileModId)
        $sourceFile = [string](Get-UGSMDayZObjectValue -Object $file -Name 'FileName' -Default '')
        $sourcePath = [string](Get-UGSMDayZObjectValue -Object $file -Name 'Path' -Default '')

        foreach ($node in @(Get-UGSMDayZEventSpawnNodesFromFileRecord -FileRecord $file)) {
            $name = [string]$node.GetAttribute('name')
            if ([string]::IsNullOrWhiteSpace($name)) { continue }

            $key = $name.ToLowerInvariant()
            $action = 'Add'
            $reason = ''

            if ($existing.ContainsKey($key)) {
                $action = 'Skip'
                $reason = 'AlreadyExistsInLiveEventSpawns'
                $skipExistingCount++
            }
            elseif ($seenIncoming.ContainsKey($key)) {
                $action = 'Skip'
                $reason = 'DuplicateIncomingEventSpawn'
                $skipDuplicateIncomingCount++
            }
            else {
                $seenIncoming[$key] = $true
                $addCount++
            }

            $entries += [pscustomobject]@{
                ClassName = $name
                Action = $action
                Reason = $reason
                SourceModId = $fileModId
                SourceModName = $fileModName
                SourceFile = $sourceFile
                SourcePath = $sourcePath
            }
        }
    }

    $plan = [pscustomobject]@{
        GeneratedAt = (Get-Date).ToString('s')
        InstanceId = [string](Get-UGSMDayZObjectValue -Object $Instance -Name 'Id' -Default '')
        InstanceName = [string](Get-UGSMDayZObjectValue -Object $Instance -Name 'Name' -Default '')
        SelectedMission = Get-UGSMDayZSelectedMissionName -Instance $Instance
        LiveEventSpawnsPath = $livePath
        RequestedModId = $ModId
        ModEventSpawnFileCount = @($modFiles).Count
        TotalIncomingEventSpawnCount = @($entries).Count
        AddCount = $addCount
        SkipExistingCount = $skipExistingCount
        SkipDuplicateIncomingCount = $skipDuplicateIncomingCount
        Entries = @($entries)
    }

    if ($WritePlan) {
        $planPath = Join-Path $paths.GeneratedFolder 'cfgeventspawns-merge-plan.json'
        Write-UGSMDayZCacheJson -Path $planPath -Data $plan -Depth 64 | Out-Null
    }

    return $plan
}

function Add-UGSMDayZEventSpawnNodesToLiveEventSpawns {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$Instance,
        [string]$ModId = ''
    )

    $paths = Get-UGSMDayZInstanceStoragePaths -Instance $Instance -Create
    $livePath = Get-UGSMDayZLiveEventSpawnsXmlPath -Instance $Instance
    if ([string]::IsNullOrWhiteSpace($livePath) -or -not (Test-Path -LiteralPath $livePath -PathType Leaf)) {
        throw ('Live DayZ cfgeventspawns.xml was not found: {0}' -f $livePath)
    }

    $plan = New-UGSMDayZEventSpawnsMergePlan -Instance $Instance -ModId $ModId -WritePlan
    $entriesToAdd = @($plan.Entries | Where-Object { [string]$_.Action -eq 'Add' })

    if (@($entriesToAdd).Count -eq 0) {
        return [pscustomobject]@{
            AppliedAt = (Get-Date).ToString('s')
            InstanceId = $plan.InstanceId
            InstanceName = $plan.InstanceName
            LiveEventSpawnsPath = $livePath
            RequestedModId = $ModId
            AddedCount = 0
            SkippedCount = @($plan.Entries).Count
            BackupPath = ''
            ContributionsPath = $paths.ContributionsPath
            Message = 'No new event spawn entries needed to be added.'
            Plan = $plan
        }
    }

    $backupPath = Backup-UGSMDayZLiveFileOnce -Instance $Instance -Path $livePath

    [xml]$liveXml = Get-Content -LiteralPath $livePath -Raw -ErrorAction Stop
    $root = $liveXml.DocumentElement
    if ($null -eq $root -or $root.Name -ne 'eventposdef') {
        throw 'Live cfgeventspawns.xml root node is not <eventposdef>.'
    }

    $entriesByKey = @{}
    foreach ($entry in $entriesToAdd) {
        $entriesByKey[[string]$entry.ClassName] = $entry
    }

    $added = @()
    $addedKeys = @{}

    $modFiles = @(Get-UGSMDayZCachedModEventSpawnFileRecords -Instance $Instance -ModId $ModId)
    foreach ($file in $modFiles) {
        foreach ($node in @(Get-UGSMDayZEventSpawnNodesFromFileRecord -FileRecord $file)) {
            $name = [string]$node.GetAttribute('name')
            if ([string]::IsNullOrWhiteSpace($name)) { continue }
            if (-not $entriesByKey.ContainsKey($name)) { continue }
            if ($addedKeys.ContainsKey($name.ToLowerInvariant())) { continue }

            $imported = $liveXml.ImportNode($node, $true)
            [void]$root.AppendChild($liveXml.CreateWhitespace("`r`n    "))
            [void]$root.AppendChild($imported)

            $entry = $entriesByKey[$name]
            $added += [pscustomobject]@{
                ClassName = $name
                SourceModId = [string]$entry.SourceModId
                SourceModName = [string]$entry.SourceModName
                SourceFile = [string]$entry.SourceFile
                SourcePath = [string]$entry.SourcePath
                LiveFile = $livePath
                Operation = 'AddEventSpawn'
                AppliedAt = (Get-Date).ToString('s')
                BackupPath = $backupPath
            }
            $addedKeys[$name.ToLowerInvariant()] = $true
        }
    }

    [void]$root.AppendChild($liveXml.CreateWhitespace("`r`n"))
    Save-UGSMDayZXmlDocumentUtf8 -Xml $liveXml -Path $livePath

    $existingContrib = Read-UGSMDayZJsonFileSafe -Path $paths.ContributionsPath -Default $null
    $oldEntries = @()
    $oldRemoved = @()
    if ($null -ne $existingContrib -and $existingContrib.PSObject.Properties.Name -contains 'Entries') {
        $oldEntries = @($existingContrib.Entries)
    }
    if ($null -ne $existingContrib -and $existingContrib.PSObject.Properties.Name -contains 'RemovedEntries') {
        $oldRemoved = @($existingContrib.RemovedEntries)
    }

    $contrib = [pscustomobject]@{
        GeneratedAt = (Get-Date).ToString('s')
        InstanceId = $plan.InstanceId
        InstanceName = $plan.InstanceName
        SelectedMission = $plan.SelectedMission
        Entries = @($oldEntries + $added)
        RemovedEntries = @($oldRemoved)
    }

    Write-UGSMDayZCacheJson -Path $paths.ContributionsPath -Data $contrib -Depth 64 | Out-Null
    try { [void](Normalize-UGSMDayZModContributions -Instance $Instance -Write) } catch { }

    $result = [pscustomobject]@{
        AppliedAt = (Get-Date).ToString('s')
        InstanceId = $plan.InstanceId
        InstanceName = $plan.InstanceName
        LiveEventSpawnsPath = $livePath
        RequestedModId = $ModId
        AddedCount = @($added).Count
        SkippedCount = (@($plan.Entries).Count - @($added).Count)
        BackupPath = $backupPath
        ContributionsPath = $paths.ContributionsPath
        Message = ('Added {0} event spawn entries to live cfgeventspawns.xml.' -f @($added).Count)
        Added = @($added)
        Plan = $plan
    }

    $resultPath = Join-Path $paths.GeneratedFolder 'cfgeventspawns-merge-result.json'
    Write-UGSMDayZCacheJson -Path $resultPath -Data $result -Depth 64 | Out-Null

    return $result
}

function New-UGSMDayZRemovedModEventSpawnsCleanupPlan {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$Instance,
        [switch]$WritePlan
    )

    $paths = Get-UGSMDayZInstanceStoragePaths -Instance $Instance -Create
    $livePath = Get-UGSMDayZLiveEventSpawnsXmlPath -Instance $Instance
    if ([string]::IsNullOrWhiteSpace($livePath) -or -not (Test-Path -LiteralPath $livePath -PathType Leaf)) {
        throw ('Live DayZ cfgeventspawns.xml was not found: {0}' -f $livePath)
    }

    $contrib = Read-UGSMDayZJsonFileSafe -Path $paths.ContributionsPath -Default $null
    $contribEntries = @()
    if ($null -ne $contrib -and $contrib.PSObject.Properties.Name -contains 'Entries') {
        $contribEntries = @($contrib.Entries)
    }

    $activeMods = @(Get-UGSMGameDayZResolvedActiveMods -Instance $Instance)
    $activeSet = @{}
    foreach ($mod in $activeMods) {
        $id = [string](Get-UGSMDayZObjectValue -Object $mod -Name 'Id' -Default '')
        if (-not [string]::IsNullOrWhiteSpace($id)) {
            $activeSet[$id] = $true
        }
    }

    $liveSet = Get-UGSMDayZExistingEventSpawnNameSet -EventSpawnsXmlPath $livePath
    $seen = @{}
    $entries = @()
    $removeCount = 0
    $skipActiveCount = 0
    $skipMissingLiveCount = 0
    $skipDuplicateLedgerCount = 0
    $skipInvalidCount = 0

    foreach ($entry in $contribEntries) {
        $className = [string](Get-UGSMDayZObjectValue -Object $entry -Name 'ClassName' -Default '')
        $sourceModId = [string](Get-UGSMDayZObjectValue -Object $entry -Name 'SourceModId' -Default '')
        $operation = [string](Get-UGSMDayZObjectValue -Object $entry -Name 'Operation' -Default '')
        $liveFile = [string](Get-UGSMDayZObjectValue -Object $entry -Name 'LiveFile' -Default '')

        if ([string]::IsNullOrWhiteSpace($className) -or [string]::IsNullOrWhiteSpace($sourceModId)) {
            $skipInvalidCount++
            continue
        }

        if ($operation -ne 'AddEventSpawn') {
            continue
        }

        if (-not [string]::IsNullOrWhiteSpace($liveFile) -and ($liveFile -ne $livePath)) {
            $skipInvalidCount++
            continue
        }

        if ($activeSet.ContainsKey($sourceModId)) {
            $skipActiveCount++
            continue
        }

        $key = $className.ToLowerInvariant()
        if ($seen.ContainsKey($key)) {
            $skipDuplicateLedgerCount++
            continue
        }
        $seen[$key] = $true

        $existsInLive = $liveSet.ContainsKey($key)

        $action = 'Remove'
        $reason = ''
        if (-not $existsInLive) {
            $action = 'Skip'
            $reason = 'MissingFromLiveEventSpawns'
            $skipMissingLiveCount++
        }
        else {
            $removeCount++
        }

        $entries += [pscustomobject]@{
            ClassName = $className
            Action = $action
            Reason = $reason
            SourceModId = $sourceModId
            SourceModName = [string](Get-UGSMDayZObjectValue -Object $entry -Name 'SourceModName' -Default $sourceModId)
            SourceFile = [string](Get-UGSMDayZObjectValue -Object $entry -Name 'SourceFile' -Default '')
            SourcePath = [string](Get-UGSMDayZObjectValue -Object $entry -Name 'SourcePath' -Default '')
            LiveFile = $livePath
            BackupPath = [string](Get-UGSMDayZObjectValue -Object $entry -Name 'BackupPath' -Default '')
        }
    }

    $inactiveModIds = @($entries | Where-Object { $_.Action -eq 'Remove' } | ForEach-Object { [string]$_.SourceModId } | Sort-Object -Unique)

    $plan = [pscustomobject]@{
        GeneratedAt = (Get-Date).ToString('s')
        InstanceId = [string](Get-UGSMDayZObjectValue -Object $Instance -Name 'Id' -Default '')
        InstanceName = [string](Get-UGSMDayZObjectValue -Object $Instance -Name 'Name' -Default '')
        SelectedMission = Get-UGSMDayZSelectedMissionName -Instance $Instance
        LiveEventSpawnsPath = $livePath
        ContributionsPath = $paths.ContributionsPath
        ActiveModCount = $activeSet.Count
        LedgerEntryCount = @($contribEntries).Count
        InactiveModIds = @($inactiveModIds)
        CleanupCandidateCount = @($entries).Count
        RemoveCount = $removeCount
        SkipActiveCount = $skipActiveCount
        SkipMissingLiveCount = $skipMissingLiveCount
        SkipDuplicateLedgerCount = $skipDuplicateLedgerCount
        SkipInvalidCount = $skipInvalidCount
        Entries = @($entries)
    }

    if ($WritePlan) {
        $planPath = Join-Path $paths.GeneratedFolder 'cfgeventspawns-cleanup-plan.json'
        Write-UGSMDayZCacheJson -Path $planPath -Data $plan -Depth 64 | Out-Null
    }

    return $plan
}

function Remove-UGSMDayZRemovedModEventSpawnNodes {
    [CmdletBinding()]
    param([Parameter(Mandatory)][object]$Instance)

    $paths = Get-UGSMDayZInstanceStoragePaths -Instance $Instance -Create
    $livePath = Get-UGSMDayZLiveEventSpawnsXmlPath -Instance $Instance
    if ([string]::IsNullOrWhiteSpace($livePath) -or -not (Test-Path -LiteralPath $livePath -PathType Leaf)) {
        throw ('Live DayZ cfgeventspawns.xml was not found: {0}' -f $livePath)
    }

    $plan = New-UGSMDayZRemovedModEventSpawnsCleanupPlan -Instance $Instance -WritePlan
    $entriesToRemove = @($plan.Entries | Where-Object { [string]$_.Action -eq 'Remove' })

    if (@($entriesToRemove).Count -eq 0) {
        return [pscustomobject]@{
            AppliedAt = (Get-Date).ToString('s')
            InstanceId = $plan.InstanceId
            InstanceName = $plan.InstanceName
            LiveEventSpawnsPath = $livePath
            RemovedCount = 0
            SkippedCount = ([int]$plan.SkipActiveCount + [int]$plan.SkipMissingLiveCount + [int]$plan.SkipDuplicateLedgerCount + [int]$plan.SkipInvalidCount)
            InactiveModIds = @($plan.InactiveModIds)
            BackupPath = ''
            ContributionsPath = $paths.ContributionsPath
            Message = 'No removed/disabled mod event spawn entries needed cleanup.'
            Plan = $plan
        }
    }

    $backupPath = Backup-UGSMDayZLiveFileOnce -Instance $Instance -Path $livePath

    $removeSet = @{}
    foreach ($entry in $entriesToRemove) {
        $name = [string]$entry.ClassName
        if (-not [string]::IsNullOrWhiteSpace($name)) {
            $removeSet[$name.ToLowerInvariant()] = $entry
        }
    }

    [xml]$xml = Get-Content -LiteralPath $livePath -Raw -ErrorAction Stop
    $removed = @()

    foreach ($node in @($xml.SelectNodes('/eventposdef/event[@name]'))) {
        $name = [string]$node.GetAttribute('name')
        if ([string]::IsNullOrWhiteSpace($name)) { continue }

        $key = $name.ToLowerInvariant()
        if (-not $removeSet.ContainsKey($key)) { continue }

        $entry = $removeSet[$key]
        [void]$node.ParentNode.RemoveChild($node)

        $removed += [pscustomobject]@{
            ClassName = $name
            SourceModId = [string]$entry.SourceModId
            SourceModName = [string]$entry.SourceModName
            SourceFile = [string]$entry.SourceFile
            SourcePath = [string]$entry.SourcePath
            LiveFile = $livePath
            Operation = 'RemoveEventSpawn'
            RemovedAt = (Get-Date).ToString('s')
            BackupPath = $backupPath
        }
    }

    Save-UGSMDayZXmlDocumentUtf8 -Xml $xml -Path $livePath

    $contrib = Read-UGSMDayZJsonFileSafe -Path $paths.ContributionsPath -Default $null
    $oldEntries = @()
    $oldRemoved = @()

    if ($null -ne $contrib -and $contrib.PSObject.Properties.Name -contains 'Entries') {
        $oldEntries = @($contrib.Entries)
    }
    if ($null -ne $contrib -and $contrib.PSObject.Properties.Name -contains 'RemovedEntries') {
        $oldRemoved = @($contrib.RemovedEntries)
    }

    $removedSet = @{}
    foreach ($r in $removed) {
        $removedSet[[string]$r.SourceModId + '|AddEventSpawn|' + ([string]$r.ClassName).ToLowerInvariant()] = $true
    }

    $remainingEntries = @()
    foreach ($e in $oldEntries) {
        $eMod = [string](Get-UGSMDayZObjectValue -Object $e -Name 'SourceModId' -Default '')
        $eName = [string](Get-UGSMDayZObjectValue -Object $e -Name 'ClassName' -Default '')
        $eOperation = [string](Get-UGSMDayZObjectValue -Object $e -Name 'Operation' -Default '')
        $eKey = $eMod + '|' + $eOperation + '|' + $eName.ToLowerInvariant()
        if (-not $removedSet.ContainsKey($eKey)) {
            $remainingEntries += $e
        }
    }

    $newContrib = [pscustomobject]@{
        GeneratedAt = (Get-Date).ToString('s')
        InstanceId = $plan.InstanceId
        InstanceName = $plan.InstanceName
        SelectedMission = $plan.SelectedMission
        Entries = @($remainingEntries)
        RemovedEntries = @($oldRemoved + $removed)
    }

    Write-UGSMDayZCacheJson -Path $paths.ContributionsPath -Data $newContrib -Depth 64 | Out-Null
    try { [void](Normalize-UGSMDayZModContributions -Instance $Instance -Write) } catch { }

    $result = [pscustomobject]@{
        AppliedAt = (Get-Date).ToString('s')
        InstanceId = $plan.InstanceId
        InstanceName = $plan.InstanceName
        LiveEventSpawnsPath = $livePath
        RemovedCount = @($removed).Count
        SkippedCount = ([int]$plan.SkipActiveCount + [int]$plan.SkipMissingLiveCount + [int]$plan.SkipDuplicateLedgerCount + [int]$plan.SkipInvalidCount)
        InactiveModIds = @($plan.InactiveModIds)
        BackupPath = $backupPath
        ContributionsPath = $paths.ContributionsPath
        Message = ('Removed {0} UGSM-owned event spawn entries for removed/disabled mods.' -f @($removed).Count)
        Removed = @($removed)
        Plan = $plan
    }

    $resultPath = Join-Path $paths.GeneratedFolder 'cfgeventspawns-cleanup-result.json'
    Write-UGSMDayZCacheJson -Path $resultPath -Data $result -Depth 64 | Out-Null

    return $result
}

function New-UGSMDayZCfgEventGroupsMergePlan {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$Instance,
        [string]$ModId = '',
        [switch]$WritePlan
    )

    $paths = Get-UGSMDayZInstanceStoragePaths -Instance $Instance -Create
    $livePath = Get-UGSMDayZLiveCfgEventGroupsXmlPath -Instance $Instance
    if ([string]::IsNullOrWhiteSpace($livePath)) {
        throw 'Could not resolve live DayZ cfgeventgroups.xml path for this instance.'
    }
    if (-not (Test-Path -LiteralPath $livePath -PathType Leaf)) {
        throw ('Live DayZ cfgeventgroups.xml was not found: {0}' -f $livePath)
    }

    $existing = Get-UGSMDayZExistingCfgEventGroupNameSet -CfgEventGroupsXmlPath $livePath
    $modFiles = @(Get-UGSMDayZCachedModCfgEventGroupFileRecords -Instance $Instance -ModId $ModId)

    $seenIncoming = @{}
    $entries = @()
    $addCount = 0
    $skipExistingCount = 0
    $skipDuplicateIncomingCount = 0

    foreach ($file in $modFiles) {
        $fileModId = [string](Get-UGSMDayZObjectValue -Object $file -Name 'ModId' -Default '')
        $fileModName = [string](Get-UGSMDayZObjectValue -Object $file -Name 'ModName' -Default $fileModId)
        $sourceFile = [string](Get-UGSMDayZObjectValue -Object $file -Name 'FileName' -Default '')
        $sourcePath = [string](Get-UGSMDayZObjectValue -Object $file -Name 'Path' -Default '')

        foreach ($node in @(Get-UGSMDayZCfgEventGroupNodesFromFileRecord -FileRecord $file)) {
            $name = [string]$node.GetAttribute('name')
            if ([string]::IsNullOrWhiteSpace($name)) { continue }

            $key = $name.ToLowerInvariant()
            $action = 'Add'
            $reason = ''

            if ($existing.ContainsKey($key)) {
                $action = 'Skip'
                $reason = 'AlreadyExistsInLiveCfgEventGroups'
                $skipExistingCount++
            }
            elseif ($seenIncoming.ContainsKey($key)) {
                $action = 'Skip'
                $reason = 'DuplicateIncomingCfgEventGroup'
                $skipDuplicateIncomingCount++
            }
            else {
                $seenIncoming[$key] = $true
                $addCount++
            }

            $entries += [pscustomobject]@{
                ClassName = $name
                Action = $action
                Reason = $reason
                SourceModId = $fileModId
                SourceModName = $fileModName
                SourceFile = $sourceFile
                SourcePath = $sourcePath
            }
        }
    }

    $plan = [pscustomobject]@{
        GeneratedAt = (Get-Date).ToString('s')
        InstanceId = [string](Get-UGSMDayZObjectValue -Object $Instance -Name 'Id' -Default '')
        InstanceName = [string](Get-UGSMDayZObjectValue -Object $Instance -Name 'Name' -Default '')
        SelectedMission = Get-UGSMDayZSelectedMissionName -Instance $Instance
        LiveCfgEventGroupsPath = $livePath
        RequestedModId = $ModId
        ModCfgEventGroupFileCount = @($modFiles).Count
        TotalIncomingCfgEventGroupCount = @($entries).Count
        AddCount = $addCount
        SkipExistingCount = $skipExistingCount
        SkipDuplicateIncomingCount = $skipDuplicateIncomingCount
        Entries = @($entries)
    }

    if ($WritePlan) {
        $planPath = Join-Path $paths.GeneratedFolder 'cfgeventgroups-merge-plan.json'
        Write-UGSMDayZCacheJson -Path $planPath -Data $plan -Depth 64 | Out-Null
    }

    return $plan
}

function Add-UGSMDayZCfgEventGroupNodesToLiveCfgEventGroups {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$Instance,
        [string]$ModId = ''
    )

    $paths = Get-UGSMDayZInstanceStoragePaths -Instance $Instance -Create
    $livePath = Get-UGSMDayZLiveCfgEventGroupsXmlPath -Instance $Instance
    if ([string]::IsNullOrWhiteSpace($livePath) -or -not (Test-Path -LiteralPath $livePath -PathType Leaf)) {
        throw ('Live DayZ cfgeventgroups.xml was not found: {0}' -f $livePath)
    }

    $plan = New-UGSMDayZCfgEventGroupsMergePlan -Instance $Instance -ModId $ModId -WritePlan
    $entriesToAdd = @($plan.Entries | Where-Object { [string]$_.Action -eq 'Add' })

    if (@($entriesToAdd).Count -eq 0) {
        return [pscustomobject]@{
            AppliedAt = (Get-Date).ToString('s')
            InstanceId = $plan.InstanceId
            InstanceName = $plan.InstanceName
            LiveCfgEventGroupsPath = $livePath
            RequestedModId = $ModId
            AddedCount = 0
            SkippedCount = @($plan.Entries).Count
            BackupPath = ''
            ContributionsPath = $paths.ContributionsPath
            Message = 'No new cfg event group entries needed to be added.'
            Plan = $plan
        }
    }

    $backupPath = Backup-UGSMDayZLiveFileOnce -Instance $Instance -Path $livePath

    [xml]$liveXml = Get-Content -LiteralPath $livePath -Raw -ErrorAction Stop
    $root = $liveXml.DocumentElement
    if ($null -eq $root -or $root.Name -ne 'eventgroupdef') {
        throw 'Live cfgeventgroups.xml root node is not <eventgroupdef>.'
    }

    $entriesByKey = @{}
    foreach ($entry in $entriesToAdd) {
        $entriesByKey[[string]$entry.ClassName] = $entry
    }

    $added = @()
    $addedKeys = @{}

    $modFiles = @(Get-UGSMDayZCachedModCfgEventGroupFileRecords -Instance $Instance -ModId $ModId)
    foreach ($file in $modFiles) {
        foreach ($node in @(Get-UGSMDayZCfgEventGroupNodesFromFileRecord -FileRecord $file)) {
            $name = [string]$node.GetAttribute('name')
            if ([string]::IsNullOrWhiteSpace($name)) { continue }
            if (-not $entriesByKey.ContainsKey($name)) { continue }
            if ($addedKeys.ContainsKey($name.ToLowerInvariant())) { continue }

            $imported = $liveXml.ImportNode($node, $true)
            [void]$root.AppendChild($liveXml.CreateWhitespace("`r`n    "))
            [void]$root.AppendChild($imported)

            $entry = $entriesByKey[$name]
            $added += [pscustomobject]@{
                ClassName = $name
                SourceModId = [string]$entry.SourceModId
                SourceModName = [string]$entry.SourceModName
                SourceFile = [string]$entry.SourceFile
                SourcePath = [string]$entry.SourcePath
                LiveFile = $livePath
                Operation = 'AddCfgEventGroup'
                AppliedAt = (Get-Date).ToString('s')
                BackupPath = $backupPath
            }
            $addedKeys[$name.ToLowerInvariant()] = $true
        }
    }

    [void]$root.AppendChild($liveXml.CreateWhitespace("`r`n"))
    Save-UGSMDayZXmlDocumentUtf8 -Xml $liveXml -Path $livePath

    $existingContrib = Read-UGSMDayZJsonFileSafe -Path $paths.ContributionsPath -Default $null
    $oldEntries = @()
    $oldRemoved = @()
    if ($null -ne $existingContrib -and $existingContrib.PSObject.Properties.Name -contains 'Entries') {
        $oldEntries = @($existingContrib.Entries)
    }
    if ($null -ne $existingContrib -and $existingContrib.PSObject.Properties.Name -contains 'RemovedEntries') {
        $oldRemoved = @($existingContrib.RemovedEntries)
    }

    $contrib = [pscustomobject]@{
        GeneratedAt = (Get-Date).ToString('s')
        InstanceId = $plan.InstanceId
        InstanceName = $plan.InstanceName
        SelectedMission = $plan.SelectedMission
        Entries = @($oldEntries + $added)
        RemovedEntries = @($oldRemoved)
    }

    Write-UGSMDayZCacheJson -Path $paths.ContributionsPath -Data $contrib -Depth 64 | Out-Null
    try { [void](Normalize-UGSMDayZModContributions -Instance $Instance -Write) } catch { }

    $result = [pscustomobject]@{
        AppliedAt = (Get-Date).ToString('s')
        InstanceId = $plan.InstanceId
        InstanceName = $plan.InstanceName
        LiveCfgEventGroupsPath = $livePath
        RequestedModId = $ModId
        AddedCount = @($added).Count
        SkippedCount = (@($plan.Entries).Count - @($added).Count)
        BackupPath = $backupPath
        ContributionsPath = $paths.ContributionsPath
        Message = ('Added {0} cfg event group entries to live cfgeventgroups.xml.' -f @($added).Count)
        Added = @($added)
        Plan = $plan
    }

    $resultPath = Join-Path $paths.GeneratedFolder 'cfgeventgroups-merge-result.json'
    Write-UGSMDayZCacheJson -Path $resultPath -Data $result -Depth 64 | Out-Null

    return $result
}

function New-UGSMDayZRemovedModCfgEventGroupsCleanupPlan {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$Instance,
        [switch]$WritePlan
    )

    $paths = Get-UGSMDayZInstanceStoragePaths -Instance $Instance -Create
    $livePath = Get-UGSMDayZLiveCfgEventGroupsXmlPath -Instance $Instance
    if ([string]::IsNullOrWhiteSpace($livePath) -or -not (Test-Path -LiteralPath $livePath -PathType Leaf)) {
        throw ('Live DayZ cfgeventgroups.xml was not found: {0}' -f $livePath)
    }

    $contrib = Read-UGSMDayZJsonFileSafe -Path $paths.ContributionsPath -Default $null
    $contribEntries = @()
    if ($null -ne $contrib -and $contrib.PSObject.Properties.Name -contains 'Entries') {
        $contribEntries = @($contrib.Entries)
    }

    $activeMods = @(Get-UGSMGameDayZResolvedActiveMods -Instance $Instance)
    $activeSet = @{}
    foreach ($mod in $activeMods) {
        $id = [string](Get-UGSMDayZObjectValue -Object $mod -Name 'Id' -Default '')
        if (-not [string]::IsNullOrWhiteSpace($id)) {
            $activeSet[$id] = $true
        }
    }

    $liveSet = Get-UGSMDayZExistingCfgEventGroupNameSet -CfgEventGroupsXmlPath $livePath
    $seen = @{}
    $entries = @()
    $removeCount = 0
    $skipActiveCount = 0
    $skipMissingLiveCount = 0
    $skipDuplicateLedgerCount = 0
    $skipInvalidCount = 0

    foreach ($entry in $contribEntries) {
        $className = [string](Get-UGSMDayZObjectValue -Object $entry -Name 'ClassName' -Default '')
        $sourceModId = [string](Get-UGSMDayZObjectValue -Object $entry -Name 'SourceModId' -Default '')
        $operation = [string](Get-UGSMDayZObjectValue -Object $entry -Name 'Operation' -Default '')
        $liveFile = [string](Get-UGSMDayZObjectValue -Object $entry -Name 'LiveFile' -Default '')

        if ([string]::IsNullOrWhiteSpace($className) -or [string]::IsNullOrWhiteSpace($sourceModId)) {
            $skipInvalidCount++
            continue
        }

        if ($operation -ne 'AddCfgEventGroup') {
            continue
        }

        if (-not [string]::IsNullOrWhiteSpace($liveFile) -and ($liveFile -ne $livePath)) {
            $skipInvalidCount++
            continue
        }

        if ($activeSet.ContainsKey($sourceModId)) {
            $skipActiveCount++
            continue
        }

        $key = $className.ToLowerInvariant()
        if ($seen.ContainsKey($key)) {
            $skipDuplicateLedgerCount++
            continue
        }
        $seen[$key] = $true

        $existsInLive = $liveSet.ContainsKey($key)

        $action = 'Remove'
        $reason = ''
        if (-not $existsInLive) {
            $action = 'Skip'
            $reason = 'MissingFromLiveCfgEventGroups'
            $skipMissingLiveCount++
        }
        else {
            $removeCount++
        }

        $entries += [pscustomobject]@{
            ClassName = $className
            Action = $action
            Reason = $reason
            SourceModId = $sourceModId
            SourceModName = [string](Get-UGSMDayZObjectValue -Object $entry -Name 'SourceModName' -Default $sourceModId)
            SourceFile = [string](Get-UGSMDayZObjectValue -Object $entry -Name 'SourceFile' -Default '')
            SourcePath = [string](Get-UGSMDayZObjectValue -Object $entry -Name 'SourcePath' -Default '')
            LiveFile = $livePath
            BackupPath = [string](Get-UGSMDayZObjectValue -Object $entry -Name 'BackupPath' -Default '')
        }
    }

    $inactiveModIds = @($entries | Where-Object { $_.Action -eq 'Remove' } | ForEach-Object { [string]$_.SourceModId } | Sort-Object -Unique)

    $plan = [pscustomobject]@{
        GeneratedAt = (Get-Date).ToString('s')
        InstanceId = [string](Get-UGSMDayZObjectValue -Object $Instance -Name 'Id' -Default '')
        InstanceName = [string](Get-UGSMDayZObjectValue -Object $Instance -Name 'Name' -Default '')
        SelectedMission = Get-UGSMDayZSelectedMissionName -Instance $Instance
        LiveCfgEventGroupsPath = $livePath
        ContributionsPath = $paths.ContributionsPath
        ActiveModCount = $activeSet.Count
        LedgerEntryCount = @($contribEntries).Count
        InactiveModIds = @($inactiveModIds)
        CleanupCandidateCount = @($entries).Count
        RemoveCount = $removeCount
        SkipActiveCount = $skipActiveCount
        SkipMissingLiveCount = $skipMissingLiveCount
        SkipDuplicateLedgerCount = $skipDuplicateLedgerCount
        SkipInvalidCount = $skipInvalidCount
        Entries = @($entries)
    }

    if ($WritePlan) {
        $planPath = Join-Path $paths.GeneratedFolder 'cfgeventgroups-cleanup-plan.json'
        Write-UGSMDayZCacheJson -Path $planPath -Data $plan -Depth 64 | Out-Null
    }

    return $plan
}

function Remove-UGSMDayZRemovedModCfgEventGroupNodes {
    [CmdletBinding()]
    param([Parameter(Mandatory)][object]$Instance)

    $paths = Get-UGSMDayZInstanceStoragePaths -Instance $Instance -Create
    $livePath = Get-UGSMDayZLiveCfgEventGroupsXmlPath -Instance $Instance
    if ([string]::IsNullOrWhiteSpace($livePath) -or -not (Test-Path -LiteralPath $livePath -PathType Leaf)) {
        throw ('Live DayZ cfgeventgroups.xml was not found: {0}' -f $livePath)
    }

    $plan = New-UGSMDayZRemovedModCfgEventGroupsCleanupPlan -Instance $Instance -WritePlan
    $entriesToRemove = @($plan.Entries | Where-Object { [string]$_.Action -eq 'Remove' })

    if (@($entriesToRemove).Count -eq 0) {
        return [pscustomobject]@{
            AppliedAt = (Get-Date).ToString('s')
            InstanceId = $plan.InstanceId
            InstanceName = $plan.InstanceName
            LiveCfgEventGroupsPath = $livePath
            RemovedCount = 0
            SkippedCount = ([int]$plan.SkipActiveCount + [int]$plan.SkipMissingLiveCount + [int]$plan.SkipDuplicateLedgerCount + [int]$plan.SkipInvalidCount)
            InactiveModIds = @($plan.InactiveModIds)
            BackupPath = ''
            ContributionsPath = $paths.ContributionsPath
            Message = 'No removed/disabled mod cfg event group entries needed cleanup.'
            Plan = $plan
        }
    }

    $backupPath = Backup-UGSMDayZLiveFileOnce -Instance $Instance -Path $livePath

    $removeSet = @{}
    foreach ($entry in $entriesToRemove) {
        $name = [string]$entry.ClassName
        if (-not [string]::IsNullOrWhiteSpace($name)) {
            $removeSet[$name.ToLowerInvariant()] = $entry
        }
    }

    [xml]$xml = Get-Content -LiteralPath $livePath -Raw -ErrorAction Stop
    $removed = @()

    foreach ($node in @($xml.SelectNodes('/eventgroupdef/group[@name]'))) {
        $name = [string]$node.GetAttribute('name')
        if ([string]::IsNullOrWhiteSpace($name)) { continue }

        $key = $name.ToLowerInvariant()
        if (-not $removeSet.ContainsKey($key)) { continue }

        $entry = $removeSet[$key]
        [void]$node.ParentNode.RemoveChild($node)

        $removed += [pscustomobject]@{
            ClassName = $name
            SourceModId = [string]$entry.SourceModId
            SourceModName = [string]$entry.SourceModName
            SourceFile = [string]$entry.SourceFile
            SourcePath = [string]$entry.SourcePath
            LiveFile = $livePath
            Operation = 'RemoveCfgEventGroup'
            RemovedAt = (Get-Date).ToString('s')
            BackupPath = $backupPath
        }
    }

    Save-UGSMDayZXmlDocumentUtf8 -Xml $xml -Path $livePath

    $contrib = Read-UGSMDayZJsonFileSafe -Path $paths.ContributionsPath -Default $null
    $oldEntries = @()
    $oldRemoved = @()

    if ($null -ne $contrib -and $contrib.PSObject.Properties.Name -contains 'Entries') {
        $oldEntries = @($contrib.Entries)
    }
    if ($null -ne $contrib -and $contrib.PSObject.Properties.Name -contains 'RemovedEntries') {
        $oldRemoved = @($contrib.RemovedEntries)
    }

    $removedSet = @{}
    foreach ($r in $removed) {
        $removedSet[[string]$r.SourceModId + '|AddCfgEventGroup|' + ([string]$r.ClassName).ToLowerInvariant()] = $true
    }

    $remainingEntries = @()
    foreach ($e in $oldEntries) {
        $eMod = [string](Get-UGSMDayZObjectValue -Object $e -Name 'SourceModId' -Default '')
        $eName = [string](Get-UGSMDayZObjectValue -Object $e -Name 'ClassName' -Default '')
        $eOperation = [string](Get-UGSMDayZObjectValue -Object $e -Name 'Operation' -Default '')
        $eKey = $eMod + '|' + $eOperation + '|' + $eName.ToLowerInvariant()
        if (-not $removedSet.ContainsKey($eKey)) {
            $remainingEntries += $e
        }
    }

    $newContrib = [pscustomobject]@{
        GeneratedAt = (Get-Date).ToString('s')
        InstanceId = $plan.InstanceId
        InstanceName = $plan.InstanceName
        SelectedMission = $plan.SelectedMission
        Entries = @($remainingEntries)
        RemovedEntries = @($oldRemoved + $removed)
    }

    Write-UGSMDayZCacheJson -Path $paths.ContributionsPath -Data $newContrib -Depth 64 | Out-Null
    try { [void](Normalize-UGSMDayZModContributions -Instance $Instance -Write) } catch { }

    $result = [pscustomobject]@{
        AppliedAt = (Get-Date).ToString('s')
        InstanceId = $plan.InstanceId
        InstanceName = $plan.InstanceName
        LiveCfgEventGroupsPath = $livePath
        RemovedCount = @($removed).Count
        SkippedCount = ([int]$plan.SkipActiveCount + [int]$plan.SkipMissingLiveCount + [int]$plan.SkipDuplicateLedgerCount + [int]$plan.SkipInvalidCount)
        InactiveModIds = @($plan.InactiveModIds)
        BackupPath = $backupPath
        ContributionsPath = $paths.ContributionsPath
        Message = ('Removed {0} UGSM-owned cfg event group entries for removed/disabled mods.' -f @($removed).Count)
        Removed = @($removed)
        Plan = $plan
    }

    $resultPath = Join-Path $paths.GeneratedFolder 'cfgeventgroups-cleanup-result.json'
    Write-UGSMDayZCacheJson -Path $resultPath -Data $result -Depth 64 | Out-Null

    return $result
}

function Invoke-UGSMDayZPreviewSelectedModEventSpawnsMerge {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$Instance,
        [Parameter(Mandatory)][string]$ModId
    )

    return (New-UGSMDayZEventSpawnsMergePlan -Instance $Instance -ModId $ModId -WritePlan)
}

function Invoke-UGSMDayZApplySelectedModEventSpawnsMerge {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$Instance,
        [Parameter(Mandatory)][string]$ModId
    )

    $result = Add-UGSMDayZEventSpawnNodesToLiveEventSpawns -Instance $Instance -ModId $ModId
    try {
        $normalized = Normalize-UGSMDayZModContributions -Instance $Instance -Write
        $result | Add-Member -NotePropertyName LedgerEntryCount -NotePropertyValue @($normalized.Entries).Count -Force
        $result | Add-Member -NotePropertyName LedgerDuplicateEntriesRemoved -NotePropertyValue ([int]$normalized.LedgerStats.RemovedDuplicateEntries) -Force
    }
    catch { }

    return $result
}

function Invoke-UGSMDayZPreviewRemovedModEventSpawnsCleanup {
    [CmdletBinding()]
    param([Parameter(Mandatory)][object]$Instance)

    [void](Normalize-UGSMDayZModContributions -Instance $Instance -Write)
    return (New-UGSMDayZRemovedModEventSpawnsCleanupPlan -Instance $Instance -WritePlan)
}

function Invoke-UGSMDayZApplyRemovedModEventSpawnsCleanup {
    [CmdletBinding()]
    param([Parameter(Mandatory)][object]$Instance)

    [void](Normalize-UGSMDayZModContributions -Instance $Instance -Write)
    $result = Remove-UGSMDayZRemovedModEventSpawnNodes -Instance $Instance
    [void](Normalize-UGSMDayZModContributions -Instance $Instance -Write)
    return $result
}

function Invoke-UGSMDayZPreviewSelectedModCfgEventGroupsMerge {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$Instance,
        [Parameter(Mandatory)][string]$ModId
    )

    return (New-UGSMDayZCfgEventGroupsMergePlan -Instance $Instance -ModId $ModId -WritePlan)
}

function Invoke-UGSMDayZApplySelectedModCfgEventGroupsMerge {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$Instance,
        [Parameter(Mandatory)][string]$ModId
    )

    $result = Add-UGSMDayZCfgEventGroupNodesToLiveCfgEventGroups -Instance $Instance -ModId $ModId
    try {
        $normalized = Normalize-UGSMDayZModContributions -Instance $Instance -Write
        $result | Add-Member -NotePropertyName LedgerEntryCount -NotePropertyValue @($normalized.Entries).Count -Force
        $result | Add-Member -NotePropertyName LedgerDuplicateEntriesRemoved -NotePropertyValue ([int]$normalized.LedgerStats.RemovedDuplicateEntries) -Force
    }
    catch { }

    return $result
}

function Invoke-UGSMDayZPreviewRemovedModCfgEventGroupsCleanup {
    [CmdletBinding()]
    param([Parameter(Mandatory)][object]$Instance)

    [void](Normalize-UGSMDayZModContributions -Instance $Instance -Write)
    return (New-UGSMDayZRemovedModCfgEventGroupsCleanupPlan -Instance $Instance -WritePlan)
}

function Invoke-UGSMDayZApplyRemovedModCfgEventGroupsCleanup {
    [CmdletBinding()]
    param([Parameter(Mandatory)][object]$Instance)

    [void](Normalize-UGSMDayZModContributions -Instance $Instance -Write)
    $result = Remove-UGSMDayZRemovedModCfgEventGroupNodes -Instance $Instance
    [void](Normalize-UGSMDayZModContributions -Instance $Instance -Write)
    return $result
}


# ============================================================
# v3 logging/safety overrides for DayZ file helpers
# Keep this section at the bottom so these wrappers are the active public entry points.
# ============================================================

function Test-UGSMDayZFilesVerboseLogging {
    [CmdletBinding()]
    param()

    if (Get-Variable -Name 'UGSM_EnableVerboseDayZFilesLogging' -Scope Script -ErrorAction SilentlyContinue) {
        try { if ([bool]$script:UGSM_EnableVerboseDayZFilesLogging) { return $true } } catch { }
    }

    $envValue = [string]$env:UGSM_VERBOSE_DAYZ_FILES
    return ($envValue -match '^(1|true|yes|on)$')
}

function ConvertTo-UGSMDayZFilesSafeLogText {
    [CmdletBinding()]
    param([AllowNull()][object]$Value)

    if ($null -eq $Value) { return '' }

    $text = [string]$Value
    if ([string]::IsNullOrEmpty($text)) { return $text }

    try {
        $text = [regex]::Replace($text, '(?i)(https://discord(?:app)?\.com/api/webhooks/)[^\s\"''<>]+', '$1<redacted>')
        $text = [regex]::Replace($text, '(?i)((?:webhook|webhookurl|discordwebhook|discordwebhookurl)\s*[:=]\s*)[^;\s\"''<>]+', '$1<redacted>')
        $text = [regex]::Replace($text, '(?i)((?:password|adminpassword|serverpassword|rconpassword|steamcmdpassword|steampassword|steampass|token|login_token|logintoken|gslt|apikey|api_key|secret)\s*[:=]\s*)[^;\s\"''<>]+', '$1<redacted>')
        $text = [regex]::Replace($text, '(?i)((?:password|adminpassword|serverpassword|rconpassword|steamcmdpassword|steampassword|steampass|token|login_token|logintoken|gslt|apikey|api_key|secret)\s*=\s*["''])(.*?)(["''])', '$1<redacted>$3')
        $text = [regex]::Replace($text, '(?i)C:\Users\[^\\;:"''<>\r\n]+', '%USERPROFILE%')
    }
    catch { }

    return $text
}

function Write-UGSMDayZFilesLog {
    [CmdletBinding()]
    param(
        [ValidateSet('TRACE','DEBUG','INFO','WARN','ERROR','FATAL')]
        [string]$Level = 'INFO',
        [Parameter(Mandatory)][string]$Message,
        [System.Exception]$Exception = $null,
        [switch]$VerboseOnly
    )

    if ($VerboseOnly -and -not (Test-UGSMDayZFilesVerboseLogging)) { return }

    $safeMessage = ConvertTo-UGSMDayZFilesSafeLogText $Message
    $safeException = $Exception

    if (Get-Command -Name Write-UGSMLog -ErrorAction SilentlyContinue) {
        try {
            if ($null -ne $Exception) {
                Write-UGSMLog -Level $Level -Category 'DayZFiles' -Message $safeMessage -Exception $safeException
            }
            else {
                Write-UGSMLog -Level $Level -Category 'DayZFiles' -Message $safeMessage
            }
            return
        }
        catch { }
    }

    try {
        $line = '[{0}] [{1}] [DayZFiles] {2}' -f (Get-Date).ToString('yyyy-MM-dd HH:mm:ss.fff'), $Level, $safeMessage
        Write-Host $line
        if ($null -ne $Exception) { Write-Host ('Exception: {0}' -f (ConvertTo-UGSMDayZFilesSafeLogText $Exception.Message)) }
    }
    catch { }
}

function Get-UGSMDayZFilesValue {
    [CmdletBinding()]
    param(
        [AllowNull()][object]$Object,
        [Parameter(Mandatory)][string]$Name,
        [object]$Default = $null
    )

    if ($null -eq $Object) { return $Default }

    try {
        if ($Object -is [System.Collections.IDictionary]) {
            if ($Object.Contains($Name)) { return $Object[$Name] }
            return $Default
        }

        $property = $Object.PSObject.Properties[$Name]
        if ($null -ne $property) { return $property.Value }
    }
    catch { }

    return $Default
}

function Get-UGSMDayZFilesInstanceLabel {
    [CmdletBinding()]
    param([AllowNull()][object]$Instance)

    $id = [string](Get-UGSMDayZFilesValue -Object $Instance -Name 'Id' -Default '')
    $name = [string](Get-UGSMDayZFilesValue -Object $Instance -Name 'Name' -Default '')
    if ([string]::IsNullOrWhiteSpace($id)) { $id = $name }
    if ([string]::IsNullOrWhiteSpace($name)) { $name = $id }
    if ([string]::IsNullOrWhiteSpace($id) -and [string]::IsNullOrWhiteSpace($name)) { return 'unknown-instance' }
    if ($id -eq $name -or [string]::IsNullOrWhiteSpace($name)) { return $id }
    return ('{0}/{1}' -f $id, $name)
}

function Get-UGSMDayZFilesResultSummary {
    [CmdletBinding()]
    param([AllowNull()][object]$Result)

    if ($null -eq $Result) { return 'Result=None' }

    $parts = New-Object System.Collections.Generic.List[string]
    foreach ($name in @(
        'AddedCount','RemovedCount','MergedExistingCount','ReconciledOwnershipCount','SkippedCount',
        'AddCount','RemoveCount','SkipCount','ModTypeFileCount','ModSpawnableTypeFileCount','ModEventFileCount',
        'ModEventSpawnFileCount','ModCfgEventGroupFileCount','TotalIncomingTypeCount','TotalIncomingSpawnableTypeCount',
        'TotalIncomingEventCount','TotalIncomingEventSpawnCount','TotalIncomingCfgEventGroupCount','WarningCount',
        'LedgerEntryCount','LedgerDuplicateEntriesRemoved'
    )) {
        $value = Get-UGSMDayZFilesValue -Object $Result -Name $name -Default $null
        if ($null -ne $value -and [string]$value -ne '') { [void]$parts.Add(('{0}={1}' -f $name, $value)) }
    }

    if ($parts.Count -eq 0) { return 'Result=OK' }
    return ($parts -join '; ')
}

function Invoke-UGSMDayZFilesLoggedOperation {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Operation,
        [AllowNull()][object]$Instance,
        [string]$ModId = '',
        [ValidateSet('TRACE','DEBUG','INFO','WARN','ERROR','FATAL')]
        [string]$StartLevel = 'INFO',
        [ValidateSet('TRACE','DEBUG','INFO','WARN','ERROR','FATAL')]
        [string]$FinishLevel = 'INFO',
        [switch]$VerboseOnly,
        [Parameter(Mandatory)][scriptblock]$ScriptBlock
    )

    $instanceLabel = Get-UGSMDayZFilesInstanceLabel -Instance $Instance
    $modText = if ([string]::IsNullOrWhiteSpace($ModId)) { '' } else { '; ModId={0}' -f $ModId }
    $sw = [System.Diagnostics.Stopwatch]::StartNew()

    Write-UGSMDayZFilesLog -Level $StartLevel -VerboseOnly:$VerboseOnly -Message ('{0} started. Instance={1}{2}' -f $Operation, $instanceLabel, $modText)

    try {
        $result = & $ScriptBlock
        $sw.Stop()
        $summary = Get-UGSMDayZFilesResultSummary -Result $result
        Write-UGSMDayZFilesLog -Level $FinishLevel -VerboseOnly:$VerboseOnly -Message ('{0} finished. Instance={1}{2}; DurationMs={3}; {4}' -f $Operation, $instanceLabel, $modText, [int]$sw.ElapsedMilliseconds, $summary)
        return $result
    }
    catch {
        $sw.Stop()
        Write-UGSMDayZFilesLog -Level 'ERROR' -Message ('{0} failed. Instance={1}{2}; DurationMs={3}' -f $Operation, $instanceLabel, $modText, [int]$sw.ElapsedMilliseconds) -Exception $_.Exception
        throw
    }
}

function Save-UGSMDayZInstanceJson {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$Instance
    )

    return (Invoke-UGSMDayZFilesLoggedOperation -Operation 'Save DayZ instance JSON' -Instance $Instance -VerboseOnly -StartLevel 'DEBUG' -FinishLevel 'DEBUG' -ScriptBlock {
        $paths = Initialize-UGSMDayZInstanceStorage -Instance $Instance -MigrateLegacyJson
        $json = $Instance | ConvertTo-Json -Depth 32
        Set-Content -LiteralPath $paths.InstanceJsonPath -Value $json -Encoding UTF8 -ErrorAction Stop
        [pscustomobject]@{ Path = [string]$paths.InstanceJsonPath }
    }).Path
}

function Invoke-UGSMDayZInstanceIndexScan {
    [CmdletBinding()]
    param([Parameter(Mandatory)][object]$Instance)

    return (Invoke-UGSMDayZFilesLoggedOperation -Operation 'DayZ instance index scan' -Instance $Instance -StartLevel 'INFO' -FinishLevel 'INFO' -ScriptBlock {
        Invoke-UGSMDayZInstanceIndexScan_CoreV3 -Instance $Instance
    })
}

function Invoke-UGSMDayZPreviewSelectedModTypesMerge {
    [CmdletBinding()]
    param([Parameter(Mandatory)][object]$Instance,[Parameter(Mandatory)][string]$ModId)
    return (Invoke-UGSMDayZFilesLoggedOperation -Operation 'Preview selected mod types.xml merge' -Instance $Instance -ModId $ModId -StartLevel 'DEBUG' -FinishLevel 'DEBUG' -ScriptBlock { New-UGSMDayZTypesMergePlan -Instance $Instance -ModId $ModId -WritePlan })
}

function Invoke-UGSMDayZApplySelectedModTypesMerge {
    [CmdletBinding()]
    param([Parameter(Mandatory)][object]$Instance,[Parameter(Mandatory)][string]$ModId)
    return (Invoke-UGSMDayZFilesLoggedOperation -Operation 'Apply selected mod types.xml merge' -Instance $Instance -ModId $ModId -ScriptBlock {
        $result = Add-UGSMDayZTypeNodesToLiveTypes -Instance $Instance -ModId $ModId
        try { [void](Format-UGSMDayZLiveTypesXml -Instance $Instance -Backup) }
        catch { Write-UGSMDayZFilesLog -Level 'WARN' -Message ('types.xml formatting after merge failed. Instance={0}; ModId={1}' -f (Get-UGSMDayZFilesInstanceLabel -Instance $Instance), $ModId) -Exception $_.Exception }
        try {
            $normalized = Normalize-UGSMDayZModContributions -Instance $Instance -Write
            $result | Add-Member -NotePropertyName LedgerEntryCount -NotePropertyValue @($normalized.Entries).Count -Force
            $result | Add-Member -NotePropertyName LedgerDuplicateEntriesRemoved -NotePropertyValue ([int]$normalized.LedgerStats.RemovedDuplicateEntries) -Force
        }
        catch { Write-UGSMDayZFilesLog -Level 'WARN' -Message ('Contribution ledger normalization after types.xml merge failed. Instance={0}; ModId={1}' -f (Get-UGSMDayZFilesInstanceLabel -Instance $Instance), $ModId) -Exception $_.Exception }
        $result
    })
}

function Invoke-UGSMDayZPreviewRemovedModTypesCleanup {
    [CmdletBinding()]
    param([Parameter(Mandatory)][object]$Instance)
    return (Invoke-UGSMDayZFilesLoggedOperation -Operation 'Preview removed mod types.xml cleanup' -Instance $Instance -StartLevel 'DEBUG' -FinishLevel 'DEBUG' -ScriptBlock {
        [void](Normalize-UGSMDayZModContributions -Instance $Instance -Write)
        New-UGSMDayZRemovedModTypesCleanupPlan -Instance $Instance -WritePlan
    })
}

function Invoke-UGSMDayZApplyRemovedModTypesCleanup {
    [CmdletBinding()]
    param([Parameter(Mandatory)][object]$Instance)
    return (Invoke-UGSMDayZFilesLoggedOperation -Operation 'Apply removed mod types.xml cleanup' -Instance $Instance -ScriptBlock {
        [void](Normalize-UGSMDayZModContributions -Instance $Instance -Write)
        $result = Remove-UGSMDayZRemovedModTypeNodes -Instance $Instance
        [void](Normalize-UGSMDayZModContributions -Instance $Instance -Write)
        $result
    })
}

function Invoke-UGSMDayZNormalizeTypeContributionLedger {
    [CmdletBinding()]
    param([Parameter(Mandatory)][object]$Instance)
    return (Invoke-UGSMDayZFilesLoggedOperation -Operation 'Normalize DayZ type contribution ledger' -Instance $Instance -StartLevel 'DEBUG' -FinishLevel 'DEBUG' -ScriptBlock { Normalize-UGSMDayZModContributions -Instance $Instance -Write })
}

function Invoke-UGSMDayZPreviewSelectedModSpawnableTypesMerge {
    [CmdletBinding()]
    param([Parameter(Mandatory)][object]$Instance,[Parameter(Mandatory)][string]$ModId)
    return (Invoke-UGSMDayZFilesLoggedOperation -Operation 'Preview selected mod cfgspawnabletypes.xml merge' -Instance $Instance -ModId $ModId -StartLevel 'DEBUG' -FinishLevel 'DEBUG' -ScriptBlock { New-UGSMDayZSpawnableTypesMergePlan -Instance $Instance -ModId $ModId -WritePlan })
}

function Invoke-UGSMDayZApplySelectedModSpawnableTypesMerge {
    [CmdletBinding()]
    param([Parameter(Mandatory)][object]$Instance,[Parameter(Mandatory)][string]$ModId)
    return (Invoke-UGSMDayZFilesLoggedOperation -Operation 'Apply selected mod cfgspawnabletypes.xml merge' -Instance $Instance -ModId $ModId -ScriptBlock {
        $result = Add-UGSMDayZSpawnableTypeNodesToLiveSpawnableTypes -Instance $Instance -ModId $ModId
        try {
            $normalized = Normalize-UGSMDayZModContributions -Instance $Instance -Write
            $result | Add-Member -NotePropertyName LedgerEntryCount -NotePropertyValue @($normalized.Entries).Count -Force
            $result | Add-Member -NotePropertyName LedgerDuplicateEntriesRemoved -NotePropertyValue ([int]$normalized.LedgerStats.RemovedDuplicateEntries) -Force
        }
        catch { Write-UGSMDayZFilesLog -Level 'WARN' -Message ('Contribution ledger normalization after cfgspawnabletypes.xml merge failed. Instance={0}; ModId={1}' -f (Get-UGSMDayZFilesInstanceLabel -Instance $Instance), $ModId) -Exception $_.Exception }
        $result
    })
}

function Invoke-UGSMDayZPreviewRemovedModSpawnableTypesCleanup {
    [CmdletBinding()]
    param([Parameter(Mandatory)][object]$Instance)
    return (Invoke-UGSMDayZFilesLoggedOperation -Operation 'Preview removed mod cfgspawnabletypes.xml cleanup' -Instance $Instance -StartLevel 'DEBUG' -FinishLevel 'DEBUG' -ScriptBlock {
        [void](Normalize-UGSMDayZModContributions -Instance $Instance -Write)
        New-UGSMDayZRemovedModSpawnableTypesCleanupPlan -Instance $Instance -WritePlan
    })
}

function Invoke-UGSMDayZApplyRemovedModSpawnableTypesCleanup {
    [CmdletBinding()]
    param([Parameter(Mandatory)][object]$Instance)
    return (Invoke-UGSMDayZFilesLoggedOperation -Operation 'Apply removed mod cfgspawnabletypes.xml cleanup' -Instance $Instance -ScriptBlock {
        [void](Normalize-UGSMDayZModContributions -Instance $Instance -Write)
        $result = Remove-UGSMDayZRemovedModSpawnableTypeNodes -Instance $Instance
        [void](Normalize-UGSMDayZModContributions -Instance $Instance -Write)
        $result
    })
}

function Invoke-UGSMDayZPreviewSelectedModEventsMerge {
    [CmdletBinding()]
    param([Parameter(Mandatory)][object]$Instance,[Parameter(Mandatory)][string]$ModId)
    return (Invoke-UGSMDayZFilesLoggedOperation -Operation 'Preview selected mod events.xml merge' -Instance $Instance -ModId $ModId -StartLevel 'DEBUG' -FinishLevel 'DEBUG' -ScriptBlock { New-UGSMDayZEventsMergePlan -Instance $Instance -ModId $ModId -WritePlan })
}

function Invoke-UGSMDayZApplySelectedModEventsMerge {
    [CmdletBinding()]
    param([Parameter(Mandatory)][object]$Instance,[Parameter(Mandatory)][string]$ModId)
    return (Invoke-UGSMDayZFilesLoggedOperation -Operation 'Apply selected mod events.xml merge' -Instance $Instance -ModId $ModId -ScriptBlock {
        $result = Add-UGSMDayZEventNodesToLiveEvents -Instance $Instance -ModId $ModId
        try {
            $normalized = Normalize-UGSMDayZModContributions -Instance $Instance -Write
            $result | Add-Member -NotePropertyName LedgerEntryCount -NotePropertyValue @($normalized.Entries).Count -Force
            $result | Add-Member -NotePropertyName LedgerDuplicateEntriesRemoved -NotePropertyValue ([int]$normalized.LedgerStats.RemovedDuplicateEntries) -Force
        }
        catch { Write-UGSMDayZFilesLog -Level 'WARN' -Message ('Contribution ledger normalization after events.xml merge failed. Instance={0}; ModId={1}' -f (Get-UGSMDayZFilesInstanceLabel -Instance $Instance), $ModId) -Exception $_.Exception }
        $result
    })
}

function Invoke-UGSMDayZPreviewRemovedModEventsCleanup {
    [CmdletBinding()]
    param([Parameter(Mandatory)][object]$Instance)
    return (Invoke-UGSMDayZFilesLoggedOperation -Operation 'Preview removed mod events.xml cleanup' -Instance $Instance -StartLevel 'DEBUG' -FinishLevel 'DEBUG' -ScriptBlock {
        [void](Normalize-UGSMDayZModContributions -Instance $Instance -Write)
        New-UGSMDayZRemovedModEventsCleanupPlan -Instance $Instance -WritePlan
    })
}

function Invoke-UGSMDayZApplyRemovedModEventsCleanup {
    [CmdletBinding()]
    param([Parameter(Mandatory)][object]$Instance)
    return (Invoke-UGSMDayZFilesLoggedOperation -Operation 'Apply removed mod events.xml cleanup' -Instance $Instance -ScriptBlock {
        [void](Normalize-UGSMDayZModContributions -Instance $Instance -Write)
        $result = Remove-UGSMDayZRemovedModEventNodes -Instance $Instance
        [void](Normalize-UGSMDayZModContributions -Instance $Instance -Write)
        $result
    })
}

function Invoke-UGSMDayZPreviewSelectedModEventSpawnsMerge {
    [CmdletBinding()]
    param([Parameter(Mandatory)][object]$Instance,[Parameter(Mandatory)][string]$ModId)
    return (Invoke-UGSMDayZFilesLoggedOperation -Operation 'Preview selected mod cfgeventspawns.xml merge' -Instance $Instance -ModId $ModId -StartLevel 'DEBUG' -FinishLevel 'DEBUG' -ScriptBlock { New-UGSMDayZEventSpawnsMergePlan -Instance $Instance -ModId $ModId -WritePlan })
}

function Invoke-UGSMDayZApplySelectedModEventSpawnsMerge {
    [CmdletBinding()]
    param([Parameter(Mandatory)][object]$Instance,[Parameter(Mandatory)][string]$ModId)
    return (Invoke-UGSMDayZFilesLoggedOperation -Operation 'Apply selected mod cfgeventspawns.xml merge' -Instance $Instance -ModId $ModId -ScriptBlock {
        $result = Add-UGSMDayZEventSpawnNodesToLiveEventSpawns -Instance $Instance -ModId $ModId
        try {
            $normalized = Normalize-UGSMDayZModContributions -Instance $Instance -Write
            $result | Add-Member -NotePropertyName LedgerEntryCount -NotePropertyValue @($normalized.Entries).Count -Force
            $result | Add-Member -NotePropertyName LedgerDuplicateEntriesRemoved -NotePropertyValue ([int]$normalized.LedgerStats.RemovedDuplicateEntries) -Force
        }
        catch { Write-UGSMDayZFilesLog -Level 'WARN' -Message ('Contribution ledger normalization after cfgeventspawns.xml merge failed. Instance={0}; ModId={1}' -f (Get-UGSMDayZFilesInstanceLabel -Instance $Instance), $ModId) -Exception $_.Exception }
        $result
    })
}

function Invoke-UGSMDayZPreviewRemovedModEventSpawnsCleanup {
    [CmdletBinding()]
    param([Parameter(Mandatory)][object]$Instance)
    return (Invoke-UGSMDayZFilesLoggedOperation -Operation 'Preview removed mod cfgeventspawns.xml cleanup' -Instance $Instance -StartLevel 'DEBUG' -FinishLevel 'DEBUG' -ScriptBlock {
        [void](Normalize-UGSMDayZModContributions -Instance $Instance -Write)
        New-UGSMDayZRemovedModEventSpawnsCleanupPlan -Instance $Instance -WritePlan
    })
}

function Invoke-UGSMDayZApplyRemovedModEventSpawnsCleanup {
    [CmdletBinding()]
    param([Parameter(Mandatory)][object]$Instance)
    return (Invoke-UGSMDayZFilesLoggedOperation -Operation 'Apply removed mod cfgeventspawns.xml cleanup' -Instance $Instance -ScriptBlock {
        [void](Normalize-UGSMDayZModContributions -Instance $Instance -Write)
        $result = Remove-UGSMDayZRemovedModEventSpawnNodes -Instance $Instance
        [void](Normalize-UGSMDayZModContributions -Instance $Instance -Write)
        $result
    })
}

function Invoke-UGSMDayZPreviewSelectedModCfgEventGroupsMerge {
    [CmdletBinding()]
    param([Parameter(Mandatory)][object]$Instance,[Parameter(Mandatory)][string]$ModId)
    return (Invoke-UGSMDayZFilesLoggedOperation -Operation 'Preview selected mod cfgeventgroups.xml merge' -Instance $Instance -ModId $ModId -StartLevel 'DEBUG' -FinishLevel 'DEBUG' -ScriptBlock { New-UGSMDayZCfgEventGroupsMergePlan -Instance $Instance -ModId $ModId -WritePlan })
}

function Invoke-UGSMDayZApplySelectedModCfgEventGroupsMerge {
    [CmdletBinding()]
    param([Parameter(Mandatory)][object]$Instance,[Parameter(Mandatory)][string]$ModId)
    return (Invoke-UGSMDayZFilesLoggedOperation -Operation 'Apply selected mod cfgeventgroups.xml merge' -Instance $Instance -ModId $ModId -ScriptBlock {
        $result = Add-UGSMDayZCfgEventGroupNodesToLiveCfgEventGroups -Instance $Instance -ModId $ModId
        try {
            $normalized = Normalize-UGSMDayZModContributions -Instance $Instance -Write
            $result | Add-Member -NotePropertyName LedgerEntryCount -NotePropertyValue @($normalized.Entries).Count -Force
            $result | Add-Member -NotePropertyName LedgerDuplicateEntriesRemoved -NotePropertyValue ([int]$normalized.LedgerStats.RemovedDuplicateEntries) -Force
        }
        catch { Write-UGSMDayZFilesLog -Level 'WARN' -Message ('Contribution ledger normalization after cfgeventgroups.xml merge failed. Instance={0}; ModId={1}' -f (Get-UGSMDayZFilesInstanceLabel -Instance $Instance), $ModId) -Exception $_.Exception }
        $result
    })
}

function Invoke-UGSMDayZPreviewRemovedModCfgEventGroupsCleanup {
    [CmdletBinding()]
    param([Parameter(Mandatory)][object]$Instance)
    return (Invoke-UGSMDayZFilesLoggedOperation -Operation 'Preview removed mod cfgeventgroups.xml cleanup' -Instance $Instance -StartLevel 'DEBUG' -FinishLevel 'DEBUG' -ScriptBlock {
        [void](Normalize-UGSMDayZModContributions -Instance $Instance -Write)
        New-UGSMDayZRemovedModCfgEventGroupsCleanupPlan -Instance $Instance -WritePlan
    })
}

function Invoke-UGSMDayZApplyRemovedModCfgEventGroupsCleanup {
    [CmdletBinding()]
    param([Parameter(Mandatory)][object]$Instance)
    return (Invoke-UGSMDayZFilesLoggedOperation -Operation 'Apply removed mod cfgeventgroups.xml cleanup' -Instance $Instance -ScriptBlock {
        [void](Normalize-UGSMDayZModContributions -Instance $Instance -Write)
        $result = Remove-UGSMDayZRemovedModCfgEventGroupNodes -Instance $Instance
        [void](Normalize-UGSMDayZModContributions -Instance $Instance -Write)
        $result
    })
}
