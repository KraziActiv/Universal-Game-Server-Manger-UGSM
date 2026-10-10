# UGSM Enshrouded Native Module
# Native Enshrouded support with Custom bridge profile pickup, settings editor,
# Discord notifications, and start/stop handlers.

function ConvertTo-UGSMGameEnshroudedSafeLogText {
    [CmdletBinding()]
    param([AllowNull()][object]$Value)

    if ($null -eq $Value) { return '' }

    $text = [string]$Value
    if ([string]::IsNullOrWhiteSpace($text)) { return $text }

    try {
        $local = [Environment]::GetFolderPath('LocalApplicationData')
        if (-not [string]::IsNullOrWhiteSpace($local)) {
            $text = $text.Replace($local, '%LOCALAPPDATA%')
        }
    } catch {}

    try {
        $profile = [Environment]::GetFolderPath('UserProfile')
        if (-not [string]::IsNullOrWhiteSpace($profile)) {
            $text = $text.Replace($profile, '%USERPROFILE%')
        }
    } catch {}

    try {
        $profileBase = Get-UGSMGameEnshroudedProfileBaseRoot
        if (-not [string]::IsNullOrWhiteSpace($profileBase)) {
            $text = $text.Replace($profileBase, '%UGSM_PROFILES%')
        }
    } catch {}

    try {
        $settings = $null
        if (Get-Command -Name Get-UGSMGlobalSettings -ErrorAction SilentlyContinue) {
            $settings = Get-UGSMGlobalSettings -CreateIfMissing
        }

        $steamRoots = New-Object System.Collections.Generic.List[string]
        if ($settings) {
            foreach ($prop in @('SteamRoot','SteamCmdRoot','SteamInstallRoot','SteamLibraryRoot','InstallRoot','InstallPath')) {
                if ($settings.PSObject.Properties[$prop] -and -not [string]::IsNullOrWhiteSpace([string]$settings.$prop)) {
                    [void]$steamRoots.Add([string]$settings.$prop)
                }
            }
        }

        foreach ($root in @($steamRoots | Sort-Object Length -Descending -Unique)) {
            if ([string]::IsNullOrWhiteSpace($root)) { continue }
            $normalized = $root.TrimEnd('\','/')
            if ([string]::IsNullOrWhiteSpace($normalized)) { continue }

            $text = $text.Replace($normalized, '%UGSM_STEAM%')
            $text = $text.Replace(($normalized + '\steamapps\common'), '%UGSM_STEAM%\steamapps\common')
        }
    } catch {}

    # Defense-in-depth secret redaction. Enshrouded user group passwords are editable
    # by UGSM, but should never be written to diagnostics.
    $text = [regex]::Replace($text, 'https://(?:canary\.|ptb\.)?discord(?:app)?\.com/api/webhooks/[^\s''"]+', '<discord-webhook-redacted>', 'IgnoreCase')
    $text = [regex]::Replace($text, '(?i)(password|pass|token|gslt|api[_-]?key|secret|webhook)\s*[:=]\s*[^;\s,}]+', '$1=<redacted>')
    $text = [regex]::Replace($text, '(?i)"(password|pass|token|gslt|api[_-]?key|secret|webhook)"\s*:\s*"[^"]*"', '"$1":"<redacted>"')
    $text = [regex]::Replace($text, '(?i)(\+login\s+)(?!anonymous\b)\S+(\s+)\S+', '$1<redacted>$2<redacted>')

    return $text
}

function Write-UGSMGameEnshroudedLog {
    [CmdletBinding()]
    param(
        [ValidateSet('TRACE','DEBUG','INFO','WARN','ERROR')][string]$Level = 'INFO',
        [Parameter(Mandatory)][string]$Message,
        [AllowNull()][System.Exception]$Exception
    )
    if (($Level -in @('TRACE','DEBUG')) -and [string]::IsNullOrWhiteSpace($env:UGSM_VERBOSE_ENSHROUDED)) { return }

    $safeMessage = ConvertTo-UGSMGameEnshroudedSafeLogText $Message
    if ($Exception) {
        $safeException = ConvertTo-UGSMGameEnshroudedSafeLogText $Exception.Message
        if (-not [string]::IsNullOrWhiteSpace($safeException)) {
            $safeMessage = ('{0} Error={1}' -f $safeMessage,$safeException)
        }
    }

    if (Get-Command -Name Write-UGSMLog -ErrorAction SilentlyContinue) {
        Write-UGSMLog -Level $Level -Category 'Enshrouded' -Message $safeMessage
        return
    }

    try { Write-Host ('[{0}] [Enshrouded] {1}' -f $Level,$safeMessage) } catch {}
}

function Get-UGSMGameEnshroudedAppDataRoot { if (Get-Command -Name Get-UGSMAppDataRoot -ErrorAction SilentlyContinue) { try { return [string](Get-UGSMAppDataRoot) } catch {} }; return (Join-Path $env:LOCALAPPDATA 'UGSM') }
function Get-UGSMGameEnshroudedProfileBaseRoot {
    $settings=$null
    if (Get-Command -Name Get-UGSMGlobalSettings -ErrorAction SilentlyContinue) { try { $settings=Get-UGSMGlobalSettings -CreateIfMissing } catch { $settings=$null } }
    if ($settings -and $settings.PSObject.Properties['ProfileBaseRoot'] -and -not [string]::IsNullOrWhiteSpace([string]$settings.ProfileBaseRoot)) { return [string]$settings.ProfileBaseRoot }
    if (Get-Command -Name Get-UGSMDefaultInstanceProfilePath -ErrorAction SilentlyContinue) { try { $probe=Get-UGSMDefaultInstanceProfilePath -GameId 'Enshrouded' -Name '_probe_'; if (-not [string]::IsNullOrWhiteSpace([string]$probe)) { return (Split-Path -Parent (Split-Path -Parent $probe)) } } catch {} }
    return (Join-Path (Get-UGSMGameEnshroudedAppDataRoot) 'Profiles')
}
function Get-UGSMGameEnshroudedGameProfileRoot { return (Join-Path (Get-UGSMGameEnshroudedProfileBaseRoot) 'Enshrouded') }
function Get-UGSMGameEnshroudedProfileName { param([AllowNull()][object]$Instance) foreach($n in @('Name','Id','ProfileName','InstanceId')){ if($Instance -and $Instance.PSObject.Properties[$n] -and -not [string]::IsNullOrWhiteSpace([string]$Instance.$n)){ return ([string]$Instance.$n -replace '[\\/:*?"<>|]','_') } }; return 'Enshrouded1' }
function Get-UGSMGameEnshroudedProfileRoot { param([Parameter(Mandatory)][object]$Instance) if($Instance -and $Instance.PSObject.Properties['ProfilePath'] -and -not [string]::IsNullOrWhiteSpace([string]$Instance.ProfilePath)){ return [string]$Instance.ProfilePath }; return (Join-Path (Get-UGSMGameEnshroudedGameProfileRoot) (Get-UGSMGameEnshroudedProfileName -Instance $Instance)) }
function Get-UGSMGameEnshroudedBridgePath { param([Parameter(Mandatory)][object]$Instance) return (Join-Path (Get-UGSMGameEnshroudedProfileRoot -Instance $Instance) 'UGSM_CustomProfile.json') }

# Removed stale Enshrouded test-stub duplicate function block during native cleanup.
function Get-UGSMGameEnshroudedSteamRootCandidates {
    [CmdletBinding()]
    param()
    $items = New-Object System.Collections.Generic.List[string]
    $seen = @{}
    function Add-Candidate([AllowNull()][string]$PathValue) {
        if ([string]::IsNullOrWhiteSpace($PathValue)) { return }
        $p = [string]$PathValue
        foreach ($suffix in @('', 'steamapps\common\Enshrouded', 'common\Enshrouded', 'Enshrouded')) {
            $candidate = if ([string]::IsNullOrWhiteSpace($suffix)) { $p } else { Join-Path $p $suffix }
            try { $full = [System.IO.Path]::GetFullPath($candidate) } catch { $full = $candidate }
            $k = $full.ToLowerInvariant()
            if (-not $seen.ContainsKey($k)) { $seen[$k] = $true; [void]$items.Add($full) }
        }
    }
    $settings = $null
    if (Get-Command -Name Get-UGSMGlobalSettings -ErrorAction SilentlyContinue) { try { $settings = Get-UGSMGlobalSettings -CreateIfMissing } catch { $settings = $null } }
    if ($settings) {
        foreach ($prop in @('InstallPath','InstallRoot','SteamLibraryRoot','SteamRoot','SteamCmdRoot','SteamInstallRoot')) {
            if ($settings.PSObject.Properties[$prop]) { Add-Candidate ([string]$settings.$prop) }
        }
    }
    return @($items)
}

function Get-UGSMGameEnshroudedBridgeProfiles {
    [CmdletBinding()]
    param()

    # Use a plain PowerShell array here.  The first bridge test used a generic
    # List plus inline scriptblock-style values inside hashtables; on the user's
    # runtime that threw "Argument types do not match" while the module registered.
    $result = @()
    $root = Get-UGSMGameEnshroudedGameProfileRoot

    Write-UGSMGameEnshroudedLog -Level 'INFO' -Message ('Scanning Enshrouded bridge profiles. Root={0}' -f $root)

    if (-not (Test-Path -LiteralPath $root -PathType Container)) {
        Write-UGSMGameEnshroudedLog -Level 'INFO' -Message ('Enshrouded bridge profile root does not exist. Root={0}' -f $root)
        return @()
    }

    $dirs = @(Get-ChildItem -LiteralPath $root -Directory -ErrorAction SilentlyContinue)
    foreach ($dir in $dirs) {
        $profileDir = [string]$dir.FullName
        foreach ($fileName in @('UGSM_CustomProfile.json','custom.instance.json')) {
            $path = Join-Path $profileDir $fileName
            if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { continue }

            try {
                $data = Get-Content -LiteralPath $path -Raw | ConvertFrom-Json

                $target = ''
                if ($data -and $data.PSObject.Properties['TargetGameKey']) { $target = [string]$data.TargetGameKey }

                $nativeReady = $false
                if ($data -and $data.PSObject.Properties['NativeImportReady']) {
                    try { $nativeReady = [System.Convert]::ToBoolean($data.NativeImportReady) } catch { $nativeReady = $false }
                }

                if ($target -ne 'Enshrouded') {
                    Write-UGSMGameEnshroudedLog -Level 'INFO' -Message ('Skipping bridge profile because TargetGameKey is not Enshrouded. Path={0}; TargetGameKey={1}' -f $path,$target)
                    continue
                }
                if (-not $nativeReady) {
                    Write-UGSMGameEnshroudedLog -Level 'INFO' -Message ('Skipping bridge profile because NativeImportReady is false. Path={0}' -f $path)
                    continue
                }

                $name = Split-Path -Leaf $profileDir
                if ($data.PSObject.Properties['Name'] -and -not [string]::IsNullOrWhiteSpace([string]$data.Name)) { $name = [string]$data.Name }

                $installPath = ''
                if ($data.PSObject.Properties['InstallPath']) { $installPath = [string]$data.InstallPath }

                $serverExecutablePath = ''
                if ($data.PSObject.Properties['ServerExecutablePath']) { $serverExecutablePath = [string]$data.ServerExecutablePath }

                $exeRel = 'enshrouded_server.exe'
                if ($data.PSObject.Properties['ExecutableRelativePath'] -and -not [string]::IsNullOrWhiteSpace([string]$data.ExecutableRelativePath)) { $exeRel = [string]$data.ExecutableRelativePath }

                $startupArgs = ''
                if ($data.PSObject.Properties['StartupArguments']) { $startupArgs = [string]$data.StartupArguments }

                $migrationStatus = 'CustomBridge'
                if ($data.PSObject.Properties['MigrationStatus'] -and -not [string]::IsNullOrWhiteSpace([string]$data.MigrationStatus)) { $migrationStatus = [string]$data.MigrationStatus }

                $result += [pscustomobject]@{
                    Name=$name
                    GameId='Enshrouded'
                    SourceGameId='CUSTOM'
                    TargetGameKey='Enshrouded'
                    ProfilePath=$profileDir
                    BridgePath=$path
                    InstallPath=$installPath
                    ServerExecutablePath=$serverExecutablePath
                    ExecutableRelativePath=$exeRel
                    StartupArguments=$startupArgs
                    MigrationStatus=$migrationStatus
                    NativeImportReady=$nativeReady
                    Manifest=$data
                }

                Write-UGSMGameEnshroudedLog -Level 'INFO' -Message ('Detected Enshrouded bridge profile. Name={0}; Path={1}' -f $name,$path)
                break
            }
            catch {
                Write-UGSMGameEnshroudedLog -Level 'WARN' -Message ('Failed to read Enshrouded bridge profile: {0}' -f $path) -Exception $_.Exception
            }
        }
    }

    return @($result)
}

function ConvertTo-UGSMGameEnshroudedNativeInstance {
    [CmdletBinding()]
    param([Parameter(Mandatory)][object]$BridgeProfile)
    $name = [string]$BridgeProfile.Name
    if ([string]::IsNullOrWhiteSpace($name)) { $name = 'Enshrouded1' }
    $id = 'Enshrouded_' + ($name -replace '[^A-Za-z0-9_.-]', '_')
    return [pscustomobject]@{
        Id=$id
        Name=$name
        GameId='Enshrouded'
        Status='Stopped'
        InstallPath=[string]$BridgeProfile.InstallPath
        ProfilePath=[string]$BridgeProfile.ProfilePath
        SourceGameId='CUSTOM'
        SourceBridgePath=[string]$BridgeProfile.BridgePath
        TargetGameKey='Enshrouded'
        NativeImportReady=$true
        MigrationStatus='DetectedCustomBridge'
        ServerExecutablePath=[string]$BridgeProfile.ServerExecutablePath
        ExecutableRelativePath=if ([string]::IsNullOrWhiteSpace([string]$BridgeProfile.ExecutableRelativePath)) { 'enshrouded_server.exe' } else { [string]$BridgeProfile.ExecutableRelativePath }
        StartupArguments=[string]$BridgeProfile.StartupArguments
    }
}

function Import-UGSMGameEnshroudedBridgeProfilesIntoInstanceStore {
    [CmdletBinding()]
    param()

    $profiles = @(Get-UGSMGameEnshroudedBridgeProfiles)
    if ($profiles.Count -le 0) {
        Write-UGSMGameEnshroudedLog -Level 'INFO' -Message 'No Enshrouded Custom bridge profiles were found to import.'
        return [pscustomobject]@{ Imported=0; Profiles=@() }
    }

    $imported = 0
    $instances = @()
    foreach ($p in $profiles) {
        $instance = ConvertTo-UGSMGameEnshroudedNativeInstance -BridgeProfile $p
        $instances += $instance

        $saved = $false
        foreach ($commandName in @('Save-UGSMInstance','Update-UGSMInstance','Set-UGSMInstance')) {
            $cmd = Get-Command -Name $commandName -ErrorAction SilentlyContinue
            if (-not $cmd) { continue }
            try {
                $savedInstance = & $commandName -Instance $instance
                if ($savedInstance) { $instance = $savedInstance }
                $saved = $true
                break
            }
            catch {
                Write-UGSMGameEnshroudedLog -Level 'WARN' -Message ('Enshrouded bridge import save command failed. Command={0}; Name={1}' -f $commandName,$p.Name) -Exception $_.Exception
            }
        }

        if ($saved) {
            $imported++
            Write-UGSMGameEnshroudedLog -Level 'INFO' -Message ('Imported Enshrouded bridge profile into instance store. Name={0}; Id={1}' -f $instance.Name,$instance.Id)
        }
        else {
            Write-UGSMGameEnshroudedLog -Level 'WARN' -Message ('Could not import Enshrouded bridge profile because no instance save command succeeded. Name={0}' -f $p.Name)
        }
    }

    if ($imported -gt 0) {
        foreach ($commandName in @('Save-UGSMInstances','Save-UGSMInstanceStore')) {
            $cmd = Get-Command -Name $commandName -ErrorAction SilentlyContinue
            if (-not $cmd) { continue }
            try { & $commandName | Out-Null; break } catch {}
        }
    }

    return [pscustomobject]@{ Imported=$imported; Profiles=$instances }
}

function Initialize-UGSMGameEnshroudedProfile {
    [CmdletBinding(DefaultParameterSetName='ByInstance')]
    param(
        [Parameter(Mandatory,ParameterSetName='ByInstance')][object]$Instance,
        [Parameter(Mandatory,ParameterSetName='ByName')][string]$ProfileName,
        [Parameter(ParameterSetName='ByName')][string]$InstallPath,
        [switch]$Force,
        [int]$BootstrapSeconds=0
    )
    if ($PSCmdlet.ParameterSetName -eq 'ByName') { $Instance=[pscustomobject]@{ Name=$ProfileName; InstallPath=$InstallPath } }
    $root=Get-UGSMGameEnshroudedProfileRoot -Instance $Instance
    if(-not(Test-Path -LiteralPath $root -PathType Container)){ New-Item -ItemType Directory -Path $root -Force | Out-Null }
    $bridge=Get-UGSMGameEnshroudedBridgePath -Instance $Instance
    $state=[ordered]@{ GameId='Enshrouded'; ProfileRoot=$root; BridgePath=$bridge; BridgeExists=(Test-Path -LiteralPath $bridge -PathType Leaf); InitializedAtUtc=[DateTime]::UtcNow.ToString('o') }
    ($state|ConvertTo-Json -Depth 5)|Set-Content -LiteralPath (Join-Path $root 'UGSM_EnshroudedStub.json') -Encoding UTF8
    [pscustomobject]$state
}

function Resolve-UGSMGameEnshroudedInstall {
    [CmdletBinding()]
    param([string]$InstallPath,[AllowNull()][object]$Instance)
    $candidates = New-Object System.Collections.Generic.List[string]
    function Add-InstallCandidate([AllowNull()][string]$PathValue) { if (-not [string]::IsNullOrWhiteSpace($PathValue)) { [void]$candidates.Add([string]$PathValue) } }
    Add-InstallCandidate $InstallPath
    if ($Instance -and $Instance.PSObject.Properties['InstallPath']) { Add-InstallCandidate ([string]$Instance.InstallPath) }
    foreach ($p in @(Get-UGSMGameEnshroudedBridgeProfiles)) { Add-InstallCandidate ([string]$p.InstallPath) }
    foreach ($p in @(Get-UGSMGameEnshroudedSteamRootCandidates)) { Add-InstallCandidate $p }
    foreach ($candidate in $candidates) {
        if ([string]::IsNullOrWhiteSpace($candidate)) { continue }
        $candidateLeaf = Split-Path -Leaf $candidate
        $exeCandidates = @()
        if ($candidateLeaf -ieq 'enshrouded_server.exe') { $exeCandidates += $candidate }
        else {
            $exeCandidates += (Join-Path $candidate 'enshrouded_server.exe')
            $exeCandidates += (Join-Path $candidate 'enshrouded.exe')
        }
        foreach ($exe in $exeCandidates) {
            if (Test-Path -LiteralPath $exe -PathType Leaf) { return [pscustomobject]@{ InstallPath=(Split-Path -Parent $exe); ExePath=$exe; IsInstalled=$true } }
        }
    }
    $first = if ($candidates.Count -gt 0) { [string]$candidates[0] } else { '' }
    return [pscustomobject]@{ InstallPath=$first; ExePath=if([string]::IsNullOrWhiteSpace($first)){''}else{Join-Path $first 'enshrouded_server.exe'}; IsInstalled=$false }
}

function Test-UGSMGameEnshroudedInstall {
    param([string]$InstallPath,[AllowNull()][object]$Instance)
    $resolved = Resolve-UGSMGameEnshroudedInstall -InstallPath $InstallPath -Instance $Instance
    [pscustomobject]@{
        GameId='Enshrouded'
        IsInstalled=[bool]$resolved.IsInstalled
        IsValid=[bool]$resolved.IsInstalled
        NeedsRepair=$false
        InstallPath=[string]$resolved.InstallPath
        ExePath=[string]$resolved.ExePath
        Message=if($resolved.IsInstalled){'Enshrouded dedicated server executable found.'}else{'Expected enshrouded_server.exe was not found.'}
        MissingItems=if($resolved.IsInstalled){@()}else{@('enshrouded_server.exe')}
    }
}
function Test-UGSMGameEnshroudedInstance { param([Parameter(Mandatory)][object]$Instance) $root=Get-UGSMGameEnshroudedProfileRoot -Instance $Instance; $bridge=Get-UGSMGameEnshroudedBridgePath -Instance $Instance; [pscustomobject]@{ GameId='Enshrouded'; ProfileRoot=$root; ProfileExists=(Test-Path -LiteralPath $root -PathType Container); BridgePath=$bridge; BridgeExists=(Test-Path -LiteralPath $bridge -PathType Leaf); IsValid=(Test-Path -LiteralPath $bridge -PathType Leaf) } }

# ============================================================================
# Native Enshrouded settings editor pass 1
# Treats Profiles\Enshrouded\<ServerName> as the native owner.  Custom bridge
# marker files may remain in place, but the Enshrouded tab edits the native copy.
# ============================================================================

function Get-UGSMGameEnshroudedColor {
    param([AllowNull()][object]$Theme,[string]$Name,[System.Drawing.Color]$Fallback)
    if ($Theme) {
        foreach ($prop in @($Name, ('Color' + $Name), ('UGSM_Color' + $Name))) {
            if ($Theme.PSObject.Properties[$prop]) {
                try { return [System.Drawing.Color]$Theme.$prop } catch {}
            }
        }
    }
    return $Fallback
}

function Get-UGSMGameEnshroudedSettingsPath {
    param([Parameter(Mandatory)][object]$Instance)
    $root = Get-UGSMGameEnshroudedProfileRoot -Instance $Instance
    return (Join-Path $root 'enshrouded_server.json')
}

function New-UGSMGameEnshroudedDefaultServerJsonObject {
    $json = @'
{
  "name": "Enshrouded Server",
  "saveDirectory": "./savegame",
  "logDirectory": "./logs",
  "ip": "0.0.0.0",
  "queryPort": 15637,
  "slotCount": 16,
  "tags": [],
  "voiceChatMode": "Proximity",
  "enableVoiceChat": false,
  "enableTextChat": false,
  "gameSettingsPreset": "Default",
  "gameSettings": {
    "playerHealthFactor": 1,
    "playerManaFactor": 1,
    "playerStaminaFactor": 1,
    "playerBodyHeatFactor": 1,
    "playerDivingTimeFactor": 1,
    "enableDurability": true,
    "enableStarvingDebuff": false,
    "foodBuffDurationFactor": 1,
    "fromHungerToStarving": 600000000000,
    "shroudTimeFactor": 1,
    "tombstoneMode": "AddBackpackMaterials",
    "enableGliderTurbulences": true,
    "weatherFrequency": "Normal",
    "fishingDifficulty": "Normal",
    "miningDamageFactor": 1,
    "plantGrowthSpeedFactor": 1,
    "resourceDropStackAmountFactor": 1,
    "factoryProductionSpeedFactor": 1,
    "perkUpgradeRecyclingFactor": 0.5,
    "perkCostFactor": 1,
    "experienceCombatFactor": 1,
    "experienceMiningFactor": 1,
    "experienceExplorationQuestsFactor": 1,
    "randomSpawnerAmount": "Normal",
    "aggroPoolAmount": "Normal",
    "enemyDamageFactor": 1,
    "enemyHealthFactor": 1,
    "enemyStaminaFactor": 1,
    "enemyPerceptionRangeFactor": 1,
    "bossDamageFactor": 1,
    "bossHealthFactor": 1,
    "threatBonus": 1,
    "pacifyAllEnemies": false,
    "tamingStartleRepercussion": "LoseSomeProgress",
    "dayTimeDuration": 1800000000000,
    "nightTimeDuration": 720000000000,
    "curseModifier": "Normal"
  },
  "userGroups": [
    { "name": "Admin", "password": "ChangeMeAdmin", "canKickBan": true, "canAccessInventories": true, "canEditWorld": true, "canEditBase": true, "canExtendBase": true, "reservedSlots": 0 },
    { "name": "Friend", "password": "ChangeMeFriend", "canKickBan": false, "canAccessInventories": true, "canEditWorld": true, "canEditBase": true, "canExtendBase": false, "reservedSlots": 0 },
    { "name": "Guest", "password": "ChangeMeGuest", "canKickBan": false, "canAccessInventories": false, "canEditWorld": true, "canEditBase": false, "canExtendBase": false, "reservedSlots": 0 },
    { "name": "Visitor", "password": "ChangeMeVisitor", "canKickBan": false, "canAccessInventories": false, "canEditWorld": false, "canEditBase": false, "canExtendBase": false, "reservedSlots": 0 }
  ],
  "bannedAccounts": []
}
'@
    return ($json | ConvertFrom-Json)
}

function Ensure-UGSMGameEnshroudedJsonArrays {
    param([Parameter(Mandatory)][object]$Settings)
    if (-not $Settings.PSObject.Properties['tags'] -or $null -eq $Settings.tags) {
        if ($Settings.PSObject.Properties['tags']) { $Settings.PSObject.Properties.Remove('tags') }
        $Settings | Add-Member -NotePropertyName 'tags' -NotePropertyValue (New-Object 'System.Collections.Generic.List[string]') -Force
    }
    if (-not $Settings.PSObject.Properties['bannedAccounts'] -or $null -eq $Settings.bannedAccounts) {
        if ($Settings.PSObject.Properties['bannedAccounts']) { $Settings.PSObject.Properties.Remove('bannedAccounts') }
        $Settings | Add-Member -NotePropertyName 'bannedAccounts' -NotePropertyValue (New-Object 'System.Collections.Generic.List[string]') -Force
    }
    if (-not $Settings.PSObject.Properties['userGroups'] -or $null -eq $Settings.userGroups) {
        if ($Settings.PSObject.Properties['userGroups']) { $Settings.PSObject.Properties.Remove('userGroups') }
        $Settings | Add-Member -NotePropertyName 'userGroups' -NotePropertyValue (New-Object 'System.Collections.Generic.List[object]') -Force
    }
    if (-not $Settings.PSObject.Properties['gameSettings'] -or $null -eq $Settings.gameSettings) { $Settings | Add-Member -NotePropertyName 'gameSettings' -NotePropertyValue ([pscustomobject]@{}) -Force }
    return $Settings
}

function Initialize-UGSMGameEnshroudedServerSettingsFile {
    [CmdletBinding()]
    param([Parameter(Mandatory)][object]$Instance,[switch]$Force)
    $profileRoot = Get-UGSMGameEnshroudedProfileRoot -Instance $Instance
    if (-not (Test-Path -LiteralPath $profileRoot -PathType Container)) { New-Item -ItemType Directory -Path $profileRoot -Force | Out-Null }
    $settingsPath = Get-UGSMGameEnshroudedSettingsPath -Instance $Instance
    if ((Test-Path -LiteralPath $settingsPath -PathType Leaf) -and -not $Force) { return $settingsPath }

    $copied = $false
    foreach ($candidateRoot in @([string]$Instance.InstallPath, (Resolve-UGSMGameEnshroudedInstall -InstallPath ([string]$Instance.InstallPath) -Instance $Instance).InstallPath)) {
        if ([string]::IsNullOrWhiteSpace($candidateRoot)) { continue }
        $source = Join-Path $candidateRoot 'enshrouded_server.json'
        if (Test-Path -LiteralPath $source -PathType Leaf) {
            try {
                Copy-Item -LiteralPath $source -Destination $settingsPath -Force
                $copied = $true
                break
            } catch {
                Write-UGSMGameEnshroudedLog -Level 'WARN' -Message 'Failed to copy Enshrouded server json into profile.' -Exception $_.Exception
            }
        }
    }
    if (-not $copied) {
        $settings = New-UGSMGameEnshroudedDefaultServerJsonObject
        ($settings | ConvertTo-Json -Depth 30) | Set-Content -LiteralPath $settingsPath -Encoding UTF8
    }
    return $settingsPath
}

function Get-UGSMGameEnshroudedServerSettings {
    [CmdletBinding()]
    param([Parameter(Mandatory)][object]$Instance)
    $path = Initialize-UGSMGameEnshroudedServerSettingsFile -Instance $Instance
    try {
        $settings = Get-Content -LiteralPath $path -Raw | ConvertFrom-Json
        return (Ensure-UGSMGameEnshroudedJsonArrays -Settings $settings)
    } catch {
        Write-UGSMGameEnshroudedLog -Level 'WARN' -Message 'Failed to read Enshrouded settings json; using defaults.' -Exception $_.Exception
        return (New-UGSMGameEnshroudedDefaultServerJsonObject)
    }
}

function Save-UGSMGameEnshroudedServerSettings {
    [CmdletBinding()]
    param([Parameter(Mandatory)][object]$Instance,[Parameter(Mandatory)][object]$Settings)
    $path = Get-UGSMGameEnshroudedSettingsPath -Instance $Instance
    $root = Split-Path -Parent $path
    if (-not (Test-Path -LiteralPath $root -PathType Container)) { New-Item -ItemType Directory -Path $root -Force | Out-Null }
    ($Settings | ConvertTo-Json -Depth 40) | Set-Content -LiteralPath $path -Encoding UTF8
    Write-UGSMGameEnshroudedLog -Level 'INFO' -Message ('Enshrouded settings saved. Profile={0}' -f (Get-UGSMGameEnshroudedProfileName -Instance $Instance))
    return [pscustomobject]@{ Success=$true; Message='Enshrouded settings saved.'; Path=$path }
}

function ConvertTo-UGSMGameEnshroudedListText { param([AllowNull()][object]$Values) if ($null -eq $Values) { return '' }; return (@($Values) | ForEach-Object { [string]$_ } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }) -join "`r`n" }
function ConvertFrom-UGSMGameEnshroudedListText { param([AllowNull()][string]$Text) if ([string]::IsNullOrWhiteSpace($Text)) { return @() }; return @($Text -split "[`r`n,;]+" | ForEach-Object { $_.Trim() } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }) }

