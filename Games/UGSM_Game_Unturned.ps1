
# Unturned dedicated server module
# First functional pass: install/create/start/stop, Commands.dat editor, WorkshopDownloadConfig.json editor, Discord tab.

function Write-UGSMGameUnturnedLog {
    [CmdletBinding()]
    param(
        [ValidateSet('TRACE','DEBUG','INFO','WARN','ERROR','FATAL')][string]$Level = 'INFO',
        [Parameter(Mandatory)][string]$Message,
        [AllowNull()][System.Exception]$Exception
    )
    $verboseEnabled = $false
    try { $verboseEnabled = [bool]$script:UGSM_EnableVerboseUnturnedLogging } catch { $verboseEnabled = $false }
    if (-not $verboseEnabled -and -not [string]::IsNullOrWhiteSpace($env:UGSM_VERBOSE_UNTURNED)) { $verboseEnabled = $true }
    if ($Level -in @('TRACE','DEBUG') -and -not $verboseEnabled) { return }
    if (Get-Command -Name Write-UGSMLog -ErrorAction SilentlyContinue) {
        if ($Exception) { Write-UGSMLog -Level $Level -Category 'Unturned' -Message $Message -Exception $Exception }
        else { Write-UGSMLog -Level $Level -Category 'Unturned' -Message $Message }
        return
    }
    if ($Exception) { Write-Warning ("[Unturned] $Message :: $($Exception.Message)") } else { Write-Host "[Unturned][$Level] $Message" }
}

function Get-UGSMGameUnturnedMetadata {
    [CmdletBinding()]
    param()
    return [pscustomobject]@{
        Id                       = 'Unturned'
        Name                     = 'Unturned'
        Category                 = 'Survival'
        Description              = 'Unturned Dedicated Server integration.'
        IsCustom                 = $false
        SupportTier              = 'Basic'
        SortOrder                = 95
        IsVisible                = $true
        SupportedTabs            = @('Home','Games','Instances','Analytics','Tasks','About','Settings')
        UseSteamArt              = $true
        SupportsInstall          = $true
        SupportsUpdate           = $true
        SupportsVerify           = $true
        SupportsRepair           = $true
        SupportsStart            = $true
        SupportsStop             = $true
        SupportsMods             = $true
        SupportsWorkshop         = $true
        SupportsRcon             = $false
        SupportsBootstrap        = $false
        SupportsProfiles         = $true
        SupportsInstanceUi       = $true
        InstallProvider          = 'SteamCMD'
        RequiresSteamLogin       = $false
        SteamLoginMode           = 'Anonymous'
        SteamAppId               = '1110390'
        SteamStoreAppId          = '304930'
        ServerExecutable         = 'ServerHelper.bat'
        ServerExecutableRelative = 'ServerHelper.bat'
        UsesSharedBinaries       = $true
        InstanceType             = 'DedicatedServer'
        ConfigRootRelative       = 'Server'
        SaveRootRelative         = 'Level'
        LogRootRelative          = 'Logs'
        RequiredFiles            = @('ServerHelper.bat','Unturned.exe')
        InstallMarkers           = @('ServerHelper.bat','Unturned.exe')
        PortSchema               = @(
            @{ Name = 'GamePort'; Protocol = 'UDP'; PreferredStart = 27015 },
            @{ Name = 'QueryPort'; Protocol = 'UDP'; PreferredStart = 27016 },
            @{ Name = 'SteamPort'; Protocol = 'UDP'; PreferredStart = 27017 }
        )
        GameTraits               = [pscustomobject]@{
            UsesIniFiles          = $false
            UsesJsonFiles         = $true
            UsesXmlFiles          = $false
            UsesSqlite            = $false
            UsesProfileSync       = $false
            UsesPluginFramework   = $true
            UsesZipMods           = $false
            UsesFolderCopyMods    = $false
            UsesFileMergeWorkflow = $false
            UsesMissionFiles      = $false
            UsesWorkshopItems     = $true
        }
        SpecialRequirements      = [pscustomobject]@{
            Notes = @(
                'SteamCMD app id 1110390 installs U3DS using anonymous login.',
                'Launch uses ServerHelper.bat with +InternetServer/<ServerId> or +LanServer/<ServerId>.',
                'UGSM stores per-profile data outside the binary folder and junctions U3DS\Servers\<ServerId> to the profile.',
                'Workshop IDs are written to WorkshopDownloadConfig.json. Workshop maps also need the Map field in Commands.dat set to the exact map folder/name.',
                'Internet-listed servers need a Steam Game Server Login Token. UGSM writes it to Config.txt under Browser > Login_Token.'
            )
        }
    }
}

function Get-UGSMGameUnturnedInstanceId {
    [CmdletBinding()]
    param([AllowNull()][object]$Instance)
    if (-not $Instance) { return '' }
    foreach ($name in @('Id','Name','ProfileName','InstanceId')) {
        if ($Instance.PSObject.Properties[$name] -and -not [string]::IsNullOrWhiteSpace([string]$Instance.$name)) { return [string]$Instance.$name }
    }
    return ''
}

function Get-UGSMGameUnturnedProfileName {
    [CmdletBinding()]
    param([AllowNull()][object]$Instance)
    $name = Get-UGSMGameUnturnedInstanceId -Instance $Instance
    if ([string]::IsNullOrWhiteSpace($name)) { $name = 'Unturned1' }
    $safe = $name -replace '[^A-Za-z0-9_.-]', '_'
    if ([string]::IsNullOrWhiteSpace($safe)) { $safe = 'Unturned1' }
    return $safe
}

function Get-UGSMGameUnturnedAppDataRoot {
    [CmdletBinding()]
    param()
    if (Get-Command -Name Get-UGSMAppDataRoot -ErrorAction SilentlyContinue) { return [string](Get-UGSMAppDataRoot) }
    return (Join-Path $env:LOCALAPPDATA 'UGSM')
}

function Get-UGSMGameUnturnedProfileBaseRoot {
    [CmdletBinding()]
    param()
    $settings = $null
    if (Get-Command -Name Get-UGSMGlobalSettings -ErrorAction SilentlyContinue) {
        try { $settings = Get-UGSMGlobalSettings -CreateIfMissing } catch { $settings = $null }
    }
    if ($settings -and $settings.PSObject.Properties['ProfileBaseRoot'] -and -not [string]::IsNullOrWhiteSpace([string]$settings.ProfileBaseRoot)) { return [string]$settings.ProfileBaseRoot }
    if (Get-Command -Name Get-UGSMDefaultInstanceProfilePath -ErrorAction SilentlyContinue) {
        $probe = Get-UGSMDefaultInstanceProfilePath -GameId 'Unturned' -Name '_probe_'
        if (-not [string]::IsNullOrWhiteSpace([string]$probe)) { return (Split-Path -Parent (Split-Path -Parent $probe)) }
    }
    return (Join-Path (Get-UGSMGameUnturnedAppDataRoot) 'Profiles')
}

