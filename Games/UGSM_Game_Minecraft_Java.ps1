# UGSM Minecraft Java Dedicated Server module
# First pass: vanilla Java server support using Mojang's official server.jar.
# Bedrock should be handled as a separate game module/card later.

$script:_ugsmMinecraftJavaProcessesVar = Get-Variable -Name 'UGSM_MinecraftJavaProcesses' -Scope Script -ErrorAction SilentlyContinue
if ($null -eq $script:_ugsmMinecraftJavaProcessesVar -or $null -eq $script:_ugsmMinecraftJavaProcessesVar.Value) {
    $script:UGSM_MinecraftJavaProcesses = @{}
}
Remove-Variable -Name '_ugsmMinecraftJavaProcessesVar' -Scope Script -ErrorAction SilentlyContinue

function Write-UGSMGameMinecraftJavaLog {
    [CmdletBinding()]
    param(
        [ValidateSet('TRACE','DEBUG','INFO','WARN','ERROR','FATAL')][string]$Level = 'INFO',
        [Parameter(Mandatory)][string]$Message,
        [AllowNull()][System.Exception]$Exception
    )
    $verboseEnabled = $false
    try { $verboseEnabled = [bool]$script:UGSM_EnableVerboseMinecraftJavaLogging } catch { $verboseEnabled = $false }
    if (-not $verboseEnabled -and -not [string]::IsNullOrWhiteSpace($env:UGSM_VERBOSE_MINECRAFTJAVA)) { $verboseEnabled = $true }
    if ($Level -in @('TRACE','DEBUG') -and -not $verboseEnabled) { return }
    if (Get-Command -Name Write-UGSMLog -ErrorAction SilentlyContinue) {
        if ($Exception) { Write-UGSMLog -Level $Level -Category 'MinecraftJava' -Message $Message -Exception $Exception }
        else { Write-UGSMLog -Level $Level -Category 'MinecraftJava' -Message $Message }
        return
    }
    if ($Exception) { Write-Warning ("[MinecraftJava] $Message :: $($Exception.Message)") } else { Write-Host "[MinecraftJava][$Level] $Message" }
}

function Get-UGSMGameMinecraftJavaMetadata {
    [CmdletBinding()]
    param()
    return [pscustomobject]@{
        Id                       = 'MinecraftJava'
        Name                     = 'Minecraft Java'
        Category                 = 'Sandbox'
        Description              = 'Minecraft Java Edition vanilla dedicated server integration using the official server.jar.'
        IsCustom                 = $false
        SupportTier              = 'Basic'
        SortOrder                = 300
        IsVisible                = $true
        SupportedTabs            = @('Home','Games','Instances','Analytics','Tasks','About','Settings')
        UseSteamArt              = $false
        # UGSM Games page install flow is SteamCMD-only right now.
        # Keep Minecraft Java as install-less so profile creation/start can bootstrap server.jar.
        SupportsInstall          = $false
        SupportsUpdate           = $false
        SupportsVerify           = $false
        SupportsRepair           = $false
        SupportsStart            = $true
        SupportsStop             = $true
        SupportsMods             = $false
        SupportsWorkshop         = $false
        SupportsRcon             = $true
        SupportsBootstrap        = $false
        SupportsProfiles         = $true
        SupportsInstanceUi       = $true
        InstallProvider          = 'MojangDownload'
        RequiresSteamLogin       = $false
        SteamLoginMode           = 'None'
        SteamAppId               = ''
        SteamStoreAppId          = ''
        ServerExecutable         = 'server.jar'
        ServerExecutableRelative = 'server.jar'
        UsesSharedBinaries       = $true
        InstanceType             = 'DedicatedServer'
        ConfigRootRelative       = '.'
        SaveRootRelative         = '.'
        LogRootRelative          = 'logs'
        RequiredFiles            = @()
        InstallMarkers           = @()
        PortSchema               = @(
            @{ Name = 'GamePort'; Protocol = 'TCP'; PreferredStart = 25565 },
            @{ Name = 'RconPort'; Protocol = 'TCP'; PreferredStart = 25575 }
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
                'Minecraft Java does not use SteamCMD and does not require buying the game to download the official server.jar.',
                'UGSM downloads the official Mojang server.jar on first profile initialization/start if it is missing.',
                'The user must accept the Minecraft EULA in the editor before UGSM starts the server.',
                'This first pass supports vanilla Java only. Paper, Fabric, Forge, and plugin/mod workflows should be added later.'
            )
        }
    }
}

function Get-UGSMGameMinecraftJavaInstanceId {
    [CmdletBinding()]
    param([AllowNull()][object]$Instance)
    if (-not $Instance) { return '' }
    foreach ($name in @('Id','Name','ProfileName','InstanceId')) {
        if ($Instance.PSObject.Properties[$name] -and -not [string]::IsNullOrWhiteSpace([string]$Instance.$name)) { return [string]$Instance.$name }
    }
    return ''
}

function Get-UGSMGameMinecraftJavaProfileName {
    [CmdletBinding()]
    param([AllowNull()][object]$Instance)
    $name = Get-UGSMGameMinecraftJavaInstanceId -Instance $Instance
    if ([string]::IsNullOrWhiteSpace($name)) { $name = 'MinecraftJava1' }
    $safe = $name -replace '[^A-Za-z0-9_.-]', '_'
    if ([string]::IsNullOrWhiteSpace($safe)) { $safe = 'MinecraftJava1' }
    return $safe
}

function Get-UGSMGameMinecraftJavaAppDataRoot {
    [CmdletBinding()]
    param()
    if (Get-Command -Name Get-UGSMAppDataRoot -ErrorAction SilentlyContinue) {
        try { return [string](Get-UGSMAppDataRoot) } catch {}
    }
    return (Join-Path $env:LOCALAPPDATA 'UGSM')
}

function Get-UGSMGameMinecraftJavaProfileBaseRoot {
    [CmdletBinding()]
    param()
    $settings = $null
    if (Get-Command -Name Get-UGSMGlobalSettings -ErrorAction SilentlyContinue) {
        try { $settings = Get-UGSMGlobalSettings -CreateIfMissing } catch { $settings = $null }
    }
    if ($settings -and $settings.PSObject.Properties['ProfileBaseRoot'] -and -not [string]::IsNullOrWhiteSpace([string]$settings.ProfileBaseRoot)) { return [string]$settings.ProfileBaseRoot }
    if (Get-Command -Name Get-UGSMDefaultInstanceProfilePath -ErrorAction SilentlyContinue) {
        $probe = Get-UGSMDefaultInstanceProfilePath -GameId 'MinecraftJava' -Name '_probe_'
        if (-not [string]::IsNullOrWhiteSpace([string]$probe)) { return (Split-Path -Parent (Split-Path -Parent $probe)) }
    }
    return (Join-Path (Get-UGSMGameMinecraftJavaAppDataRoot) 'Profiles')
}

function Get-UGSMGameMinecraftJavaInstallRoot {
    [CmdletBinding()]
    param([string]$InstallPath, [AllowNull()][object]$Instance)
    if (-not [string]::IsNullOrWhiteSpace($InstallPath)) { return $InstallPath }
    if ($Instance -and $Instance.PSObject.Properties['InstallPath'] -and -not [string]::IsNullOrWhiteSpace([string]$Instance.InstallPath)) { return [string]$Instance.InstallPath }

    $settings = $null
    if (Get-Command -Name Get-UGSMGlobalSettings -ErrorAction SilentlyContinue) {
        try { $settings = Get-UGSMGlobalSettings -CreateIfMissing } catch { $settings = $null }
    }

    $bases = @()
    if ($settings) {
        foreach ($propName in @('InstallRoot','ServerRoot','SteamLibraryRoot','SteamRoot')) {
            if ($settings.PSObject.Properties[$propName] -and -not [string]::IsNullOrWhiteSpace([string]$settings.$propName)) { $bases += [string]$settings.$propName }
        }
    }
    $profileBase = Get-UGSMGameMinecraftJavaProfileBaseRoot
    if (-not [string]::IsNullOrWhiteSpace($profileBase)) {
        try { $bases += (Split-Path -Parent $profileBase) } catch {}
    }
    $binariesRoot = Join-Path (Get-UGSMGameMinecraftJavaAppDataRoot) 'Binaries'
    if (-not [string]::IsNullOrWhiteSpace($binariesRoot)) { $bases += $binariesRoot }

    foreach ($base in ($bases | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -Unique)) {
        foreach ($candidate in @(
            (Join-Path $base 'MinecraftJava'),
            (Join-Path $base 'Minecraft Java'),
            (Join-Path $base 'Binaries\MinecraftJava'),
            (Join-Path $base 'Servers\MinecraftJava')
        )) {
            if (Test-Path -LiteralPath (Join-Path $candidate 'server.jar') -PathType Leaf) { return $candidate }
        }
    }

    foreach ($base in ($bases | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -Unique)) {
        return (Join-Path $base 'MinecraftJava')
    }
    return (Join-Path (Get-UGSMGameMinecraftJavaAppDataRoot) 'Binaries\MinecraftJava')
}

function Get-UGSMGameMinecraftJavaInstallDefinition {
    [CmdletBinding()]
    param([string]$InstallPath, [AllowNull()][object]$Instance)
    $root = Get-UGSMGameMinecraftJavaInstallRoot -InstallPath $InstallPath -Instance $Instance
    return [pscustomobject]@{
        InstallPath          = $root
        ServerJarPath        = Join-Path $root 'server.jar'
        VersionInfoPath      = Join-Path $root 'UGSM_MinecraftJavaVersion.json'
        ServerExecutablePath = Join-Path $root 'server.jar'
    }
}