function New-UGSMGameEnshroudedStringList {
    param([AllowNull()][string]$Text)
    $list = New-Object 'System.Collections.Generic.List[string]'
    if (-not [string]::IsNullOrWhiteSpace($Text)) {
        foreach ($item in ($Text -split "[`r`n,;]+")) {
            $v = ([string]$item).Trim()
            if (-not [string]::IsNullOrWhiteSpace($v)) { [void]$list.Add($v) }
        }
    }
    return $list
}
function Set-UGSMGameEnshroudedJsonListProperty {
    param([Parameter(Mandatory)][object]$Object,[Parameter(Mandatory)][string]$Name,[AllowNull()][object]$List)
    if ($null -eq $List) { $List = New-Object 'System.Collections.Generic.List[string]' }
    if ($Object.PSObject.Properties[$Name]) { $Object.PSObject.Properties.Remove($Name) }
    $Object | Add-Member -NotePropertyName $Name -NotePropertyValue $List -Force
}
function Get-UGSMGameEnshroudedTextValue { param([hashtable]$Controls,[string]$Key,[string]$Default='') if ($Controls.ContainsKey($Key)) { return [string]$Controls[$Key].Text }; return $Default }
function Get-UGSMGameEnshroudedBoolValue { param([hashtable]$Controls,[string]$Key,[bool]$Default=$false) if ($Controls.ContainsKey($Key)) { return [bool]$Controls[$Key].Checked }; return $Default }
function Get-UGSMGameEnshroudedDoubleValue { param([hashtable]$Controls,[string]$Key,[double]$Default=0) $d=$Default; if ($Controls.ContainsKey($Key)) { [void][double]::TryParse(([string]$Controls[$Key].Text),[ref]$d) }; return $d }
function Get-UGSMGameEnshroudedInt64Value { param([hashtable]$Controls,[string]$Key,[Int64]$Default=0) $n=$Default; if ($Controls.ContainsKey($Key)) { [void][Int64]::TryParse(([string]$Controls[$Key].Text),[ref]$n) }; return $n }
function Set-UGSMGameEnshroudedJsonProperty { param([Parameter(Mandatory)][object]$Object,[string]$Name,[AllowNull()][object]$Value) if ($Object.PSObject.Properties[$Name]) { $Object.$Name = $Value } else { $Object | Add-Member -NotePropertyName $Name -NotePropertyValue $Value -Force } }