function Get-UGSMGameUnturnedProfileRoot {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$ProfileName)
    return (Join-Path (Join-Path (Get-UGSMGameUnturnedProfileBaseRoot) 'Unturned') $ProfileName)
}

function Get-UGSMGameUnturnedInstallPath {
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
                $base = [string]$settings.$propName
                foreach ($candidate in @(
                    (Join-Path $base 'steamapps\common\U3DS'),
                    (Join-Path $base 'steamapps\common\Unturned Dedicated Server'),
                    (Join-Path $base 'U3DS'),
                    (Join-Path $base 'Unturned Dedicated Server')
                )) {
                    if (Test-Path -LiteralPath (Join-Path $candidate 'ServerHelper.bat') -PathType Leaf) { return $candidate }
                }
            }
        }
    }
    if ($settings -and $settings.PSObject.Properties['SteamLibraryRoot'] -and -not [string]::IsNullOrWhiteSpace([string]$settings.SteamLibraryRoot)) {
        return (Join-Path ([string]$settings.SteamLibraryRoot) 'steamapps\common\U3DS')
    }
    return ''
}

function Get-UGSMGameUnturnedInstallDefinition {
    [CmdletBinding()]
    param([string]$InstallPath, [AllowNull()][object]$Instance)
    $root = Get-UGSMGameUnturnedInstallPath -Instance $Instance -InstallPath $InstallPath
    if ([string]::IsNullOrWhiteSpace([string]$root)) {
        return [pscustomobject]@{
            InstallPath          = ''
            ServerHelperPath     = ''
            ServerExecutablePath = ''
            UnturnedExePath      = ''
            ServersRoot          = ''
        }
    }
    return [pscustomobject]@{
        InstallPath          = $root
        ServerHelperPath     = Join-Path $root 'ServerHelper.bat'
        ServerExecutablePath = Join-Path $root 'ServerHelper.bat'
        UnturnedExePath      = Join-Path $root 'Unturned.exe'
        ServersRoot          = Join-Path $root 'Servers'
    }
}

function Test-UGSMGameUnturnedInstall {
    [CmdletBinding()]
    param([string]$InstallPath, [AllowNull()][object]$Instance)
    $definition = Get-UGSMGameUnturnedInstallDefinition -InstallPath $InstallPath -Instance $Instance
    $ok = (-not [string]::IsNullOrWhiteSpace([string]$definition.InstallPath)) -and (Test-Path -LiteralPath $definition.ServerHelperPath -PathType Leaf) -and (Test-Path -LiteralPath $definition.UnturnedExePath -PathType Leaf)
    return [pscustomobject]@{ Success = [bool]$ok; IsInstalled = [bool]$ok; InstallPath = $definition.InstallPath; ServerExecutablePath = $definition.ServerHelperPath; Message = if ($ok) { 'Unturned Dedicated Server install detected.' } else { 'Unturned Dedicated Server was not detected.' } }
}

function Get-UGSMGameUnturnedAssignedPort {
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

function Get-UGSMGameUnturnedProfilePaths {
    [CmdletBinding()]
    param([Parameter(Mandatory)][object]$Instance, [string]$InstallPath)
    $profileName = Get-UGSMGameUnturnedProfileName -Instance $Instance
    $profileRoot = Get-UGSMGameUnturnedProfileRoot -ProfileName $profileName
    $externalServerRoot = Join-Path $profileRoot 'ServerData'
    $serverConfigRoot = Join-Path $externalServerRoot 'Server'
    $logsRoot = Join-Path $profileRoot 'Logs'
    $centralLogRoot = Join-Path (Join-Path (Get-UGSMGameUnturnedAppDataRoot) 'Logs\Unturned') $profileName
    $definition = Get-UGSMGameUnturnedInstallDefinition -InstallPath $InstallPath -Instance $Instance
    return [pscustomobject]@{
        ProfileName                = $profileName
        ProfileRoot                = $profileRoot
        ExternalServerRoot         = $externalServerRoot
        ServerConfigRoot           = $serverConfigRoot
        CommandsPath               = Join-Path $serverConfigRoot 'Commands.dat'
        ConfigPath                 = Join-Path $externalServerRoot 'Config.txt'
        WorkshopDownloadConfigPath = Join-Path $externalServerRoot 'WorkshopDownloadConfig.json'
        SettingsPath               = Join-Path $profileRoot 'UGSM_UnturnedSettings.json'
        LogsRoot                   = $logsRoot
        CentralLogRoot             = $centralLogRoot
        LaunchLogPath              = Join-Path $centralLogRoot 'server-launch.log'
        InstallServerLinkPath      = Join-Path $definition.ServersRoot $profileName
        LauncherPath               = Join-Path $logsRoot 'UGSM_Start_Unturned.cmd'
    }
}

function Get-UGSMGameUnturnedDefaultSettings {
    [CmdletBinding()]
    param([Parameter(Mandatory)][object]$Instance)
    $profileName = Get-UGSMGameUnturnedProfileName -Instance $Instance
    return [pscustomobject]@{
        ServerId          = $profileName
        ServerName        = $profileName
        ServerMode        = 'Internet'
        Map               = 'PEI'
        GamePort          = Get-UGSMGameUnturnedAssignedPort -Instance $Instance -Name 'GamePort' -Default 27015
        MaxPlayers        = 24
        Password          = ''
        OwnerSteam64      = ''
        LoginToken        = ''
        Difficulty        = 'Normal'
        Perspective       = 'Both'
        Cheats            = $false
        PvE               = $false
        Welcome           = ''
        ExtraCommands     = ''
        WorkshopFileIds   = @()
        Discord           = [pscustomobject]@{ WebhookUrl=''; NotifyOnStart=$false; NotifyOnStop=$false; ShowInDashboard=$false }
    }
}

function Convert-UGSMGameUnturnedWorkshopInputToId {
    [CmdletBinding()]
    param([AllowNull()][string]$InputText)
    $text = ([string]$InputText).Trim()
    if ([string]::IsNullOrWhiteSpace($text)) { return '' }
    if ($text -match '[?&]id=(\d+)') { return $matches[1] }
    if ($text -match '^(\d+)$') { return $matches[1] }
    if ($text -match '(\d{6,})') { return $matches[1] }
    return $text
}

function ConvertFrom-UGSMGameUnturnedMultilineList {
    [CmdletBinding()]
    param([AllowNull()][string]$Text)
    $items = New-Object System.Collections.Generic.List[string]
    foreach ($raw in (([string]$Text) -split '[\r\n,;]+')) {
        $value = Convert-UGSMGameUnturnedWorkshopInputToId -InputText $raw
        if (-not [string]::IsNullOrWhiteSpace($value) -and -not $items.Contains($value)) { [void]$items.Add($value) }
    }
    return @($items.ToArray())
}

function Read-UGSMGameUnturnedSettingsFile {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $null }
    try { return (Get-Content -LiteralPath $Path -Raw -ErrorAction Stop | ConvertFrom-Json) } catch { return $null }
}

