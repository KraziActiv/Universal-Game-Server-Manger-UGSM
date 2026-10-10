# Valheim dedicated server module
# Supported pass: logging, lightweight profiles, start/stop, basic settings editor, Discord.

function Write-UGSMGameValheimLog {
    [CmdletBinding()]
    param(
        [ValidateSet('TRACE','DEBUG','INFO','WARN','ERROR','FATAL')]
        [string]$Level = 'INFO',
        [Parameter(Mandatory)][string]$Message,
        [AllowNull()][System.Exception]$Exception
    )

    $verboseEnabled = $false
    try { $verboseEnabled = [bool]$script:UGSM_EnableVerboseValheimLogging } catch { $verboseEnabled = $false }
    if (-not $verboseEnabled -and -not [string]::IsNullOrWhiteSpace($env:UGSM_VERBOSE_VALHEIM)) { $verboseEnabled = $true }
    if ($Level -in @('TRACE','DEBUG') -and -not $verboseEnabled) { return }

    if (Get-Command -Name Write-UGSMLog -ErrorAction SilentlyContinue) {
        if ($Exception) { Write-UGSMLog -Level $Level -Category 'Valheim' -Message $Message -Exception $Exception }
        else { Write-UGSMLog -Level $Level -Category 'Valheim' -Message $Message }
        return
    }

    if ($Exception) { Write-Warning ("[Valheim] $Message :: $($Exception.Message)") }
    else { Write-Host "[Valheim][$Level] $Message" }
}

function Get-UGSMGameValheimInstanceId {
    [CmdletBinding()]
    param([AllowNull()][object]$Instance)

    if (-not $Instance) { return '' }
    foreach ($name in @('Id','Name','ProfileName')) {
        if ($Instance.PSObject.Properties[$name] -and -not [string]::IsNullOrWhiteSpace([string]$Instance.$name)) {
            return [string]$Instance.$name
        }
    }
    return ''
}

function Get-UGSMGameValheimMetadata {
    [CmdletBinding()]
    param()

    return [pscustomobject]@{
        Id                       = 'Valheim'
        Name                     = 'Valheim'
        Category                 = 'Survival'
        Description              = 'Valheim dedicated server integration.'
        IsCustom                 = $false
        SupportTier              = 'Basic'
        SortOrder                = 80
        IsVisible                = $true
        SupportedTabs            = @('Home','Games','Instances','Analytics','Tasks','About','Settings')
        UseSteamArt              = $true
        SupportsInstall          = $true
        SupportsUpdate           = $true
        SupportsVerify           = $true
        SupportsRepair           = $true
        SupportsStart            = $true
        SupportsStop             = $true
        SupportsMods             = $false
        SupportsWorkshop         = $false
        SupportsRcon             = $false
        SupportsBootstrap        = $false
        SupportsProfiles         = $true
        SupportsInstanceUi       = $true
        InstallProvider          = 'SteamCMD'
        RequiresSteamLogin       = $false
        SteamLoginMode           = 'Anonymous'
        SteamAppId               = '896660'
        SteamStoreAppId          = '892970'
        ServerExecutable         = 'valheim_server.exe'
        ServerExecutableRelative = 'valheim_server.exe'
        UsesSharedBinaries       = $true
        InstanceType             = 'DedicatedServer'
        ConfigRootRelative       = 'Config'
        SaveRootRelative         = 'Worlds'
        LogRootRelative          = 'Logs'
        RequiredFiles            = @('valheim_server.exe')
        InstallMarkers           = @('valheim_server.exe')
        PortSchema               = @(
            @{ Name = 'GamePort';  Protocol = 'UDP'; PreferredStart = 2456 }
            @{ Name = 'QueryPort'; Protocol = 'UDP'; PreferredStart = 2457 }
            @{ Name = 'SteamPort'; Protocol = 'UDP'; PreferredStart = 2458 }
        )
        GameTraits               = [pscustomobject]@{
            UsesIniFiles          = $false
            UsesJsonFiles         = $true
            UsesXmlFiles          = $false
            UsesSqlite            = $false
            UsesProfileSync       = $false
            UsesPluginFramework   = $false
            UsesZipMods           = $false
            UsesFolderCopyMods    = $false
            UsesFileMergeWorkflow = $false
            UsesMissionFiles      = $false
            UsesWorkshopItems     = $false
        }
        SpecialRequirements      = [pscustomobject]@{
            Notes = @(
                'Valheim does not use Steam Workshop server mods in this module pass.',
                'World data is stored per profile; binaries remain shared in the Steam install folder.'
            )
        }
    }
}

function Get-UGSMGameValheimAppDataRoot {
    [CmdletBinding()]
    param()
    if (Get-Command -Name Get-UGSMAppDataRoot -ErrorAction SilentlyContinue) { return [string](Get-UGSMAppDataRoot) }
    return (Join-Path $env:LOCALAPPDATA 'UGSM')
}

function Get-UGSMGameValheimProfileBaseRoot {
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
        $probe = Get-UGSMDefaultInstanceProfilePath -GameId 'Valheim' -Name '_probe_'
        if (-not [string]::IsNullOrWhiteSpace([string]$probe)) { return (Split-Path -Parent (Split-Path -Parent $probe)) }
    }
    return (Join-Path (Get-UGSMGameValheimAppDataRoot) 'Profiles')
}

function ConvertTo-UGSMGameValheimArgumentString {
    [CmdletBinding()]
    param([AllowNull()][object[]]$Arguments)

    $parts = New-Object System.Collections.Generic.List[string]
    foreach ($arg in @($Arguments)) {
        if ($null -eq $arg) { continue }
        $text = [string]$arg
        if ($text.Length -eq 0) { continue }
        if ($text -match '[\s"`]') {
            $escaped = $text -replace '"','\"'
            [void]$parts.Add('"' + $escaped + '"')
        } else {
            [void]$parts.Add($text)
        }
    }
    return ($parts -join ' ')
}

function Get-UGSMGameValheimProfileName {
    [CmdletBinding()]
    param([Parameter(Mandatory)][object]$Instance)
    foreach ($name in @('Name','Id','ProfileName')) {
        if ($Instance.PSObject.Properties[$name] -and -not [string]::IsNullOrWhiteSpace([string]$Instance.$name)) { return [string]$Instance.$name }
    }
    return 'ValheimServer'
}

function Get-UGSMGameValheimProfileRoot {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$ProfileName)
    return (Join-Path (Join-Path (Get-UGSMGameValheimProfileBaseRoot) 'Valheim') $ProfileName)
}