function New-UGSMGameEnshroudedTabPage {
    param([System.Windows.Forms.TabControl]$Tabs,[string]$Title,[System.Drawing.Color]$BackColor)
    $tab = New-Object System.Windows.Forms.TabPage
    $tab.Text = $Title
    $panel = New-Object System.Windows.Forms.Panel
    $panel.Dock = 'Fill'
    $panel.AutoScroll = $true
    $panel.BackColor = $BackColor
    $tab.Controls.Add($panel)
    [void]$Tabs.TabPages.Add($tab)
    return $panel
}

function Add-UGSMGameEnshroudedField {
    param([System.Windows.Forms.Panel]$Parent,[hashtable]$Controls,[string]$Key,[string]$Label,[AllowNull()][object]$Value,[int]$Row,[AllowNull()][object]$Theme,[switch]$Multiline,[int]$Height=24)
    $lbl = New-Object System.Windows.Forms.Label
    $lbl.Text = $Label
    $lbl.AutoSize = $false
    $lbl.Left = 24
    $lbl.Top = 16 + ($Row * 42)
    $lbl.Width = 230
    $lbl.Height = 24
    $lbl.ForeColor = Get-UGSMGameEnshroudedColor -Theme $Theme -Name 'Text' -Fallback ([System.Drawing.Color]::White)
    $Parent.Controls.Add($lbl)
    $txt = New-Object System.Windows.Forms.TextBox
    $txt.Left = 270
    $txt.Top = 12 + ($Row * 42)
    $txt.Width = 570
    $txt.Height = $Height
    $txt.Text = if ($null -eq $Value) { '' } else { [string]$Value }
    $txt.Multiline = [bool]$Multiline
    if ($Multiline) { $txt.ScrollBars = 'Vertical'; $txt.AcceptsReturn = $true }
    $txt.ForeColor = Get-UGSMGameEnshroudedColor -Theme $Theme -Name 'Text' -Fallback ([System.Drawing.Color]::White)
    $txt.BackColor = Get-UGSMGameEnshroudedColor -Theme $Theme -Name 'Input' -Fallback ([System.Drawing.Color]::FromArgb(2,12,24))
    $Parent.Controls.Add($txt)
    $Controls[$Key] = $txt
    return $txt
}

function Add-UGSMGameEnshroudedCheckField {
    param([System.Windows.Forms.Panel]$Parent,[hashtable]$Controls,[string]$Key,[string]$Label,[bool]$Value,[int]$Row,[AllowNull()][object]$Theme)
    $chk = New-Object System.Windows.Forms.CheckBox
    $chk.Left = 270
    $chk.Top = 14 + ($Row * 42)
    $chk.Width = 570
    $chk.Height = 24
    $chk.Text = $Label
    $chk.Checked = [bool]$Value
    $chk.ForeColor = Get-UGSMGameEnshroudedColor -Theme $Theme -Name 'Text' -Fallback ([System.Drawing.Color]::White)
    $chk.BackColor = Get-UGSMGameEnshroudedColor -Theme $Theme -Name 'Background' -Fallback ([System.Drawing.Color]::FromArgb(8,18,31))
    $Parent.Controls.Add($chk)
    $Controls[$Key] = $chk
    return $chk
}