function Merge-UGSMGameUnturnedSettings {
    [CmdletBinding()]
    param([Parameter(Mandatory)][object]$Base, [AllowNull()][object]$Override)
    if (-not $Override) { return $Base }
    foreach ($prop in $Override.PSObject.Properties) {
        if ($Base.PSObject.Properties[$prop.Name]) { $Base.($prop.Name) = $prop.Value }
        else { Add-Member -InputObject $Base -MemberType NoteProperty -Name $prop.Name -Value $prop.Value -Force }
    }
    return $Base
}

function Get-UGSMGameUnturnedSettings {
    [CmdletBinding()]
    param([Parameter(Mandatory)][object]$Instance, [string]$InstallPath)
    $settings = Get-UGSMGameUnturnedDefaultSettings -Instance $Instance
    $paths = Get-UGSMGameUnturnedProfilePaths -Instance $Instance -InstallPath $InstallPath
    $saved = Read-UGSMGameUnturnedSettingsFile -Path $paths.SettingsPath
    if ($saved) { $settings = Merge-UGSMGameUnturnedSettings -Base $settings -Override $saved }
    if (-not $settings.PSObject.Properties['LoginToken']) {
        Add-Member -InputObject $settings -MemberType NoteProperty -Name LoginToken -Value '' -Force
    }
    if ($settings.PSObject.Properties['GSLT'] -and [string]::IsNullOrWhiteSpace([string]$settings.LoginToken) -and -not [string]::IsNullOrWhiteSpace([string]$settings.GSLT)) {
        $settings.LoginToken = [string]$settings.GSLT
    }
    if (-not $settings.WorkshopFileIds) { $settings.WorkshopFileIds = @() }
    if (-not $settings.Discord) { $settings.Discord = [pscustomobject]@{ WebhookUrl=''; NotifyOnStart=$false; NotifyOnStop=$false; ShowInDashboard=$false } }
    return $settings
}

function Save-UGSMGameUnturnedJsonFile {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Path, [Parameter(Mandatory)][object]$InputObject)
    $parent = Split-Path -Parent $Path
    if (-not (Test-Path -LiteralPath $parent -PathType Container)) { New-Item -ItemType Directory -Force -Path $parent | Out-Null }
    $json = $InputObject | ConvertTo-Json -Depth 12
    Set-Content -LiteralPath $Path -Value $json -Encoding UTF8
}

function Save-UGSMGameUnturnedCommandsDat {
    [CmdletBinding()]
    param([Parameter(Mandatory)][object]$Settings, [Parameter(Mandatory)][string]$Path)
    $lines = New-Object System.Collections.Generic.List[string]
    [void]$lines.Add('// Managed by UGSM. Edit from UGSM where possible.')
    if (-not [string]::IsNullOrWhiteSpace([string]$Settings.ServerName)) { [void]$lines.Add('Name ' + [string]$Settings.ServerName) }
    if (-not [string]::IsNullOrWhiteSpace([string]$Settings.Map)) { [void]$lines.Add('Map ' + [string]$Settings.Map) }
    if ([int]$Settings.GamePort -gt 0) { [void]$lines.Add('Port ' + [int]$Settings.GamePort) }
    if ([int]$Settings.MaxPlayers -gt 0) { [void]$lines.Add('MaxPlayers ' + [int]$Settings.MaxPlayers) }
    if (-not [string]::IsNullOrWhiteSpace([string]$Settings.Password)) { [void]$lines.Add('Password ' + [string]$Settings.Password) }
    if (-not [string]::IsNullOrWhiteSpace([string]$Settings.OwnerSteam64)) { [void]$lines.Add('Owner ' + [string]$Settings.OwnerSteam64) }
    if (-not [string]::IsNullOrWhiteSpace([string]$Settings.Difficulty)) { [void]$lines.Add('Difficulty ' + [string]$Settings.Difficulty) }
    if (-not [string]::IsNullOrWhiteSpace([string]$Settings.Perspective)) { [void]$lines.Add('Perspective ' + [string]$Settings.Perspective) }
    if ([bool]$Settings.Cheats) { [void]$lines.Add('Cheats') }
    if ([bool]$Settings.PvE) { [void]$lines.Add('PvE') }
    if (-not [string]::IsNullOrWhiteSpace([string]$Settings.Welcome)) { [void]$lines.Add('Welcome ' + [string]$Settings.Welcome) }
    if (-not [string]::IsNullOrWhiteSpace([string]$Settings.ExtraCommands)) {
        foreach ($line in (([string]$Settings.ExtraCommands) -split '\r?\n')) {
            if (-not [string]::IsNullOrWhiteSpace($line)) { [void]$lines.Add($line) }
        }
    }
    $parent = Split-Path -Parent $Path
    if (-not (Test-Path -LiteralPath $parent -PathType Container)) { New-Item -ItemType Directory -Force -Path $parent | Out-Null }
    Set-Content -LiteralPath $Path -Value $lines.ToArray() -Encoding UTF8
}


function Set-UGSMGameUnturnedConfigValue {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Content,
        [Parameter(Mandatory)][string]$Section,
        [Parameter(Mandatory)][string]$Key,
        [AllowNull()][string]$Value
    )
    $safeValue = [string]$Value
    $sectionPattern = '(?ms)^(?<indent>\s*)' + [regex]::Escape($Section) + '\s*\{(?<body>.*?)^\s*\}'
    $m = [regex]::Match($Content, $sectionPattern)
    if (-not $m.Success) {
        $block = [Environment]::NewLine + $Section + [Environment]::NewLine + '{' + [Environment]::NewLine + "\t" + $Key + ' ' + $safeValue + [Environment]::NewLine + '}' + [Environment]::NewLine
        return ($Content.TrimEnd() + $block)
    }
    $body = $m.Groups['body'].Value
    $keyPattern = '(?m)^(?<indent>\s*)' + [regex]::Escape($Key) + '(?:\s+.*)?$'
    if ([regex]::IsMatch($body, $keyPattern)) {
        $newBody = [regex]::Replace($body, $keyPattern, ('${indent}' + $Key + ' ' + $safeValue), 1)
    } else {
        $newBody = $body.TrimEnd() + [Environment]::NewLine + "\t" + $Key + ' ' + $safeValue + [Environment]::NewLine
    }
    return $Content.Substring(0, $m.Groups['body'].Index) + $newBody + $Content.Substring($m.Groups['body'].Index + $m.Groups['body'].Length)
}