function Test-UGSMGameMinecraftJavaInstall {
    [CmdletBinding()]
    param([string]$InstallPath, [AllowNull()][object]$Instance)
    $definition = Get-UGSMGameMinecraftJavaInstallDefinition -InstallPath $InstallPath -Instance $Instance
    $jarOk = Test-Path -LiteralPath $definition.ServerJarPath -PathType Leaf
    $javaOk = $false
    try { $cmd = Get-Command -Name 'java.exe' -ErrorAction SilentlyContinue; if ($cmd) { $javaOk = $true } } catch { $javaOk = $false }

    # Non-Steam bootstrap model: consider the game available even before server.jar exists.
    # The profile initialization/start path downloads server.jar from Mojang. This avoids
    # the current SteamCMD-only Games page install workflow.
    return [pscustomobject]@{
        Success=$true
        IsInstalled=$true
        InstallPath=$definition.InstallPath
        ServerExecutablePath=$definition.ServerJarPath
        ServerJarExists=[bool]$jarOk
        JavaAvailable=$javaOk
        Message=if ($jarOk -and $javaOk) { 'Minecraft Java server.jar detected and Java runtime is available.' } elseif ($jarOk) { 'Minecraft Java server.jar detected. Java is required before starting.' } else { 'Minecraft Java will download server.jar when a profile is created or started. Java is required before starting.' }
    }
}

function Get-UGSMGameMinecraftJavaAssignedPort {
    [CmdletBinding()]
    param([Parameter(Mandatory)][object]$Instance, [Parameter(Mandatory)][string]$Name, [int]$Default)
    foreach ($propName in @('Ports','AssignedPorts')) {
        if (-not ($Instance.PSObject.Properties[$propName])) { continue }
        $ports = $Instance.$propName
        if ($ports -is [hashtable] -and $ports.ContainsKey($Name)) {
            $entry = $ports[$Name]
            if ($entry -is [int]) { return [int]$entry }
            if ($entry -and $entry.PSObject.Properties['Port']) { return [int]$entry.Port }
        } elseif ($ports) {
            foreach ($entry in @($ports)) {
                if ($entry -and $entry.PSObject.Properties['Name'] -and [string]$entry.Name -eq $Name -and $entry.PSObject.Properties['Port']) { return [int]$entry.Port }
            }
        }
    }
    return $Default
}

function Get-UGSMGameMinecraftJavaProfileRoot {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$ProfileName)
    return (Join-Path (Join-Path (Get-UGSMGameMinecraftJavaProfileBaseRoot) 'MinecraftJava') $ProfileName)
}

function Get-UGSMGameMinecraftJavaProfilePaths {
    [CmdletBinding()]
    param([Parameter(Mandatory)][object]$Instance, [string]$InstallPath)
    $profileName = Get-UGSMGameMinecraftJavaProfileName -Instance $Instance
    $profileRoot = Get-UGSMGameMinecraftJavaProfileRoot -ProfileName $profileName
    $logsRoot = Join-Path $profileRoot 'logs'
    $centralLogRoot = Join-Path (Join-Path (Get-UGSMGameMinecraftJavaAppDataRoot) 'Logs\MinecraftJava') $profileName
    $definition = Get-UGSMGameMinecraftJavaInstallDefinition -InstallPath $InstallPath -Instance $Instance
    return [pscustomobject]@{
        ProfileName       = $profileName
        ProfileRoot       = $profileRoot
        LogsRoot          = $logsRoot
        CentralLogRoot    = $centralLogRoot
        SettingsPath      = Join-Path $profileRoot 'UGSM_MinecraftJavaSettings.json'
        ServerProperties  = Join-Path $profileRoot 'server.properties'
        EulaPath          = Join-Path $profileRoot 'eula.txt'
        RuntimeStatePath  = Join-Path $profileRoot 'UGSM_MinecraftJavaRuntime.json'
        LaunchLogPath     = Join-Path $centralLogRoot 'server-console.log'
        ErrorLogPath      = Join-Path $centralLogRoot 'server-error.log'
        InstallPath       = $definition.InstallPath
        ServerJarPath     = $definition.ServerJarPath
    }
}

function Get-UGSMGameMinecraftJavaDefaultSettings {
    [CmdletBinding()]
    param([AllowNull()][object]$Instance)
    $profileName = Get-UGSMGameMinecraftJavaProfileName -Instance $Instance
    $gamePort = 25565
    $rconPort = 25575
    if ($Instance) {
        $gamePort = Get-UGSMGameMinecraftJavaAssignedPort -Instance $Instance -Name 'GamePort' -Default 25565
        $rconPort = Get-UGSMGameMinecraftJavaAssignedPort -Instance $Instance -Name 'RconPort' -Default 25575
    }
    return [pscustomobject]@{
        ServerName          = $profileName
        Motd                = 'A UGSM Minecraft Java Server'
        GamePort            = [int]$gamePort
        MaxPlayers          = 20
        OnlineMode          = $true
        EnforceSecureProfile= $true
        Difficulty          = 'normal'
        Gamemode            = 'survival'
        LevelName           = 'world'
        LevelSeed           = ''
        ViewDistance        = 10
        SimulationDistance  = 10
        Pvp                 = $true
        AllowNether         = $true
        SpawnProtection     = 16
        EnableCommandBlock  = $false
        Whitelist           = $false
        EnableRcon          = $true
        RconPort            = [int]$rconPort
        RconPassword        = 'changeme'
        MemoryMinMB         = 1024
        MemoryMaxMB         = 2048
        ExtraJavaArgs       = ''
        ExtraServerProperties = ''
        AcceptEula          = $false
        MinecraftVersion    = 'latest-compatible'
        UseLatestCompatibleJava = $true
        Discord             = [pscustomobject]@{
            WebhookUrl      = ''
            NotifyOnStart   = $false
            NotifyOnStop    = $false
            ShowInDashboard = $false
        }
    }
}

function Merge-UGSMGameMinecraftJavaSettings {
    param([Parameter(Mandatory)][object]$Settings, [Parameter(Mandatory)][object]$Defaults)
    foreach ($prop in $Defaults.PSObject.Properties) {
        if (-not $Settings.PSObject.Properties[$prop.Name]) { Add-Member -InputObject $Settings -MemberType NoteProperty -Name $prop.Name -Value $prop.Value -Force }
    }
    if (-not $Settings.PSObject.Properties['Discord'] -or -not $Settings.Discord) { $Settings.Discord = $Defaults.Discord }
    foreach ($prop in $Defaults.Discord.PSObject.Properties) {
        if (-not $Settings.Discord.PSObject.Properties[$prop.Name]) { Add-Member -InputObject $Settings.Discord -MemberType NoteProperty -Name $prop.Name -Value $prop.Value -Force }
    }
    return $Settings
}

function Get-UGSMGameMinecraftJavaSettings {
    [CmdletBinding()]
    param([Parameter(Mandatory)][object]$Instance, [string]$InstallPath)
    $paths = Get-UGSMGameMinecraftJavaProfilePaths -Instance $Instance -InstallPath $InstallPath
    $defaults = Get-UGSMGameMinecraftJavaDefaultSettings -Instance $Instance
    if (Test-Path -LiteralPath $paths.SettingsPath -PathType Leaf) {
        try {
            $settings = Get-Content -LiteralPath $paths.SettingsPath -Raw | ConvertFrom-Json
            return (Merge-UGSMGameMinecraftJavaSettings -Settings $settings -Defaults $defaults)
        } catch {
            Write-UGSMGameMinecraftJavaLog -Level 'WARN' -Message "Failed to read settings; using defaults." -Exception $_.Exception
        }
    }
    return $defaults
}

function ConvertTo-UGSMGameMinecraftJavaBoolText {
    param([bool]$Value)
    if ($Value) { return 'true' }
    return 'false'
}