function Add-UGSMGameEnshroudedComboField {
    param([System.Windows.Forms.Panel]$Parent,[hashtable]$Controls,[string]$Key,[string]$Label,[AllowNull()][object]$Value,[string[]]$Items,[int]$Row,[AllowNull()][object]$Theme)
    $lbl = New-Object System.Windows.Forms.Label
    $lbl.Text = $Label
    $lbl.AutoSize = $false
    $lbl.Left = 24
    $lbl.Top = 16 + ($Row * 42)
    $lbl.Width = 230
    $lbl.Height = 24
    $lbl.ForeColor = Get-UGSMGameEnshroudedColor -Theme $Theme -Name 'Text' -Fallback ([System.Drawing.Color]::White)
    $Parent.Controls.Add($lbl)
    $cmb = New-Object System.Windows.Forms.ComboBox
    $cmb.Left = 270
    $cmb.Top = 12 + ($Row * 42)
    $cmb.Width = 300
    $cmb.DropDownStyle = 'DropDown'
    [void]$cmb.Items.AddRange($Items)
    $cmb.Text = if ($null -eq $Value) { '' } else { [string]$Value }
    $cmb.ForeColor = Get-UGSMGameEnshroudedColor -Theme $Theme -Name 'Text' -Fallback ([System.Drawing.Color]::White)
    $cmb.BackColor = Get-UGSMGameEnshroudedColor -Theme $Theme -Name 'Input' -Fallback ([System.Drawing.Color]::FromArgb(2,12,24))
    $Parent.Controls.Add($cmb)
    $Controls[$Key] = $cmb
    return $cmb
}


function Get-UGSMGameEnshroudedDiscordSettingsPath {
    param([Parameter(Mandatory)][object]$Instance)
    return (Join-Path (Get-UGSMGameEnshroudedProfileRoot -Instance $Instance) 'UGSM_Discord.json')
}

function Get-UGSMGameEnshroudedDefaultDiscordSettings {
    [pscustomobject]@{
        WebhookUrl = ''
        NotifyOnStart = $false
        NotifyOnStop = $false
        ShowInDashboard = $false
        EffectiveWebhookUrl = ''
    }
}

function Ensure-UGSMGameEnshroudedDiscordSettings {
    param([AllowNull()][object]$Settings)
    $default = Get-UGSMGameEnshroudedDefaultDiscordSettings
    if (-not $Settings) { return $default }
    foreach ($prop in @('WebhookUrl','NotifyOnStart','NotifyOnStop','ShowInDashboard','EffectiveWebhookUrl')) {
        if (-not $Settings.PSObject.Properties[$prop]) {
            Add-Member -InputObject $Settings -MemberType NoteProperty -Name $prop -Value $default.$prop -Force
        }
    }
    return $Settings
}

function Get-UGSMGameEnshroudedDiscordSettings {
    [CmdletBinding()]
    param([Parameter(Mandatory)][object]$Instance)

    if (Get-Command -Name Get-UGSMInstanceDiscordSettingsModel -ErrorAction SilentlyContinue) {
        try {
            $model = Get-UGSMInstanceDiscordSettingsModel -Instance $Instance
            if ($model) { return (Ensure-UGSMGameEnshroudedDiscordSettings -Settings $model) }
        } catch {
            Write-UGSMGameEnshroudedLog -Level 'WARN' -Message 'Failed to read Enshrouded Discord settings from shared Discord service. Falling back to profile file.' -Exception $_.Exception
        }
    }

    $path = Get-UGSMGameEnshroudedDiscordSettingsPath -Instance $Instance
    if (Test-Path -LiteralPath $path -PathType Leaf) {
        try {
            $loaded = Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json
            return (Ensure-UGSMGameEnshroudedDiscordSettings -Settings $loaded)
        } catch {
            Write-UGSMGameEnshroudedLog -Level 'WARN' -Message 'Failed to read Enshrouded profile Discord settings. Defaults will be used.' -Exception $_.Exception
        }
    }

    if ($Instance -and $Instance.PSObject.Properties['Discord'] -and $Instance.Discord) {
        return (Ensure-UGSMGameEnshroudedDiscordSettings -Settings $Instance.Discord)
    }

    return (Get-UGSMGameEnshroudedDefaultDiscordSettings)
}