function Get-UGSMGameValheimInstallPath {
    [CmdletBinding()]
    param([AllowNull()][object]$Instance, [string]$InstallPath)

    if (-not [string]::IsNullOrWhiteSpace($InstallPath)) { return $InstallPath }
    if ($Instance -and $Instance.PSObject.Properties['InstallPath'] -and -not [string]::IsNullOrWhiteSpace([string]$Instance.InstallPath)) { return [string]$Instance.InstallPath }

    $settings = $null
    if (Get-Command -Name Get-UGSMGlobalSettings -ErrorAction SilentlyContinue) {
        try { $settings = Get-UGSMGlobalSettings -CreateIfMissing } catch { $settings = $null }
    }
    if ($settings) {
        foreach ($propName in @('SteamLibraryRoot','SteamRoot','SteamCmdRoot','InstallRoot')) {
            if ($settings.PSObject.Properties[$propName] -and -not [string]::IsNullOrWhiteSpace([string]$settings.$propName)) {
                $root = [string]$settings.$propName
                $candidate = Join-Path $root 'steamapps\common\Valheim dedicated server'
                return $candidate
            }
        }
    }
    return (Join-Path (Get-UGSMGameValheimAppDataRoot) 'Servers\Valheim')
}

function Get-UGSMGameValheimInstallDefinition {
    [CmdletBinding()]
    param([string]$InstallPath, [object]$Instance)

    $InstallPath = Get-UGSMGameValheimInstallPath -Instance $Instance -InstallPath $InstallPath
    $meta = Get-UGSMGameValheimMetadata
    return [pscustomobject]@{
        GameId               = $meta.Id
        GameName             = $meta.Name
        SteamAppId           = $meta.SteamAppId
        InstallPath          = $InstallPath
        ServerExecutablePath = Join-Path $InstallPath $meta.ServerExecutableRelative
        RequiredFiles        = @($meta.RequiredFiles)
        InstallMarkers       = @($meta.InstallMarkers)
        ConfigRootPath       = Join-Path $InstallPath 'Config'
        SaveRootPath         = Join-Path $InstallPath 'Worlds'
        LogRootPath          = Join-Path $InstallPath 'Logs'
    }
}

function Get-UGSMGameValheimProfilePaths {
    [CmdletBinding()]
    param([Parameter(Mandatory)][object]$Instance)

    $profileName = Get-UGSMGameValheimProfileName -Instance $Instance
    $profileRoot = if ($Instance.PSObject.Properties['ProfilePath'] -and -not [string]::IsNullOrWhiteSpace([string]$Instance.ProfilePath)) { [string]$Instance.ProfilePath } else { Get-UGSMGameValheimProfileRoot -ProfileName $profileName }
    $configRoot = Join-Path $profileRoot 'Config'
    $worldRoot = Join-Path $profileRoot 'Worlds'
    $logRoot = Join-Path $profileRoot 'Logs'
    $settingsPath = Join-Path $configRoot 'UGSM_ValheimSettings.json'
    $centralLogRoot = Join-Path (Join-Path (Get-UGSMGameValheimAppDataRoot) 'Logs\Valheim') $profileName

    return [pscustomobject]@{
        ProfileName     = $profileName
        ProfileRoot     = $profileRoot
        ConfigRoot      = $configRoot
        WorldRoot       = $worldRoot
        LogRoot         = $logRoot
        SettingsPath    = $settingsPath
        CentralLogRoot  = $centralLogRoot
    }
}

function Get-UGSMGameValheimAssignedPort {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$Instance,
        [Parameter(Mandatory)][string]$Name,
        [int]$Default
    )

    if ($Instance.PSObject.Properties[$Name]) {
        $value = $Instance.$Name
        if ($value -as [int]) { return [int]$value }
    }
    if ($Instance.PSObject.Properties['Ports'] -and $null -ne $Instance.Ports) {
        $ports = $Instance.Ports
        if ($ports -is [hashtable] -and $ports.ContainsKey($Name)) {
            $value = $ports[$Name]
            if ($value -as [int]) { return [int]$value }
        }
        if ($ports.PSObject.Properties[$Name]) {
            $value = $ports.$Name
            if ($value -as [int]) { return [int]$value }
        }
        foreach ($entry in @($ports)) {
            if ($entry -and $entry.PSObject.Properties['Name'] -and [string]$entry.Name -eq $Name -and $entry.PSObject.Properties['Port']) {
                $value = $entry.Port
                if ($value -as [int]) { return [int]$value }
            }
        }
    }

    if (Get-Command -Name Get-UGSMPortAssignments -ErrorAction SilentlyContinue) {
        try {
            $instanceId = Get-UGSMGameValheimInstanceId -Instance $Instance
            $assignments = @(Get-UGSMPortAssignments)
            foreach ($assignment in $assignments) {
                if ($assignment.InstanceId -eq $instanceId -and $assignment.PSObject.Properties['Ports']) {
                    $ports = $assignment.Ports
                    if ($ports.PSObject.Properties[$Name]) {
                        $value = $ports.$Name
                        if ($value -as [int]) { return [int]$value }
                    }
                }
            }
        } catch {}
    }

    return $Default
}

function Get-UGSMGameValheimDefaultSettings {
    [CmdletBinding()]
    param([Parameter(Mandatory)][object]$Instance)

    $profileName = Get-UGSMGameValheimProfileName -Instance $Instance
    $gamePort = Get-UGSMGameValheimAssignedPort -Instance $Instance -Name 'GamePort' -Default 2456
    $queryPort = Get-UGSMGameValheimAssignedPort -Instance $Instance -Name 'QueryPort' -Default ($gamePort + 1)
    $steamPort = Get-UGSMGameValheimAssignedPort -Instance $Instance -Name 'SteamPort' -Default ($gamePort + 2)

    return [ordered]@{
        ServerName       = $profileName
        WorldName        = $profileName
        Password         = 'changeme'
        GamePort         = $gamePort
        QueryPort        = $queryPort
        SteamPort        = $steamPort
        Public           = $true
        Crossplay        = $false
        Preset           = 'normal'
        ModifierList     = ''
        SaveInterval     = 1800
        Backups          = 4
        BackupShort      = 7200
        BackupLong       = 43200
    }
}

function Get-UGSMGameValheimSettings {
    [CmdletBinding()]
    param([Parameter(Mandatory)][object]$Instance)

    $paths = Get-UGSMGameValheimProfilePaths -Instance $Instance
    $defaults = Get-UGSMGameValheimDefaultSettings -Instance $Instance
    $settings = [ordered]@{}
    foreach ($key in $defaults.Keys) { $settings[$key] = $defaults[$key] }

    if (Test-Path -LiteralPath $paths.SettingsPath) {
        try {
            $json = Get-Content -LiteralPath $paths.SettingsPath -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
            foreach ($prop in $json.PSObject.Properties) { $settings[$prop.Name] = $prop.Value }
        } catch {
            Write-UGSMGameValheimLog -Level 'WARN' -Message ("Failed to read Valheim settings. Path=$($paths.SettingsPath)") -Exception $_.Exception
        }
    }

    $settings['GamePort'] = Get-UGSMGameValheimAssignedPort -Instance $Instance -Name 'GamePort' -Default ([int]$settings['GamePort'])
    $settings['QueryPort'] = Get-UGSMGameValheimAssignedPort -Instance $Instance -Name 'QueryPort' -Default ([int]$settings['QueryPort'])
    $settings['SteamPort'] = Get-UGSMGameValheimAssignedPort -Instance $Instance -Name 'SteamPort' -Default ([int]$settings['SteamPort'])

    return [pscustomobject]$settings
}