function ConvertTo-UGSMGameMinecraftJavaPropertiesText {
    [CmdletBinding()]
    param([Parameter(Mandatory)][object]$Settings)
    $lines = New-Object System.Collections.Generic.List[string]
    $lines.Add('#Minecraft server properties') | Out-Null
    $lines.Add('#Managed by UGSM. Edit in UGSM or Advanced Properties.') | Out-Null
    $lines.Add(('server-port={0}' -f ([int]$Settings.GamePort))) | Out-Null
    $lines.Add(('motd={0}' -f ([string]$Settings.Motd))) | Out-Null
    $lines.Add(('max-players={0}' -f ([int]$Settings.MaxPlayers))) | Out-Null
    $lines.Add(('online-mode={0}' -f (ConvertTo-UGSMGameMinecraftJavaBoolText ([bool]$Settings.OnlineMode)))) | Out-Null
    $lines.Add(('enforce-secure-profile={0}' -f (ConvertTo-UGSMGameMinecraftJavaBoolText ([bool]$Settings.EnforceSecureProfile)))) | Out-Null
    $lines.Add(('difficulty={0}' -f ([string]$Settings.Difficulty))) | Out-Null
    $lines.Add(('gamemode={0}' -f ([string]$Settings.Gamemode))) | Out-Null
    $lines.Add(('level-name={0}' -f ([string]$Settings.LevelName))) | Out-Null
    if (-not [string]::IsNullOrWhiteSpace([string]$Settings.LevelSeed)) { $lines.Add(('level-seed={0}' -f ([string]$Settings.LevelSeed))) | Out-Null } else { $lines.Add('level-seed=') | Out-Null }
    $lines.Add(('view-distance={0}' -f ([int]$Settings.ViewDistance))) | Out-Null
    $lines.Add(('simulation-distance={0}' -f ([int]$Settings.SimulationDistance))) | Out-Null
    $lines.Add(('pvp={0}' -f (ConvertTo-UGSMGameMinecraftJavaBoolText ([bool]$Settings.Pvp)))) | Out-Null
    $lines.Add(('allow-nether={0}' -f (ConvertTo-UGSMGameMinecraftJavaBoolText ([bool]$Settings.AllowNether)))) | Out-Null
    $lines.Add(('spawn-protection={0}' -f ([int]$Settings.SpawnProtection))) | Out-Null
    $lines.Add(('enable-command-block={0}' -f (ConvertTo-UGSMGameMinecraftJavaBoolText ([bool]$Settings.EnableCommandBlock)))) | Out-Null
    $lines.Add(('white-list={0}' -f (ConvertTo-UGSMGameMinecraftJavaBoolText ([bool]$Settings.Whitelist)))) | Out-Null
    $lines.Add(('enable-rcon={0}' -f (ConvertTo-UGSMGameMinecraftJavaBoolText ([bool]$Settings.EnableRcon)))) | Out-Null
    $lines.Add(('rcon.port={0}' -f ([int]$Settings.RconPort))) | Out-Null
    $lines.Add(('rcon.password={0}' -f ([string]$Settings.RconPassword))) | Out-Null
    $lines.Add('enable-query=true') | Out-Null
    $lines.Add(('query.port={0}' -f ([int]$Settings.GamePort))) | Out-Null
    $extra = [string]$Settings.ExtraServerProperties
    if (-not [string]::IsNullOrWhiteSpace($extra)) {
        $lines.Add('') | Out-Null
        $lines.Add('# UGSM extra server.properties') | Out-Null
        foreach ($line in ($extra -split "`r?`n")) {
            if (-not [string]::IsNullOrWhiteSpace($line)) { $lines.Add($line) | Out-Null }
        }
    }
    return ($lines -join [Environment]::NewLine)
}

function Save-UGSMGameMinecraftJavaSettings {
    [CmdletBinding()]
    param([Parameter(Mandatory)][object]$Instance, [Parameter(Mandatory)][object]$Settings, [string]$InstallPath)
    $paths = Get-UGSMGameMinecraftJavaProfilePaths -Instance $Instance -InstallPath $InstallPath
    New-Item -ItemType Directory -Force -Path $paths.ProfileRoot, $paths.LogsRoot, $paths.CentralLogRoot | Out-Null
    $Settings | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $paths.SettingsPath -Encoding UTF8
    ConvertTo-UGSMGameMinecraftJavaPropertiesText -Settings $Settings | Set-Content -LiteralPath $paths.ServerProperties -Encoding UTF8
    $eulaText = if ([bool]$Settings.AcceptEula) { 'eula=true' } else { 'eula=false' }
    @('# By changing the setting below to TRUE you are indicating your agreement to the Minecraft EULA.',$eulaText) | Set-Content -LiteralPath $paths.EulaPath -Encoding UTF8
    Write-UGSMGameMinecraftJavaLog -Level 'INFO' -Message ("Settings saved. InstanceId=$(Get-UGSMGameMinecraftJavaInstanceId -Instance $Instance); Profile=$($paths.ProfileName)")
    return [pscustomobject]@{ Success=$true; SettingsPath=$paths.SettingsPath; ServerProperties=$paths.ServerProperties; EulaPath=$paths.EulaPath }
}

function Get-UGSMGameMinecraftJavaLatestServerDownload {
    [CmdletBinding()]
    param(
        [string]$TargetVersion = 'latest',
        [int]$MaxJavaMajor = 0,
        [int]$ScanLimit = 80
    )
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    $manifestUrl = 'https://piston-meta.mojang.com/mc/game/version_manifest_v2.json'
    $manifest = Invoke-RestMethod -Uri $manifestUrl -UseBasicParsing -ErrorAction Stop

    $target = if ([string]::IsNullOrWhiteSpace($TargetVersion)) { 'latest' } else { [string]$TargetVersion }
    $versionEntry = $null
    $versionJson = $null

    if ($target -eq 'latest' -or $target -eq 'latest-release') {
        $latestRelease = [string]$manifest.latest.release
        $versionEntry = $manifest.versions | Where-Object { [string]$_.id -eq $latestRelease } | Select-Object -First 1
        if (-not $versionEntry) { throw 'Could not find the latest Minecraft Java release in the Mojang version manifest.' }
        $versionJson = Invoke-RestMethod -Uri ([string]$versionEntry.url) -UseBasicParsing -ErrorAction Stop
    }
    elseif ($target -eq 'latest-compatible') {
        if ($MaxJavaMajor -le 0) {
            $latestRelease = [string]$manifest.latest.release
            $versionEntry = $manifest.versions | Where-Object { [string]$_.id -eq $latestRelease } | Select-Object -First 1
            if (-not $versionEntry) { throw 'Could not find the latest Minecraft Java release in the Mojang version manifest.' }
            $versionJson = Invoke-RestMethod -Uri ([string]$versionEntry.url) -UseBasicParsing -ErrorAction Stop
        } else {
            $checked = 0
            foreach ($entry in ($manifest.versions | Where-Object { [string]$_.type -eq 'release' })) {
                if ($checked -ge $ScanLimit) { break }
                $checked++
                try {
                    $candidate = Invoke-RestMethod -Uri ([string]$entry.url) -UseBasicParsing -ErrorAction Stop
                    $candidateJava = 0
                    try { $candidateJava = [int]$candidate.javaVersion.majorVersion } catch { $candidateJava = 0 }
                    if ($candidateJava -le 0 -or $candidateJava -le $MaxJavaMajor) {
                        $versionEntry = $entry
                        $versionJson = $candidate
                        break
                    }
                } catch {}
            }
            if (-not $versionEntry -or -not $versionJson) { throw "Could not find a recent Minecraft Java release compatible with Java $MaxJavaMajor." }
        }
    }
    else {
        $versionEntry = $manifest.versions | Where-Object { [string]$_.id -eq $target } | Select-Object -First 1
        if (-not $versionEntry -or [string]::IsNullOrWhiteSpace([string]$versionEntry.url)) { throw "Could not find Minecraft Java version '$target' in Mojang's version manifest." }
        $versionJson = Invoke-RestMethod -Uri ([string]$versionEntry.url) -UseBasicParsing -ErrorAction Stop
    }

    $serverUrl = [string]$versionJson.downloads.server.url
    if ([string]::IsNullOrWhiteSpace($serverUrl)) { throw 'Could not find the official server.jar download URL in the Mojang version JSON.' }
    $javaMajor = 0
    try { $javaMajor = [int]$versionJson.javaVersion.majorVersion } catch { $javaMajor = 0 }
    return [pscustomobject]@{
        Version   = [string]$versionJson.id
        Url       = $serverUrl
        Sha1      = [string]$versionJson.downloads.server.sha1
        Size      = [int64]$versionJson.downloads.server.size
        JavaMajor = $javaMajor
        Selection = $target
    }
}

function Test-UGSMGameMinecraftJavaServerJarHash {
    [CmdletBinding()]
    param([Parameter(Mandatory)][object]$Definition)
    try {
        if (-not (Test-Path -LiteralPath $Definition.ServerJarPath -PathType Leaf)) { return $false }
        if (-not (Test-Path -LiteralPath $Definition.VersionInfoPath -PathType Leaf)) { return $true }
        $info = Get-Content -LiteralPath $Definition.VersionInfoPath -Raw -ErrorAction Stop | ConvertFrom-Json
        $expected = [string]$info.Sha1
        if ([string]::IsNullOrWhiteSpace($expected)) { return $true }
        $actual = (Get-FileHash -LiteralPath $Definition.ServerJarPath -Algorithm SHA1 -ErrorAction Stop).Hash.ToLowerInvariant()
        return ($actual -eq $expected.ToLowerInvariant())
    } catch {
        return $true
    }
}

function Add-UGSMGameMinecraftJavaRecentServerLogToLaunchLog {
    [CmdletBinding()]
    param([Parameter(Mandatory)][object]$Paths)
    try {
        $latest = Join-Path $Paths.ProfileRoot 'logs\latest.log'
        if (Test-Path -LiteralPath $latest -PathType Leaf) {
            Add-Content -LiteralPath $Paths.LaunchLogPath -Value '' -Encoding UTF8
            Add-Content -LiteralPath $Paths.LaunchLogPath -Value '----- Minecraft logs/latest.log tail -----' -Encoding UTF8
            Get-Content -LiteralPath $latest -Tail 120 -ErrorAction SilentlyContinue | Add-Content -LiteralPath $Paths.LaunchLogPath -Encoding UTF8
        }
        $crashRoot = Join-Path $Paths.ProfileRoot 'crash-reports'
        if (Test-Path -LiteralPath $crashRoot -PathType Container) {
            $crash = Get-ChildItem -LiteralPath $crashRoot -Filter '*.txt' -File -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 1
            if ($crash) {
                Add-Content -LiteralPath $Paths.ErrorLogPath -Value '' -Encoding UTF8
                Add-Content -LiteralPath $Paths.ErrorLogPath -Value ("----- Latest Minecraft crash report: {0} -----" -f $crash.Name) -Encoding UTF8
                Get-Content -LiteralPath $crash.FullName -Tail 160 -ErrorAction SilentlyContinue | Add-Content -LiteralPath $Paths.ErrorLogPath -Encoding UTF8
            }
        }
    } catch {}
}