function Save-UGSMGameEnshroudedDiscordSettings {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$Instance,
        [Parameter(Mandatory)][object]$InputObject
    )

    $safe = [pscustomobject]@{
        WebhookUrl = [string]$InputObject.WebhookUrl
        NotifyOnStart = [bool]$InputObject.NotifyOnStart
        NotifyOnStop = [bool]$InputObject.NotifyOnStop
        ShowInDashboard = [bool]$InputObject.ShowInDashboard
    }

    if ($Instance.PSObject.Properties['Discord']) { $Instance.Discord = $safe }
    else { Add-Member -InputObject $Instance -MemberType NoteProperty -Name 'Discord' -Value $safe -Force }

    $sharedSaved = $false
    if (Get-Command -Name Save-UGSMInstanceDiscordSettingsModel -ErrorAction SilentlyContinue) {
        try {
            $persistScript = {
                param($updated)
                if (Get-Command -Name Save-UGSMInstance -ErrorAction SilentlyContinue) { return (Save-UGSMInstance -Instance $updated) }
                if (Get-Command -Name Update-UGSMInstance -ErrorAction SilentlyContinue) { return (Update-UGSMInstance -Instance $updated) }
                if (Get-Command -Name Set-UGSMInstance -ErrorAction SilentlyContinue) { return (Set-UGSMInstance -Instance $updated) }
                return $updated
            }
            $saveResult = Save-UGSMInstanceDiscordSettingsModel -Instance $Instance -InputObject $safe -PersistInstance $persistScript
            if ($saveResult -and $saveResult.PSObject.Properties['Instance'] -and $saveResult.Instance) { $Instance = $saveResult.Instance }
            $sharedSaved = $true
        } catch {
            Write-UGSMGameEnshroudedLog -Level 'WARN' -Message 'Shared Discord settings save failed for Enshrouded. Profile fallback will still be written.' -Exception $_.Exception
        }
    }

    $path = Get-UGSMGameEnshroudedDiscordSettingsPath -Instance $Instance
    $dir = Split-Path -Parent $path
    if (-not [string]::IsNullOrWhiteSpace($dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    ($safe | ConvertTo-Json -Depth 8) | Set-Content -LiteralPath $path -Encoding UTF8

    Write-UGSMGameEnshroudedLog -Level 'INFO' -Message ('Enshrouded Discord settings saved. Profile={0}; HasInstanceWebhook={1}; NotifyStart={2}; NotifyStop={3}; Dashboard={4}' -f (Get-UGSMGameEnshroudedProfileName -Instance $Instance), (-not [string]::IsNullOrWhiteSpace([string]$safe.WebhookUrl)), [bool]$safe.NotifyOnStart, [bool]$safe.NotifyOnStop, [bool]$safe.ShowInDashboard)
    return [pscustomobject]@{ Success=$true; Instance=$Instance; SharedSaved=$sharedSaved; Path=$path }
}

function Save-UGSMGameEnshroudedDiscordSettingsFromControls {
    [CmdletBinding()]
    param([Parameter(Mandatory)][object]$Instance,[Parameter(Mandatory)][hashtable]$Controls)
    if (-not ($Controls.ContainsKey('DiscordWebhookUrl') -or $Controls.ContainsKey('NotifyOnStart') -or $Controls.ContainsKey('NotifyOnStop') -or $Controls.ContainsKey('ShowInDashboard'))) {
        return $null
    }
    $input = [pscustomobject]@{
        WebhookUrl = if ($Controls.ContainsKey('DiscordWebhookUrl')) { [string]$Controls['DiscordWebhookUrl'].Text } else { '' }
        NotifyOnStart = if ($Controls.ContainsKey('NotifyOnStart')) { [bool]$Controls['NotifyOnStart'].Checked } else { $false }
        NotifyOnStop = if ($Controls.ContainsKey('NotifyOnStop')) { [bool]$Controls['NotifyOnStop'].Checked } else { $false }
        ShowInDashboard = if ($Controls.ContainsKey('ShowInDashboard')) { [bool]$Controls['ShowInDashboard'].Checked } else { $false }
    }
    return Save-UGSMGameEnshroudedDiscordSettings -Instance $Instance -InputObject $input
}

function Save-UGSMGameEnshroudedInstanceEditor {
    [CmdletBinding()]
    param([AllowNull()][object]$Instance,[Parameter(Mandatory)][object]$EditorState)
    $controls = $EditorState.Controls
    if (-not $Instance -and $EditorState.PSObject.Properties['Instance']) { $Instance = $EditorState.Instance }
    if (-not $Instance) { throw 'Enshrouded save failed because no instance was provided.' }
    $settings = Get-UGSMGameEnshroudedServerSettings -Instance $Instance
    $settings = Ensure-UGSMGameEnshroudedJsonArrays -Settings $settings

    Set-UGSMGameEnshroudedJsonProperty -Object $settings -Name 'name' -Value (Get-UGSMGameEnshroudedTextValue -Controls $controls -Key 'name' -Default $settings.name)
    Set-UGSMGameEnshroudedJsonProperty -Object $settings -Name 'saveDirectory' -Value (Get-UGSMGameEnshroudedTextValue -Controls $controls -Key 'saveDirectory' -Default $settings.saveDirectory)
    Set-UGSMGameEnshroudedJsonProperty -Object $settings -Name 'logDirectory' -Value (Get-UGSMGameEnshroudedTextValue -Controls $controls -Key 'logDirectory' -Default $settings.logDirectory)
    Set-UGSMGameEnshroudedJsonProperty -Object $settings -Name 'ip' -Value (Get-UGSMGameEnshroudedTextValue -Controls $controls -Key 'ip' -Default $settings.ip)
    Set-UGSMGameEnshroudedJsonProperty -Object $settings -Name 'queryPort' -Value ([int](Get-UGSMGameEnshroudedInt64Value -Controls $controls -Key 'queryPort' -Default ([Int64]$settings.queryPort)))
    Set-UGSMGameEnshroudedJsonProperty -Object $settings -Name 'slotCount' -Value ([int](Get-UGSMGameEnshroudedInt64Value -Controls $controls -Key 'slotCount' -Default ([Int64]$settings.slotCount)))
    Set-UGSMGameEnshroudedJsonProperty -Object $settings -Name 'enableVoiceChat' -Value (Get-UGSMGameEnshroudedBoolValue -Controls $controls -Key 'enableVoiceChat' -Default ([bool]$settings.enableVoiceChat))
    Set-UGSMGameEnshroudedJsonProperty -Object $settings -Name 'enableTextChat' -Value (Get-UGSMGameEnshroudedBoolValue -Controls $controls -Key 'enableTextChat' -Default ([bool]$settings.enableTextChat))
    Set-UGSMGameEnshroudedJsonProperty -Object $settings -Name 'voiceChatMode' -Value (Get-UGSMGameEnshroudedTextValue -Controls $controls -Key 'voiceChatMode' -Default $settings.voiceChatMode)
    Set-UGSMGameEnshroudedJsonProperty -Object $settings -Name 'gameSettingsPreset' -Value (Get-UGSMGameEnshroudedTextValue -Controls $controls -Key 'gameSettingsPreset' -Default $settings.gameSettingsPreset)
    Set-UGSMGameEnshroudedJsonListProperty -Object $settings -Name 'tags' -List (New-UGSMGameEnshroudedStringList -Text (Get-UGSMGameEnshroudedTextValue -Controls $controls -Key 'tags'))
    Set-UGSMGameEnshroudedJsonListProperty -Object $settings -Name 'bannedAccounts' -List (New-UGSMGameEnshroudedStringList -Text (Get-UGSMGameEnshroudedTextValue -Controls $controls -Key 'bannedAccounts'))

    $gs = $settings.gameSettings
    foreach ($key in @('playerHealthFactor','playerManaFactor','playerStaminaFactor','playerBodyHeatFactor','playerDivingTimeFactor','foodBuffDurationFactor','shroudTimeFactor','miningDamageFactor','plantGrowthSpeedFactor','resourceDropStackAmountFactor','factoryProductionSpeedFactor','perkUpgradeRecyclingFactor','perkCostFactor','experienceCombatFactor','experienceMiningFactor','experienceExplorationQuestsFactor','enemyDamageFactor','enemyHealthFactor','enemyStaminaFactor','enemyPerceptionRangeFactor','bossDamageFactor','bossHealthFactor','threatBonus')) {
        Set-UGSMGameEnshroudedJsonProperty -Object $gs -Name $key -Value (Get-UGSMGameEnshroudedDoubleValue -Controls $controls -Key $key -Default ([double]$gs.$key))
    }
    foreach ($key in @('fromHungerToStarving','dayTimeDuration','nightTimeDuration')) {
        Set-UGSMGameEnshroudedJsonProperty -Object $gs -Name $key -Value (Get-UGSMGameEnshroudedInt64Value -Controls $controls -Key $key -Default ([Int64]$gs.$key))
    }
    foreach ($key in @('enableDurability','enableStarvingDebuff','enableGliderTurbulences','pacifyAllEnemies')) {
        Set-UGSMGameEnshroudedJsonProperty -Object $gs -Name $key -Value (Get-UGSMGameEnshroudedBoolValue -Controls $controls -Key $key -Default ([bool]$gs.$key))
    }
    foreach ($key in @('tombstoneMode','weatherFrequency','fishingDifficulty','randomSpawnerAmount','aggroPoolAmount','tamingStartleRepercussion','curseModifier')) {
        Set-UGSMGameEnshroudedJsonProperty -Object $gs -Name $key -Value (Get-UGSMGameEnshroudedTextValue -Controls $controls -Key $key -Default ([string]$gs.$key))
    }

    $groups = @()
    for ($i=0; $i -lt 4; $i++) {
        $groupName = Get-UGSMGameEnshroudedTextValue -Controls $controls -Key "group_${i}_name"
        if ([string]::IsNullOrWhiteSpace($groupName)) { continue }
        $groups += [pscustomobject]@{
            name = $groupName
            password = Get-UGSMGameEnshroudedTextValue -Controls $controls -Key "group_${i}_password"
            canKickBan = Get-UGSMGameEnshroudedBoolValue -Controls $controls -Key "group_${i}_canKickBan"
            canAccessInventories = Get-UGSMGameEnshroudedBoolValue -Controls $controls -Key "group_${i}_canAccessInventories"
            canEditWorld = Get-UGSMGameEnshroudedBoolValue -Controls $controls -Key "group_${i}_canEditWorld"
            canEditBase = Get-UGSMGameEnshroudedBoolValue -Controls $controls -Key "group_${i}_canEditBase"
            canExtendBase = Get-UGSMGameEnshroudedBoolValue -Controls $controls -Key "group_${i}_canExtendBase"
            reservedSlots = [int](Get-UGSMGameEnshroudedInt64Value -Controls $controls -Key "group_${i}_reservedSlots" -Default 0)
        }
    }
    Set-UGSMGameEnshroudedJsonProperty -Object $settings -Name 'userGroups' -Value $groups
    $saveResult = Save-UGSMGameEnshroudedServerSettings -Instance $Instance -Settings $settings
    try { Save-UGSMGameEnshroudedDiscordSettingsFromControls -Instance $Instance -Controls $controls | Out-Null } catch { Write-UGSMGameEnshroudedLog -Level 'WARN' -Message 'Enshrouded Discord settings were not saved from the main save action.' -Exception $_.Exception }
    return $saveResult
}

function New-UGSMGameEnshroudedInstanceEditor {
    [CmdletBinding()]
    param([Parameter(Mandatory)][object]$Instance,[Parameter(Mandatory)][System.Windows.Forms.Control]$HostPanel,[AllowNull()][object]$Theme,[AllowNull()][System.Windows.Forms.Label]$StatusLabel)
    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing
    $HostPanel.SuspendLayout()
    try {
        $HostPanel.Controls.Clear()
        $back = Get-UGSMGameEnshroudedColor -Theme $Theme -Name 'Background' -Fallback ([System.Drawing.Color]::FromArgb(8,18,31))
        $HostPanel.BackColor = $back
        $settings = Get-UGSMGameEnshroudedServerSettings -Instance $Instance
        $settingsPath = Get-UGSMGameEnshroudedSettingsPath -Instance $Instance
        $discordSettings = Get-UGSMGameEnshroudedDiscordSettings -Instance $Instance
        $controls = @{}
        $tabs = New-Object System.Windows.Forms.TabControl
        $tabs.Dock = 'Fill'
        $HostPanel.Controls.Add($tabs)

        $serverPanel = New-UGSMGameEnshroudedTabPage -Tabs $tabs -Title 'Server' -BackColor $back
        Add-UGSMGameEnshroudedField -Parent $serverPanel -Controls $controls -Key 'name' -Label 'Server name' -Value $settings.name -Row 0 -Theme $Theme | Out-Null
        Add-UGSMGameEnshroudedField -Parent $serverPanel -Controls $controls -Key 'slotCount' -Label 'Player slots' -Value $settings.slotCount -Row 1 -Theme $Theme | Out-Null
        Add-UGSMGameEnshroudedField -Parent $serverPanel -Controls $controls -Key 'saveDirectory' -Label 'Save directory' -Value $settings.saveDirectory -Row 2 -Theme $Theme | Out-Null
        Add-UGSMGameEnshroudedField -Parent $serverPanel -Controls $controls -Key 'logDirectory' -Label 'Log directory' -Value $settings.logDirectory -Row 3 -Theme $Theme | Out-Null
        Add-UGSMGameEnshroudedField -Parent $serverPanel -Controls $controls -Key 'tags' -Label 'Tags one per line' -Value (ConvertTo-UGSMGameEnshroudedListText -Values $settings.tags) -Row 4 -Theme $Theme -Multiline -Height 95 | Out-Null
        $pathLabel = New-Object System.Windows.Forms.Label
        $pathLabel.Text = 'Profile settings file: ' + $settingsPath
        $pathLabel.Left = 24; $pathLabel.Top = 280; $pathLabel.Width = 900; $pathLabel.Height = 40
        $pathLabel.ForeColor = Get-UGSMGameEnshroudedColor -Theme $Theme -Name 'Muted' -Fallback ([System.Drawing.Color]::LightGray)
        $serverPanel.Controls.Add($pathLabel)

        $networkPanel = New-UGSMGameEnshroudedTabPage -Tabs $tabs -Title 'Network / Chat' -BackColor $back
        Add-UGSMGameEnshroudedField -Parent $networkPanel -Controls $controls -Key 'ip' -Label 'Bind IP' -Value $settings.ip -Row 0 -Theme $Theme | Out-Null
        Add-UGSMGameEnshroudedField -Parent $networkPanel -Controls $controls -Key 'queryPort' -Label 'Query port' -Value $settings.queryPort -Row 1 -Theme $Theme | Out-Null
        Add-UGSMGameEnshroudedCheckField -Parent $networkPanel -Controls $controls -Key 'enableVoiceChat' -Label 'Enable voice chat' -Value ([bool]$settings.enableVoiceChat) -Row 2 -Theme $Theme | Out-Null
        Add-UGSMGameEnshroudedCheckField -Parent $networkPanel -Controls $controls -Key 'enableTextChat' -Label 'Enable text chat' -Value ([bool]$settings.enableTextChat) -Row 3 -Theme $Theme | Out-Null
        Add-UGSMGameEnshroudedComboField -Parent $networkPanel -Controls $controls -Key 'voiceChatMode' -Label 'Voice chat mode' -Value $settings.voiceChatMode -Items @('Proximity','Global') -Row 4 -Theme $Theme | Out-Null

        $playerPanel = New-UGSMGameEnshroudedTabPage -Tabs $tabs -Title 'Player' -BackColor $back
        Add-UGSMGameEnshroudedField -Parent $playerPanel -Controls $controls -Key 'gameSettingsPreset' -Label 'Settings preset' -Value $settings.gameSettingsPreset -Row 0 -Theme $Theme | Out-Null
        Add-UGSMGameEnshroudedField -Parent $playerPanel -Controls $controls -Key 'playerHealthFactor' -Label 'Player health factor' -Value $settings.gameSettings.playerHealthFactor -Row 1 -Theme $Theme | Out-Null
        Add-UGSMGameEnshroudedField -Parent $playerPanel -Controls $controls -Key 'playerManaFactor' -Label 'Player mana factor' -Value $settings.gameSettings.playerManaFactor -Row 2 -Theme $Theme | Out-Null
        Add-UGSMGameEnshroudedField -Parent $playerPanel -Controls $controls -Key 'playerStaminaFactor' -Label 'Player stamina factor' -Value $settings.gameSettings.playerStaminaFactor -Row 3 -Theme $Theme | Out-Null
        Add-UGSMGameEnshroudedField -Parent $playerPanel -Controls $controls -Key 'playerBodyHeatFactor' -Label 'Body heat factor' -Value $settings.gameSettings.playerBodyHeatFactor -Row 4 -Theme $Theme | Out-Null
        Add-UGSMGameEnshroudedField -Parent $playerPanel -Controls $controls -Key 'playerDivingTimeFactor' -Label 'Diving time factor' -Value $settings.gameSettings.playerDivingTimeFactor -Row 5 -Theme $Theme | Out-Null
        Add-UGSMGameEnshroudedCheckField -Parent $playerPanel -Controls $controls -Key 'enableDurability' -Label 'Enable durability' -Value ([bool]$settings.gameSettings.enableDurability) -Row 6 -Theme $Theme | Out-Null
        Add-UGSMGameEnshroudedCheckField -Parent $playerPanel -Controls $controls -Key 'enableStarvingDebuff' -Label 'Enable starving debuff' -Value ([bool]$settings.gameSettings.enableStarvingDebuff) -Row 7 -Theme $Theme | Out-Null
        Add-UGSMGameEnshroudedField -Parent $playerPanel -Controls $controls -Key 'foodBuffDurationFactor' -Label 'Food buff duration factor' -Value $settings.gameSettings.foodBuffDurationFactor -Row 8 -Theme $Theme | Out-Null
        Add-UGSMGameEnshroudedField -Parent $playerPanel -Controls $controls -Key 'fromHungerToStarving' -Label 'Hunger to starving ticks' -Value $settings.gameSettings.fromHungerToStarving -Row 9 -Theme $Theme | Out-Null
        Add-UGSMGameEnshroudedComboField -Parent $playerPanel -Controls $controls -Key 'tombstoneMode' -Label 'Tombstone mode' -Value $settings.gameSettings.tombstoneMode -Items @('AddBackpackMaterials','DropBackpack','NoTombstone') -Row 10 -Theme $Theme | Out-Null
        Add-UGSMGameEnshroudedCheckField -Parent $playerPanel -Controls $controls -Key 'enableGliderTurbulences' -Label 'Enable glider turbulences' -Value ([bool]$settings.gameSettings.enableGliderTurbulences) -Row 11 -Theme $Theme | Out-Null

        $worldPanel = New-UGSMGameEnshroudedTabPage -Tabs $tabs -Title 'World / Resources' -BackColor $back
        Add-UGSMGameEnshroudedField -Parent $worldPanel -Controls $controls -Key 'shroudTimeFactor' -Label 'Shroud time factor' -Value $settings.gameSettings.shroudTimeFactor -Row 0 -Theme $Theme | Out-Null
        Add-UGSMGameEnshroudedComboField -Parent $worldPanel -Controls $controls -Key 'weatherFrequency' -Label 'Weather frequency' -Value $settings.gameSettings.weatherFrequency -Items @('Low','Normal','High') -Row 1 -Theme $Theme | Out-Null
        Add-UGSMGameEnshroudedComboField -Parent $worldPanel -Controls $controls -Key 'fishingDifficulty' -Label 'Fishing difficulty' -Value $settings.gameSettings.fishingDifficulty -Items @('Easy','Normal','Hard') -Row 2 -Theme $Theme | Out-Null
        Add-UGSMGameEnshroudedField -Parent $worldPanel -Controls $controls -Key 'miningDamageFactor' -Label 'Mining damage factor' -Value $settings.gameSettings.miningDamageFactor -Row 3 -Theme $Theme | Out-Null
        Add-UGSMGameEnshroudedField -Parent $worldPanel -Controls $controls -Key 'plantGrowthSpeedFactor' -Label 'Plant growth speed factor' -Value $settings.gameSettings.plantGrowthSpeedFactor -Row 4 -Theme $Theme | Out-Null
        Add-UGSMGameEnshroudedField -Parent $worldPanel -Controls $controls -Key 'resourceDropStackAmountFactor' -Label 'Resource drop amount factor' -Value $settings.gameSettings.resourceDropStackAmountFactor -Row 5 -Theme $Theme | Out-Null
        Add-UGSMGameEnshroudedField -Parent $worldPanel -Controls $controls -Key 'factoryProductionSpeedFactor' -Label 'Factory production factor' -Value $settings.gameSettings.factoryProductionSpeedFactor -Row 6 -Theme $Theme | Out-Null
        Add-UGSMGameEnshroudedField -Parent $worldPanel -Controls $controls -Key 'perkUpgradeRecyclingFactor' -Label 'Perk recycling factor' -Value $settings.gameSettings.perkUpgradeRecyclingFactor -Row 7 -Theme $Theme | Out-Null
        Add-UGSMGameEnshroudedField -Parent $worldPanel -Controls $controls -Key 'perkCostFactor' -Label 'Perk cost factor' -Value $settings.gameSettings.perkCostFactor -Row 8 -Theme $Theme | Out-Null
        Add-UGSMGameEnshroudedField -Parent $worldPanel -Controls $controls -Key 'dayTimeDuration' -Label 'Day duration ticks' -Value $settings.gameSettings.dayTimeDuration -Row 9 -Theme $Theme | Out-Null
        Add-UGSMGameEnshroudedField -Parent $worldPanel -Controls $controls -Key 'nightTimeDuration' -Label 'Night duration ticks' -Value $settings.gameSettings.nightTimeDuration -Row 10 -Theme $Theme | Out-Null

        $enemyPanel = New-UGSMGameEnshroudedTabPage -Tabs $tabs -Title 'Enemies / XP' -BackColor $back
        Add-UGSMGameEnshroudedField -Parent $enemyPanel -Controls $controls -Key 'experienceCombatFactor' -Label 'Combat XP factor' -Value $settings.gameSettings.experienceCombatFactor -Row 0 -Theme $Theme | Out-Null
        Add-UGSMGameEnshroudedField -Parent $enemyPanel -Controls $controls -Key 'experienceMiningFactor' -Label 'Mining XP factor' -Value $settings.gameSettings.experienceMiningFactor -Row 1 -Theme $Theme | Out-Null
        Add-UGSMGameEnshroudedField -Parent $enemyPanel -Controls $controls -Key 'experienceExplorationQuestsFactor' -Label 'Exploration/quest XP factor' -Value $settings.gameSettings.experienceExplorationQuestsFactor -Row 2 -Theme $Theme | Out-Null
        Add-UGSMGameEnshroudedComboField -Parent $enemyPanel -Controls $controls -Key 'randomSpawnerAmount' -Label 'Random spawner amount' -Value $settings.gameSettings.randomSpawnerAmount -Items @('Low','Normal','High') -Row 3 -Theme $Theme | Out-Null
        Add-UGSMGameEnshroudedComboField -Parent $enemyPanel -Controls $controls -Key 'aggroPoolAmount' -Label 'Aggro pool amount' -Value $settings.gameSettings.aggroPoolAmount -Items @('Low','Normal','High') -Row 4 -Theme $Theme | Out-Null
        Add-UGSMGameEnshroudedField -Parent $enemyPanel -Controls $controls -Key 'enemyDamageFactor' -Label 'Enemy damage factor' -Value $settings.gameSettings.enemyDamageFactor -Row 5 -Theme $Theme | Out-Null
        Add-UGSMGameEnshroudedField -Parent $enemyPanel -Controls $controls -Key 'enemyHealthFactor' -Label 'Enemy health factor' -Value $settings.gameSettings.enemyHealthFactor -Row 6 -Theme $Theme | Out-Null
        Add-UGSMGameEnshroudedField -Parent $enemyPanel -Controls $controls -Key 'enemyStaminaFactor' -Label 'Enemy stamina factor' -Value $settings.gameSettings.enemyStaminaFactor -Row 7 -Theme $Theme | Out-Null
        Add-UGSMGameEnshroudedField -Parent $enemyPanel -Controls $controls -Key 'enemyPerceptionRangeFactor' -Label 'Enemy perception factor' -Value $settings.gameSettings.enemyPerceptionRangeFactor -Row 8 -Theme $Theme | Out-Null
        Add-UGSMGameEnshroudedField -Parent $enemyPanel -Controls $controls -Key 'bossDamageFactor' -Label 'Boss damage factor' -Value $settings.gameSettings.bossDamageFactor -Row 9 -Theme $Theme | Out-Null
        Add-UGSMGameEnshroudedField -Parent $enemyPanel -Controls $controls -Key 'bossHealthFactor' -Label 'Boss health factor' -Value $settings.gameSettings.bossHealthFactor -Row 10 -Theme $Theme | Out-Null
        Add-UGSMGameEnshroudedField -Parent $enemyPanel -Controls $controls -Key 'threatBonus' -Label 'Threat bonus' -Value $settings.gameSettings.threatBonus -Row 11 -Theme $Theme | Out-Null
        Add-UGSMGameEnshroudedCheckField -Parent $enemyPanel -Controls $controls -Key 'pacifyAllEnemies' -Label 'Pacify all enemies' -Value ([bool]$settings.gameSettings.pacifyAllEnemies) -Row 12 -Theme $Theme | Out-Null
        Add-UGSMGameEnshroudedComboField -Parent $enemyPanel -Controls $controls -Key 'tamingStartleRepercussion' -Label 'Taming startle repercussion' -Value $settings.gameSettings.tamingStartleRepercussion -Items @('LoseSomeProgress','LoseAllProgress','NoLostProgress') -Row 13 -Theme $Theme | Out-Null
        Add-UGSMGameEnshroudedComboField -Parent $enemyPanel -Controls $controls -Key 'curseModifier' -Label 'Curse modifier' -Value $settings.gameSettings.curseModifier -Items @('Off','Normal','Hard') -Row 14 -Theme $Theme | Out-Null

        $groupsPanel = New-UGSMGameEnshroudedTabPage -Tabs $tabs -Title 'User Groups' -BackColor $back
        $row = 0
        $idx = 0
        foreach ($g in @($settings.userGroups)) {
            if ($idx -ge 4) { break }
            Add-UGSMGameEnshroudedField -Parent $groupsPanel -Controls $controls -Key "group_${idx}_name" -Label "Group $($idx+1) name" -Value $g.name -Row $row -Theme $Theme | Out-Null; $row++
            Add-UGSMGameEnshroudedField -Parent $groupsPanel -Controls $controls -Key "group_${idx}_password" -Label "Group $($idx+1) password" -Value $g.password -Row $row -Theme $Theme | Out-Null; $row++
            Add-UGSMGameEnshroudedField -Parent $groupsPanel -Controls $controls -Key "group_${idx}_reservedSlots" -Label "Group $($idx+1) reserved slots" -Value $g.reservedSlots -Row $row -Theme $Theme | Out-Null; $row++
            Add-UGSMGameEnshroudedCheckField -Parent $groupsPanel -Controls $controls -Key "group_${idx}_canKickBan" -Label "Group $($idx+1): can kick/ban" -Value ([bool]$g.canKickBan) -Row $row -Theme $Theme | Out-Null; $row++
            Add-UGSMGameEnshroudedCheckField -Parent $groupsPanel -Controls $controls -Key "group_${idx}_canAccessInventories" -Label "Group $($idx+1): can access inventories" -Value ([bool]$g.canAccessInventories) -Row $row -Theme $Theme | Out-Null; $row++
            Add-UGSMGameEnshroudedCheckField -Parent $groupsPanel -Controls $controls -Key "group_${idx}_canEditWorld" -Label "Group $($idx+1): can edit world" -Value ([bool]$g.canEditWorld) -Row $row -Theme $Theme | Out-Null; $row++
            Add-UGSMGameEnshroudedCheckField -Parent $groupsPanel -Controls $controls -Key "group_${idx}_canEditBase" -Label "Group $($idx+1): can edit base" -Value ([bool]$g.canEditBase) -Row $row -Theme $Theme | Out-Null; $row++
            Add-UGSMGameEnshroudedCheckField -Parent $groupsPanel -Controls $controls -Key "group_${idx}_canExtendBase" -Label "Group $($idx+1): can extend base" -Value ([bool]$g.canExtendBase) -Row $row -Theme $Theme | Out-Null; $row += 2
            $idx++
        }


        $discordPanel = New-UGSMGameEnshroudedTabPage -Tabs $tabs -Title 'Discord' -BackColor $back
        Add-UGSMGameEnshroudedField -Parent $discordPanel -Controls $controls -Key 'DiscordWebhookUrl' -Label 'Private Discord webhook URL' -Value ([string]$discordSettings.WebhookUrl) -Row 0 -Theme $Theme | Out-Null
        Add-UGSMGameEnshroudedCheckField -Parent $discordPanel -Controls $controls -Key 'NotifyOnStart' -Label 'Notify on Start' -Value ([bool]$discordSettings.NotifyOnStart) -Row 1 -Theme $Theme | Out-Null
        Add-UGSMGameEnshroudedCheckField -Parent $discordPanel -Controls $controls -Key 'NotifyOnStop' -Label 'Notify on Stop' -Value ([bool]$discordSettings.NotifyOnStop) -Row 2 -Theme $Theme | Out-Null
        Add-UGSMGameEnshroudedCheckField -Parent $discordPanel -Controls $controls -Key 'ShowInDashboard' -Label 'Show in Discord/dashboard status' -Value ([bool]$discordSettings.ShowInDashboard) -Row 3 -Theme $Theme | Out-Null
        $discordHelp = New-Object System.Windows.Forms.Label
        $discordHelp.Text = 'Optional per-server webhook override. Leave blank to use the global Discord webhook from Settings. The webhook URL is saved but never written to logs.'
        $discordHelp.Left = 24; $discordHelp.Top = 190; $discordHelp.Width = 900; $discordHelp.Height = 44
        $discordHelp.ForeColor = Get-UGSMGameEnshroudedColor -Theme $Theme -Name 'Muted' -Fallback ([System.Drawing.Color]::LightGray)
        $discordPanel.Controls.Add($discordHelp)
        $btnSaveDiscord = New-Object System.Windows.Forms.Button
        $btnSaveDiscord.Text = 'Save Discord'
        $btnSaveDiscord.Left = 270; $btnSaveDiscord.Top = 250; $btnSaveDiscord.Width = 140; $btnSaveDiscord.Height = 30
        $btnSaveDiscord.Tag = [pscustomobject]@{ Instance=$Instance; Controls=$controls; StatusLabel=$StatusLabel }
        $btnSaveDiscord.Add_Click({
            param($sender,$eventArgs)
            $st = $sender.Tag
            try {
                Save-UGSMGameEnshroudedDiscordSettingsFromControls -Instance $st.Instance -Controls $st.Controls | Out-Null
                if ($st.StatusLabel) { $st.StatusLabel.Text = 'Enshrouded Discord settings saved.' }
            } catch {
                if ($st.StatusLabel) { $st.StatusLabel.Text = 'Enshrouded Discord save failed: ' + $_.Exception.Message }
                Write-UGSMGameEnshroudedLog -Level 'ERROR' -Message 'Enshrouded Discord save failed.' -Exception $_.Exception
            }
        })
        $discordPanel.Controls.Add($btnSaveDiscord)
        $btnTestDiscord = New-Object System.Windows.Forms.Button
        $btnTestDiscord.Text = 'Test Discord'
        $btnTestDiscord.Left = 420; $btnTestDiscord.Top = 250; $btnTestDiscord.Width = 140; $btnTestDiscord.Height = 30
        $btnTestDiscord.Tag = [pscustomobject]@{ Instance=$Instance; Controls=$controls; StatusLabel=$StatusLabel }
        $btnTestDiscord.Add_Click({
            param($sender,$eventArgs)
            $st = $sender.Tag
            try {
                Save-UGSMGameEnshroudedDiscordSettingsFromControls -Instance $st.Instance -Controls $st.Controls | Out-Null
                $model = Get-UGSMGameEnshroudedDiscordSettings -Instance $st.Instance
                $target = ''
                if ($model.PSObject.Properties['EffectiveWebhookUrl']) { $target = [string]$model.EffectiveWebhookUrl }
                if ([string]::IsNullOrWhiteSpace($target) -and $model.PSObject.Properties['WebhookUrl']) { $target = [string]$model.WebhookUrl }
                if ([string]::IsNullOrWhiteSpace($target) -and $st.Controls.ContainsKey('DiscordWebhookUrl')) { $target = [string]$st.Controls['DiscordWebhookUrl'].Text }
                if (Get-Command -Name Test-UGSMDiscordWebhook -ErrorAction SilentlyContinue) {
                    if ([string]::IsNullOrWhiteSpace($target)) { throw 'No Discord webhook is configured for this server or globally.' }
                    $testResult = Test-UGSMDiscordWebhook -WebhookUrl $target -Label ('Enshrouded ' + [string](Get-UGSMGameEnshroudedProfileName -Instance $st.Instance))
                    if ($testResult -and $testResult.PSObject.Properties['Success'] -and -not [bool]$testResult.Success) {
                        $err = if ($testResult.PSObject.Properties['Error']) { [string]$testResult.Error } else { 'Unknown Discord test failure.' }
                        throw $err
                    }
                } elseif (Get-Command -Name Send-UGSMInstanceDiscordNotification -ErrorAction SilentlyContinue) {
                    Send-UGSMInstanceDiscordNotification -Instance $st.Instance -Event 'Test' | Out-Null
                } else {
                    throw 'Discord test service is not loaded.'
                }
                if ($st.StatusLabel) { $st.StatusLabel.Text = 'Enshrouded Discord test sent.' }
            } catch {
                if ($st.StatusLabel) { $st.StatusLabel.Text = 'Enshrouded Discord test failed: ' + $_.Exception.Message }
                Write-UGSMGameEnshroudedLog -Level 'ERROR' -Message 'Enshrouded Discord test failed.' -Exception $_.Exception
            }
        })
        $discordPanel.Controls.Add($btnTestDiscord)

        $advancedPanel = New-UGSMGameEnshroudedTabPage -Tabs $tabs -Title 'Advanced' -BackColor $back
        Add-UGSMGameEnshroudedField -Parent $advancedPanel -Controls $controls -Key 'bannedAccounts' -Label 'Banned accounts one per line' -Value (ConvertTo-UGSMGameEnshroudedListText -Values $settings.bannedAccounts) -Row 0 -Theme $Theme -Multiline -Height 120 | Out-Null
        $note = New-Object System.Windows.Forms.Label
        $note.Text = 'Passwords stay inside the profile JSON and are not written to UGSM logs. Save writes only Profiles\Enshrouded\<ServerName>\enshrouded_server.json.'
        $note.Left = 24; $note.Top = 170; $note.Width = 900; $note.Height = 50
        $note.ForeColor = Get-UGSMGameEnshroudedColor -Theme $Theme -Name 'Muted' -Fallback ([System.Drawing.Color]::LightGray)
        $advancedPanel.Controls.Add($note)

        $btnSave = New-Object System.Windows.Forms.Button
        $btnSave.Text = 'Save Enshrouded Settings'
        $btnSave.Dock = 'Bottom'
        $btnSave.Height = 34
        $btnSave.Tag = [pscustomobject]@{ Instance=$Instance; Controls=$controls; StatusLabel=$StatusLabel }
        $btnSave.Add_Click({
            param($sender,$eventArgs)
            $st = $sender.Tag
            try {
                Save-UGSMGameEnshroudedInstanceEditor -Instance $st.Instance -EditorState $st | Out-Null
                if ($st.StatusLabel) { $st.StatusLabel.Text = 'Enshrouded settings saved.' }
            } catch {
                if ($st.StatusLabel) { $st.StatusLabel.Text = 'Enshrouded save failed: ' + $_.Exception.Message }
                Write-UGSMGameEnshroudedLog -Level 'ERROR' -Message 'Enshrouded editor save failed.' -Exception $_.Exception
            }
        })
        $HostPanel.Controls.Add($btnSave)
        $btnSave.BringToFront()
        if ($StatusLabel) { $StatusLabel.Text = 'Enshrouded native editor loaded.' }
        return [pscustomobject]@{ Success=$true; Instance=$Instance; Controls=$controls; SettingsPath=$settingsPath }
    } catch {
        Write-UGSMGameEnshroudedLog -Level 'ERROR' -Message 'Enshrouded editor creation failed.' -Exception $_.Exception
        throw
    } finally {
        $HostPanel.ResumeLayout($true)
    }
}


function Get-UGSMGameEnshroudedInstanceId {
    param([AllowNull()][object]$Instance)
    if ($Instance -and $Instance.PSObject.Properties['Id'] -and -not [string]::IsNullOrWhiteSpace([string]$Instance.Id)) { return [string]$Instance.Id }
    if ($Instance -and $Instance.PSObject.Properties['Name'] -and -not [string]::IsNullOrWhiteSpace([string]$Instance.Name)) { return ('Enshrouded_' + ([string]$Instance.Name -replace '[^A-Za-z0-9_.-]', '_')) }
    return 'Enshrouded_Unknown'
}

function Set-UGSMGameEnshroudedInstanceState {
    [CmdletBinding()]
    param([Parameter(Mandatory)][object]$Instance,[string]$Status,[Nullable[int]]$ServerProcessId)
    if (-not [string]::IsNullOrWhiteSpace($Status)) {
        if ($Instance.PSObject.Properties['Status']) { $Instance.Status = $Status } else { Add-Member -InputObject $Instance -MemberType NoteProperty -Name Status -Value $Status -Force }
    }
    if ($null -ne $ServerProcessId) {
        if ($Instance.PSObject.Properties['Pid']) { $Instance.Pid = [int]$ServerProcessId } else { Add-Member -InputObject $Instance -MemberType NoteProperty -Name Pid -Value ([int]$ServerProcessId) -Force }
        if ($Instance.PSObject.Properties['ProcessId']) { $Instance.ProcessId = [int]$ServerProcessId } else { Add-Member -InputObject $Instance -MemberType NoteProperty -Name ProcessId -Value ([int]$ServerProcessId) -Force }
    }
    elseif ($Status -eq 'Stopped') {
        if ($Instance.PSObject.Properties['Pid']) { $Instance.Pid = $null }
        if ($Instance.PSObject.Properties['ProcessId']) { $Instance.ProcessId = $null }
    }
    foreach ($commandName in @('Save-UGSMInstance','Update-UGSMInstance','Set-UGSMInstance')) {
        if (Get-Command -Name $commandName -ErrorAction SilentlyContinue) {
            try { & $commandName -Instance $Instance | Out-Null; break } catch {}
        }
    }
}

function Get-UGSMGameEnshroudedRuntimeSettingsPath {
    [CmdletBinding()]
    param([Parameter(Mandatory)][object]$Instance,[Parameter(Mandatory)][string]$InstallPath)
    return (Join-Path $InstallPath 'enshrouded_server.json')
}

function Write-UGSMGameEnshroudedUtf8NoBomFile {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Path,[AllowNull()][string]$Text)
    $parent = Split-Path -Parent $Path
    if (-not [string]::IsNullOrWhiteSpace($parent) -and -not (Test-Path -LiteralPath $parent -PathType Container)) {
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
    }
    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($Path, [string]$Text, $utf8NoBom)
}