function Save-UGSMGameUnturnedConfigTxt {
    [CmdletBinding()]
    param([Parameter(Mandatory)][object]$Settings, [Parameter(Mandatory)][string]$Path)
    $parent = Split-Path -Parent $Path
    if (-not (Test-Path -LiteralPath $parent -PathType Container)) { New-Item -ItemType Directory -Force -Path $parent | Out-Null }
    $content = $null
    if (Test-Path -LiteralPath $Path -PathType Leaf) {
        try { $content = Get-Content -LiteralPath $Path -Raw -ErrorAction Stop } catch { $content = $null }
    }
    if ([string]::IsNullOrWhiteSpace($content)) {
        $content = @'
// > Unturned Server Configuration File
Version 1

Browser
{
	// > Steam Game Server Login Token. Generate at Steam > Game Server Account Management.
	Login_Token
}
'@
    }
    $token = ''
    if ($Settings.PSObject.Properties['LoginToken']) { $token = [string]$Settings.LoginToken }
    elseif ($Settings.PSObject.Properties['GSLT']) { $token = [string]$Settings.GSLT }
    $content = Set-UGSMGameUnturnedConfigValue -Content $content -Section 'Browser' -Key 'Login_Token' -Value $token
    Set-Content -LiteralPath $Path -Value $content -Encoding UTF8
}

function Save-UGSMGameUnturnedWorkshopConfig {
    [CmdletBinding()]
    param([Parameter(Mandatory)][object]$Settings, [Parameter(Mandatory)][string]$Path)
    $ids = @()
    if ($Settings.WorkshopFileIds) { $ids = @($Settings.WorkshopFileIds | ForEach-Object { Convert-UGSMGameUnturnedWorkshopInputToId -InputText ([string]$_) } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -Unique) }
    $numericIds = @()
    foreach ($id in $ids) { try { $numericIds += [int64]$id } catch {} }
    $obj = [ordered]@{
        File_IDs = @($numericIds)
        Ignore_Children_File_IDs = @()
        Query_Cache_Max_Age_Seconds = 600
        Max_Query_Retries = 2
        Use_Cached_Downloads = $true
        Should_Monitor_Updates = $true
        Shutdown_Update_Detected_Timer = 600
        Shutdown_Update_Detected_Message = 'Workshop update detected. Server restarting soon.'
    }
    Save-UGSMGameUnturnedJsonFile -Path $Path -InputObject $obj
}

function Save-UGSMGameUnturnedSettings {
    [CmdletBinding()]
    param([Parameter(Mandatory)][object]$Instance, [Parameter(Mandatory)][object]$Settings, [string]$InstallPath)
    $paths = Get-UGSMGameUnturnedProfilePaths -Instance $Instance -InstallPath $InstallPath
    New-Item -ItemType Directory -Force -Path $paths.ProfileRoot, $paths.ExternalServerRoot, $paths.ServerConfigRoot, $paths.LogsRoot, $paths.CentralLogRoot | Out-Null
    Save-UGSMGameUnturnedJsonFile -Path $paths.SettingsPath -InputObject $Settings
    Save-UGSMGameUnturnedCommandsDat -Settings $Settings -Path $paths.CommandsPath
    Save-UGSMGameUnturnedConfigTxt -Settings $Settings -Path $paths.ConfigPath
    Save-UGSMGameUnturnedWorkshopConfig -Settings $Settings -Path $paths.WorkshopDownloadConfigPath

    foreach ($pair in @(
        @{Name='Port';Value=[int]$Settings.GamePort},
        @{Name='NotifyOnStart';Value=[bool]$Settings.Discord.NotifyOnStart},
        @{Name='NotifyOnStop';Value=[bool]$Settings.Discord.NotifyOnStop},
        @{Name='ShowInDashboard';Value=[bool]$Settings.Discord.ShowInDashboard}
    )) {
        if ($Instance.PSObject.Properties[$pair.Name]) { $Instance.($pair.Name) = $pair.Value }
        else { Add-Member -InputObject $Instance -MemberType NoteProperty -Name $pair.Name -Value $pair.Value -Force }
    }
    if ($Instance.PSObject.Properties['PrivateWebhookUrl']) { $Instance.PrivateWebhookUrl = [string]$Settings.Discord.WebhookUrl }
    else { Add-Member -InputObject $Instance -MemberType NoteProperty -Name PrivateWebhookUrl -Value ([string]$Settings.Discord.WebhookUrl) -Force }

    if (Get-Command -Name Save-UGSMDiscordInstanceSettings -ErrorAction SilentlyContinue) {
        try {
            Save-UGSMDiscordInstanceSettings -Instance $Instance -WebhookUrl ([string]$Settings.Discord.WebhookUrl) -NotifyOnStart:([bool]$Settings.Discord.NotifyOnStart) -NotifyOnStop:([bool]$Settings.Discord.NotifyOnStop) -ShowInDashboard:([bool]$Settings.Discord.ShowInDashboard) | Out-Null
        } catch { Write-UGSMGameUnturnedLog -Level 'WARN' -Message 'Discord settings save failed.' -Exception $_.Exception }
    }
    return [pscustomobject]@{ Success=$true; SettingsPath=$paths.SettingsPath; CommandsPath=$paths.CommandsPath; ConfigPath=$paths.ConfigPath; WorkshopDownloadConfigPath=$paths.WorkshopDownloadConfigPath }
}

function Ensure-UGSMGameUnturnedInstallServerLink {
    [CmdletBinding()]
    param([Parameter(Mandatory)][object]$Instance, [string]$InstallPath)
    $definition = Get-UGSMGameUnturnedInstallDefinition -InstallPath $InstallPath -Instance $Instance
    $paths = Get-UGSMGameUnturnedProfilePaths -Instance $Instance -InstallPath $definition.InstallPath
    New-Item -ItemType Directory -Force -Path $definition.ServersRoot, $paths.ExternalServerRoot | Out-Null
    if (Test-Path -LiteralPath $paths.InstallServerLinkPath) {
        $item = Get-Item -LiteralPath $paths.InstallServerLinkPath -Force
        if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { return $paths.InstallServerLinkPath }
        return $paths.InstallServerLinkPath
    }
    try {
        New-Item -ItemType Junction -Path $paths.InstallServerLinkPath -Target $paths.ExternalServerRoot -Force | Out-Null
        Write-UGSMGameUnturnedLog -Level 'INFO' -Message ("Created profile junction. Link=$($paths.InstallServerLinkPath); Target=$($paths.ExternalServerRoot)")
    } catch {
        Write-UGSMGameUnturnedLog -Level 'WARN' -Message 'Failed to create junction; falling back to normal folder under install Servers root.' -Exception $_.Exception
        New-Item -ItemType Directory -Force -Path $paths.InstallServerLinkPath | Out-Null
    }
    return $paths.InstallServerLinkPath
}

function Ensure-UGSMGameUnturnedTemplate {
    [CmdletBinding()]
    param([string]$InstallPath)
    return [pscustomobject]@{ Success=$true; Message='Unturned uses per-profile Commands.dat and WorkshopDownloadConfig.json templates generated by UGSM.' }
}