function Ensure-UGSMGameMinecraftJavaServerJar {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$Definition,
        [switch]$Force,
        [string]$TargetVersion = 'latest-compatible',
        [int]$MaxJavaMajor = 0
    )
    New-Item -ItemType Directory -Force -Path $Definition.InstallPath | Out-Null
    if (-not $Force -and (Test-Path -LiteralPath $Definition.ServerJarPath -PathType Leaf)) {
        $needDownload = $false
        try {
            if (Test-Path -LiteralPath $Definition.VersionInfoPath -PathType Leaf) {
                $existingInfo = Get-Content -LiteralPath $Definition.VersionInfoPath -Raw -ErrorAction Stop | ConvertFrom-Json
                if ($TargetVersion -eq 'latest-compatible' -and $MaxJavaMajor -gt 0 -and $existingInfo.PSObject.Properties['JavaMajor'] -and ([int]$existingInfo.JavaMajor) -gt $MaxJavaMajor) { $needDownload = $true }
                elseif ($TargetVersion -and $TargetVersion -notin @('latest','latest-release','latest-compatible') -and [string]$existingInfo.Version -ne $TargetVersion) { $needDownload = $true }
            }
        } catch {}
        if (-not $needDownload) { return $Definition.ServerJarPath }
        Write-UGSMGameMinecraftJavaLog -Level 'INFO' -Message 'Existing Minecraft Java server.jar is not compatible with the selected Java/version; downloading another official server.jar.'
    }
    Write-UGSMGameMinecraftJavaLog -Level 'INFO' -Message 'Downloading official Minecraft Java server.jar from Mojang.'
    $info = Get-UGSMGameMinecraftJavaLatestServerDownload -TargetVersion $TargetVersion -MaxJavaMajor $MaxJavaMajor
    $tmp = $Definition.ServerJarPath + '.download'
    Invoke-WebRequest -Uri $info.Url -OutFile $tmp -UseBasicParsing -ErrorAction Stop
    Move-Item -LiteralPath $tmp -Destination $Definition.ServerJarPath -Force
    $info | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $Definition.VersionInfoPath -Encoding UTF8
    Write-UGSMGameMinecraftJavaLog -Level 'INFO' -Message ("Minecraft Java server.jar downloaded. Version=$($info.Version)")
    return $Definition.ServerJarPath
}

function Install-UGSMGameMinecraftJavaServer {
    [CmdletBinding()]
    param(
        [string]$InstallPath,
        [AllowNull()][object]$Instance,
        [switch]$Force,
        [switch]$Validate,
        [int]$BootstrapSeconds = 0
    )

    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    $definition = Get-UGSMGameMinecraftJavaInstallDefinition -InstallPath $InstallPath -Instance $Instance
    try {
        New-Item -ItemType Directory -Force -Path $definition.InstallPath | Out-Null
        $detectedJavaMajor = Get-UGSMGameMinecraftJavaDetectedJavaMajor
        Ensure-UGSMGameMinecraftJavaServerJar -Definition $definition -Force:$Force -TargetVersion 'latest-compatible' -MaxJavaMajor $detectedJavaMajor | Out-Null
        $test = Test-UGSMGameMinecraftJavaInstall -InstallPath $definition.InstallPath -Instance $Instance
        $sw.Stop()
        Write-UGSMGameMinecraftJavaLog -Level 'INFO' -Message ("Install completed. DurationMs=$($sw.ElapsedMilliseconds); JavaAvailable=$($test.JavaAvailable)")
        return [pscustomobject]@{
            Success              = [bool](Test-Path -LiteralPath $definition.ServerJarPath -PathType Leaf)
            IsValid              = [bool](Test-Path -LiteralPath $definition.ServerJarPath -PathType Leaf)
            InstallPath          = $definition.InstallPath
            ServerExecutablePath = $definition.ServerExecutablePath
            JavaAvailable        = [bool]$test.JavaAvailable
            Message              = if ($test.JavaAvailable) { 'Minecraft Java server.jar installed.' } else { 'Minecraft Java server.jar installed. Java is required before starting.' }
        }
    } catch {
        $sw.Stop()
        Write-UGSMGameMinecraftJavaLog -Level 'ERROR' -Message ("Install failed. DurationMs=$($sw.ElapsedMilliseconds)") -Exception $_.Exception
        return [pscustomobject]@{
            Success     = $false
            IsValid     = $false
            InstallPath = $definition.InstallPath
            Message     = $_.Exception.Message
        }
    }
}

function Ensure-UGSMGameMinecraftJavaTemplate {
    [CmdletBinding()]
    param(
        [AllowNull()][object]$Instance,
        [int]$BootstrapSeconds = 0,
        [switch]$Force
    )
    if ($Instance) { return Initialize-UGSMGameMinecraftJavaProfile -Instance $Instance -BootstrapSeconds $BootstrapSeconds -Force:$Force }
    $definition = Get-UGSMGameMinecraftJavaInstallDefinition
    return Install-UGSMGameMinecraftJavaServer -InstallPath $definition.InstallPath -Force:$Force
}

function Initialize-UGSMGameMinecraftJavaProfile {
    [CmdletBinding()]
    param([Parameter(Mandatory)][object]$Instance, [string]$InstallPath, [switch]$Force, [int]$BootstrapSeconds = 0)
    $definition = Get-UGSMGameMinecraftJavaInstallDefinition -InstallPath $InstallPath -Instance $Instance
    New-Item -ItemType Directory -Force -Path $definition.InstallPath | Out-Null
    $detectedJavaMajor = Get-UGSMGameMinecraftJavaDetectedJavaMajor
    $tmpSettings = $null
    try { $tmpSettings = Get-UGSMGameMinecraftJavaSettings -Instance $Instance -InstallPath $definition.InstallPath } catch {}
    $targetVersion = if ($tmpSettings -and $tmpSettings.PSObject.Properties['MinecraftVersion']) { [string]$tmpSettings.MinecraftVersion } else { 'latest-compatible' }
    if ([string]::IsNullOrWhiteSpace($targetVersion)) { $targetVersion = 'latest-compatible' }
    Ensure-UGSMGameMinecraftJavaServerJar -Definition $definition -TargetVersion $targetVersion -MaxJavaMajor $detectedJavaMajor | Out-Null
    $paths = Get-UGSMGameMinecraftJavaProfilePaths -Instance $Instance -InstallPath $definition.InstallPath
    New-Item -ItemType Directory -Force -Path $paths.ProfileRoot, $paths.LogsRoot, $paths.CentralLogRoot | Out-Null
    if ($Instance.PSObject.Properties['ProfilePath']) { $Instance.ProfilePath = $paths.ProfileRoot } else { Add-Member -InputObject $Instance -MemberType NoteProperty -Name ProfilePath -Value $paths.ProfileRoot -Force }
    if ($Instance.PSObject.Properties['InstallPath']) { $Instance.InstallPath = $definition.InstallPath } else { Add-Member -InputObject $Instance -MemberType NoteProperty -Name InstallPath -Value $definition.InstallPath -Force }
    $settings = Get-UGSMGameMinecraftJavaSettings -Instance $Instance -InstallPath $definition.InstallPath
    if ($Force -or -not (Test-Path -LiteralPath $paths.SettingsPath -PathType Leaf)) { $settings = Get-UGSMGameMinecraftJavaDefaultSettings -Instance $Instance }
    Save-UGSMGameMinecraftJavaSettings -Instance $Instance -Settings $settings -InstallPath $definition.InstallPath | Out-Null
    Write-UGSMGameMinecraftJavaLog -Level 'INFO' -Message ("Profile initialized. InstanceId=$(Get-UGSMGameMinecraftJavaInstanceId -Instance $Instance); Profile=$($paths.ProfileName)")
    return [pscustomobject]@{ Success=$true; ProfilePath=$paths.ProfileRoot; ConfigPath=$paths.ServerProperties; InstallPath=$definition.InstallPath }
}

function Test-UGSMGameMinecraftJavaInstance {
    [CmdletBinding()]
    param([Parameter(Mandatory)][object]$Instance, [string]$InstallPath)
    $paths = Get-UGSMGameMinecraftJavaProfilePaths -Instance $Instance -InstallPath $InstallPath
    $ok = (Test-Path -LiteralPath $paths.SettingsPath -PathType Leaf)
    return [pscustomobject]@{ Success=[bool]$ok; Exists=[bool]$ok; ProfilePath=$paths.ProfileRoot; ConfigPath=$paths.ServerProperties; Message=if ($ok) { 'Minecraft Java profile exists.' } else { 'Minecraft Java profile has not been initialized.' } }
}

function ConvertTo-UGSMGameMinecraftJavaRedactedText {
    [CmdletBinding()]
    param([AllowNull()][string]$Text)
    if ([string]::IsNullOrWhiteSpace($Text)) { return $Text }
    $value = [string]$Text
    $value = [regex]::Replace($value, '(?i)(rcon\.password\s*=\s*)[^\r\n\s]+', '$1<redacted>')
    $value = [regex]::Replace($value, '(?i)(-D[^\s]*(password|token|secret|key)[^\s]*=)[^\s]+', '$1<redacted>')
    return $value
}

