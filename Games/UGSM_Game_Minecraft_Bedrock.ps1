# UGSM Minecraft Bedrock Dedicated Server module
# First pass: official Windows Bedrock Dedicated Server bootstrap/download, profile settings, start/stop, Discord.

$script:_ugsmMinecraftBedrockProcessesVar = Get-Variable -Name 'UGSM_MinecraftBedrockProcesses' -Scope Script -ErrorAction SilentlyContinue
if ($null -eq $script:_ugsmMinecraftBedrockProcessesVar -or $null -eq $script:_ugsmMinecraftBedrockProcessesVar.Value) {
    $script:UGSM_MinecraftBedrockProcesses = @{}
}
Remove-Variable -Name '_ugsmMinecraftBedrockProcessesVar' -Scope Script -ErrorAction SilentlyContinue

function Write-UGSMGameMinecraftBedrockLog {
    [CmdletBinding()]
    param(
        [ValidateSet('TRACE','DEBUG','INFO','WARN','ERROR','FATAL')][string]$Level = 'INFO',
        [Parameter(Mandatory)][string]$Message,
        [AllowNull()][System.Exception]$Exception
    )
    if ($Level -in @('TRACE','DEBUG') -and -not $env:UGSM_VERBOSE_MINECRAFTBEDROCK) { return }
    if (Get-Command -Name Write-UGSMLog -ErrorAction SilentlyContinue) {
        if ($Exception) { Write-UGSMLog -Level $Level -Category 'MinecraftBedrock' -Message $Message -Exception $Exception }
        else { Write-UGSMLog -Level $Level -Category 'MinecraftBedrock' -Message $Message }
        return
    }
    if ($Exception) { Write-Warning "[MinecraftBedrock] $Message :: $($Exception.Message)" } else { Write-Host "[MinecraftBedrock][$Level] $Message" }
}

function Get-UGSMGameMinecraftBedrockMetadata {
    [CmdletBinding()] param()
    return [pscustomobject]@{
        Id                       = 'MinecraftBedrock'
        Name                     = 'Minecraft Bedrock'
        Category                 = 'Sandbox'
        Description              = 'Minecraft Bedrock Dedicated Server for Windows using the official Bedrock server zip.'
        IsCustom                 = $false
        SupportTier              = 'Basic'
        SortOrder                = 301
        IsVisible                = $true
        SupportedTabs            = @('Home','Games','Instances','Analytics','Tasks','About','Settings')
        UseSteamArt              = $false
        SupportsInstall          = $true
        SupportsUpdate           = $false
        SupportsVerify           = $false
        SupportsRepair           = $false
        SupportsStart            = $true
        SupportsStop             = $true
        SupportsMods             = $false
        SupportsWorkshop         = $false
        SupportsRcon             = $false
        SupportsBootstrap        = $true
        SupportsProfiles         = $true
        SupportsInstanceUi       = $true
        InstallProvider          = 'MojangBedrockDownload'
        RequiresSteamLogin       = $false
        SteamLoginMode           = 'None'
        SteamAppId               = ''
        SteamStoreAppId          = ''
        ServerExecutable         = 'bedrock_server.exe'
        ServerExecutableRelative = 'bedrock_server.exe'
        UsesSharedBinaries       = $true
        InstanceType             = 'DedicatedServer'
        ConfigRootRelative       = '.'
        SaveRootRelative         = 'worlds'
        LogRootRelative          = 'logs'
        RequiredFiles            = @()
        InstallMarkers           = @()
        PortSchema               = @(
            @{ Name='GamePort'; Protocol='UDP'; PreferredStart=19132 },
            @{ Name='IPv6Port'; Protocol='UDP'; PreferredStart=19133 }
        )
        GameTraits               = [pscustomobject]@{
            UsesIniFiles=$false; UsesJsonFiles=$true; UsesXmlFiles=$false; UsesSqlite=$false; UsesProfileSync=$false
            UsesPluginFramework=$false; UsesZipMods=$false; UsesFolderCopyMods=$false; UsesFileMergeWorkflow=$false; UsesMissionFiles=$false; UsesWorkshopItems=$false
        }
        SpecialRequirements      = [pscustomobject]@{
            Notes=@(
                'Minecraft Bedrock does not use SteamCMD and does not require buying the game to download the dedicated server files.',
                'UGSM downloads the official Windows Bedrock Dedicated Server zip on first profile initialization/start if it is missing.',
                'This first pass manages vanilla server.properties only. Add-ons/resource packs should be handled in a later pass.'
            )
        }
    }
}