function Save-UGSMGameValheimSettings {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$Instance,
        [Parameter(Mandatory)][object]$Settings
    )

    $paths = Get-UGSMGameValheimProfilePaths -Instance $Instance
    New-Item -ItemType Directory -Force -Path $paths.ConfigRoot, $paths.WorldRoot, $paths.LogRoot, $paths.CentralLogRoot | Out-Null
    $Settings | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $paths.SettingsPath -Encoding UTF8
    Write-UGSMGameValheimLog -Level 'INFO' -Message ("Settings saved. InstanceId=$(Get-UGSMGameValheimInstanceId -Instance $Instance); Path=$($paths.SettingsPath)")
}

function Test-UGSMGameValheimInstall {
    [CmdletBinding()]
    param([string]$InstallPath, [object]$Instance)

    $definition = Get-UGSMGameValheimInstallDefinition -InstallPath $InstallPath -Instance $Instance
    $exists = Test-Path -LiteralPath $definition.ServerExecutablePath -PathType Leaf
    return [pscustomobject]@{
        GameId        = 'Valheim'
        IsInstalled   = [bool]$exists
        InstallPath   = $definition.InstallPath
        Executable    = $definition.ServerExecutablePath
        MissingFiles  = if ($exists) { @() } else { @($definition.ServerExecutablePath) }
    }
}

function Test-UGSMGameValheimInstance {
    [CmdletBinding()]
    param([Parameter(Mandatory)][object]$Instance)

    $paths = Get-UGSMGameValheimProfilePaths -Instance $Instance
    return [pscustomobject]@{
        GameId        = 'Valheim'
        InstanceId    = Get-UGSMGameValheimInstanceId -Instance $Instance
        Exists        = (Test-Path -LiteralPath $paths.ProfileRoot)
        ProfilePath   = $paths.ProfileRoot
        ConfigPath    = $paths.SettingsPath
        HasSettings   = (Test-Path -LiteralPath $paths.SettingsPath)
    }
}

function Ensure-UGSMGameValheimTemplate {
    [CmdletBinding()]
    param(
        [AllowNull()][object]$Instance,
        [string]$InstallPath,
        [int]$BootstrapSeconds = 0,
        [switch]$Force,
        [switch]$ForceRefresh
    )

    $instanceId = Get-UGSMGameValheimInstanceId -Instance $Instance
    Write-UGSMGameValheimLog -Level 'INFO' -Message ("Template ensure requested. InstanceId=$instanceId; Force=$([bool]$Force); ForceRefresh=$([bool]$ForceRefresh)")
    if ($Instance) { Initialize-UGSMGameValheimProfile -Instance $Instance -InstallPath $InstallPath -BootstrapSeconds $BootstrapSeconds -Force:$Force | Out-Null }
    return [pscustomobject]@{ Success = $true; InstanceId = $instanceId }
}

function Initialize-UGSMGameValheimProfile {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$Instance,
        [string]$InstallPath,
        [int]$BootstrapSeconds = 0,
        [switch]$Force
    )

    $instanceId = Get-UGSMGameValheimInstanceId -Instance $Instance
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    Write-UGSMGameValheimLog -Level 'INFO' -Message ("Profile initialization requested. InstanceId=$instanceId; Force=$([bool]$Force)")

    $paths = Get-UGSMGameValheimProfilePaths -Instance $Instance
    New-Item -ItemType Directory -Force -Path $paths.ProfileRoot, $paths.ConfigRoot, $paths.WorldRoot, $paths.LogRoot, $paths.CentralLogRoot | Out-Null

    if ($Instance.PSObject.Properties['ProfilePath']) { $Instance.ProfilePath = $paths.ProfileRoot }
    else { Add-Member -InputObject $Instance -MemberType NoteProperty -Name ProfilePath -Value $paths.ProfileRoot -Force }

    if ($Instance.PSObject.Properties['InstallPath'] -and -not [string]::IsNullOrWhiteSpace($InstallPath)) { $Instance.InstallPath = $InstallPath }
    elseif (-not $Instance.PSObject.Properties['InstallPath'] -and -not [string]::IsNullOrWhiteSpace($InstallPath)) { Add-Member -InputObject $Instance -MemberType NoteProperty -Name InstallPath -Value $InstallPath -Force }

    if ($Force -or -not (Test-Path -LiteralPath $paths.SettingsPath)) {
        $settings = Get-UGSMGameValheimDefaultSettings -Instance $Instance
        Save-UGSMGameValheimSettings -Instance $Instance -Settings ([pscustomobject]$settings)
    } else {
        # still sync assigned ports into the model if port allocation changed
        $settings = Get-UGSMGameValheimSettings -Instance $Instance
        Save-UGSMGameValheimSettings -Instance $Instance -Settings $settings
    }

    $sw.Stop()
    Write-UGSMGameValheimLog -Level 'INFO' -Message ("Profile initialized. InstanceId=$instanceId; ProfilePath=$($paths.ProfileRoot); DurationMs=$($sw.ElapsedMilliseconds)")
    return [pscustomobject]@{ Success = $true; ProfilePath = $paths.ProfileRoot; ConfigPath = $paths.SettingsPath }
}