function Get-UGSMGameMinecraftJavaRuntimeInfo {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$JavaPath)
    $raw = ''
    $major = 0
    try {
        $raw = (& $JavaPath -version 2>&1 | Out-String).Trim()
        if ($raw -match 'version\s+"(?<major>\d+)') { $major = [int]$Matches['major'] }
        elseif ($raw -match 'openjdk\s+(?<major>\d+)') { $major = [int]$Matches['major'] }
    } catch {
        $raw = $_.Exception.Message
    }
    return [pscustomobject]@{ Raw=$raw; Major=$major }
}




function Get-UGSMGameMinecraftJavaDetectedJavaMajor {
    [CmdletBinding()]
    param()
    $javaCmd = Get-Command -Name 'java.exe' -ErrorAction SilentlyContinue
    if (-not $javaCmd) { return 0 }
    try {
        $javaInfo = Get-UGSMGameMinecraftJavaRuntimeInfo -JavaPath ([string]$javaCmd.Source)
        return [int]$javaInfo.Major
    } catch { return 0 }
}

function Get-UGSMGameMinecraftJavaUpdateMessage {
    [CmdletBinding()]
    param([int]$RequiredJavaMajor, [int]$DetectedJavaMajor)
    if ($DetectedJavaMajor -gt 0) {
        return ("Detected Java {0}. The selected Minecraft server requires Java {1} or newer. Update Java or select 'latest-compatible'. Recommended free options: Microsoft Build of OpenJDK or Eclipse Temurin." -f $DetectedJavaMajor, $RequiredJavaMajor)
    }
    return ("Java was not detected. Install Java {0} or newer. Recommended free options: Microsoft Build of OpenJDK or Eclipse Temurin." -f $RequiredJavaMajor)
}

function Get-UGSMGameMinecraftJavaRequiredJavaMajor {
    [CmdletBinding()]
    param([Parameter(Mandatory)][object]$Definition)
    $major = 21
    try {
        if (Test-Path -LiteralPath $Definition.VersionInfoPath -PathType Leaf) {
            $info = Get-Content -LiteralPath $Definition.VersionInfoPath -Raw -ErrorAction Stop | ConvertFrom-Json
            if ($info.PSObject.Properties['JavaMajor'] -and ([int]$info.JavaMajor) -gt 0) { return [int]$info.JavaMajor }
            if ($info.PSObject.Properties['Version'] -and -not [string]::IsNullOrWhiteSpace([string]$info.Version)) {
                # Refresh only the small Mojang metadata file so UGSM can show a clean Java requirement.
                $latest = Get-UGSMGameMinecraftJavaLatestServerDownload
                if ([string]$latest.Version -eq [string]$info.Version -and [int]$latest.JavaMajor -gt 0) {
                    $merged = [pscustomobject]@{
                        Version   = [string]$info.Version
                        Url       = if ($info.PSObject.Properties['Url']) { [string]$info.Url } else { [string]$latest.Url }
                        Sha1      = if ($info.PSObject.Properties['Sha1']) { [string]$info.Sha1 } else { [string]$latest.Sha1 }
                        Size      = if ($info.PSObject.Properties['Size']) { [int64]$info.Size } else { [int64]$latest.Size }
                        JavaMajor = [int]$latest.JavaMajor
                    }
                    $merged | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $Definition.VersionInfoPath -Encoding UTF8
                    return [int]$latest.JavaMajor
                }
            }
        }
    } catch {
        Write-UGSMGameMinecraftJavaLog -Level 'WARN' -Message 'Could not determine exact Minecraft Java runtime requirement; using Java 21 as fallback.' -Exception $_.Exception
    }
    return $major
}