function Initialize-UGSMGameUnturnedProfile {
    [CmdletBinding()]
    param([Parameter(Mandatory)][object]$Instance, [string]$InstallPath, [int]$BootstrapSeconds = 0, [switch]$Force)
    $definition = Get-UGSMGameUnturnedInstallDefinition -InstallPath $InstallPath -Instance $Instance
    $paths = Get-UGSMGameUnturnedProfilePaths -Instance $Instance -InstallPath $definition.InstallPath
    New-Item -ItemType Directory -Force -Path $paths.ProfileRoot, $paths.ExternalServerRoot, $paths.ServerConfigRoot, $paths.LogsRoot, $paths.CentralLogRoot | Out-Null
    Ensure-UGSMGameUnturnedInstallServerLink -Instance $Instance -InstallPath $definition.InstallPath | Out-Null
    if ($Instance.PSObject.Properties['ProfilePath']) { $Instance.ProfilePath = $paths.ProfileRoot }
    else { Add-Member -InputObject $Instance -MemberType NoteProperty -Name ProfilePath -Value $paths.ProfileRoot -Force }
    if ($Instance.PSObject.Properties['InstallPath']) { $Instance.InstallPath = $definition.InstallPath }
    else { Add-Member -InputObject $Instance -MemberType NoteProperty -Name InstallPath -Value $definition.InstallPath -Force }
    $settings = Get-UGSMGameUnturnedSettings -Instance $Instance -InstallPath $definition.InstallPath
    if ($Force -or -not (Test-Path -LiteralPath $paths.SettingsPath) -or -not (Test-Path -LiteralPath $paths.CommandsPath)) { $settings = Get-UGSMGameUnturnedDefaultSettings -Instance $Instance }
    Save-UGSMGameUnturnedSettings -Instance $Instance -Settings $settings -InstallPath $definition.InstallPath | Out-Null
    Write-UGSMGameUnturnedLog -Level 'INFO' -Message ("Profile initialized. InstanceId=$(Get-UGSMGameUnturnedInstanceId -Instance $Instance); ProfilePath=$($paths.ProfileRoot)")
    return [pscustomobject]@{ Success=$true; ProfilePath=$paths.ProfileRoot; ConfigPath=$paths.CommandsPath }
}

function Test-UGSMGameUnturnedInstance {
    [CmdletBinding()]
    param([Parameter(Mandatory)][object]$Instance, [string]$InstallPath)
    $paths = Get-UGSMGameUnturnedProfilePaths -Instance $Instance -InstallPath $InstallPath
    $ok = (Test-Path -LiteralPath $paths.CommandsPath -PathType Leaf)
    return [pscustomobject]@{ Success=[bool]$ok; Exists=[bool]$ok; ProfilePath=$paths.ProfileRoot; ConfigPath=$paths.CommandsPath; Message=if ($ok) { 'Unturned profile exists.' } else { 'Unturned profile has not been initialized.' } }
}

function New-UGSMGameUnturnedLaunchWrapper {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$InstallPath, [Parameter(Mandatory)][object]$Paths, [Parameter(Mandatory)][object]$Settings)
    New-Item -ItemType Directory -Force -Path $Paths.LogsRoot | Out-Null
    $serverType = if ([string]$Settings.ServerMode -eq 'LAN') { 'LanServer' } else { 'InternetServer' }
    $serverId = $Paths.ProfileName
    $lines = @(
        '@echo off',
        'setlocal enableextensions',
        ('cd /d "{0}"' -f $InstallPath),
        ('echo [%date% %time%] UGSM Unturned launcher started. ServerId={0}; Mode={1}' -f $serverId, $serverType),
        ('call "{0}" +{1}/{2}' -f (Join-Path $InstallPath 'ServerHelper.bat'), $serverType, $serverId),
        'set EXITCODE=%ERRORLEVEL%',
        'echo [%date% %time%] UGSM Unturned launcher exited with code %EXITCODE%.',
        'exit /b %EXITCODE%'
    )
    Set-Content -LiteralPath $Paths.LauncherPath -Value $lines -Encoding ASCII
    return $Paths.LauncherPath
}