function Ensure-UGSMGameEnshroudedSteamAppIdFile {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$InstallPath)
    try {
        if (-not (Test-Path -LiteralPath $InstallPath -PathType Container)) { return }
        $appidPath = Join-Path $InstallPath 'steam_appid.txt'
        $desired = '1203620'
        $current = ''
        if (Test-Path -LiteralPath $appidPath -PathType Leaf) {
            try { $current = [string](Get-Content -LiteralPath $appidPath -Raw -ErrorAction Stop).Trim() } catch { $current = '' }
        }
        if ($current -ne $desired) {
            Write-UGSMGameEnshroudedUtf8NoBomFile -Path $appidPath -Text $desired
            Write-UGSMGameEnshroudedLog -Level 'INFO' -Message 'Ensured Enshrouded steam_appid.txt exists.'
        }
    } catch {
        Write-UGSMGameEnshroudedLog -Level 'WARN' -Message 'Could not ensure Enshrouded steam_appid.txt.' -Exception $_.Exception
    }
}

function Get-UGSMGameEnshroudedTailText {
    [CmdletBinding()]
    param([string]$Path,[int]$LineCount=30)
    if ([string]::IsNullOrWhiteSpace($Path) -or -not (Test-Path -LiteralPath $Path -PathType Leaf)) { return '' }
    try { return ((Get-Content -LiteralPath $Path -Tail $LineCount -ErrorAction Stop) -join [Environment]::NewLine) } catch { return '' }
}