function Get-UGSMGameMinecraftBedrockInstanceId { [CmdletBinding()] param([AllowNull()][object]$Instance)
    if (-not $Instance) { return '' }
    foreach ($name in @('Id','Name','ProfileName','InstanceId')) { if ($Instance.PSObject.Properties[$name] -and -not [string]::IsNullOrWhiteSpace([string]$Instance.$name)) { return [string]$Instance.$name } }
    return ''
}
function Get-UGSMGameMinecraftBedrockProfileName { [CmdletBinding()] param([AllowNull()][object]$Instance)
    $name = Get-UGSMGameMinecraftBedrockInstanceId -Instance $Instance
    if ([string]::IsNullOrWhiteSpace($name)) { $name = 'MinecraftBedrock1' }
    $safe = $name -replace '[^A-Za-z0-9_.-]','_'
    if ([string]::IsNullOrWhiteSpace($safe)) { $safe = 'MinecraftBedrock1' }
    return $safe
}
function Get-UGSMGameMinecraftBedrockAppDataRoot { [CmdletBinding()] param()
    if (Get-Command -Name Get-UGSMAppDataRoot -ErrorAction SilentlyContinue) { try { return [string](Get-UGSMAppDataRoot) } catch {} }
    return (Join-Path $env:LOCALAPPDATA 'UGSM')
}
function Get-UGSMGameMinecraftBedrockProfileBaseRoot { [CmdletBinding()] param()
    $settings = $null
    if (Get-Command -Name Get-UGSMGlobalSettings -ErrorAction SilentlyContinue) { try { $settings = Get-UGSMGlobalSettings -CreateIfMissing } catch {} }
    if ($settings -and $settings.PSObject.Properties['ProfileBaseRoot'] -and -not [string]::IsNullOrWhiteSpace([string]$settings.ProfileBaseRoot)) { return [string]$settings.ProfileBaseRoot }
    if (Get-Command -Name Get-UGSMDefaultInstanceProfilePath -ErrorAction SilentlyContinue) { try { $probe=Get-UGSMDefaultInstanceProfilePath -GameId 'MinecraftBedrock' -Name '_probe_'; if ($probe) { return (Split-Path -Parent (Split-Path -Parent $probe)) } } catch {} }
    return (Join-Path (Get-UGSMGameMinecraftBedrockAppDataRoot) 'Profiles')
}
function Get-UGSMGameMinecraftBedrockInstallRoot { [CmdletBinding()] param([string]$InstallPath,[AllowNull()][object]$Instance)
    if (-not [string]::IsNullOrWhiteSpace($InstallPath)) { return $InstallPath }
    if ($Instance -and $Instance.PSObject.Properties['InstallPath'] -and -not [string]::IsNullOrWhiteSpace([string]$Instance.InstallPath)) { return [string]$Instance.InstallPath }
    $settings=$null
    if (Get-Command -Name Get-UGSMGlobalSettings -ErrorAction SilentlyContinue) { try { $settings=Get-UGSMGlobalSettings -CreateIfMissing } catch {} }
    $bases=@()
    if ($settings) { foreach ($p in @('InstallRoot','ServerRoot','SteamLibraryRoot','SteamRoot')) { if ($settings.PSObject.Properties[$p] -and -not [string]::IsNullOrWhiteSpace([string]$settings.$p)) { $bases += [string]$settings.$p } } }
    $profileBase = Get-UGSMGameMinecraftBedrockProfileBaseRoot
    if ($profileBase) { try { $bases += (Split-Path -Parent $profileBase) } catch {} }
    $binariesRoot = Join-Path (Get-UGSMGameMinecraftBedrockAppDataRoot) 'Binaries'
    if (-not [string]::IsNullOrWhiteSpace($binariesRoot)) { $bases += $binariesRoot }
    foreach ($base in ($bases | Where-Object { $_ } | Select-Object -Unique)) {
        foreach ($candidate in @((Join-Path $base 'MinecraftBedrock'),(Join-Path $base 'Minecraft Bedrock'),(Join-Path $base 'Binaries\MinecraftBedrock'),(Join-Path $base 'Servers\MinecraftBedrock'))) {
            if (Test-Path -LiteralPath (Join-Path $candidate 'bedrock_server.exe') -PathType Leaf) { return $candidate }
        }
    }
    foreach ($base in ($bases | Where-Object { $_ } | Select-Object -Unique)) { return (Join-Path $base 'MinecraftBedrock') }
    return (Join-Path (Get-UGSMGameMinecraftBedrockAppDataRoot) 'Binaries\MinecraftBedrock')
}
function Get-UGSMGameMinecraftBedrockInstallDefinition { [CmdletBinding()] param([string]$InstallPath,[AllowNull()][object]$Instance)
    $root=Get-UGSMGameMinecraftBedrockInstallRoot -InstallPath $InstallPath -Instance $Instance
    return [pscustomobject]@{ InstallPath=$root; ServerExecutablePath=(Join-Path $root 'bedrock_server.exe'); VersionInfoPath=(Join-Path $root 'UGSM_MinecraftBedrockVersion.json') }
}
function Test-UGSMGameMinecraftBedrockInstall { [CmdletBinding()] param([string]$InstallPath,[AllowNull()][object]$Instance)
    $d=Get-UGSMGameMinecraftBedrockInstallDefinition -InstallPath $InstallPath -Instance $Instance
    $exists=Test-Path -LiteralPath $d.ServerExecutablePath -PathType Leaf
    return [pscustomobject]@{ Success=$true; IsInstalled=$true; InstallPath=$d.InstallPath; ServerExecutablePath=$d.ServerExecutablePath; ServerExists=[bool]$exists; Message=if($exists){'Minecraft Bedrock server detected.'}else{'Minecraft Bedrock will download the official server zip when a profile is created or started.'} }
}

function Get-UGSMGameMinecraftBedrockProfileRoot { [CmdletBinding()] param([Parameter(Mandatory)][object]$Instance)
    foreach ($p in @('ProfilePath','Path','RootPath')) { if ($Instance.PSObject.Properties[$p] -and -not [string]::IsNullOrWhiteSpace([string]$Instance.$p)) { return [string]$Instance.$p } }
    return (Join-Path (Join-Path (Get-UGSMGameMinecraftBedrockProfileBaseRoot) 'MinecraftBedrock') (Get-UGSMGameMinecraftBedrockProfileName -Instance $Instance))
}
function Get-UGSMGameMinecraftBedrockSettingsPath { [CmdletBinding()] param([Parameter(Mandatory)][object]$Instance)
    return (Join-Path (Get-UGSMGameMinecraftBedrockProfileRoot -Instance $Instance) 'UGSM_MinecraftBedrockSettings.json')
}
function Get-UGSMGameMinecraftBedrockPropertiesPath { [CmdletBinding()] param([Parameter(Mandatory)][object]$Instance)
    return (Join-Path (Get-UGSMGameMinecraftBedrockProfileRoot -Instance $Instance) 'server.properties')
}
function Get-UGSMGameMinecraftBedrockLogRoot { [CmdletBinding()] param([Parameter(Mandatory)][object]$Instance)
    $name=Get-UGSMGameMinecraftBedrockProfileName -Instance $Instance
    return (Join-Path (Join-Path (Join-Path (Get-UGSMGameMinecraftBedrockAppDataRoot) 'Logs') 'MinecraftBedrock') $name)
}
function Get-UGSMGameMinecraftBedrockAssignedPort { [CmdletBinding()] param([Parameter(Mandatory)][object]$Instance,[Parameter(Mandatory)][string]$Name,[int]$Default)
    foreach ($propName in @('Ports','AssignedPorts')) {
        if (-not $Instance.PSObject.Properties[$propName]) { continue }
        $ports=$Instance.$propName
        if ($ports -is [hashtable] -and $ports.ContainsKey($Name)) { try { return [int]$ports[$Name] } catch {} }
        if ($ports) { foreach ($p in @($ports)) { if ($p.Name -eq $Name -and $p.Port) { try { return [int]$p.Port } catch {} } } }
    }
    return $Default
}