function Start-UGSMGameMinecraftJavaInstance {
    [CmdletBinding()]
    param([Parameter(Mandatory)][object]$Instance, [string]$InstallPath)
    $instanceId = Get-UGSMGameMinecraftJavaInstanceId -Instance $Instance
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    Write-UGSMGameMinecraftJavaLog -Level 'INFO' -Message ("Start requested. InstanceId=$instanceId")
    $definition = Get-UGSMGameMinecraftJavaInstallDefinition -InstallPath $InstallPath -Instance $Instance
    Initialize-UGSMGameMinecraftJavaProfile -Instance $Instance -InstallPath $definition.InstallPath | Out-Null
    $paths = Get-UGSMGameMinecraftJavaProfilePaths -Instance $Instance -InstallPath $definition.InstallPath
    $settings = Get-UGSMGameMinecraftJavaSettings -Instance $Instance -InstallPath $definition.InstallPath
    if (-not [bool]$settings.AcceptEula) { throw 'Minecraft Java EULA has not been accepted. Open the editor, check Accept Minecraft EULA, save, then start again.' }
    $selectedVersion = if ($settings.PSObject.Properties['MinecraftVersion']) { [string]$settings.MinecraftVersion } else { 'latest-compatible' }
    if ([string]::IsNullOrWhiteSpace($selectedVersion)) { $selectedVersion = 'latest-compatible' }
    $detectedJavaForDownload = Get-UGSMGameMinecraftJavaDetectedJavaMajor
    if (-not (Test-Path -LiteralPath $definition.ServerJarPath -PathType Leaf)) { Ensure-UGSMGameMinecraftJavaServerJar -Definition $definition -TargetVersion $selectedVersion -MaxJavaMajor $detectedJavaForDownload | Out-Null }
    if (-not (Test-UGSMGameMinecraftJavaServerJarHash -Definition $definition)) { Write-UGSMGameMinecraftJavaLog -Level 'WARN' -Message 'Minecraft Java server.jar hash mismatch; redownloading official jar.'; Ensure-UGSMGameMinecraftJavaServerJar -Definition $definition -Force -TargetVersion $selectedVersion -MaxJavaMajor $detectedJavaForDownload | Out-Null }
    $javaCmd = Get-Command -Name 'java.exe' -ErrorAction SilentlyContinue
    if (-not $javaCmd) { throw 'java.exe was not found in PATH. Install the Java runtime required by the selected Minecraft server.jar, then restart UGSM.' }
    $javaInfo = Get-UGSMGameMinecraftJavaRuntimeInfo -JavaPath ([string]$javaCmd.Source)
    $requiredJavaMajor = Get-UGSMGameMinecraftJavaRequiredJavaMajor -Definition $definition
    if ($javaInfo.Major -gt 0 -and $javaInfo.Major -lt $requiredJavaMajor) {
        throw (Get-UGSMGameMinecraftJavaUpdateMessage -RequiredJavaMajor $requiredJavaMajor -DetectedJavaMajor $javaInfo.Major)
    }
    Save-UGSMGameMinecraftJavaSettings -Instance $Instance -Settings $settings -InstallPath $definition.InstallPath | Out-Null

    $min = [Math]::Max(256, [int]$settings.MemoryMinMB)
    $max = [Math]::Max($min, [int]$settings.MemoryMaxMB)
    $argParts = New-Object System.Collections.Generic.List[string]
    $argParts.Add(("-Xms{0}M" -f $min)) | Out-Null
    $argParts.Add(("-Xmx{0}M" -f $max)) | Out-Null
    if (-not [string]::IsNullOrWhiteSpace([string]$settings.ExtraJavaArgs)) { $argParts.Add([string]$settings.ExtraJavaArgs) | Out-Null }
    $argParts.Add('-jar') | Out-Null
    $argParts.Add(('"{0}"' -f $definition.ServerJarPath)) | Out-Null
    $argParts.Add('nogui') | Out-Null
    $argString = ($argParts -join ' ')

    try {
        $header = @(
            ('[{0}] UGSM starting Minecraft Java.' -f (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')),
            ('Profile: {0}' -f $paths.ProfileName),
            ('ServerJar: {0}' -f $definition.ServerJarPath),
            ('GamePort: {0}' -f $settings.GamePort),
            ('RconPort: {0}' -f $settings.RconPort),
            ('JavaArgs: {0}' -f (ConvertTo-UGSMGameMinecraftJavaRedactedText -Text $argString)),
            ('JavaVersion: {0}' -f (($javaInfo.Raw -split "`r?`n" | Select-Object -First 1))),
            ('RequiredJavaMajor: {0}' -f $requiredJavaMajor),
            ''
        )
        Set-Content -LiteralPath $paths.LaunchLogPath -Value $header -Encoding UTF8
        Set-Content -LiteralPath $paths.ErrorLogPath -Value @() -Encoding UTF8
    } catch {}

    # Stable launcher path for first Minecraft Java pass.
    # Run Java through a tiny cmd wrapper so stdout/stderr are captured without
    # async .NET event handlers, which previously destabilized the WinForms host.
    $launcherPath = Join-Path $paths.ProfileRoot 'UGSM_Start_MinecraftJava.cmd'
    $javaExe = [string]$javaCmd.Source
    $consoleLog = $paths.LaunchLogPath
    $errorLog = $paths.ErrorLogPath
    $batchLines = @(
        '@echo off',
        'setlocal',
        ('cd /d "{0}"' -f $paths.ProfileRoot),
        ('echo [{0}] UGSM Minecraft Java cmd launcher started. Profile={1}>>"{2}"' -f (Get-Date).ToString('yyyy-MM-dd HH:mm:ss'), $paths.ProfileName, $consoleLog),
        ('"{0}" {1} >>"{2}" 2>>"{3}"' -f $javaExe, $argString, $consoleLog, $errorLog),
        'set EXITCODE=%ERRORLEVEL%',
        ('echo [{0}] Java process exited with code %EXITCODE%.>>"{1}"' -f (Get-Date).ToString('yyyy-MM-dd HH:mm:ss'), $consoleLog),
        'exit /b %EXITCODE%'
    )
    Set-Content -LiteralPath $launcherPath -Value $batchLines -Encoding ASCII

    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = 'cmd.exe'
    $psi.WorkingDirectory = $paths.ProfileRoot
    $psi.Arguments = ('/c "{0}"' -f $launcherPath)
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true
    $process = New-Object System.Diagnostics.Process
    $process.StartInfo = $psi
    [void]$process.Start()
    Start-Sleep -Seconds 8
    try { $process.Refresh() } catch {}
    if ($process.HasExited) {
        try { Add-UGSMGameMinecraftJavaRecentServerLogToLaunchLog -Paths $paths } catch {}
        try { Add-Content -LiteralPath $paths.LaunchLogPath -Value ("[{0}] Minecraft Java launcher exited with code {1}." -f (Get-Date).ToString('yyyy-MM-dd HH:mm:ss'), $process.ExitCode) -Encoding UTF8 } catch {}
        throw "Minecraft Java process exited immediately with code $($process.ExitCode). Check $($paths.LaunchLogPath) and $($paths.ErrorLogPath)."
    }
    $script:UGSM_MinecraftJavaProcesses[$instanceId] = $process
    $runtime = [pscustomobject]@{ ProcessId=[int]$process.Id; StartedAt=(Get-Date).ToString('o'); ProfileName=$paths.ProfileName; Jar=$definition.ServerJarPath }
    try { $runtime | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $paths.RuntimeStatePath -Encoding UTF8 } catch {}
    if ($Instance.PSObject.Properties['ProcessId']) { $Instance.ProcessId = [int]$process.Id } else { Add-Member -InputObject $Instance -MemberType NoteProperty -Name ProcessId -Value ([int]$process.Id) -Force }
    if ($Instance.PSObject.Properties['Status']) { $Instance.Status = 'Running' } else { Add-Member -InputObject $Instance -MemberType NoteProperty -Name Status -Value 'Running' -Force }
    if (Get-Command -Name Send-UGSMInstanceDiscordNotification -ErrorAction SilentlyContinue) {
        try { Send-UGSMInstanceDiscordNotification -Instance $Instance -Event 'Start' | Out-Null } catch { Write-UGSMGameMinecraftJavaLog -Level 'WARN' -Message ("Discord start notification failed. InstanceId=$instanceId") -Exception $_.Exception }
    }
    $sw.Stop()
    Write-UGSMGameMinecraftJavaLog -Level 'INFO' -Message ("Start completed. InstanceId=$instanceId; Pid=$($process.Id); DurationMs=$($sw.ElapsedMilliseconds)")
    return [pscustomobject]@{ Success=$true; Status='Running'; ProcessId=[int]$process.Id; Pid=[int]$process.Id }
}

function Stop-UGSMGameMinecraftJavaInstance {
    [CmdletBinding()]
    param([Parameter(Mandatory)][object]$Instance)
    $instanceId = Get-UGSMGameMinecraftJavaInstanceId -Instance $Instance
    $profileName = Get-UGSMGameMinecraftJavaProfileName -Instance $Instance
    $processId = 0
    if ($Instance.PSObject.Properties['ProcessId'] -and ($Instance.ProcessId -as [int])) { $processId = [int]$Instance.ProcessId }
    Write-UGSMGameMinecraftJavaLog -Level 'INFO' -Message ("Stop requested. InstanceId=$instanceId; Pid=$processId")
    $stopped = $false
    $graceful = $false

    if ($script:UGSM_MinecraftJavaProcesses.ContainsKey($instanceId)) {
        $procObj = $script:UGSM_MinecraftJavaProcesses[$instanceId]
        try {
            if ($procObj -and -not $procObj.HasExited -and $procObj.StartInfo -and [bool]$procObj.StartInfo.RedirectStandardInput) {
                $procObj.StandardInput.WriteLine('say Server stopping by UGSM.')
                $procObj.StandardInput.Flush()
                Start-Sleep -Milliseconds 500
                $procObj.StandardInput.WriteLine('stop')
                $procObj.StandardInput.Flush()
                $graceful = $procObj.WaitForExit(30000)
                $stopped = $graceful
            }
        } catch { Write-UGSMGameMinecraftJavaLog -Level 'WARN' -Message ("Graceful stdin stop failed. InstanceId=$instanceId") -Exception $_.Exception }
    }

    if (-not $stopped -and $processId -gt 0) {
        try {
            $proc = Get-Process -Id $processId -ErrorAction Stop
            Stop-Process -Id $processId -Force -ErrorAction Stop
            $stopped = $true
        } catch [System.ArgumentException] { $stopped = $true } catch { Write-UGSMGameMinecraftJavaLog -Level 'ERROR' -Message ("Forced stop failed. InstanceId=$instanceId; Pid=$processId") -Exception $_.Exception }
    }

    try {
        Get-CimInstance Win32_Process -Filter "name = 'java.exe' or name = 'javaw.exe'" -ErrorAction SilentlyContinue |
            Where-Object { $_.CommandLine -match [Regex]::Escape($profileName) -or $_.CommandLine -match 'server\.jar' -and $_.CommandLine -match 'nogui' } |
            ForEach-Object { Stop-Process -Id ([int]$_.ProcessId) -Force -ErrorAction SilentlyContinue; $stopped = $true }
    } catch {}

    if ($script:UGSM_MinecraftJavaProcesses.ContainsKey($instanceId)) { $script:UGSM_MinecraftJavaProcesses.Remove($instanceId) }
    if ($Instance.PSObject.Properties['Status']) { $Instance.Status = 'Stopped' } else { Add-Member -InputObject $Instance -MemberType NoteProperty -Name Status -Value 'Stopped' -Force }
    if ($Instance.PSObject.Properties['ProcessId']) { $Instance.ProcessId = $null }
    if (Get-Command -Name Send-UGSMInstanceDiscordNotification -ErrorAction SilentlyContinue) {
        try { Send-UGSMInstanceDiscordNotification -Instance $Instance -Event 'Stop' | Out-Null } catch { Write-UGSMGameMinecraftJavaLog -Level 'WARN' -Message ("Discord stop notification failed. InstanceId=$instanceId") -Exception $_.Exception }
    }
    Write-UGSMGameMinecraftJavaLog -Level 'INFO' -Message ("Stop completed. InstanceId=$instanceId; Stopped=$stopped; Graceful=$graceful")
    return [pscustomobject]@{ Success=$true; Status='Stopped'; Stopped=[bool]$stopped; Graceful=[bool]$graceful }
}

function Get-UGSMGameMinecraftJavaColor {
    [CmdletBinding()]
    param([AllowNull()][object]$Theme, [Parameter(Mandatory)][string]$Name, [System.Drawing.Color]$Fallback)
    if ($Theme) {
        $prop = $Theme.PSObject.Properties[$Name]
        if ($prop -and $prop.Value -is [System.Drawing.Color]) { return $prop.Value }
    }
    $globalName = switch ($Name) {
        'Background' { 'UGSM_ColorBackground' }
        'Surface' { 'UGSM_ColorSurface' }
        'Input' { 'UGSM_ColorInputBackground' }
        'Text' { 'UGSM_ColorText' }
        'Muted' { 'UGSM_ColorMutedText' }
        'Accent' { 'UGSM_ColorAccent' }
        default { '' }
    }
    if ($globalName -and (Get-Variable -Name $globalName -Scope Global -ErrorAction SilentlyContinue)) {
        $value = (Get-Variable -Name $globalName -Scope Global).Value
        if ($value -is [System.Drawing.Color]) { return $value }
    }
    return $Fallback
}

function Add-UGSMGameMinecraftJavaField {
    param([System.Windows.Forms.Panel]$Parent, [hashtable]$Controls, [string]$Key, [string]$Label, [string]$Value, [int]$Row, [object]$Theme, [switch]$Multiline, [int]$Height = 24)
    $labelControl = New-Object System.Windows.Forms.Label
    $labelControl.Text = $Label
    $labelControl.AutoSize = $false
    $labelControl.Left = 24
    $labelControl.Top = 18 + ($Row * 42)
    $labelControl.Width = 190
    $labelControl.Height = 24
    $labelControl.ForeColor = Get-UGSMGameMinecraftJavaColor -Theme $Theme -Name 'Text' -Fallback ([System.Drawing.Color]::White)
    $Parent.Controls.Add($labelControl)
    $txt = New-Object System.Windows.Forms.TextBox
    $txt.Left = 230
    $txt.Top = 14 + ($Row * 42)
    $txt.Width = 520
    $txt.Height = $Height
    $txt.Text = $Value
    $txt.Multiline = [bool]$Multiline
    if ($Multiline) { $txt.ScrollBars = 'Vertical'; $txt.AcceptsReturn = $true }
    $txt.ForeColor = Get-UGSMGameMinecraftJavaColor -Theme $Theme -Name 'Text' -Fallback ([System.Drawing.Color]::White)
    $txt.BackColor = Get-UGSMGameMinecraftJavaColor -Theme $Theme -Name 'Input' -Fallback ([System.Drawing.Color]::FromArgb(2,12,24))
    $Parent.Controls.Add($txt)
    $Controls[$Key] = $txt
    return $txt
}

function Add-UGSMGameMinecraftJavaCheckField {
    param([System.Windows.Forms.Panel]$Parent, [hashtable]$Controls, [string]$Key, [string]$Label, [bool]$Value, [int]$Row, [object]$Theme)
    $chk = New-Object System.Windows.Forms.CheckBox
    $chk.Left = 230
    $chk.Top = 16 + ($Row * 42)
    $chk.Width = 560
    $chk.Height = 24
    $chk.Text = $Label
    $chk.Checked = [bool]$Value
    $chk.ForeColor = Get-UGSMGameMinecraftJavaColor -Theme $Theme -Name 'Text' -Fallback ([System.Drawing.Color]::White)
    $chk.BackColor = Get-UGSMGameMinecraftJavaColor -Theme $Theme -Name 'Background' -Fallback ([System.Drawing.Color]::FromArgb(8,18,31))
    $Parent.Controls.Add($chk)
    $Controls[$Key] = $chk
    return $chk
}

function Add-UGSMGameMinecraftJavaNote {
    param([System.Windows.Forms.Panel]$Parent, [string]$Text, [int]$Top, [object]$Theme)
    $lbl = New-Object System.Windows.Forms.Label
    $lbl.Left = 24
    $lbl.Top = $Top
    $lbl.Width = 760
    $lbl.Height = 48
    $lbl.AutoSize = $false
    $lbl.Text = $Text
    $lbl.ForeColor = Get-UGSMGameMinecraftJavaColor -Theme $Theme -Name 'Muted' -Fallback ([System.Drawing.Color]::LightGray)
    $Parent.Controls.Add($lbl)
    return $lbl
}

function Save-UGSMGameMinecraftJavaInstanceEditor {
    [CmdletBinding()]
    param([Parameter(Mandatory)][object]$EditorState)
    $instance = $EditorState.Instance
    $controls = $EditorState.Controls
    $settings = Get-UGSMGameMinecraftJavaSettings -Instance $instance
    foreach ($name in @('ServerName','Motd','Difficulty','Gamemode','LevelName','LevelSeed','RconPassword','ExtraJavaArgs','ExtraServerProperties','MinecraftVersion')) {
        if ($controls.ContainsKey($name)) { $settings.$name = [string]$controls[$name].Text }
    }
    foreach ($name in @('GamePort','MaxPlayers','ViewDistance','SimulationDistance','SpawnProtection','RconPort','MemoryMinMB','MemoryMaxMB')) {
        if ($controls.ContainsKey($name)) { $n = 0; if ([int]::TryParse([string]$controls[$name].Text, [ref]$n)) { $settings.$name = $n } }
    }
    foreach ($name in @('OnlineMode','EnforceSecureProfile','Pvp','AllowNether','EnableCommandBlock','Whitelist','EnableRcon','AcceptEula')) {
        if ($controls.ContainsKey($name)) { $settings.$name = [bool]$controls[$name].Checked }
    }
    if ($controls.ContainsKey('DiscordWebhookUrl')) { $settings.Discord.WebhookUrl = [string]$controls['DiscordWebhookUrl'].Text }
    if ($controls.ContainsKey('NotifyOnStart')) { $settings.Discord.NotifyOnStart = [bool]$controls['NotifyOnStart'].Checked }
    if ($controls.ContainsKey('NotifyOnStop')) { $settings.Discord.NotifyOnStop = [bool]$controls['NotifyOnStop'].Checked }
    if ($controls.ContainsKey('ShowInDashboard')) { $settings.Discord.ShowInDashboard = [bool]$controls['ShowInDashboard'].Checked }
    return Save-UGSMGameMinecraftJavaSettings -Instance $instance -Settings $settings
}

function New-UGSMGameMinecraftJavaInstanceEditor {
    [CmdletBinding()]
    param([Parameter(Mandatory)][object]$Instance, [Parameter(Mandatory)][System.Windows.Forms.Control]$HostPanel, [AllowNull()][object]$Theme, [AllowNull()][System.Windows.Forms.Label]$StatusLabel)
    $instanceId = Get-UGSMGameMinecraftJavaInstanceId -Instance $Instance
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    Write-UGSMGameMinecraftJavaLog -Level 'INFO' -Message ("Editor creation started. InstanceId=$instanceId")
    $HostPanel.SuspendLayout()
    try {
        $HostPanel.Controls.Clear()
        $HostPanel.BackColor = Get-UGSMGameMinecraftJavaColor -Theme $Theme -Name 'Background' -Fallback ([System.Drawing.Color]::FromArgb(8,18,31))
        $tabs = New-Object System.Windows.Forms.TabControl
        $tabs.Dock = 'Fill'
        $tabs.Multiline = $false
        $HostPanel.Controls.Add($tabs)
        $settings = Get-UGSMGameMinecraftJavaSettings -Instance $Instance
        $controls = @{}

        $serverTab = New-Object System.Windows.Forms.TabPage
        $serverTab.Text = 'Server'
        $serverPanel = New-Object System.Windows.Forms.Panel
        $serverPanel.Dock = 'Fill'
        $serverPanel.AutoScroll = $true
        $serverPanel.BackColor = $HostPanel.BackColor
        $serverTab.Controls.Add($serverPanel)
        [void]$tabs.TabPages.Add($serverTab)
        Add-UGSMGameMinecraftJavaNote -Parent $serverPanel -Text 'Minecraft Java server files are downloaded from Mojang. You must accept the Minecraft EULA before starting the server.' -Top 8 -Theme $Theme | Out-Null
        Add-UGSMGameMinecraftJavaField -Parent $serverPanel -Controls $controls -Key 'ServerName' -Label 'Server name' -Value $settings.ServerName -Row 2 -Theme $Theme | Out-Null
        Add-UGSMGameMinecraftJavaField -Parent $serverPanel -Controls $controls -Key 'Motd' -Label 'MOTD' -Value $settings.Motd -Row 3 -Theme $Theme | Out-Null
        Add-UGSMGameMinecraftJavaField -Parent $serverPanel -Controls $controls -Key 'GamePort' -Label 'Server port' -Value ([string]$settings.GamePort) -Row 4 -Theme $Theme | Out-Null
        Add-UGSMGameMinecraftJavaField -Parent $serverPanel -Controls $controls -Key 'MaxPlayers' -Label 'Max players' -Value ([string]$settings.MaxPlayers) -Row 5 -Theme $Theme | Out-Null
        Add-UGSMGameMinecraftJavaField -Parent $serverPanel -Controls $controls -Key 'LevelName' -Label 'World folder/name' -Value $settings.LevelName -Row 6 -Theme $Theme | Out-Null
        Add-UGSMGameMinecraftJavaField -Parent $serverPanel -Controls $controls -Key 'LevelSeed' -Label 'World seed optional' -Value $settings.LevelSeed -Row 7 -Theme $Theme | Out-Null
        Add-UGSMGameMinecraftJavaField -Parent $serverPanel -Controls $controls -Key 'Difficulty' -Label 'Difficulty' -Value $settings.Difficulty -Row 8 -Theme $Theme | Out-Null
        Add-UGSMGameMinecraftJavaField -Parent $serverPanel -Controls $controls -Key 'Gamemode' -Label 'Game mode' -Value $settings.Gamemode -Row 9 -Theme $Theme | Out-Null
        Add-UGSMGameMinecraftJavaCheckField -Parent $serverPanel -Controls $controls -Key 'OnlineMode' -Label 'Online mode / authenticate players' -Value ([bool]$settings.OnlineMode) -Row 10 -Theme $Theme | Out-Null
        Add-UGSMGameMinecraftJavaCheckField -Parent $serverPanel -Controls $controls -Key 'EnforceSecureProfile' -Label 'Enforce secure profile' -Value ([bool]$settings.EnforceSecureProfile) -Row 11 -Theme $Theme | Out-Null
        Add-UGSMGameMinecraftJavaCheckField -Parent $serverPanel -Controls $controls -Key 'AcceptEula' -Label 'I accept the Minecraft EULA for this server' -Value ([bool]$settings.AcceptEula) -Row 12 -Theme $Theme | Out-Null

        $gameplayTab = New-Object System.Windows.Forms.TabPage
        $gameplayTab.Text = 'Gameplay'
        $gameplayPanel = New-Object System.Windows.Forms.Panel
        $gameplayPanel.Dock = 'Fill'
        $gameplayPanel.AutoScroll = $true
        $gameplayPanel.BackColor = $HostPanel.BackColor
        $gameplayTab.Controls.Add($gameplayPanel)
        [void]$tabs.TabPages.Add($gameplayTab)
        Add-UGSMGameMinecraftJavaField -Parent $gameplayPanel -Controls $controls -Key 'ViewDistance' -Label 'View distance' -Value ([string]$settings.ViewDistance) -Row 0 -Theme $Theme | Out-Null
        Add-UGSMGameMinecraftJavaField -Parent $gameplayPanel -Controls $controls -Key 'SimulationDistance' -Label 'Simulation distance' -Value ([string]$settings.SimulationDistance) -Row 1 -Theme $Theme | Out-Null
        Add-UGSMGameMinecraftJavaField -Parent $gameplayPanel -Controls $controls -Key 'SpawnProtection' -Label 'Spawn protection' -Value ([string]$settings.SpawnProtection) -Row 2 -Theme $Theme | Out-Null
        Add-UGSMGameMinecraftJavaCheckField -Parent $gameplayPanel -Controls $controls -Key 'Pvp' -Label 'Enable PvP' -Value ([bool]$settings.Pvp) -Row 3 -Theme $Theme | Out-Null
        Add-UGSMGameMinecraftJavaCheckField -Parent $gameplayPanel -Controls $controls -Key 'AllowNether' -Label 'Allow Nether' -Value ([bool]$settings.AllowNether) -Row 4 -Theme $Theme | Out-Null
        Add-UGSMGameMinecraftJavaCheckField -Parent $gameplayPanel -Controls $controls -Key 'EnableCommandBlock' -Label 'Enable command blocks' -Value ([bool]$settings.EnableCommandBlock) -Row 5 -Theme $Theme | Out-Null
        Add-UGSMGameMinecraftJavaCheckField -Parent $gameplayPanel -Controls $controls -Key 'Whitelist' -Label 'Enable whitelist' -Value ([bool]$settings.Whitelist) -Row 6 -Theme $Theme | Out-Null

        $advancedTab = New-Object System.Windows.Forms.TabPage
        $advancedTab.Text = 'Java / Advanced'
        $advancedPanel = New-Object System.Windows.Forms.Panel
        $advancedPanel.Dock = 'Fill'
        $advancedPanel.AutoScroll = $true
        $advancedPanel.BackColor = $HostPanel.BackColor
        $advancedTab.Controls.Add($advancedPanel)
        [void]$tabs.TabPages.Add($advancedTab)
        Add-UGSMGameMinecraftJavaNote -Parent $advancedPanel -Text 'Minecraft version: use latest-compatible to run the newest server.jar your installed Java supports. Use latest to require the newest Java. Free Java options: Microsoft Build of OpenJDK or Eclipse Temurin.' -Top 8 -Theme $Theme | Out-Null
        Add-UGSMGameMinecraftJavaField -Parent $advancedPanel -Controls $controls -Key 'MinecraftVersion' -Label 'Minecraft version' -Value ([string]$settings.MinecraftVersion) -Row 2 -Theme $Theme | Out-Null
        Add-UGSMGameMinecraftJavaField -Parent $advancedPanel -Controls $controls -Key 'MemoryMinMB' -Label 'Min memory MB' -Value ([string]$settings.MemoryMinMB) -Row 3 -Theme $Theme | Out-Null
        Add-UGSMGameMinecraftJavaField -Parent $advancedPanel -Controls $controls -Key 'MemoryMaxMB' -Label 'Max memory MB' -Value ([string]$settings.MemoryMaxMB) -Row 4 -Theme $Theme | Out-Null
        Add-UGSMGameMinecraftJavaCheckField -Parent $advancedPanel -Controls $controls -Key 'EnableRcon' -Label 'Enable RCON' -Value ([bool]$settings.EnableRcon) -Row 5 -Theme $Theme | Out-Null
        Add-UGSMGameMinecraftJavaField -Parent $advancedPanel -Controls $controls -Key 'RconPort' -Label 'RCON port' -Value ([string]$settings.RconPort) -Row 6 -Theme $Theme | Out-Null
        Add-UGSMGameMinecraftJavaField -Parent $advancedPanel -Controls $controls -Key 'RconPassword' -Label 'RCON password' -Value ([string]$settings.RconPassword) -Row 7 -Theme $Theme | Out-Null
        Add-UGSMGameMinecraftJavaField -Parent $advancedPanel -Controls $controls -Key 'ExtraJavaArgs' -Label 'Extra Java args' -Value ([string]$settings.ExtraJavaArgs) -Row 8 -Theme $Theme -Multiline -Height 70 | Out-Null
        Add-UGSMGameMinecraftJavaField -Parent $advancedPanel -Controls $controls -Key 'ExtraServerProperties' -Label 'Extra properties' -Value ([string]$settings.ExtraServerProperties) -Row 10 -Theme $Theme -Multiline -Height 160 | Out-Null

        $discordTab = New-Object System.Windows.Forms.TabPage
        $discordTab.Text = 'Discord'
        $discordPanel = New-Object System.Windows.Forms.Panel
        $discordPanel.Dock = 'Fill'
        $discordPanel.AutoScroll = $true
        $discordPanel.BackColor = $HostPanel.BackColor
        $discordTab.Controls.Add($discordPanel)
        [void]$tabs.TabPages.Add($discordTab)
        Add-UGSMGameMinecraftJavaField -Parent $discordPanel -Controls $controls -Key 'DiscordWebhookUrl' -Label 'Private Discord webhook URL' -Value $settings.Discord.WebhookUrl -Row 0 -Theme $Theme | Out-Null
        Add-UGSMGameMinecraftJavaCheckField -Parent $discordPanel -Controls $controls -Key 'NotifyOnStart' -Label 'Notify on Start' -Value ([bool]$settings.Discord.NotifyOnStart) -Row 1 -Theme $Theme | Out-Null
        Add-UGSMGameMinecraftJavaCheckField -Parent $discordPanel -Controls $controls -Key 'NotifyOnStop' -Label 'Notify on Stop' -Value ([bool]$settings.Discord.NotifyOnStop) -Row 2 -Theme $Theme | Out-Null
        Add-UGSMGameMinecraftJavaCheckField -Parent $discordPanel -Controls $controls -Key 'ShowInDashboard' -Label 'Show in Discord/dashboard status' -Value ([bool]$settings.Discord.ShowInDashboard) -Row 3 -Theme $Theme | Out-Null
        $btnTestDiscord = New-Object System.Windows.Forms.Button
        $btnTestDiscord.Text = 'Test Discord'
        $btnTestDiscord.Left = 230; $btnTestDiscord.Top = 190; $btnTestDiscord.Width = 160; $btnTestDiscord.Height = 30
        $btnTestDiscord.Tag = [pscustomobject]@{ Instance=$Instance; Controls=$controls; StatusLabel=$StatusLabel }
        $btnTestDiscord.Add_Click({ param($sender,$eventArgs) $st=$sender.Tag; try { Save-UGSMGameMinecraftJavaInstanceEditor -EditorState $st | Out-Null; if (Get-Command -Name Send-UGSMInstanceDiscordNotification -ErrorAction SilentlyContinue) { Send-UGSMInstanceDiscordNotification -Instance $st.Instance -Event 'Test' | Out-Null }; if ($st.StatusLabel) { $st.StatusLabel.Text = 'Minecraft Java Discord test sent.' } } catch { if ($st.StatusLabel) { $st.StatusLabel.Text = 'Minecraft Java Discord test failed: ' + $_.Exception.Message }; Write-UGSMGameMinecraftJavaLog -Level 'ERROR' -Message 'Discord test failed.' -Exception $_.Exception } })
        $discordPanel.Controls.Add($btnTestDiscord)

        $btnSave = New-Object System.Windows.Forms.Button
        $btnSave.Text = 'Save Settings'
        $btnSave.Dock = 'Bottom'
        $btnSave.Height = 32
        $btnSave.Tag = [pscustomobject]@{ Instance=$Instance; Controls=$controls; StatusLabel=$StatusLabel }
        $btnSave.Add_Click({ param($sender,$eventArgs) $st=$sender.Tag; try { Save-UGSMGameMinecraftJavaInstanceEditor -EditorState $st | Out-Null; if ($st.StatusLabel) { $st.StatusLabel.Text = 'Minecraft Java settings saved.' } } catch { if ($st.StatusLabel) { $st.StatusLabel.Text = 'Minecraft Java save failed: ' + $_.Exception.Message }; Write-UGSMGameMinecraftJavaLog -Level 'ERROR' -Message 'Minecraft Java editor save failed.' -Exception $_.Exception } })
        $HostPanel.Controls.Add($btnSave)
        $btnSave.BringToFront()
        $sw.Stop()
        Write-UGSMGameMinecraftJavaLog -Level 'INFO' -Message ("Editor creation completed. InstanceId=$instanceId; DurationMs=$($sw.ElapsedMilliseconds)")
        return [pscustomobject]@{ Success=$true; Controls=$controls }
    } catch {
        Write-UGSMGameMinecraftJavaLog -Level 'ERROR' -Message ("Editor creation failed. InstanceId=$instanceId") -Exception $_.Exception
        throw
    } finally {
        $HostPanel.ResumeLayout($true)
    }
}

function Register-UGSMGameMinecraftJavaModule {
    [CmdletBinding()]
    param()
    $metadata = Get-UGSMGameMinecraftJavaMetadata
    return [pscustomobject]@{
        Id       = [string]$metadata.Id
        Metadata = $metadata
        Handlers = [pscustomobject]@{
            GetMetadata       = 'Get-UGSMGameMinecraftJavaMetadata'
            TestInstall       = 'Test-UGSMGameMinecraftJavaInstall'
            Install           = 'Install-UGSMGameMinecraftJavaServer'
            TestInstance      = 'Test-UGSMGameMinecraftJavaInstance'
            EnsureTemplate    = 'Ensure-UGSMGameMinecraftJavaTemplate'
            InitializeProfile = 'Initialize-UGSMGameMinecraftJavaProfile'
            Start             = 'Start-UGSMGameMinecraftJavaInstance'
            Stop              = 'Stop-UGSMGameMinecraftJavaInstance'
            BuildEditor       = 'New-UGSMGameMinecraftJavaInstanceEditor'
            SaveEditor        = 'Save-UGSMGameMinecraftJavaInstanceEditor'
        }
    }
}