function Get-UGSMGameEnshroudedLocalLogRoot {
    [CmdletBinding()]
    param([Parameter(Mandatory)][object]$Instance)
    $name = Get-UGSMGameEnshroudedProfileName -Instance $Instance
    if ([string]::IsNullOrWhiteSpace($name)) { $name = 'Unknown' }
    $safeName = [Regex]::Replace([string]$name, '[^A-Za-z0-9_.-]', '_')
    $base = $env:LOCALAPPDATA
    if ([string]::IsNullOrWhiteSpace($base)) { $base = Join-Path $env:USERPROFILE 'AppData\Local' }
    return (Join-Path (Join-Path (Join-Path $base 'UGSM') 'Logs') (Join-Path 'Enshrouded' $safeName))
}

function Prepare-UGSMGameEnshroudedRuntimeConfig {
    [CmdletBinding()]
    param([Parameter(Mandatory)][object]$Instance,[Parameter(Mandatory)][string]$InstallPath)

    $profileRoot = Get-UGSMGameEnshroudedProfileRoot -Instance $Instance
    if (-not (Test-Path -LiteralPath $profileRoot -PathType Container)) { New-Item -ItemType Directory -Path $profileRoot -Force | Out-Null }

    $settings = Get-UGSMGameEnshroudedServerSettings -Instance $Instance
    $settings = Ensure-UGSMGameEnshroudedJsonArrays -Settings $settings

    $saveRoot = Join-Path $profileRoot 'SaveGame'
    $logRoot  = Get-UGSMGameEnshroudedLocalLogRoot -Instance $Instance
    foreach ($dir in @($saveRoot,$logRoot)) { if (-not (Test-Path -LiteralPath $dir -PathType Container)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null } }

    if ($settings.PSObject.Properties['saveDirectory']) { $settings.saveDirectory = $saveRoot } else { $settings | Add-Member -NotePropertyName 'saveDirectory' -NotePropertyValue $saveRoot -Force }
    if ($settings.PSObject.Properties['logDirectory']) { $settings.logDirectory = $logRoot } else { $settings | Add-Member -NotePropertyName 'logDirectory' -NotePropertyValue $logRoot -Force }

    # Keep the profile copy in sync with the runtime-safe save/log directories.
    Save-UGSMGameEnshroudedServerSettings -Instance $Instance -Settings $settings | Out-Null

    $runtimeConfig = Get-UGSMGameEnshroudedRuntimeSettingsPath -Instance $Instance -InstallPath $InstallPath
    $jsonText = ($settings | ConvertTo-Json -Depth 40)
    Write-UGSMGameEnshroudedUtf8NoBomFile -Path $runtimeConfig -Text $jsonText

    return [pscustomobject]@{
        ProfileRoot=$profileRoot
        ProfileSettingsPath=(Get-UGSMGameEnshroudedSettingsPath -Instance $Instance)
        RuntimeSettingsPath=$runtimeConfig
        SaveRoot=$saveRoot
        LogRoot=$logRoot
    }
}