function Get-UGSMGameMinecraftBedrockDefaultSettings { [CmdletBinding()] param([AllowNull()][object]$Instance)
    $name = if ($Instance) { Get-UGSMGameMinecraftBedrockProfileName -Instance $Instance } else { 'Minecraft Bedrock Server' }
    return [ordered]@{
        ServerName=$name
        Gamemode='survival'
        ForceGamemode=$false
        Difficulty='easy'
        AllowCheats=$false
        MaxPlayers=10
        OnlineMode=$true
        AllowList=$false
        GamePort=19132
        IPv6Port=19133
        ViewDistance=32
        TickDistance=4
        PlayerIdleTimeout=30
        MaxThreads=8
        LevelName='Bedrock level'
        LevelSeed=''
        DefaultPlayerPermissionLevel='member'
        TexturePackRequired=$false
        ContentLogFileEnabled=$false
        CompressionThreshold=1
        ServerAuthoritativeMovement='server-auth'
        PlayerMovementScoreThreshold=20
        PlayerMovementDistanceThreshold='0.3'
        PlayerMovementDurationThresholdInMs=500
        CorrectPlayerMovement=$false
        ExtraProperties=''
        Discord=[ordered]@{ WebhookUrl=''; NotifyOnStart=$false; NotifyOnStop=$false; ShowInDashboard=$false }
    }
}
function Get-UGSMGameMinecraftBedrockSettings { [CmdletBinding()] param([Parameter(Mandatory)][object]$Instance)
    $defaults=Get-UGSMGameMinecraftBedrockDefaultSettings -Instance $Instance
    $path=Get-UGSMGameMinecraftBedrockSettingsPath -Instance $Instance
    if (Test-Path -LiteralPath $path -PathType Leaf) {
        try {
            $json=Get-Content -LiteralPath $path -Raw | ConvertFrom-Json
            foreach ($prop in $json.PSObject.Properties) {
                if ($prop.Name -eq 'Discord' -and $prop.Value) { foreach ($dprop in $prop.Value.PSObject.Properties) { $defaults.Discord[$dprop.Name]=$dprop.Value } }
                else { $defaults[$prop.Name]=$prop.Value }
            }
        } catch { Write-UGSMGameMinecraftBedrockLog -Level 'WARN' -Message 'Failed to read Minecraft Bedrock settings; using defaults.' -Exception $_.Exception }
    }
    $defaults.GamePort = Get-UGSMGameMinecraftBedrockAssignedPort -Instance $Instance -Name 'GamePort' -Default ([int]$defaults.GamePort)
    $defaults.IPv6Port = Get-UGSMGameMinecraftBedrockAssignedPort -Instance $Instance -Name 'IPv6Port' -Default ([int]$defaults.IPv6Port)
    return [pscustomobject]$defaults
}
function Save-UGSMGameMinecraftBedrockSettings { [CmdletBinding()] param([Parameter(Mandatory)][object]$Instance,[Parameter(Mandatory)][object]$Settings)
    $root=Get-UGSMGameMinecraftBedrockProfileRoot -Instance $Instance
    New-Item -ItemType Directory -Force -Path $root | Out-Null
    $path=Get-UGSMGameMinecraftBedrockSettingsPath -Instance $Instance
    $Settings | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $path -Encoding UTF8
}
function ConvertTo-UGSMGameMinecraftBedrockPropertyValue { param([AllowNull()][object]$Value)
    if ($null -eq $Value) { return '' }
    if ($Value -is [bool]) { if ($Value) { return 'true' } else { return 'false' } }
    return [string]$Value
}
function Write-UGSMGameMinecraftBedrockServerProperties { [CmdletBinding()] param([Parameter(Mandatory)][object]$Instance,[Parameter(Mandatory)][object]$Settings)
    $root=Get-UGSMGameMinecraftBedrockProfileRoot -Instance $Instance
    New-Item -ItemType Directory -Force -Path $root | Out-Null
    foreach ($dir in @('worlds','behavior_packs','resource_packs','logs')) { New-Item -ItemType Directory -Force -Path (Join-Path $root $dir) | Out-Null }
    $props=[ordered]@{
        'server-name'=$Settings.ServerName
        'gamemode'=$Settings.Gamemode
        'force-gamemode'=$Settings.ForceGamemode
        'difficulty'=$Settings.Difficulty
        'allow-cheats'=$Settings.AllowCheats
        'max-players'=$Settings.MaxPlayers
        'online-mode'=$Settings.OnlineMode
        'allow-list'=$Settings.AllowList
        'server-port'=$Settings.GamePort
        'server-portv6'=$Settings.IPv6Port
        'view-distance'=$Settings.ViewDistance
        'tick-distance'=$Settings.TickDistance
        'player-idle-timeout'=$Settings.PlayerIdleTimeout
        'max-threads'=$Settings.MaxThreads
        'level-name'=$Settings.LevelName
        'level-seed'=$Settings.LevelSeed
        'default-player-permission-level'=$Settings.DefaultPlayerPermissionLevel
        'texturepack-required'=$Settings.TexturePackRequired
        'content-log-file-enabled'=$Settings.ContentLogFileEnabled
        'compression-threshold'=$Settings.CompressionThreshold
        'server-authoritative-movement'=$Settings.ServerAuthoritativeMovement
        'player-movement-score-threshold'=$Settings.PlayerMovementScoreThreshold
        'player-movement-distance-threshold'=$Settings.PlayerMovementDistanceThreshold
        'player-movement-duration-threshold-in-ms'=$Settings.PlayerMovementDurationThresholdInMs
        'correct-player-movement'=$Settings.CorrectPlayerMovement
    }
    $lines=New-Object System.Collections.Generic.List[string]
    $lines.Add('# Minecraft Bedrock server.properties generated by UGSM')
    $lines.Add('# Secrets are not written to UGSM logs.')
    foreach ($kv in $props.GetEnumerator()) { $lines.Add(('{0}={1}' -f $kv.Key,(ConvertTo-UGSMGameMinecraftBedrockPropertyValue $kv.Value))) }
    if (-not [string]::IsNullOrWhiteSpace([string]$Settings.ExtraProperties)) {
        $lines.Add('')
        $lines.Add('# Extra properties')
        foreach ($line in ([string]$Settings.ExtraProperties -split "`r?`n")) { if (-not [string]::IsNullOrWhiteSpace($line)) { $lines.Add($line) } }
    }
    Set-Content -LiteralPath (Get-UGSMGameMinecraftBedrockPropertiesPath -Instance $Instance) -Value $lines -Encoding UTF8
}