function Start-UGSMGameValheimInstance {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$Instance,
        [string]$InstallPath
    )

    $instanceId = Get-UGSMGameValheimInstanceId -Instance $Instance
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    Write-UGSMGameValheimLog -Level 'INFO' -Message ("Start requested. InstanceId=$instanceId")

    $definition = Get-UGSMGameValheimInstallDefinition -InstallPath $InstallPath -Instance $Instance
    if (-not (Test-Path -LiteralPath $definition.ServerExecutablePath -PathType Leaf)) {
        throw "Valheim server executable was not found: $($definition.ServerExecutablePath)"
    }

    Initialize-UGSMGameValheimProfile -Instance $Instance -InstallPath $definition.InstallPath | Out-Null
    $paths = Get-UGSMGameValheimProfilePaths -Instance $Instance
    $settings = Get-UGSMGameValheimSettings -Instance $Instance
    Save-UGSMGameValheimSettings -Instance $Instance -Settings $settings

    $password = [string]$settings.Password
    if ([string]::IsNullOrWhiteSpace($password) -or $password.Length -lt 5) {
        Write-UGSMGameValheimLog -Level 'WARN' -Message ("Valheim server password is blank or shorter than 5 characters. InstanceId=$instanceId")
    }

    $args = New-Object System.Collections.Generic.List[string]
    [void]$args.Add('-nographics')
    [void]$args.Add('-batchmode')
    [void]$args.Add('-name')
    [void]$args.Add([string]$settings.ServerName)
    [void]$args.Add('-port')
    [void]$args.Add([string][int]$settings.GamePort)
    [void]$args.Add('-world')
    [void]$args.Add([string]$settings.WorldName)
    [void]$args.Add('-password')
    [void]$args.Add([string]$settings.Password)
    [void]$args.Add('-savedir')
    [void]$args.Add([string]$paths.WorldRoot)
    [void]$args.Add('-public')
    [void]$args.Add($(if ([bool]$settings.Public) { '1' } else { '0' }))
    if ([bool]$settings.Crossplay) { [void]$args.Add('-crossplay') }
    if (-not [string]::IsNullOrWhiteSpace([string]$settings.Preset) -and [string]$settings.Preset -ne 'normal') {
        [void]$args.Add('-preset')
        [void]$args.Add([string]$settings.Preset)
    }
    if (-not [string]::IsNullOrWhiteSpace([string]$settings.ModifierList)) {
        [void]$args.Add('-modifier')
        [void]$args.Add([string]$settings.ModifierList)
    }
    if ([int]$settings.SaveInterval -gt 0) { [void]$args.Add('-saveinterval'); [void]$args.Add([string][int]$settings.SaveInterval) }
    if ([int]$settings.Backups -gt 0) { [void]$args.Add('-backups'); [void]$args.Add([string][int]$settings.Backups) }
    if ([int]$settings.BackupShort -gt 0) { [void]$args.Add('-backupshort'); [void]$args.Add([string][int]$settings.BackupShort) }
    if ([int]$settings.BackupLong -gt 0) { [void]$args.Add('-backuplong'); [void]$args.Add([string][int]$settings.BackupLong) }

    $argString = ConvertTo-UGSMGameValheimArgumentString -Arguments $args.ToArray()
    $safeArgString = $argString -replace '(-password\s+)"?[^"\s]+"?', '$1<redacted>'
    Write-UGSMGameValheimLog -Level 'INFO' -Message ("Launching process. InstanceId=$instanceId; Exe=$($definition.ServerExecutablePath); GamePort=$($settings.GamePort); Args=$safeArgString")

    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $definition.ServerExecutablePath
    $psi.WorkingDirectory = $definition.InstallPath
    $psi.Arguments = $argString
    $psi.UseShellExecute = $true

    $process = [System.Diagnostics.Process]::Start($psi)
    if (-not $process) { throw 'Valheim process failed to start.' }

    Start-Sleep -Seconds 2
    try { $process.Refresh() } catch {}
    if ($process.HasExited) {
        throw "Valheim process exited immediately with code $($process.ExitCode)."
    }

    if ($Instance.PSObject.Properties['ProcessId']) { $Instance.ProcessId = [int]$process.Id }
    else { Add-Member -InputObject $Instance -MemberType NoteProperty -Name ProcessId -Value ([int]$process.Id) -Force }
    if ($Instance.PSObject.Properties['Status']) { $Instance.Status = 'Running' }
    else { Add-Member -InputObject $Instance -MemberType NoteProperty -Name Status -Value 'Running' -Force }

    if (Get-Command -Name Send-UGSMInstanceDiscordNotification -ErrorAction SilentlyContinue) {
        try { Send-UGSMInstanceDiscordNotification -Instance $Instance -Event 'Start' | Out-Null } catch { Write-UGSMGameValheimLog -Level 'WARN' -Message ("Discord start notification failed. InstanceId=$instanceId") -Exception $_.Exception }
    }

    $sw.Stop()
    Write-UGSMGameValheimLog -Level 'INFO' -Message ("Start completed. InstanceId=$instanceId; Pid=$($process.Id); DurationMs=$($sw.ElapsedMilliseconds)")
    return [pscustomobject]@{ Success = $true; Status = 'Running'; ProcessId = [int]$process.Id; Pid = [int]$process.Id }
}

function Stop-UGSMGameValheimInstance {
    [CmdletBinding()]
    param([Parameter(Mandatory)][object]$Instance)

    $instanceId = Get-UGSMGameValheimInstanceId -Instance $Instance
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    $processId = 0
    if ($Instance.PSObject.Properties['ProcessId'] -and ($Instance.ProcessId -as [int])) { $processId = [int]$Instance.ProcessId }
    Write-UGSMGameValheimLog -Level 'INFO' -Message ("Stop requested. InstanceId=$instanceId; Pid=$processId")

    $stopped = $false
    if ($processId -gt 0) {
        try {
            $proc = Get-Process -Id $processId -ErrorAction Stop
            try {
                if ($proc.CloseMainWindow()) {
                    Write-UGSMGameValheimLog -Level 'DEBUG' -Message ("CloseMainWindow sent. InstanceId=$instanceId; Pid=$processId")
                    $stopped = $proc.WaitForExit(30000)
                }
            } catch {}
            if (-not $stopped) {
                Write-UGSMGameValheimLog -Level 'WARN' -Message ("Valheim process did not exit from CloseMainWindow; forcing stop. InstanceId=$instanceId; Pid=$processId")
                Stop-Process -Id $processId -Force -ErrorAction Stop
                $stopped = $true
            }
        } catch [System.ArgumentException] {
            $stopped = $true
        } catch {
            Write-UGSMGameValheimLog -Level 'ERROR' -Message ("Stop failed. InstanceId=$instanceId; Pid=$processId") -Exception $_.Exception
            throw
        }
    } else {
        Write-UGSMGameValheimLog -Level 'WARN' -Message ("Stop requested with no process id. InstanceId=$instanceId")
    }

    if ($Instance.PSObject.Properties['Status']) { $Instance.Status = 'Stopped' }
    else { Add-Member -InputObject $Instance -MemberType NoteProperty -Name Status -Value 'Stopped' -Force }
    if ($Instance.PSObject.Properties['ProcessId']) { $Instance.ProcessId = $null }

    if (Get-Command -Name Send-UGSMInstanceDiscordNotification -ErrorAction SilentlyContinue) {
        try { Send-UGSMInstanceDiscordNotification -Instance $Instance -Event 'Stop' | Out-Null } catch { Write-UGSMGameValheimLog -Level 'WARN' -Message ("Discord stop notification failed. InstanceId=$instanceId") -Exception $_.Exception }
    }

    $sw.Stop()
    Write-UGSMGameValheimLog -Level 'INFO' -Message ("Stop completed. InstanceId=$instanceId; Stopped=$stopped; DurationMs=$($sw.ElapsedMilliseconds)")
    return [pscustomobject]@{ Success = $true; Status = 'Stopped'; Stopped = $stopped }
}

function Get-UGSMGameValheimColor {
    [CmdletBinding()]
    param([object]$Theme, [string]$Name, [System.Drawing.Color]$Fallback)

    try {
        if ($Theme -and $Theme.PSObject.Properties[$Name] -and $Theme.$Name) { return [System.Drawing.Color]$Theme.$Name }
    } catch {}
    $globalNameMap = @{
        Background = 'UGSM_ColorBackground'
        Surface    = 'UGSM_ColorSurface'
        Panel      = 'UGSM_ColorPanel'
        Text       = 'UGSM_ColorText'
        Muted      = 'UGSM_ColorTextMuted'
        Border     = 'UGSM_ColorBorder'
        Accent     = 'UGSM_ColorAccent'
        Input      = 'UGSM_ColorInputBackground'
        Button     = 'UGSM_ColorNeutral'
    }
    if ($globalNameMap.ContainsKey($Name)) {
        $varName = $globalNameMap[$Name]
        try {
            $var = Get-Variable -Name $varName -Scope Global -ErrorAction SilentlyContinue
            if ($var -and $var.Value) { return [System.Drawing.Color]$var.Value }
        } catch {}
    }
    return $Fallback
}