function Start-UGSMGameUnturnedInstance {
    [CmdletBinding()]
    param([Parameter(Mandatory)][object]$Instance, [string]$InstallPath)
    $instanceId = Get-UGSMGameUnturnedInstanceId -Instance $Instance
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    Write-UGSMGameUnturnedLog -Level 'INFO' -Message ("Start requested. InstanceId=$instanceId")
    $definition = Get-UGSMGameUnturnedInstallDefinition -InstallPath $InstallPath -Instance $Instance
    if (-not (Test-Path -LiteralPath $definition.ServerHelperPath -PathType Leaf)) { throw "Unturned ServerHelper.bat was not found: $($definition.ServerHelperPath)" }
    Initialize-UGSMGameUnturnedProfile -Instance $Instance -InstallPath $definition.InstallPath | Out-Null
    $paths = Get-UGSMGameUnturnedProfilePaths -Instance $Instance -InstallPath $definition.InstallPath
    $settings = Get-UGSMGameUnturnedSettings -Instance $Instance -InstallPath $definition.InstallPath
    Save-UGSMGameUnturnedSettings -Instance $Instance -Settings $settings -InstallPath $definition.InstallPath | Out-Null
    $launcherPath = New-UGSMGameUnturnedLaunchWrapper -InstallPath $definition.InstallPath -Paths $paths -Settings $settings
    try {
        $safeMode = if ([string]$settings.ServerMode -eq 'LAN') { 'LanServer' } else { 'InternetServer' }
        $header = @(
            ('[{0}] UGSM starting Unturned.' -f (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')),
            ('InstallPath: {0}' -f $definition.InstallPath),
            ('Launcher: {0}' -f $launcherPath),
            ('Server: +{0}/{1}' -f $safeMode, $paths.ProfileName),
            ('GamePort: {0}' -f $settings.GamePort),
            ''
        )
        Set-Content -LiteralPath $paths.LaunchLogPath -Value $header -Encoding UTF8
    } catch {}
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = 'cmd.exe'
    $psi.WorkingDirectory = $definition.InstallPath
    $psi.Arguments = '/d /k "' + $launcherPath + '"'
    $psi.UseShellExecute = $true
    $process = [System.Diagnostics.Process]::Start($psi)
    if (-not $process) { throw 'Unturned process failed to start.' }
    Start-Sleep -Seconds 3
    try { $process.Refresh() } catch {}
    if ($process.HasExited) { throw "Unturned process exited immediately with code $($process.ExitCode). Check $($paths.LaunchLogPath)." }
    if ($Instance.PSObject.Properties['ProcessId']) { $Instance.ProcessId = [int]$process.Id } else { Add-Member -InputObject $Instance -MemberType NoteProperty -Name ProcessId -Value ([int]$process.Id) -Force }
    if ($Instance.PSObject.Properties['Status']) { $Instance.Status = 'Running' } else { Add-Member -InputObject $Instance -MemberType NoteProperty -Name Status -Value 'Running' -Force }
    if (Get-Command -Name Send-UGSMInstanceDiscordNotification -ErrorAction SilentlyContinue) {
        try { Send-UGSMInstanceDiscordNotification -Instance $Instance -Event 'Start' | Out-Null } catch { Write-UGSMGameUnturnedLog -Level 'WARN' -Message ("Discord start notification failed. InstanceId=$instanceId") -Exception $_.Exception }
    }
    $sw.Stop()
    Write-UGSMGameUnturnedLog -Level 'INFO' -Message ("Start completed. InstanceId=$instanceId; Pid=$($process.Id); DurationMs=$($sw.ElapsedMilliseconds)")
    return [pscustomobject]@{ Success=$true; Status='Running'; ProcessId=[int]$process.Id; Pid=[int]$process.Id }
}

function Stop-UGSMGameUnturnedInstance {
    [CmdletBinding()]
    param([Parameter(Mandatory)][object]$Instance)
    $instanceId = Get-UGSMGameUnturnedInstanceId -Instance $Instance
    $processId = 0
    if ($Instance.PSObject.Properties['ProcessId'] -and ($Instance.ProcessId -as [int])) { $processId = [int]$Instance.ProcessId }
    Write-UGSMGameUnturnedLog -Level 'INFO' -Message ("Stop requested. InstanceId=$instanceId; Pid=$processId")
    $stopped = $false
    if ($processId -gt 0) {
        try {
            $proc = Get-Process -Id $processId -ErrorAction Stop
            try { if ($proc.CloseMainWindow()) { $stopped = $proc.WaitForExit(15000) } } catch {}
            if (-not $stopped) { Stop-Process -Id $processId -Force -ErrorAction Stop; $stopped = $true }
        } catch [System.ArgumentException] { $stopped = $true } catch { Write-UGSMGameUnturnedLog -Level 'ERROR' -Message ("Stop failed. InstanceId=$instanceId; Pid=$processId") -Exception $_.Exception }
    }
    try {
        $profileName = Get-UGSMGameUnturnedProfileName -Instance $Instance
        Get-CimInstance Win32_Process -Filter "name = 'Unturned.exe' or name = 'cmd.exe'" -ErrorAction SilentlyContinue |
            Where-Object { $_.CommandLine -match [Regex]::Escape($profileName) -and $_.CommandLine -match 'ServerHelper|InternetServer|LanServer|Unturned' } |
            ForEach-Object { Stop-Process -Id ([int]$_.ProcessId) -Force -ErrorAction SilentlyContinue; $stopped = $true }
    } catch {}
    if ($Instance.PSObject.Properties['Status']) { $Instance.Status = 'Stopped' } else { Add-Member -InputObject $Instance -MemberType NoteProperty -Name Status -Value 'Stopped' -Force }
    if ($Instance.PSObject.Properties['ProcessId']) { $Instance.ProcessId = $null }
    if (Get-Command -Name Send-UGSMInstanceDiscordNotification -ErrorAction SilentlyContinue) {
        try { Send-UGSMInstanceDiscordNotification -Instance $Instance -Event 'Stop' | Out-Null } catch { Write-UGSMGameUnturnedLog -Level 'WARN' -Message ("Discord stop notification failed. InstanceId=$instanceId") -Exception $_.Exception }
    }
    return [pscustomobject]@{ Success=$true; Status='Stopped'; Stopped=[bool]$stopped }
}

function Get-UGSMGameUnturnedColor {
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

function Add-UGSMGameUnturnedField {
    param([System.Windows.Forms.Panel]$Parent, [hashtable]$Controls, [string]$Key, [string]$Label, [string]$Value, [int]$Row, [object]$Theme, [switch]$Multiline, [int]$Height = 24)
    $labelControl = New-Object System.Windows.Forms.Label
    $labelControl.Text = $Label
    $labelControl.AutoSize = $false
    $labelControl.Left = 24
    $labelControl.Top = 18 + ($Row * 42)
    $labelControl.Width = 180
    $labelControl.Height = 22
    $labelControl.ForeColor = Get-UGSMGameUnturnedColor -Theme $Theme -Name 'Text' -Fallback ([System.Drawing.Color]::White)
    $text = New-Object System.Windows.Forms.TextBox
    $text.Left = 220
    $text.Top = $labelControl.Top - 2
    $text.Width = 520
    $text.Height = if ($Multiline) { $Height } else { 24 }
    $text.Multiline = [bool]$Multiline
    if ($Multiline) { $text.ScrollBars = 'Vertical'; $text.AcceptsReturn = $true }
    $text.Text = [string]$Value
    $text.BackColor = Get-UGSMGameUnturnedColor -Theme $Theme -Name 'Input' -Fallback ([System.Drawing.Color]::FromArgb(12,22,34))
    $text.ForeColor = Get-UGSMGameUnturnedColor -Theme $Theme -Name 'Text' -Fallback ([System.Drawing.Color]::White)
    $Parent.Controls.Add($labelControl)
    $Parent.Controls.Add($text)
    $Controls[$Key] = $text
    return $text
}

function Add-UGSMGameUnturnedCheckField {
    param([System.Windows.Forms.Panel]$Parent, [hashtable]$Controls, [string]$Key, [string]$Label, [bool]$Value, [int]$Row, [object]$Theme)
    $chk = New-Object System.Windows.Forms.CheckBox
    $chk.Left = 220
    $chk.Top = 18 + ($Row * 42)
    $chk.Width = 400
    $chk.Height = 24
    $chk.Text = $Label
    $chk.Checked = [bool]$Value
    $chk.ForeColor = Get-UGSMGameUnturnedColor -Theme $Theme -Name 'Text' -Fallback ([System.Drawing.Color]::White)
    $chk.BackColor = Get-UGSMGameUnturnedColor -Theme $Theme -Name 'Background' -Fallback ([System.Drawing.Color]::FromArgb(8,18,31))
    $Parent.Controls.Add($chk)
    $Controls[$Key] = $chk
    return $chk
}

function Save-UGSMGameUnturnedInstanceEditor {
    [CmdletBinding()]
    param([Parameter(Mandatory)][object]$EditorState)
    $instance = $EditorState.Instance
    $controls = $EditorState.Controls
    $settings = Get-UGSMGameUnturnedSettings -Instance $instance
    foreach ($name in @('ServerName','ServerMode','Map','Password','OwnerSteam64','LoginToken','Difficulty','Perspective','Welcome','ExtraCommands')) {
        if ($controls.ContainsKey($name)) { $settings.$name = [string]$controls[$name].Text }
    }
    foreach ($name in @('GamePort','MaxPlayers')) {
        if ($controls.ContainsKey($name)) { $n = 0; if ([int]::TryParse([string]$controls[$name].Text, [ref]$n)) { $settings.$name = $n } }
    }
    foreach ($name in @('Cheats','PvE')) { if ($controls.ContainsKey($name)) { $settings.$name = [bool]$controls[$name].Checked } }
    if ($controls.ContainsKey('WorkshopFileIds')) { $settings.WorkshopFileIds = @(ConvertFrom-UGSMGameUnturnedMultilineList -Text ([string]$controls['WorkshopFileIds'].Text)) }
    if ($controls.ContainsKey('DiscordWebhookUrl')) { $settings.Discord.WebhookUrl = [string]$controls['DiscordWebhookUrl'].Text }
    if ($controls.ContainsKey('NotifyOnStart')) { $settings.Discord.NotifyOnStart = [bool]$controls['NotifyOnStart'].Checked }
    if ($controls.ContainsKey('NotifyOnStop')) { $settings.Discord.NotifyOnStop = [bool]$controls['NotifyOnStop'].Checked }
    if ($controls.ContainsKey('ShowInDashboard')) { $settings.Discord.ShowInDashboard = [bool]$controls['ShowInDashboard'].Checked }
    return Save-UGSMGameUnturnedSettings -Instance $instance -Settings $settings
}

function New-UGSMGameUnturnedInstanceEditor {
    [CmdletBinding()]
    param([Parameter(Mandatory)][object]$Instance, [Parameter(Mandatory)][System.Windows.Forms.Control]$HostPanel, [AllowNull()][object]$Theme, [AllowNull()][System.Windows.Forms.Label]$StatusLabel)
    $instanceId = Get-UGSMGameUnturnedInstanceId -Instance $Instance
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    Write-UGSMGameUnturnedLog -Level 'INFO' -Message ("Editor creation started. InstanceId=$instanceId")
    $HostPanel.SuspendLayout()
    try {
        $HostPanel.Controls.Clear()
        $HostPanel.BackColor = Get-UGSMGameUnturnedColor -Theme $Theme -Name 'Background' -Fallback ([System.Drawing.Color]::FromArgb(8,18,31))
        $tabs = New-Object System.Windows.Forms.TabControl
        $tabs.Dock = 'Fill'
        $tabs.Multiline = $false
        $HostPanel.Controls.Add($tabs)

        $settings = Get-UGSMGameUnturnedSettings -Instance $Instance
        $controls = @{}

        $serverTab = New-Object System.Windows.Forms.TabPage
        $serverTab.Text = 'Server'
        $serverPanel = New-Object System.Windows.Forms.Panel
        $serverPanel.Dock = 'Fill'
        $serverPanel.AutoScroll = $true
        $serverPanel.BackColor = $HostPanel.BackColor
        $serverTab.Controls.Add($serverPanel)
        [void]$tabs.TabPages.Add($serverTab)
        Add-UGSMGameUnturnedField -Parent $serverPanel -Controls $controls -Key 'ServerName' -Label 'Server name' -Value $settings.ServerName -Row 0 -Theme $Theme | Out-Null
        Add-UGSMGameUnturnedField -Parent $serverPanel -Controls $controls -Key 'ServerMode' -Label 'Server mode Internet/LAN' -Value $settings.ServerMode -Row 1 -Theme $Theme | Out-Null
        Add-UGSMGameUnturnedField -Parent $serverPanel -Controls $controls -Key 'Map' -Label 'Map name' -Value $settings.Map -Row 2 -Theme $Theme | Out-Null
        Add-UGSMGameUnturnedField -Parent $serverPanel -Controls $controls -Key 'GamePort' -Label 'Game port' -Value ([string]$settings.GamePort) -Row 3 -Theme $Theme | Out-Null
        Add-UGSMGameUnturnedField -Parent $serverPanel -Controls $controls -Key 'MaxPlayers' -Label 'Max players' -Value ([string]$settings.MaxPlayers) -Row 4 -Theme $Theme | Out-Null
        Add-UGSMGameUnturnedField -Parent $serverPanel -Controls $controls -Key 'Password' -Label 'Password' -Value $settings.Password -Row 5 -Theme $Theme | Out-Null
        Add-UGSMGameUnturnedField -Parent $serverPanel -Controls $controls -Key 'OwnerSteam64' -Label 'Owner Steam64 ID' -Value $settings.OwnerSteam64 -Row 6 -Theme $Theme | Out-Null
        Add-UGSMGameUnturnedField -Parent $serverPanel -Controls $controls -Key 'LoginToken' -Label 'Login token / GSLT' -Value $settings.LoginToken -Row 7 -Theme $Theme | Out-Null
        Add-UGSMGameUnturnedField -Parent $serverPanel -Controls $controls -Key 'Difficulty' -Label 'Difficulty' -Value $settings.Difficulty -Row 8 -Theme $Theme | Out-Null
        Add-UGSMGameUnturnedField -Parent $serverPanel -Controls $controls -Key 'Perspective' -Label 'Perspective' -Value $settings.Perspective -Row 9 -Theme $Theme | Out-Null
        Add-UGSMGameUnturnedCheckField -Parent $serverPanel -Controls $controls -Key 'Cheats' -Label 'Enable cheats' -Value ([bool]$settings.Cheats) -Row 10 -Theme $Theme | Out-Null
        Add-UGSMGameUnturnedCheckField -Parent $serverPanel -Controls $controls -Key 'PvE' -Label 'PvE' -Value ([bool]$settings.PvE) -Row 11 -Theme $Theme | Out-Null
        Add-UGSMGameUnturnedField -Parent $serverPanel -Controls $controls -Key 'Welcome' -Label 'Welcome message' -Value $settings.Welcome -Row 12 -Theme $Theme | Out-Null
        Add-UGSMGameUnturnedField -Parent $serverPanel -Controls $controls -Key 'ExtraCommands' -Label 'Extra Commands.dat lines' -Value $settings.ExtraCommands -Row 13 -Theme $Theme -Multiline -Height 90 | Out-Null

        $modsTab = New-Object System.Windows.Forms.TabPage
        $modsTab.Text = 'Mods'
        $modsPanel = New-Object System.Windows.Forms.Panel
        $modsPanel.Dock = 'Fill'
        $modsPanel.AutoScroll = $true
        $modsPanel.BackColor = $HostPanel.BackColor
        $modsTab.Controls.Add($modsPanel)
        [void]$tabs.TabPages.Add($modsTab)
        $note = New-Object System.Windows.Forms.Label
        $note.Text = 'Workshop mods/maps go in WorkshopDownloadConfig.json as File_IDs. For a Workshop map, also set Server > Map name to the exact map folder/name.'
        $note.Left = 24; $note.Top = 18; $note.Width = 900; $note.Height = 36
        $note.ForeColor = Get-UGSMGameUnturnedColor -Theme $Theme -Name 'Text' -Fallback ([System.Drawing.Color]::White)
        $modsPanel.Controls.Add($note)
        Add-UGSMGameUnturnedField -Parent $modsPanel -Controls $controls -Key 'WorkshopFileIds' -Label 'Workshop IDs/URLs' -Value ((@($settings.WorkshopFileIds) -join [Environment]::NewLine)) -Row 2 -Theme $Theme -Multiline -Height 160 | Out-Null
        $btnOpenWorkshop = New-Object System.Windows.Forms.Button
        $btnOpenWorkshop.Text = 'Open WorkshopDownloadConfig.json'
        $btnOpenWorkshop.Left = 220; $btnOpenWorkshop.Top = 280; $btnOpenWorkshop.Width = 240; $btnOpenWorkshop.Height = 30
        $btnOpenWorkshop.Tag = [pscustomobject]@{ Instance=$Instance; StatusLabel=$StatusLabel }
        $btnOpenWorkshop.Add_Click({ param($sender,$eventArgs) try { $s=$sender.Tag; $p=Get-UGSMGameUnturnedProfilePaths -Instance $s.Instance; if (-not (Test-Path -LiteralPath $p.WorkshopDownloadConfigPath)) { Initialize-UGSMGameUnturnedProfile -Instance $s.Instance | Out-Null }; Invoke-Item -LiteralPath $p.WorkshopDownloadConfigPath } catch { if ($s.StatusLabel) { $s.StatusLabel.Text = 'Open WorkshopDownloadConfig failed: ' + $_.Exception.Message } } })
        $modsPanel.Controls.Add($btnOpenWorkshop)

        $discordTab = New-Object System.Windows.Forms.TabPage
        $discordTab.Text = 'Discord'
        $discordPanel = New-Object System.Windows.Forms.Panel
        $discordPanel.Dock = 'Fill'
        $discordPanel.AutoScroll = $true
        $discordPanel.BackColor = $HostPanel.BackColor
        $discordTab.Controls.Add($discordPanel)
        [void]$tabs.TabPages.Add($discordTab)
        Add-UGSMGameUnturnedField -Parent $discordPanel -Controls $controls -Key 'DiscordWebhookUrl' -Label 'Private Discord webhook URL' -Value $settings.Discord.WebhookUrl -Row 0 -Theme $Theme | Out-Null
        Add-UGSMGameUnturnedCheckField -Parent $discordPanel -Controls $controls -Key 'NotifyOnStart' -Label 'Notify on Start' -Value ([bool]$settings.Discord.NotifyOnStart) -Row 1 -Theme $Theme | Out-Null
        Add-UGSMGameUnturnedCheckField -Parent $discordPanel -Controls $controls -Key 'NotifyOnStop' -Label 'Notify on Stop' -Value ([bool]$settings.Discord.NotifyOnStop) -Row 2 -Theme $Theme | Out-Null
        Add-UGSMGameUnturnedCheckField -Parent $discordPanel -Controls $controls -Key 'ShowInDashboard' -Label 'Show in Discord/dashboard status' -Value ([bool]$settings.Discord.ShowInDashboard) -Row 3 -Theme $Theme | Out-Null
        $btnTestDiscord = New-Object System.Windows.Forms.Button
        $btnTestDiscord.Text = 'Test Discord'
        $btnTestDiscord.Left = 220; $btnTestDiscord.Top = 190; $btnTestDiscord.Width = 160; $btnTestDiscord.Height = 30
        $btnTestDiscord.Tag = [pscustomobject]@{ Instance=$Instance; Controls=$controls; StatusLabel=$StatusLabel }
        $btnTestDiscord.Add_Click({ param($sender,$eventArgs) $st=$sender.Tag; try { Save-UGSMGameUnturnedInstanceEditor -EditorState $st | Out-Null; if (Get-Command -Name Send-UGSMInstanceDiscordNotification -ErrorAction SilentlyContinue) { Send-UGSMInstanceDiscordNotification -Instance $st.Instance -Event 'Test' | Out-Null }; if ($st.StatusLabel) { $st.StatusLabel.Text = 'Unturned Discord test sent.' } } catch { if ($st.StatusLabel) { $st.StatusLabel.Text = 'Unturned Discord test failed: ' + $_.Exception.Message }; Write-UGSMGameUnturnedLog -Level 'ERROR' -Message 'Discord test failed.' -Exception $_.Exception } })
        $discordPanel.Controls.Add($btnTestDiscord)

        $state = [pscustomobject]@{ Instance=$Instance; Controls=$controls; StatusLabel=$StatusLabel }
        $btnSave = New-Object System.Windows.Forms.Button
        $btnSave.Text = 'Save Settings'
        $btnSave.Dock = 'Bottom'
        $btnSave.Height = 34
        $btnSave.BackColor = Get-UGSMGameUnturnedColor -Theme $Theme -Name 'Accent' -Fallback ([System.Drawing.Color]::DodgerBlue)
        $btnSave.ForeColor = Get-UGSMGameUnturnedColor -Theme $Theme -Name 'Text' -Fallback ([System.Drawing.Color]::White)
        $btnSave.Tag = $state
        $HostPanel.Controls.Add($btnSave)
        $btnSave.BringToFront()
        $btnSave.Add_Click({ param($sender,$eventArgs) $clickedState=$sender.Tag; try { Save-UGSMGameUnturnedInstanceEditor -EditorState $clickedState | Out-Null; if ($clickedState.StatusLabel) { $clickedState.StatusLabel.Text = 'Unturned settings saved.' } } catch { if ($clickedState.StatusLabel) { $clickedState.StatusLabel.Text = 'Unturned save failed: ' + $_.Exception.Message }; Write-UGSMGameUnturnedLog -Level 'ERROR' -Message 'Editor save failed.' -Exception $_.Exception } })
    }
    finally { $HostPanel.ResumeLayout($true) }
    $sw.Stop()
    Write-UGSMGameUnturnedLog -Level 'INFO' -Message ("Editor creation finished. InstanceId=$instanceId; DurationMs=$($sw.ElapsedMilliseconds)")
}

function Register-UGSMGameUnturnedModule {
    [CmdletBinding()]
    param()
    $metadata = Get-UGSMGameUnturnedMetadata
    return [pscustomobject]@{
        Id       = [string]$metadata.Id
        Metadata = $metadata
        Handlers = [pscustomobject]@{
            GetMetadata       = 'Get-UGSMGameUnturnedMetadata'
            TestInstall       = 'Test-UGSMGameUnturnedInstall'
            TestInstance      = 'Test-UGSMGameUnturnedInstance'
            EnsureTemplate    = 'Ensure-UGSMGameUnturnedTemplate'
            InitializeProfile = 'Initialize-UGSMGameUnturnedProfile'
            Start             = 'Start-UGSMGameUnturnedInstance'
            Stop              = 'Stop-UGSMGameUnturnedInstance'
            BuildEditor       = 'New-UGSMGameUnturnedInstanceEditor'
            SaveEditor        = 'Save-UGSMGameUnturnedInstanceEditor'
        }
    }
}