function Get-UGSMGameMinecraftBedrockDownloadUrl { [CmdletBinding()] param()
    # Mojang/Microsoft moved the Bedrock download links behind page JavaScript.
    # Prefer the official download links API, then fall back to page scraping.
    $api='https://net-secondary.web.minecraft-services.net/api/v1.0/download/links'
    try {
        $resp=Invoke-WebRequest -Uri $api -UseBasicParsing -ErrorAction Stop
        $json=$resp.Content | ConvertFrom-Json
        $links=@()
        if ($json -and $json.result -and $json.result.links) { $links=@($json.result.links) }
        foreach ($link in $links) {
            if ([string]$link.downloadType -eq 'serverBedrockWindows' -and -not [string]::IsNullOrWhiteSpace([string]$link.downloadUrl)) {
                return ([string]$link.downloadUrl -replace '&amp;','&')
            }
        }
    } catch { Write-UGSMGameMinecraftBedrockLog -Level 'WARN' -Message 'Failed to discover Bedrock download URL from official download links API.' -Exception $_.Exception }

    $page='https://www.minecraft.net/en-us/download/server/bedrock'
    try {
        $resp=Invoke-WebRequest -Uri $page -UseBasicParsing -ErrorAction Stop
        $text=[string]$resp.Content
        $patterns=@(
            'https?://[^"''<>\s]+/bedrockdedicatedserver/bin-win/bedrock-server-[^"''<>\s]+?\.zip',
            'https?://[^"''<>\s]+/bin-win/bedrock-server-[^"''<>\s]+?\.zip',
            'https?://[^"''<>\s]+bedrock-server-[^"''<>\s]+?\.zip'
        )
        foreach ($pattern in $patterns) {
            $matches=[regex]::Matches($text,$pattern)
            foreach ($m in $matches) { return ($m.Value -replace '&amp;','&') }
        }
        $matches=[regex]::Matches($text,'href=["'']([^"'']+bedrock-server-[^"'']+?\.zip)["'']')
        foreach ($m in $matches) {
            $u=$m.Groups[1].Value -replace '&amp;','&'
            if ($u -like 'http*') { return $u }
            return ([Uri]::new([Uri]$page,$u)).AbsoluteUri
        }
    } catch { Write-UGSMGameMinecraftBedrockLog -Level 'WARN' -Message 'Failed to discover Bedrock download URL from official page.' -Exception $_.Exception }

    throw 'Unable to find the official Minecraft Bedrock Dedicated Server Windows zip URL. Mojang may have changed the download API/page. For now, open the Minecraft Bedrock server download page and install manually.'
}
function Install-UGSMGameMinecraftBedrockServer { [CmdletBinding()] param([string]$InstallPath,[AllowNull()][object]$Instance,[switch]$Force)
    $d=Get-UGSMGameMinecraftBedrockInstallDefinition -InstallPath $InstallPath -Instance $Instance
    if ((Test-Path -LiteralPath $d.ServerExecutablePath -PathType Leaf) -and -not $Force) { return [pscustomobject]@{ Success=$true; InstallPath=$d.InstallPath; ServerExecutablePath=$d.ServerExecutablePath; Message='Minecraft Bedrock already installed.' } }
    New-Item -ItemType Directory -Force -Path $d.InstallPath | Out-Null
    $url=Get-UGSMGameMinecraftBedrockDownloadUrl
    $tmp=Join-Path ([System.IO.Path]::GetTempPath()) ('UGSM_Bedrock_{0}.zip' -f ([guid]::NewGuid().ToString('N')))
    Write-UGSMGameMinecraftBedrockLog -Level 'INFO' -Message 'Downloading official Minecraft Bedrock server zip.'
    Invoke-WebRequest -Uri $url -OutFile $tmp -UseBasicParsing -ErrorAction Stop
    Expand-Archive -LiteralPath $tmp -DestinationPath $d.InstallPath -Force
    Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue
    if (-not (Test-Path -LiteralPath $d.ServerExecutablePath -PathType Leaf)) { throw 'Minecraft Bedrock install completed but bedrock_server.exe was not found.' }
    [pscustomobject]@{ Url=$url; InstalledAt=(Get-Date).ToString('o') } | ConvertTo-Json | Set-Content -LiteralPath $d.VersionInfoPath -Encoding UTF8
    return [pscustomobject]@{ Success=$true; InstallPath=$d.InstallPath; ServerExecutablePath=$d.ServerExecutablePath; Message='Minecraft Bedrock server installed.' }
}
function Ensure-UGSMGameMinecraftBedrockInstalled { [CmdletBinding()] param([string]$InstallPath,[AllowNull()][object]$Instance)
    $d=Get-UGSMGameMinecraftBedrockInstallDefinition -InstallPath $InstallPath -Instance $Instance
    if (-not (Test-Path -LiteralPath $d.ServerExecutablePath -PathType Leaf)) { Install-UGSMGameMinecraftBedrockServer -InstallPath $InstallPath -Instance $Instance | Out-Null }
    return (Get-UGSMGameMinecraftBedrockInstallDefinition -InstallPath $InstallPath -Instance $Instance)
}
function Ensure-UGSMGameMinecraftBedrockTemplate { [CmdletBinding()] param([string]$InstallPath,[AllowNull()][object]$Instance)
    Ensure-UGSMGameMinecraftBedrockInstalled -InstallPath $InstallPath -Instance $Instance | Out-Null
    return [pscustomobject]@{ Success=$true }
}
function Initialize-UGSMGameMinecraftBedrockProfile { [CmdletBinding()] param([Parameter(Mandatory)][object]$Instance,[string]$InstallPath,[int]$BootstrapSeconds=0,[switch]$Force)
    $id=Get-UGSMGameMinecraftBedrockInstanceId -Instance $Instance
    Write-UGSMGameMinecraftBedrockLog -Level 'INFO' -Message "Profile initialization started. InstanceId=$id"
    $install=Ensure-UGSMGameMinecraftBedrockInstalled -InstallPath $InstallPath -Instance $Instance
    $root=Get-UGSMGameMinecraftBedrockProfileRoot -Instance $Instance
    New-Item -ItemType Directory -Force -Path $root | Out-Null
    $settings=Get-UGSMGameMinecraftBedrockSettings -Instance $Instance
    Save-UGSMGameMinecraftBedrockSettings -Instance $Instance -Settings $settings
    Write-UGSMGameMinecraftBedrockServerProperties -Instance $Instance -Settings $settings
    return [pscustomobject]@{ Success=$true; ProfilePath=$root; InstallPath=$install.InstallPath }
}
function Test-UGSMGameMinecraftBedrockInstance { [CmdletBinding()] param([Parameter(Mandatory)][object]$Instance,[string]$InstallPath)
    $root=Get-UGSMGameMinecraftBedrockProfileRoot -Instance $Instance
    return [pscustomobject]@{ Success=(Test-Path -LiteralPath $root -PathType Container); ProfilePath=$root; PropertiesPath=(Get-UGSMGameMinecraftBedrockPropertiesPath -Instance $Instance) }
}