function New-UGSMGameValheimLabel {
    param([string]$Text, [object]$Theme)
    $label = New-Object System.Windows.Forms.Label
    $label.Text = $Text
    $label.AutoSize = $false
    $label.Height = 22
    $label.Dock = 'Top'
    $label.ForeColor = Get-UGSMGameValheimColor -Theme $Theme -Name 'Muted' -Fallback ([System.Drawing.Color]::Gainsboro)
    return $label
}

function New-UGSMGameValheimTextBox {
    param([string]$Text, [object]$Theme, [switch]$Password)
    $box = New-Object System.Windows.Forms.TextBox
    $box.Text = $Text
    $box.Dock = 'Top'
    $box.Height = 24
    $box.BackColor = Get-UGSMGameValheimColor -Theme $Theme -Name 'Input' -Fallback ([System.Drawing.Color]::FromArgb(32,36,44))
    $box.ForeColor = Get-UGSMGameValheimColor -Theme $Theme -Name 'Text' -Fallback ([System.Drawing.Color]::White)
    $box.BorderStyle = 'FixedSingle'
    if ($Password) { $box.UseSystemPasswordChar = $true }
    return $box
}

function New-UGSMGameValheimCheckBox {
    param([string]$Text, [bool]$Checked, [object]$Theme)
    $box = New-Object System.Windows.Forms.CheckBox
    $box.Text = $Text
    $box.Checked = $Checked
    $box.AutoSize = $false
    $box.Height = 26
    $box.Dock = 'Top'
    $box.ForeColor = Get-UGSMGameValheimColor -Theme $Theme -Name 'Text' -Fallback ([System.Drawing.Color]::White)
    $box.BackColor = Get-UGSMGameValheimColor -Theme $Theme -Name 'Surface' -Fallback ([System.Drawing.Color]::FromArgb(24,28,34))
    return $box
}

function Add-UGSMGameValheimField {
    param(
        [Parameter(Mandatory)][System.Windows.Forms.Control]$Panel,
        [Parameter(Mandatory)][hashtable]$Controls,
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][string]$Label,
        [AllowNull()][object]$Value,
        [object]$Theme,
        [switch]$Password
    )
    $tb = New-UGSMGameValheimTextBox -Text ([string]$Value) -Theme $Theme -Password:$Password
    $lbl = New-UGSMGameValheimLabel -Text $Label -Theme $Theme
    $Panel.Controls.Add($tb)
    $Panel.Controls.Add($lbl)
    $lbl.BringToFront(); $tb.BringToFront()
    $Controls[$Name] = $tb
    return $tb
}

function Add-UGSMGameValheimCheckField {
    param(
        [Parameter(Mandatory)][System.Windows.Forms.Control]$Panel,
        [Parameter(Mandatory)][hashtable]$Controls,
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][string]$Label,
        [bool]$Value,
        [object]$Theme
    )
    $cb = New-UGSMGameValheimCheckBox -Text $Label -Checked $Value -Theme $Theme
    $Panel.Controls.Add($cb)
    $cb.BringToFront()
    $Controls[$Name] = $cb
    return $cb
}

function Save-UGSMGameValheimInstanceEditor {
    [CmdletBinding()]
    param([Parameter(Mandatory)][object]$EditorState)

    $instance = $EditorState.Instance
    $controls = $EditorState.Controls
    $instanceId = Get-UGSMGameValheimInstanceId -Instance $instance

    $settings = [ordered]@{
        ServerName   = [string]$controls.ServerName.Text
        WorldName    = [string]$controls.WorldName.Text
        Password     = [string]$controls.Password.Text
        GamePort     = [int]$controls.GamePort.Text
        QueryPort    = [int]$controls.QueryPort.Text
        SteamPort    = [int]$controls.SteamPort.Text
        Public       = [bool]$controls.Public.Checked
        Crossplay    = [bool]$controls.Crossplay.Checked
        Preset       = [string]$controls.Preset.Text
        ModifierList = [string]$controls.ModifierList.Text
        SaveInterval = [int]$controls.SaveInterval.Text
        Backups      = [int]$controls.Backups.Text
        BackupShort  = [int]$controls.BackupShort.Text
        BackupLong   = [int]$controls.BackupLong.Text
    }

    Save-UGSMGameValheimSettings -Instance $instance -Settings ([pscustomobject]$settings)

    if (Get-Command -Name Save-UGSMInstance -ErrorAction SilentlyContinue) {
        try { Save-UGSMInstance -Instance $instance | Out-Null } catch { Write-UGSMGameValheimLog -Level 'WARN' -Message ("Failed to save instance object after editor save. InstanceId=$instanceId") -Exception $_.Exception }
    }

    Write-UGSMGameValheimLog -Level 'INFO' -Message ("Editor settings saved. InstanceId=$instanceId; ServerName=$($settings.ServerName); WorldName=$($settings.WorldName); GamePort=$($settings.GamePort)")
    return [pscustomobject]@{ Success = $true; Settings = [pscustomobject]$settings }
}