function Find-UGSMGameEnshroudedServerProcess {
    [CmdletBinding()]
    param([Nullable[int]]$ServerProcessId,[string]$InstallPath)
    try {
        if ($ServerProcessId -and [int]$ServerProcessId -gt 0) {
            $byPid = Get-CimInstance Win32_Process -Filter ('ProcessId=' + [string][int]$ServerProcessId) -ErrorAction SilentlyContinue
            if ($byPid) { return $byPid }
        }
        $items = @(Get-CimInstance Win32_Process -Filter "Name='enshrouded_server.exe'" -ErrorAction SilentlyContinue)
        if (-not [string]::IsNullOrWhiteSpace($InstallPath)) {
            $safe = [Regex]::Escape($InstallPath)
            $matched = @($items | Where-Object { ([string]$_.ExecutablePath -match $safe) -or ([string]$_.CommandLine -match $safe) })
            if ($matched.Count -gt 0) { return $matched[0] }
        }
        if ($items.Count -gt 0) { return $items[0] }
    } catch {}
    return $null
}

function Start-UGSMGameEnshroudedInstance {
    [CmdletBinding()]
    param([Parameter(Mandatory)][object]$Instance,[string]$InstallPath)

    $instanceId = Get-UGSMGameEnshroudedInstanceId -Instance $Instance
    Write-UGSMGameEnshroudedLog -Level 'INFO' -Message ('Start requested. InstanceId={0}' -f $instanceId)

    $resolved = Resolve-UGSMGameEnshroudedInstall -InstallPath $InstallPath -Instance $Instance
    if (-not $resolved -or -not [bool]$resolved.IsInstalled -or -not (Test-Path -LiteralPath ([string]$resolved.ExePath) -PathType Leaf)) {
        throw 'Enshrouded start failed: enshrouded_server.exe was not found.'
    }

    Initialize-UGSMGameEnshroudedProfile -Instance $Instance | Out-Null
    $runtime = Prepare-UGSMGameEnshroudedRuntimeConfig -Instance $Instance -InstallPath ([string]$resolved.InstallPath)

    Ensure-UGSMGameEnshroudedSteamAppIdFile -InstallPath ([string]$resolved.InstallPath)

    $stdoutLog = Join-Path ([string]$runtime.LogRoot) 'server-console.log'
    $stderrLog = Join-Path ([string]$runtime.LogRoot) 'server-error.log'
    foreach ($logFile in @($stdoutLog,$stderrLog)) {
        try { if (-not (Test-Path -LiteralPath $logFile -PathType Leaf)) { Write-UGSMGameEnshroudedUtf8NoBomFile -Path $logFile -Text '' } } catch {}
    }

    Write-UGSMGameEnshroudedLog -Level 'INFO' -Message ('Launching Enshrouded server. InstanceId={0}; RuntimeConfig={1}; LogRoot={2}; Console=Visible' -f $instanceId, [string]$runtime.RuntimeSettingsPath, [string]$runtime.LogRoot)

    # Keep the dedicated server console visible. Most UGSM games launch with a visible
    # server window so the owner can see live server activity. Do not redirect stdout
    # here, because redirecting produces a blank console window and moves live output
    # into server-console.log instead. Enshrouded still writes its own server log under
    # the profile/UGSM diagnostics log directory through logDirectory in enshrouded_server.json.
    $startArgs = @{
        FilePath = [string]$resolved.ExePath
        WorkingDirectory = [string]$resolved.InstallPath
        PassThru = $true
        WindowStyle = 'Normal'
    }
    $proc = Start-Process @startArgs
    if (-not $proc -or -not $proc.Id) { throw 'Enshrouded start failed: process did not start.' }

    Start-Sleep -Seconds 12
    try { $proc.Refresh() } catch {}

    # Some dedicated servers briefly spawn/replace their launching process.
    # If the returned process exited, look again by executable path before failing.
    $actualProcess = $null
    if (-not $proc.HasExited) {
        $actualProcess = $proc
    } else {
        $found = Find-UGSMGameEnshroudedServerProcess -ServerProcessId $null -InstallPath ([string]$resolved.InstallPath)
        if ($found) {
            try { $actualProcess = Get-Process -Id ([int]$found.ProcessId) -ErrorAction SilentlyContinue } catch { $actualProcess = $null }
        }
    }

    if (-not $actualProcess) {
        $exitCode = $null
        try { $exitCode = $proc.ExitCode } catch {}
        $tailOut = Get-UGSMGameEnshroudedTailText -Path $stdoutLog -LineCount 20
        $tailErr = Get-UGSMGameEnshroudedTailText -Path $stderrLog -LineCount 20
        $detail = ''
        if (-not [string]::IsNullOrWhiteSpace($tailErr)) { $detail = ' Last error log lines: ' + ($tailErr -replace '[\r\n]+',' | ') }
        elseif (-not [string]::IsNullOrWhiteSpace($tailOut)) { $detail = ' Last console log lines: ' + ($tailOut -replace '[\r\n]+',' | ') }
        throw ('Enshrouded start failed: process exited immediately. ExitCode={0}. Check profile logs under {1}.{2}' -f $exitCode, [string]$runtime.LogRoot, $detail)
    }

    $pidValue = [int]$actualProcess.Id
    Set-UGSMGameEnshroudedInstanceState -Instance $Instance -Status 'Running' -ServerProcessId $pidValue

    if (Get-Command -Name Send-UGSMInstanceDiscordNotification -ErrorAction SilentlyContinue) {
        try { Send-UGSMInstanceDiscordNotification -Instance $Instance -Event 'Start' | Out-Null } catch { Write-UGSMGameEnshroudedLog -Level 'WARN' -Message 'Discord start notification failed.' -Exception $_.Exception }
    }

    Write-UGSMGameEnshroudedLog -Level 'INFO' -Message ('Start completed. InstanceId={0}; Pid={1}' -f $instanceId,$pidValue)
    return [pscustomobject]@{ Success=$true; Instance=$Instance; Status='Running'; Pid=$pidValue; Runtime=$runtime }
}

function Stop-UGSMGameEnshroudedInstance {
    [CmdletBinding()]
    param([Parameter(Mandatory)][object]$Instance,[string]$InstallPath)

    $instanceId = Get-UGSMGameEnshroudedInstanceId -Instance $Instance
    Write-UGSMGameEnshroudedLog -Level 'INFO' -Message ('Stop requested. InstanceId={0}' -f $instanceId)

    $pidValue = $null
    if ($Instance.PSObject.Properties['Pid'] -and $Instance.Pid) { try { $pidValue = [int]$Instance.Pid } catch {} }
    if ((-not $pidValue) -and $Instance.PSObject.Properties['ProcessId'] -and $Instance.ProcessId) { try { $pidValue = [int]$Instance.ProcessId } catch {} }

    $resolved = Resolve-UGSMGameEnshroudedInstall -InstallPath $InstallPath -Instance $Instance
    $procInfo = Find-UGSMGameEnshroudedServerProcess -ServerProcessId $pidValue -InstallPath ([string]$resolved.InstallPath)
    if (-not $procInfo) {
        Set-UGSMGameEnshroudedInstanceState -Instance $Instance -Status 'Stopped' -ServerProcessId $null
        Write-UGSMGameEnshroudedLog -Level 'INFO' -Message ('Stop completed; no running process found. InstanceId={0}' -f $instanceId)
        return [pscustomobject]@{ Success=$true; Instance=$Instance; Status='Stopped'; WasRunning=$false }
    }

    $targetPid = [int]$procInfo.ProcessId
    $stopped = $false
    try {
        $p = Get-Process -Id $targetPid -ErrorAction Stop
        try { if ($p.CloseMainWindow()) { $p.WaitForExit(15000) } } catch {}
        try { $p.Refresh() } catch {}
        if (-not $p.HasExited) { Stop-Process -Id $targetPid -Force -ErrorAction Stop; Start-Sleep -Seconds 2 }
        $stopped = $true
    }
    catch {
        Write-UGSMGameEnshroudedLog -Level 'WARN' -Message ('Stop process action failed. InstanceId={0}; Pid={1}' -f $instanceId,$targetPid) -Exception $_.Exception
    }

    Set-UGSMGameEnshroudedInstanceState -Instance $Instance -Status 'Stopped' -ServerProcessId $null

    if (Get-Command -Name Send-UGSMInstanceDiscordNotification -ErrorAction SilentlyContinue) {
        try { Send-UGSMInstanceDiscordNotification -Instance $Instance -Event 'Stop' | Out-Null } catch { Write-UGSMGameEnshroudedLog -Level 'WARN' -Message 'Discord stop notification failed.' -Exception $_.Exception }
    }

    Write-UGSMGameEnshroudedLog -Level 'INFO' -Message ('Stop completed. InstanceId={0}; Pid={1}; Stopped={2}' -f $instanceId,$targetPid,$stopped)
    return [pscustomobject]@{ Success=$true; Instance=$Instance; Status='Stopped'; Pid=$targetPid; Stopped=$stopped }
}

function Get-UGSMGameEnshroudedMetadata {
    [pscustomobject]@{
        Id='Enshrouded'
        Name='Enshrouded'
        Category='Survival'
        Description='Enshrouded dedicated server profile, settings editor, and Discord notifications.'
        IsCustom=$false
        IsVisible=$true
        SupportTier='NativeDraft'
        SortOrder=170
        UseSteamArt=$true
        SupportsInstall=$true
        SupportsUpdate=$false
        SupportsVerify=$false
        SupportsRepair=$false
        SupportsStart=$true
        SupportsStop=$true
        SupportsMods=$false
        SupportsWorkshop=$false
        SupportsProfiles=$true
        SupportsInstanceUi=$true
        InstallProvider='SteamCMD'
        RequiresSteamLogin=$false
        SteamAppId='2278520'
        SteamStoreAppId='1203620'
        ServerExecutable='enshrouded_server.exe'
        ServerExecutableRelative='enshrouded_server.exe'
        UsesSharedBinaries=$true
        InstanceType='DedicatedServer'
        PortSchema=@()
        GameTraits=[pscustomobject]@{ UsesJsonFiles=$true; UsesWorkshopItems=$false }
        SpecialRequirements=[pscustomobject]@{ Notes=@('Native draft editor. Profiles under Profiles\Enshrouded are treated as Enshrouded-owned profiles.') }
    }
}

function Register-UGSMGameEnshroudedModule {
    try { [void](Import-UGSMGameEnshroudedBridgeProfilesIntoInstanceStore) } catch { Write-UGSMGameEnshroudedLog -Level 'WARN' -Message 'Enshrouded profile pickup failed during registration.' -Exception $_.Exception }
    $metadata = Get-UGSMGameEnshroudedMetadata
    [pscustomobject]@{
        Id='Enshrouded'
        Metadata=$metadata
        Handlers=[pscustomobject]@{
            GetMetadata='Get-UGSMGameEnshroudedMetadata'
            TestInstall='Test-UGSMGameEnshroudedInstall'
            TestInstance='Test-UGSMGameEnshroudedInstance'
            InitializeProfile='Initialize-UGSMGameEnshroudedProfile'
            Start='Start-UGSMGameEnshroudedInstance'
            Stop='Stop-UGSMGameEnshroudedInstance'
            BuildEditor='New-UGSMGameEnshroudedInstanceEditor'
            SaveEditor='Save-UGSMGameEnshroudedInstanceEditor'
            DiscoverBridgeProfiles='Get-UGSMGameEnshroudedBridgeProfiles'
            ImportBridgeProfiles='Import-UGSMGameEnshroudedBridgeProfilesIntoInstanceStore'
        }
    }
}