function Start-UGSMGameMinecraftBedrockInstance { [CmdletBinding()] param([Parameter(Mandatory)][object]$Instance,[string]$InstallPath)
    $id=Get-UGSMGameMinecraftBedrockInstanceId -Instance $Instance
    try {
        Initialize-UGSMGameMinecraftBedrockProfile -Instance $Instance -InstallPath $InstallPath | Out-Null
        $install=Ensure-UGSMGameMinecraftBedrockInstalled -InstallPath $InstallPath -Instance $Instance
        $root=Get-UGSMGameMinecraftBedrockProfileRoot -Instance $Instance
        $logRoot=Get-UGSMGameMinecraftBedrockLogRoot -Instance $Instance
        New-Item -ItemType Directory -Force -Path $logRoot | Out-Null
        $consoleLog=Join-Path $logRoot 'server-console.log'
        $errorLog=Join-Path $logRoot 'server-error.log'
        $cmd=Join-Path $root 'UGSM_Start_MinecraftBedrock.cmd'
        $exe=$install.ServerExecutablePath
        $cmdLines=@(
            '@echo off',
            'cd /d "%~dp0"',
            ('echo UGSM starting Minecraft Bedrock at %DATE% %TIME% > "{0}"' -f $consoleLog),
            ('"{0}" >> "{1}" 2>> "{2}"' -f $exe,$consoleLog,$errorLog)
        )
        Set-Content -LiteralPath $cmd -Value $cmdLines -Encoding ASCII
        Write-UGSMGameMinecraftBedrockLog -Level 'INFO' -Message "Start requested. InstanceId=$id"
        $proc=Start-Process -FilePath $cmd -WorkingDirectory $root -PassThru -WindowStyle Hidden
        Start-Sleep -Seconds 3
        $children=@()
        try { $children = Get-CimInstance Win32_Process -Filter "ParentProcessId=$($proc.Id)" | Where-Object { $_.Name -like 'bedrock_server*' } } catch {}
        $targetPid=$proc.Id
        if ($children -and $children.Count -gt 0) { $targetPid=[int]$children[0].ProcessId }
        $target=Get-Process -Id $targetPid -ErrorAction SilentlyContinue
        if (-not $target) { throw "Minecraft Bedrock process exited immediately. Check $consoleLog and $errorLog." }
        $script:UGSM_MinecraftBedrockProcesses[$id]=[pscustomobject]@{ Pid=$target.Id; LauncherPid=$proc.Id; ProfileRoot=$root; InstallPath=$install.InstallPath; StartedAt=Get-Date }
        Write-UGSMGameMinecraftBedrockLog -Level 'INFO' -Message "Start completed. InstanceId=$id; Pid=$($target.Id)"
        if (Get-Command -Name Send-UGSMInstanceDiscordNotification -ErrorAction SilentlyContinue) { try { Send-UGSMInstanceDiscordNotification -Instance $Instance -Event 'Start' | Out-Null } catch { Write-UGSMGameMinecraftBedrockLog -Level 'WARN' -Message 'Discord start notification failed.' -Exception $_.Exception } }
        return [pscustomobject]@{ Success=$true; ProcessId=$target.Id; Pid=$target.Id; ProfilePath=$root }
    } catch { Write-UGSMGameMinecraftBedrockLog -Level 'ERROR' -Message "Start failed. InstanceId=$id" -Exception $_.Exception; throw }
}
function Stop-UGSMGameMinecraftBedrockInstance { [CmdletBinding()] param([Parameter(Mandatory)][object]$Instance,[string]$InstallPath)
    $id=Get-UGSMGameMinecraftBedrockInstanceId -Instance $Instance
    Write-UGSMGameMinecraftBedrockLog -Level 'INFO' -Message "Stop requested. InstanceId=$id"
    $targets=@()
    if ($script:UGSM_MinecraftBedrockProcesses.ContainsKey($id)) {
        foreach ($procId in @($script:UGSM_MinecraftBedrockProcesses[$id].Pid,$script:UGSM_MinecraftBedrockProcesses[$id].LauncherPid)) { if ($procId) { $p=Get-Process -Id ([int]$procId) -ErrorAction SilentlyContinue; if ($p) { $targets += $p } } }
    }
    $profileRoot=Get-UGSMGameMinecraftBedrockProfileRoot -Instance $Instance
    try {
        $procs=Get-CimInstance Win32_Process -Filter "Name='bedrock_server.exe'" -ErrorAction SilentlyContinue
        foreach ($wp in @($procs)) { if ($wp.CommandLine -and ($wp.CommandLine -like "*$profileRoot*" -or $wp.ExecutablePath -like "*MinecraftBedrock*")) { $p=Get-Process -Id ([int]$wp.ProcessId) -ErrorAction SilentlyContinue; if ($p) { $targets += $p } } }
    } catch {}
    $targets=@($targets | Where-Object { $_ -and $_.Id -ne $PID } | Sort-Object Id -Unique)
    $stopped=$false
    foreach ($p in $targets) { try { Stop-Process -Id $p.Id -Force -ErrorAction Stop; $stopped=$true } catch { Write-UGSMGameMinecraftBedrockLog -Level 'WARN' -Message "Failed to stop Minecraft Bedrock process. Pid=$($p.Id)" -Exception $_.Exception } }
    if ($script:UGSM_MinecraftBedrockProcesses.ContainsKey($id)) { $script:UGSM_MinecraftBedrockProcesses.Remove($id) }
    if (Get-Command -Name Send-UGSMInstanceDiscordNotification -ErrorAction SilentlyContinue) { try { Send-UGSMInstanceDiscordNotification -Instance $Instance -Event 'Stop' | Out-Null } catch { Write-UGSMGameMinecraftBedrockLog -Level 'WARN' -Message 'Discord stop notification failed.' -Exception $_.Exception } }
    Write-UGSMGameMinecraftBedrockLog -Level 'INFO' -Message "Stop completed. InstanceId=$id; Stopped=$stopped"
    return [pscustomobject]@{ Success=$true; Stopped=$stopped; Graceful=$false }
}