function New-UGSMGameValheimInstanceEditor {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$Instance,
        [AllowNull()][object]$AppState,
        [AllowNull()][object]$Theme,
        [AllowNull()][System.Windows.Forms.Panel]$HostPanel,
        [AllowNull()][System.Windows.Forms.Label]$StatusLabel
    )

    $instanceId = Get-UGSMGameValheimInstanceId -Instance $Instance
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    Write-UGSMGameValheimLog -Level 'INFO' -Message ("Editor creation started. InstanceId=$instanceId")

    if (-not $HostPanel) {
        $HostPanel = New-Object System.Windows.Forms.Panel
        $HostPanel.Dock = 'Fill'
    }

    $HostPanel.SuspendLayout()
    try {
        $HostPanel.Controls.Clear()
        $HostPanel.BackColor = Get-UGSMGameValheimColor -Theme $Theme -Name 'Background' -Fallback ([System.Drawing.Color]::FromArgb(18,22,28))

        $settings = Get-UGSMGameValheimSettings -Instance $Instance
        $controls = @{}

        $status = New-Object System.Windows.Forms.Label
        $status.Dock = 'Bottom'
        $status.Height = 24
        $status.Text = ''
        $status.ForeColor = Get-UGSMGameValheimColor -Theme $Theme -Name 'Muted' -Fallback ([System.Drawing.Color]::Gainsboro)
        $status.BackColor = Get-UGSMGameValheimColor -Theme $Theme -Name 'Surface' -Fallback ([System.Drawing.Color]::FromArgb(24,28,34))
        $HostPanel.Controls.Add($status)

        $tabs = New-Object System.Windows.Forms.TabControl
        $tabs.Dock = 'Fill'
        $tabs.BackColor = Get-UGSMGameValheimColor -Theme $Theme -Name 'Surface' -Fallback ([System.Drawing.Color]::FromArgb(24,28,34))
        $tabs.ForeColor = Get-UGSMGameValheimColor -Theme $Theme -Name 'Text' -Fallback ([System.Drawing.Color]::White)
        $HostPanel.Controls.Add($tabs)
        $tabs.BringToFront()

        $tabServer = New-Object System.Windows.Forms.TabPage
        $tabServer.Text = 'Server'
        $tabServer.BackColor = Get-UGSMGameValheimColor -Theme $Theme -Name 'Surface' -Fallback ([System.Drawing.Color]::FromArgb(24,28,34))
        $tabNetwork = New-Object System.Windows.Forms.TabPage
        $tabNetwork.Text = 'Network / World'
        $tabNetwork.BackColor = $tabServer.BackColor
        $tabDiscord = New-Object System.Windows.Forms.TabPage
        $tabDiscord.Text = 'Discord'
        $tabDiscord.BackColor = $tabServer.BackColor
        [void]$tabs.TabPages.Add($tabServer)
        [void]$tabs.TabPages.Add($tabNetwork)
        [void]$tabs.TabPages.Add($tabDiscord)

        $serverPanel = New-Object System.Windows.Forms.Panel
        $serverPanel.Dock = 'Fill'
        $serverPanel.AutoScroll = $true
        $serverPanel.Padding = '12,12,12,12'
        $serverPanel.BackColor = $tabServer.BackColor
        $tabServer.Controls.Add($serverPanel)

        Add-UGSMGameValheimCheckField -Panel $serverPanel -Controls $controls -Name 'Crossplay' -Label 'Crossplay enabled' -Value ([bool]$settings.Crossplay) -Theme $Theme | Out-Null
        Add-UGSMGameValheimCheckField -Panel $serverPanel -Controls $controls -Name 'Public' -Label 'Public server' -Value ([bool]$settings.Public) -Theme $Theme | Out-Null
        Add-UGSMGameValheimField -Panel $serverPanel -Controls $controls -Name 'Password' -Label 'Server password' -Value $settings.Password -Theme $Theme -Password | Out-Null
        Add-UGSMGameValheimField -Panel $serverPanel -Controls $controls -Name 'WorldName' -Label 'World name' -Value $settings.WorldName -Theme $Theme | Out-Null
        Add-UGSMGameValheimField -Panel $serverPanel -Controls $controls -Name 'ServerName' -Label 'Server name' -Value $settings.ServerName -Theme $Theme | Out-Null

        $networkPanel = New-Object System.Windows.Forms.Panel
        $networkPanel.Dock = 'Fill'
        $networkPanel.AutoScroll = $true
        $networkPanel.Padding = '12,12,12,12'
        $networkPanel.BackColor = $tabNetwork.BackColor
        $tabNetwork.Controls.Add($networkPanel)

        Add-UGSMGameValheimField -Panel $networkPanel -Controls $controls -Name 'BackupLong' -Label 'Backup long interval seconds' -Value $settings.BackupLong -Theme $Theme | Out-Null
        Add-UGSMGameValheimField -Panel $networkPanel -Controls $controls -Name 'BackupShort' -Label 'Backup short interval seconds' -Value $settings.BackupShort -Theme $Theme | Out-Null
        Add-UGSMGameValheimField -Panel $networkPanel -Controls $controls -Name 'Backups' -Label 'Backups to keep' -Value $settings.Backups -Theme $Theme | Out-Null
        Add-UGSMGameValheimField -Panel $networkPanel -Controls $controls -Name 'SaveInterval' -Label 'Save interval seconds' -Value $settings.SaveInterval -Theme $Theme | Out-Null
        Add-UGSMGameValheimField -Panel $networkPanel -Controls $controls -Name 'ModifierList' -Label 'World modifiers' -Value $settings.ModifierList -Theme $Theme | Out-Null
        Add-UGSMGameValheimField -Panel $networkPanel -Controls $controls -Name 'Preset' -Label 'World preset' -Value $settings.Preset -Theme $Theme | Out-Null
        Add-UGSMGameValheimField -Panel $networkPanel -Controls $controls -Name 'SteamPort' -Label 'Steam port' -Value $settings.SteamPort -Theme $Theme | Out-Null
        Add-UGSMGameValheimField -Panel $networkPanel -Controls $controls -Name 'QueryPort' -Label 'Query port' -Value $settings.QueryPort -Theme $Theme | Out-Null
        Add-UGSMGameValheimField -Panel $networkPanel -Controls $controls -Name 'GamePort' -Label 'Game port' -Value $settings.GamePort -Theme $Theme | Out-Null

        # Discord tab
        $discordPanel = New-Object System.Windows.Forms.Panel
        $discordPanel.Dock = 'Fill'
        $discordPanel.AutoScroll = $true
        $discordPanel.Padding = '12,12,12,12'
        $discordPanel.BackColor = $tabDiscord.BackColor
        $tabDiscord.Controls.Add($discordPanel)

        $discordControls = @{}
        $discordModel = $null
        if (Get-Command -Name Get-UGSMInstanceDiscordSettingsModel -ErrorAction SilentlyContinue) {
            try { $discordModel = Get-UGSMInstanceDiscordSettingsModel -Instance $Instance } catch { $discordModel = $null }
        }
        if (-not $discordModel) { $discordModel = [pscustomobject]@{ WebhookUrl=''; NotifyOnStart=$false; NotifyOnStop=$false; ShowInDashboard=$false } }

        Add-UGSMGameValheimCheckField -Panel $discordPanel -Controls $discordControls -Name 'ShowInDashboard' -Label 'Show in Discord/dashboard status' -Value ([bool]$discordModel.ShowInDashboard) -Theme $Theme | Out-Null
        Add-UGSMGameValheimCheckField -Panel $discordPanel -Controls $discordControls -Name 'NotifyOnStop' -Label 'Notify on Stop' -Value ([bool]$discordModel.NotifyOnStop) -Theme $Theme | Out-Null
        Add-UGSMGameValheimCheckField -Panel $discordPanel -Controls $discordControls -Name 'NotifyOnStart' -Label 'Notify on Start' -Value ([bool]$discordModel.NotifyOnStart) -Theme $Theme | Out-Null
        Add-UGSMGameValheimField -Panel $discordPanel -Controls $discordControls -Name 'WebhookUrl' -Label 'Private Discord webhook URL (blank uses global)' -Value $discordModel.WebhookUrl -Theme $Theme | Out-Null

        $discordStatus = New-Object System.Windows.Forms.Label
        $discordStatus.Dock = 'Bottom'
        $discordStatus.Height = 24
        $discordStatus.Text = ''
        $discordStatus.ForeColor = Get-UGSMGameValheimColor -Theme $Theme -Name 'Muted' -Fallback ([System.Drawing.Color]::Gainsboro)
        $discordStatus.BackColor = $discordPanel.BackColor
        $tabDiscord.Controls.Add($discordStatus)

        $btnTestDiscord = New-Object System.Windows.Forms.Button
        $btnTestDiscord.Text = 'Test Discord'
        $btnTestDiscord.Dock = 'Bottom'
        $btnTestDiscord.Height = 32
        $btnTestDiscord.BackColor = Get-UGSMGameValheimColor -Theme $Theme -Name 'Button' -Fallback ([System.Drawing.Color]::FromArgb(52,58,70))
        $btnTestDiscord.ForeColor = Get-UGSMGameValheimColor -Theme $Theme -Name 'Text' -Fallback ([System.Drawing.Color]::White)
        $tabDiscord.Controls.Add($btnTestDiscord)

        $btnSaveDiscord = New-Object System.Windows.Forms.Button
        $btnSaveDiscord.Text = 'Save Discord'
        $btnSaveDiscord.Dock = 'Bottom'
        $btnSaveDiscord.Height = 32
        $btnSaveDiscord.BackColor = Get-UGSMGameValheimColor -Theme $Theme -Name 'Accent' -Fallback ([System.Drawing.Color]::DodgerBlue)
        $btnSaveDiscord.ForeColor = Get-UGSMGameValheimColor -Theme $Theme -Name 'Text' -Fallback ([System.Drawing.Color]::White)
        $tabDiscord.Controls.Add($btnSaveDiscord)

        $discordState = [pscustomobject]@{ Instance=$Instance; Controls=$discordControls; StatusLabel=$discordStatus }
        $btnSaveDiscord.Tag = $discordState
        $btnTestDiscord.Tag = $discordState

        $discordAction = {
            param($sender, $eventArgs, [bool]$DoTest)
            $stateObj = $null
            try { if ($sender -and ($sender -is [System.Windows.Forms.Control])) { $stateObj = $sender.Tag } } catch {}
            if (-not $stateObj) { throw 'Valheim Discord editor state was not attached to the button.' }
            $actionInstance = $stateObj.Instance
            $actionControls = $stateObj.Controls
            $actionStatus = $stateObj.StatusLabel
            $actionInstanceId = Get-UGSMGameValheimInstanceId -Instance $actionInstance
            try {
                $input = [pscustomobject]@{
                    WebhookUrl      = [string]$actionControls.WebhookUrl.Text
                    NotifyOnStart   = [bool]$actionControls.NotifyOnStart.Checked
                    NotifyOnStop    = [bool]$actionControls.NotifyOnStop.Checked
                    ShowInDashboard = [bool]$actionControls.ShowInDashboard.Checked
                }
                if (Get-Command -Name Save-UGSMInstanceDiscordSettingsModel -ErrorAction SilentlyContinue) {
                    $persist = { param($updated) if (Get-Command -Name Save-UGSMInstance -ErrorAction SilentlyContinue) { Save-UGSMInstance -Instance $updated | Out-Null } }
                    $saveResult = Save-UGSMInstanceDiscordSettingsModel -Instance $actionInstance -InputObject $input -PersistInstance $persist
                    if ($saveResult -and $saveResult.Instance) { $stateObj.Instance = $saveResult.Instance; $actionInstance = $saveResult.Instance }
                }
                if ($actionStatus) { $actionStatus.Text = 'Valheim Discord settings saved.' }
                Write-UGSMGameValheimLog -Level 'INFO' -Message ("Discord settings saved from editor. InstanceId=$actionInstanceId; Test=$DoTest")
                if ($DoTest) {
                    $model = Get-UGSMInstanceDiscordSettingsModel -Instance $actionInstance
                    $webhookUrl = [string]$model.EffectiveWebhookUrl
                    if ([string]::IsNullOrWhiteSpace($webhookUrl)) { $webhookUrl = [string]$model.WebhookUrl }
                    if ([string]::IsNullOrWhiteSpace($webhookUrl)) { throw 'No Discord webhook URL is configured.' }
                    if (Get-Command -Name Test-UGSMDiscordWebhook -ErrorAction SilentlyContinue) {
                        $result = Test-UGSMDiscordWebhook -WebhookUrl $webhookUrl -Label ("Valheim {0}" -f (Get-UGSMGameValheimProfileName -Instance $actionInstance))
                        if ($result -and $result.Success -eq $false) { throw ([string]$result.Error) }
                    } else { throw 'Discord webhook tester was not loaded.' }
                    if ($actionStatus) { $actionStatus.Text = 'Valheim Discord test sent.' }
                }
            } catch {
                if ($actionStatus) { $actionStatus.Text = 'Valheim Discord action failed: ' + $_.Exception.Message }
                Write-UGSMGameValheimLog -Level 'ERROR' -Message ("Discord action failed from editor. InstanceId=$actionInstanceId; Test=$DoTest") -Exception $_.Exception
            }
        }
        $btnSaveDiscord.Add_Click({
            param($sender,$eventArgs)
            try {
                $stateObj = $null
                try { if ($sender -and ($sender -is [System.Windows.Forms.Control])) { $stateObj = $sender.Tag } } catch {}
                if (-not $stateObj) { throw 'Valheim Discord editor state was not attached to the button.' }
                $actionInstance = $stateObj.Instance
                $actionControls = $stateObj.Controls
                $actionStatus = $stateObj.StatusLabel
                $actionInstanceId = Get-UGSMGameValheimInstanceId -Instance $actionInstance

                $input = [pscustomobject]@{
                    WebhookUrl      = [string]$actionControls.WebhookUrl.Text
                    NotifyOnStart   = [bool]$actionControls.NotifyOnStart.Checked
                    NotifyOnStop    = [bool]$actionControls.NotifyOnStop.Checked
                    ShowInDashboard = [bool]$actionControls.ShowInDashboard.Checked
                }
                if (Get-Command -Name Save-UGSMInstanceDiscordSettingsModel -ErrorAction SilentlyContinue) {
                    $persist = { param($updated) if (Get-Command -Name Save-UGSMInstance -ErrorAction SilentlyContinue) { Save-UGSMInstance -Instance $updated | Out-Null } }
                    $saveResult = Save-UGSMInstanceDiscordSettingsModel -Instance $actionInstance -InputObject $input -PersistInstance $persist
                    if ($saveResult -and $saveResult.Instance) { $stateObj.Instance = $saveResult.Instance; $actionInstance = $saveResult.Instance }
                }
                if ($actionStatus) { $actionStatus.Text = 'Valheim Discord settings saved.' }
                Write-UGSMGameValheimLog -Level 'INFO' -Message ("Discord settings saved from editor. InstanceId=$actionInstanceId; Test=False")
            } catch {
                try { if ($stateObj -and $stateObj.StatusLabel) { $stateObj.StatusLabel.Text = 'Valheim Discord save failed: ' + $_.Exception.Message } } catch {}
                $logId = if ($stateObj -and $stateObj.Instance) { Get-UGSMGameValheimInstanceId -Instance $stateObj.Instance } else { $instanceId }
                Write-UGSMGameValheimLog -Level 'ERROR' -Message ("Discord save failed from editor. InstanceId=$logId") -Exception $_.Exception
            }
        })
        $btnTestDiscord.Add_Click({
            param($sender,$eventArgs)
            try {
                $stateObj = $null
                try { if ($sender -and ($sender -is [System.Windows.Forms.Control])) { $stateObj = $sender.Tag } } catch {}
                if (-not $stateObj) { throw 'Valheim Discord editor state was not attached to the button.' }
                $actionInstance = $stateObj.Instance
                $actionControls = $stateObj.Controls
                $actionStatus = $stateObj.StatusLabel
                $actionInstanceId = Get-UGSMGameValheimInstanceId -Instance $actionInstance

                $input = [pscustomobject]@{
                    WebhookUrl      = [string]$actionControls.WebhookUrl.Text
                    NotifyOnStart   = [bool]$actionControls.NotifyOnStart.Checked
                    NotifyOnStop    = [bool]$actionControls.NotifyOnStop.Checked
                    ShowInDashboard = [bool]$actionControls.ShowInDashboard.Checked
                }
                if (Get-Command -Name Save-UGSMInstanceDiscordSettingsModel -ErrorAction SilentlyContinue) {
                    $persist = { param($updated) if (Get-Command -Name Save-UGSMInstance -ErrorAction SilentlyContinue) { Save-UGSMInstance -Instance $updated | Out-Null } }
                    $saveResult = Save-UGSMInstanceDiscordSettingsModel -Instance $actionInstance -InputObject $input -PersistInstance $persist
                    if ($saveResult -and $saveResult.Instance) { $stateObj.Instance = $saveResult.Instance; $actionInstance = $saveResult.Instance }
                }

                $model = $null
                if (Get-Command -Name Get-UGSMInstanceDiscordSettingsModel -ErrorAction SilentlyContinue) { $model = Get-UGSMInstanceDiscordSettingsModel -Instance $actionInstance }
                $webhookUrl = ''
                if ($model -and $model.PSObject.Properties['EffectiveWebhookUrl']) { $webhookUrl = [string]$model.EffectiveWebhookUrl }
                if ([string]::IsNullOrWhiteSpace($webhookUrl) -and $model -and $model.PSObject.Properties['WebhookUrl']) { $webhookUrl = [string]$model.WebhookUrl }
                if ([string]::IsNullOrWhiteSpace($webhookUrl)) { $webhookUrl = [string]$actionControls.WebhookUrl.Text }
                if ([string]::IsNullOrWhiteSpace($webhookUrl)) { throw 'No Discord webhook URL is configured.' }

                if (Get-Command -Name Test-UGSMDiscordWebhook -ErrorAction SilentlyContinue) {
                    $result = Test-UGSMDiscordWebhook -WebhookUrl $webhookUrl -Label ("Valheim {0}" -f (Get-UGSMGameValheimProfileName -Instance $actionInstance))
                    if ($result -and $result.Success -eq $false) { throw ([string]$result.Error) }
                } else { throw 'Discord webhook tester was not loaded.' }

                if ($actionStatus) { $actionStatus.Text = 'Valheim Discord test sent.' }
                Write-UGSMGameValheimLog -Level 'INFO' -Message ("Discord test sent from editor. InstanceId=$actionInstanceId")
            } catch {
                try { if ($stateObj -and $stateObj.StatusLabel) { $stateObj.StatusLabel.Text = 'Valheim Discord test failed: ' + $_.Exception.Message } } catch {}
                $logId = if ($stateObj -and $stateObj.Instance) { Get-UGSMGameValheimInstanceId -Instance $stateObj.Instance } else { $instanceId }
                Write-UGSMGameValheimLog -Level 'ERROR' -Message ("Discord test failed from editor. InstanceId=$logId") -Exception $_.Exception
            }
        })

        $state = [pscustomobject]@{ Instance=$Instance; Controls=$controls; StatusLabel=$status }
        $btnSave = New-Object System.Windows.Forms.Button
        $btnSave.Text = 'Save Settings'
        $btnSave.Dock = 'Bottom'
        $btnSave.Height = 34
        $btnSave.BackColor = Get-UGSMGameValheimColor -Theme $Theme -Name 'Accent' -Fallback ([System.Drawing.Color]::DodgerBlue)
        $btnSave.ForeColor = Get-UGSMGameValheimColor -Theme $Theme -Name 'Text' -Fallback ([System.Drawing.Color]::White)
        $btnSave.Tag = $state
        $HostPanel.Controls.Add($btnSave)
        $btnSave.BringToFront()
        $btnSave.Add_Click({
            param($sender,$eventArgs)
            $clickedState = $null
            try {
                $clickedState = $sender.Tag
                if (-not $clickedState) { throw 'Valheim editor state was not attached to Save button.' }
                $null = Save-UGSMGameValheimInstanceEditor -EditorState $clickedState
                if ($clickedState.StatusLabel) { $clickedState.StatusLabel.Text = 'Valheim settings saved.' }
            } catch {
                $failLabel = if ($clickedState -and $clickedState.StatusLabel) { $clickedState.StatusLabel } else { $StatusLabel }
                if ($failLabel) { $failLabel.Text = 'Valheim save failed: ' + $_.Exception.Message }
                $failInstanceId = if ($clickedState -and $clickedState.Instance) { Get-UGSMGameValheimInstanceId -Instance $clickedState.Instance } else { $instanceId }
                Write-UGSMGameValheimLog -Level 'ERROR' -Message ("Editor save failed. InstanceId=$failInstanceId") -Exception $_.Exception
            }
        })
    }
    finally {
        $HostPanel.ResumeLayout($true)
    }

    $sw.Stop()
    Write-UGSMGameValheimLog -Level 'INFO' -Message ("Editor creation finished. InstanceId=$instanceId; DurationMs=$($sw.ElapsedMilliseconds)")
}

function Register-UGSMGameValheimModule {
    [CmdletBinding()]
    param()

    $metadata = Get-UGSMGameValheimMetadata
    return [pscustomobject]@{
        Id       = [string]$metadata.Id
        Metadata = $metadata
        Handlers = [pscustomobject]@{
            GetMetadata       = 'Get-UGSMGameValheimMetadata'
            TestInstall       = 'Test-UGSMGameValheimInstall'
            TestInstance      = 'Test-UGSMGameValheimInstance'
            EnsureTemplate    = 'Ensure-UGSMGameValheimTemplate'
            InitializeProfile = 'Initialize-UGSMGameValheimProfile'
            Start             = 'Start-UGSMGameValheimInstance'
            Stop              = 'Stop-UGSMGameValheimInstance'
            BuildEditor       = 'New-UGSMGameValheimInstanceEditor'
            SaveEditor        = 'Save-UGSMGameValheimInstanceEditor'
        }
    }
}