function Resolve-UGSMGameMinecraftBedrockColor {
    param([AllowNull()][object]$Theme,[string[]]$ThemeNames,[string[]]$GlobalNames,[System.Drawing.Color]$Fallback)
    if ($Theme) {
        foreach ($name in $ThemeNames) {
            try { if ($Theme.PSObject.Properties[$name] -and $Theme.$name) { return [System.Drawing.Color]$Theme.$name } } catch {}
        }
    }
    foreach ($name in $GlobalNames) {
        try {
            $var = Get-Variable -Name $name -Scope Global -ErrorAction SilentlyContinue
            if ($var -and $var.Value) { return [System.Drawing.Color]$var.Value }
        } catch {}
    }
    return $Fallback
}
function Set-UGSMGameMinecraftBedrockControlColors { param([System.Windows.Forms.Control]$Control,[object]$Theme,[switch]$IsInput,[switch]$Muted)
    $bg = Resolve-UGSMGameMinecraftBedrockColor -Theme $Theme -ThemeNames @('SurfaceBackColor','BackColor','BackgroundColor') -GlobalNames @('UGSM_ColorSurface','UGSM_ColorBackground') -Fallback ([System.Drawing.Color]::FromArgb(8,20,36))
    $inputBg = Resolve-UGSMGameMinecraftBedrockColor -Theme $Theme -ThemeNames @('InputBackColor','InputBackColor','InputBackgroundColor') -GlobalNames @('UGSM_ColorInputBackground','UGSM_ColorSurface') -Fallback ([System.Drawing.Color]::FromArgb(4,12,24))
    $fg = Resolve-UGSMGameMinecraftBedrockColor -Theme $Theme -ThemeNames @('TextColor','ForeColor') -GlobalNames @('UGSM_ColorText') -Fallback ([System.Drawing.Color]::White)
    $mutedFg = Resolve-UGSMGameMinecraftBedrockColor -Theme $Theme -ThemeNames @('MutedTextColor','SubtleTextColor') -GlobalNames @('UGSM_ColorMutedText','UGSM_ColorText') -Fallback ([System.Drawing.Color]::Gainsboro)
    if ($IsInput) { $Control.BackColor = $inputBg } else { $Control.BackColor = $bg }
    if ($Muted) { $Control.ForeColor = $mutedFg } else { $Control.ForeColor = $fg }
}
function New-UGSMGameMinecraftBedrockLabel { param($Parent,[string]$Text,[int]$Left,[int]$Top,[int]$Width=210,[object]$Theme)
    $l=New-Object System.Windows.Forms.Label; $l.Text=$Text; $l.Left=$Left; $l.Top=$Top+4; $l.Width=$Width; $l.Height=22
    Set-UGSMGameMinecraftBedrockControlColors -Control $l -Theme $Theme
    $Parent.Controls.Add($l); return $l
}
function Add-UGSMGameMinecraftBedrockField { param($Parent,[hashtable]$Controls,[string]$Key,[string]$Label,[string]$Value,[int]$Row,[object]$Theme,[switch]$Multiline,[int]$Height=24)
    $top=12+($Row*40); New-UGSMGameMinecraftBedrockLabel -Parent $Parent -Text $Label -Left 16 -Top $top -Theme $Theme | Out-Null
    $tb=New-Object System.Windows.Forms.TextBox; $tb.Left=240; $tb.Top=$top; $tb.Width=360; $tb.Height=$Height; $tb.Text=$Value
    if($Multiline){$tb.Multiline=$true;$tb.ScrollBars='Vertical';$tb.AcceptsReturn=$true}
    Set-UGSMGameMinecraftBedrockControlColors -Control $tb -Theme $Theme -IsInput
    $Parent.Controls.Add($tb); $Controls[$Key]=$tb; return $tb
}
function Add-UGSMGameMinecraftBedrockCheckField { param($Parent,[hashtable]$Controls,[string]$Key,[string]$Label,[bool]$Value,[int]$Row,[object]$Theme)
    $top=12+($Row*40); $cb=New-Object System.Windows.Forms.CheckBox; $cb.Left=240; $cb.Top=$top; $cb.Width=390; $cb.Height=24; $cb.Text=$Label; $cb.Checked=$Value
    Set-UGSMGameMinecraftBedrockControlColors -Control $cb -Theme $Theme
    $Parent.Controls.Add($cb); $Controls[$Key]=$cb; return $cb
}
function Add-UGSMGameMinecraftBedrockNote { param($Parent,[string]$Text,[int]$Top,[object]$Theme)
    $l=New-Object System.Windows.Forms.Label; $l.Left=16; $l.Top=$Top; $l.Width=760; $l.Height=44; $l.Text=$Text
    Set-UGSMGameMinecraftBedrockControlColors -Control $l -Theme $Theme -Muted
    $Parent.Controls.Add($l); return $l
}
function Get-UGSMGameMinecraftBedrockEditorValue { param([hashtable]$Controls,[string]$Key,[AllowNull()][object]$Default)
    if (-not $Controls.ContainsKey($Key)) { return $Default }
    $c=$Controls[$Key]
    if ($c -is [System.Windows.Forms.CheckBox]) { return [bool]$c.Checked }
    return [string]$c.Text
}
function Save-UGSMGameMinecraftBedrockInstanceEditor { [CmdletBinding()] param([Parameter(Mandatory)][object]$EditorState)
    $Instance=$EditorState.Instance; $controls=$EditorState.Controls
    $settings=Get-UGSMGameMinecraftBedrockSettings -Instance $Instance
    foreach ($key in @('ServerName','Gamemode','Difficulty','MaxPlayers','GamePort','IPv6Port','ViewDistance','TickDistance','PlayerIdleTimeout','MaxThreads','LevelName','LevelSeed','DefaultPlayerPermissionLevel','CompressionThreshold','ServerAuthoritativeMovement','PlayerMovementScoreThreshold','PlayerMovementDistanceThreshold','PlayerMovementDurationThresholdInMs','ExtraProperties')) { if ($controls.ContainsKey($key)) { $settings.$key = Get-UGSMGameMinecraftBedrockEditorValue -Controls $controls -Key $key -Default $settings.$key } }
    foreach ($key in @('ForceGamemode','AllowCheats','OnlineMode','AllowList','TexturePackRequired','ContentLogFileEnabled','CorrectPlayerMovement')) { if ($controls.ContainsKey($key)) { $settings.$key = [bool](Get-UGSMGameMinecraftBedrockEditorValue -Controls $controls -Key $key -Default $settings.$key) } }
    if ($controls.ContainsKey('DiscordWebhookUrl')) { $settings.Discord.WebhookUrl=[string](Get-UGSMGameMinecraftBedrockEditorValue -Controls $controls -Key 'DiscordWebhookUrl' -Default '') }
    foreach ($key in @('NotifyOnStart','NotifyOnStop','ShowInDashboard')) { if ($controls.ContainsKey($key)) { $settings.Discord.$key=[bool](Get-UGSMGameMinecraftBedrockEditorValue -Controls $controls -Key $key -Default $false) } }
    Save-UGSMGameMinecraftBedrockSettings -Instance $Instance -Settings $settings
    Write-UGSMGameMinecraftBedrockServerProperties -Instance $Instance -Settings $settings
    Write-UGSMGameMinecraftBedrockLog -Level 'INFO' -Message ('Settings saved. InstanceId=' + (Get-UGSMGameMinecraftBedrockInstanceId -Instance $Instance))
    return [pscustomobject]@{ Success=$true; Settings=$settings }
}
function New-UGSMGameMinecraftBedrockInstanceEditor { [CmdletBinding()] param([Parameter(Mandatory)]$HostPanel,[Parameter(Mandatory)][object]$Instance,[object]$Theme,[object]$StatusLabel)
    $HostPanel.SuspendLayout()
    try {
        $HostPanel.Controls.Clear()
        $settings=Get-UGSMGameMinecraftBedrockSettings -Instance $Instance
        $controls=@{}
        $tabs=New-Object System.Windows.Forms.TabControl; $tabs.Dock='Fill'; Set-UGSMGameMinecraftBedrockControlColors -Control $tabs -Theme $Theme; $HostPanel.Controls.Add($tabs)
        foreach ($tabInfo in @(
            @{Name='Server'; Rows=@(
                @('ServerName','Server name'),@('Gamemode','Gamemode'),@('Difficulty','Difficulty'),@('MaxPlayers','Max players'),@('GamePort','IPv4 UDP port'),@('IPv6Port','IPv6 UDP port'),@('LevelName','Level name'),@('LevelSeed','Level seed'),@('DefaultPlayerPermissionLevel','Default permission') )},
            @{Name='Gameplay'; Rows=@(
                @('ViewDistance','View distance'),@('TickDistance','Tick distance'),@('PlayerIdleTimeout','Idle timeout minutes'),@('MaxThreads','Max threads'),@('CompressionThreshold','Compression threshold'),@('ServerAuthoritativeMovement','Movement authority'),@('PlayerMovementScoreThreshold','Movement score threshold'),@('PlayerMovementDistanceThreshold','Movement distance threshold'),@('PlayerMovementDurationThresholdInMs','Movement duration ms') )}
        )) {
            $tab=New-Object System.Windows.Forms.TabPage; $tab.Text=$tabInfo.Name; Set-UGSMGameMinecraftBedrockControlColors -Control $tab -Theme $Theme
            $panel=New-Object System.Windows.Forms.Panel; $panel.Dock='Fill'; $panel.AutoScroll=$true; Set-UGSMGameMinecraftBedrockControlColors -Control $panel -Theme $Theme; $tab.Controls.Add($panel); [void]$tabs.TabPages.Add($tab)
            $row=0; foreach ($r in $tabInfo.Rows) { Add-UGSMGameMinecraftBedrockField -Parent $panel -Controls $controls -Key $r[0] -Label $r[1] -Value ([string]$settings.($r[0])) -Row $row -Theme $Theme | Out-Null; $row++ }
        }
        $flagsTab=New-Object System.Windows.Forms.TabPage; $flagsTab.Text='Flags'; Set-UGSMGameMinecraftBedrockControlColors -Control $flagsTab -Theme $Theme; $flagsPanel=New-Object System.Windows.Forms.Panel; $flagsPanel.Dock='Fill'; $flagsPanel.AutoScroll=$true; Set-UGSMGameMinecraftBedrockControlColors -Control $flagsPanel -Theme $Theme; $flagsTab.Controls.Add($flagsPanel); [void]$tabs.TabPages.Add($flagsTab)
        $row=0; foreach ($r in @(@('ForceGamemode','Force gamemode'),@('AllowCheats','Allow cheats'),@('OnlineMode','Online mode'),@('AllowList','Allow-list / whitelist'),@('TexturePackRequired','Texture pack required'),@('ContentLogFileEnabled','Content log file enabled'),@('CorrectPlayerMovement','Correct player movement'))) { Add-UGSMGameMinecraftBedrockCheckField -Parent $flagsPanel -Controls $controls -Key $r[0] -Label $r[1] -Value ([bool]$settings.($r[0])) -Row $row -Theme $Theme | Out-Null; $row++ }
        $advTab=New-Object System.Windows.Forms.TabPage; $advTab.Text='Advanced'; Set-UGSMGameMinecraftBedrockControlColors -Control $advTab -Theme $Theme; $advPanel=New-Object System.Windows.Forms.Panel; $advPanel.Dock='Fill'; $advPanel.AutoScroll=$true; Set-UGSMGameMinecraftBedrockControlColors -Control $advPanel -Theme $Theme; $advTab.Controls.Add($advPanel); [void]$tabs.TabPages.Add($advTab)
        Add-UGSMGameMinecraftBedrockNote -Parent $advPanel -Text 'Minecraft Bedrock runs from the official bedrock_server.exe. This pass manages server.properties; add-ons/resource packs can be added later.' -Top 8 -Theme $Theme | Out-Null
        Add-UGSMGameMinecraftBedrockField -Parent $advPanel -Controls $controls -Key 'ExtraProperties' -Label 'Extra server.properties' -Value ([string]$settings.ExtraProperties) -Row 2 -Theme $Theme -Multiline -Height 220 | Out-Null
        $discordTab=New-Object System.Windows.Forms.TabPage; $discordTab.Text='Discord'; Set-UGSMGameMinecraftBedrockControlColors -Control $discordTab -Theme $Theme; $discordPanel=New-Object System.Windows.Forms.Panel; $discordPanel.Dock='Fill'; $discordPanel.AutoScroll=$true; Set-UGSMGameMinecraftBedrockControlColors -Control $discordPanel -Theme $Theme; $discordTab.Controls.Add($discordPanel); [void]$tabs.TabPages.Add($discordTab)
        Add-UGSMGameMinecraftBedrockField -Parent $discordPanel -Controls $controls -Key 'DiscordWebhookUrl' -Label 'Private Discord webhook URL' -Value ([string]$settings.Discord.WebhookUrl) -Row 0 -Theme $Theme | Out-Null
        Add-UGSMGameMinecraftBedrockCheckField -Parent $discordPanel -Controls $controls -Key 'NotifyOnStart' -Label 'Notify on Start' -Value ([bool]$settings.Discord.NotifyOnStart) -Row 1 -Theme $Theme | Out-Null
        Add-UGSMGameMinecraftBedrockCheckField -Parent $discordPanel -Controls $controls -Key 'NotifyOnStop' -Label 'Notify on Stop' -Value ([bool]$settings.Discord.NotifyOnStop) -Row 2 -Theme $Theme | Out-Null
        Add-UGSMGameMinecraftBedrockCheckField -Parent $discordPanel -Controls $controls -Key 'ShowInDashboard' -Label 'Show in Discord/dashboard status' -Value ([bool]$settings.Discord.ShowInDashboard) -Row 3 -Theme $Theme | Out-Null
        $btnTest=New-Object System.Windows.Forms.Button; $btnTest.Text='Test Discord'; Set-UGSMGameMinecraftBedrockControlColors -Control $btnTest -Theme $Theme; $btnTest.Left=240; $btnTest.Top=190; $btnTest.Width=160; $btnTest.Height=30; $btnTest.Tag=[pscustomobject]@{ Instance=$Instance; Controls=$controls; StatusLabel=$StatusLabel }
        $btnTest.Add_Click({ param($sender,$eventArgs) $st=$sender.Tag; try { Save-UGSMGameMinecraftBedrockInstanceEditor -EditorState $st | Out-Null; if (Get-Command -Name Send-UGSMInstanceDiscordNotification -ErrorAction SilentlyContinue) { Send-UGSMInstanceDiscordNotification -Instance $st.Instance -Event 'Test' | Out-Null }; if($st.StatusLabel){$st.StatusLabel.Text='Minecraft Bedrock Discord test sent.'} } catch { if($st.StatusLabel){$st.StatusLabel.Text='Minecraft Bedrock Discord test failed: '+$_.Exception.Message}; Write-UGSMGameMinecraftBedrockLog -Level 'ERROR' -Message 'Discord test failed.' -Exception $_.Exception } })
        $discordPanel.Controls.Add($btnTest)
        $btnSave=New-Object System.Windows.Forms.Button; $btnSave.Text='Save Settings'; Set-UGSMGameMinecraftBedrockControlColors -Control $btnSave -Theme $Theme; $btnSave.Dock='Bottom'; $btnSave.Height=32; $btnSave.Tag=[pscustomobject]@{ Instance=$Instance; Controls=$controls; StatusLabel=$StatusLabel }
        $btnSave.Add_Click({ param($sender,$eventArgs) $st=$sender.Tag; try { Save-UGSMGameMinecraftBedrockInstanceEditor -EditorState $st | Out-Null; if($st.StatusLabel){$st.StatusLabel.Text='Minecraft Bedrock settings saved.'} } catch { if($st.StatusLabel){$st.StatusLabel.Text='Minecraft Bedrock save failed: '+$_.Exception.Message}; Write-UGSMGameMinecraftBedrockLog -Level 'ERROR' -Message 'Editor save failed.' -Exception $_.Exception } })
        $HostPanel.Controls.Add($btnSave); $btnSave.BringToFront()
        Write-UGSMGameMinecraftBedrockLog -Level 'INFO' -Message ('Editor creation completed. InstanceId=' + (Get-UGSMGameMinecraftBedrockInstanceId -Instance $Instance))
        return [pscustomobject]@{ Success=$true; Controls=$controls }
    } catch { Write-UGSMGameMinecraftBedrockLog -Level 'ERROR' -Message 'Editor creation failed.' -Exception $_.Exception; throw } finally { $HostPanel.ResumeLayout($true) }
}

function Register-UGSMGameMinecraftBedrockModule {
    [CmdletBinding()] param()
    $metadata=Get-UGSMGameMinecraftBedrockMetadata
    return [pscustomobject]@{
        Id=[string]$metadata.Id
        Metadata=$metadata
        Handlers=[pscustomobject]@{
            GetMetadata='Get-UGSMGameMinecraftBedrockMetadata'
            TestInstall='Test-UGSMGameMinecraftBedrockInstall'
            Install='Install-UGSMGameMinecraftBedrockServer'
            TestInstance='Test-UGSMGameMinecraftBedrockInstance'
            EnsureTemplate='Ensure-UGSMGameMinecraftBedrockTemplate'
            InitializeProfile='Initialize-UGSMGameMinecraftBedrockProfile'
            Start='Start-UGSMGameMinecraftBedrockInstance'
            Stop='Stop-UGSMGameMinecraftBedrockInstance'
            BuildEditor='New-UGSMGameMinecraftBedrockInstanceEditor'
            SaveEditor='Save-UGSMGameMinecraftBedrockInstanceEditor'
        }
    }
}
