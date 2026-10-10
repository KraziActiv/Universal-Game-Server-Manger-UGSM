# UGSM Game Module: Conan Exiles
# First supported pass: logging, lightweight profile runtime, basic config editor, Discord, and Workshop .pak mod handling.

function Write-UGSMGameConanExilesLog {
    [CmdletBinding()]
    param(
        [ValidateSet('TRACE','DEBUG','INFO','WARN','ERROR','FATAL')][string]$Level = 'INFO',
        [Parameter(Mandatory)][string]$Message,
        [System.Exception]$Exception
    )

    if (Get-Command -Name Write-UGSMLog -ErrorAction SilentlyContinue) {
        if ($Exception) { Write-UGSMLog -Level $Level -Category 'ConanExiles' -Message $Message -Exception $Exception }
        else { Write-UGSMLog -Level $Level -Category 'ConanExiles' -Message $Message }
        return
    }

    if ($Exception) { Write-Host "[$Level] [ConanExiles] $Message $($Exception.Message)" }
    else { Write-Host "[$Level] [ConanExiles] $Message" }
}

function Test-UGSMGameConanExilesVerboseLogging {
    [CmdletBinding()]
    param()
    if ((Get-Variable -Name UGSM_EnableVerboseConanExilesLogging -Scope Script -ErrorAction SilentlyContinue) -and $script:UGSM_EnableVerboseConanExilesLogging) { return $true }
    if ($env:UGSM_VERBOSE_CONAN_EXILES -in @('1','true','yes','on')) { return $true }
    return $false
}

function Get-UGSMGameConanExilesObjectValue {
    [CmdletBinding()]
    param([object]$InputObject,[string[]]$Names,[object]$Default = $null)
    if ($null -eq $InputObject) { return $Default }
    foreach ($name in $Names) {
        if ([string]::IsNullOrWhiteSpace($name)) { continue }
        try {
            if ($InputObject -is [hashtable] -and $InputObject.ContainsKey($name)) { return $InputObject[$name] }
            $prop = $InputObject.PSObject.Properties[$name]
            if ($prop) { return $prop.Value }
        } catch {}
    }
    return $Default
}

function Set-UGSMGameConanExilesObjectValue {
    [CmdletBinding()]
    param([Parameter(Mandatory)][object]$InputObject,[Parameter(Mandatory)][string]$Name,[object]$Value)
    if ($InputObject -is [hashtable]) { $InputObject[$Name] = $Value; return }
    $prop = $InputObject.PSObject.Properties[$Name]
    if ($prop) { $InputObject.$Name = $Value }
    else { $InputObject | Add-Member -NotePropertyName $Name -NotePropertyValue $Value -Force }
}


function Get-UGSMGameConanExilesEffectiveDiscordWebhookUrl {
    [CmdletBinding()]
    param(
        [string]$InstanceWebhookUrl
    )

    $instanceWebhook = ([string]$InstanceWebhookUrl).Trim()
    if (-not [string]::IsNullOrWhiteSpace($instanceWebhook)) {
        return [pscustomobject]@{
            WebhookUrl = $instanceWebhook
            Source     = 'Instance'
        }
    }

    $globalWebhook = ''
    try {
        if (Get-Command -Name Get-UGSMGlobalSettingsModel -ErrorAction SilentlyContinue) {
            $settingsModel = Get-UGSMGlobalSettingsModel
            if ($settingsModel -and $settingsModel.PSObject.Properties['GlobalDiscordWebhookUrl']) {
                $globalWebhook = ([string]$settingsModel.GlobalDiscordWebhookUrl).Trim()
            }
        }
    }
    catch {
        Write-UGSMGameConanExilesLog -Level 'WARN' -Message 'Failed to load global Discord webhook for Conan Exiles test.' -Exception $_.Exception
    }

    return [pscustomobject]@{
        WebhookUrl = $globalWebhook
        Source     = if ([string]::IsNullOrWhiteSpace($globalWebhook)) { 'None' } else { 'Global' }
    }
}

function New-UGSMGameConanExilesDirectory {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path -PathType Container)) { [void](New-Item -ItemType Directory -Path $Path -Force) }
    return $Path
}

function ConvertTo-UGSMGameConanExilesArg {
    [CmdletBinding()]
    param([string]$Value)
    if ($null -eq $Value) { return '""' }
    $text = [string]$Value
    if ($text -notmatch '[\s"]') { return $text }
    return ('"{0}"' -f ($text -replace '"','\"'))
}

function Get-UGSMGameConanExilesMetadata {
    [CmdletBinding()]
    param()

    return [pscustomobject]@{
        Id                       = 'ConanExiles'
        Name                     = 'Conan Exiles'
        Category                 = 'Survival'
        Description              = 'Conan Exiles dedicated server with lightweight profiles, Discord notifications, and Steam Workshop .pak mod support.'
        IsCustom                 = $false
        SupportTier              = 'Full'
        SortOrder                = 75
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
        SupportsBootstrap        = $true
        SupportsProfiles         = $true
        SupportsInstanceUi       = $true
        InstallProvider          = 'SteamCMD'
        RequiresSteamLogin       = $false
        SteamLoginMode           = 'Anonymous'
        SteamAppId               = '443030'
        SteamStoreAppId          = '440900'
        ServerExecutable         = 'ConanSandboxServer-Win64-Shipping.exe'
        ServerExecutableRelative = (Join-Path 'ConanSandbox\Binaries\Win64' 'ConanSandboxServer-Win64-Shipping.exe')
        UsesSharedBinaries       = $true
        InstanceType             = 'DedicatedServer'
        ConfigRootRelative       = 'ConanSandbox\Saved\Config\WindowsServer'
        SaveRootRelative         = 'ConanSandbox\Saved\SaveGames'
        LogRootRelative          = 'ConanSandbox\Saved\Logs'
        RequiredFiles            = @('ConanSandbox\Binaries\Win64','ConanSandbox')
        InstallMarkers           = @('ConanSandbox')
        PortSchema               = @(
            @{ Name = 'GamePort'; Protocol = 'UDP'; PreferredStart = 7777 }
            @{ Name = 'QueryPort'; Protocol = 'UDP'; PreferredStart = 27015 }
            @{ Name = 'RconPort'; Protocol = 'TCP'; PreferredStart = 25575 }
        )
        GameTraits               = [pscustomobject]@{
            UsesIniFiles          = $true
            UsesJsonFiles         = $true
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
                'Conan Exiles dedicated server app id is 443030 and usually installs anonymously with SteamCMD.',
                'Game port defaults to UDP 7777; pinger port is game port + 1; query port defaults to UDP 27015.',
                'Mods are Steam Workshop .pak files listed in ConanSandbox\Mods\modlist.txt with an asterisk prefix.'
            )
        }
    }
}

function Get-UGSMGameConanExilesInstallDefinition {
    [CmdletBinding()]
    param([string]$InstallPath,[object]$Instance)

    if ([string]::IsNullOrWhiteSpace($InstallPath) -and $Instance) {
        $InstallPath = [string](Get-UGSMGameConanExilesObjectValue $Instance @('InstallPath','ServerPath','GameInstallPath') '')
    }

    if ([string]::IsNullOrWhiteSpace($InstallPath)) {
        $settings = $null
        if (Get-Command -Name Get-UGSMGlobalSettings -ErrorAction SilentlyContinue) {
            try { $settings = Get-UGSMGlobalSettings -CreateIfMissing } catch { $settings = $null }
        }
        $root = $null
        foreach ($propName in @('SteamLibraryRoot','SteamRoot','InstallRoot','SteamCmdRoot','ServerInstallRoot')) {
            $value = [string](Get-UGSMGameConanExilesObjectValue $settings @($propName) '')
            if (-not [string]::IsNullOrWhiteSpace($value)) { $root = $value; break }
        }
        if ([string]::IsNullOrWhiteSpace($root)) { $root = Join-Path (Join-Path $env:LOCALAPPDATA 'UGSM') 'Servers' }

        $commonRoot = $root
        if ((Split-Path -Leaf $commonRoot) -ne 'common') {
            if (Test-Path -LiteralPath (Join-Path $commonRoot 'steamapps\common')) { $commonRoot = Join-Path $commonRoot 'steamapps\common' }
            elseif (Test-Path -LiteralPath (Join-Path $commonRoot 'Steam\steamapps\common')) { $commonRoot = Join-Path $commonRoot 'Steam\steamapps\common' }
        }
        $InstallPath = Join-Path $commonRoot 'Conan Exiles Dedicated Server'
    }

    $meta = Get-UGSMGameConanExilesMetadata
    $exePath = Join-Path $InstallPath $meta.ServerExecutableRelative
    if (-not (Test-Path -LiteralPath $exePath -PathType Leaf)) {
        $fallback = Join-Path $InstallPath 'ConanSandboxServer.exe'
        if (Test-Path -LiteralPath $fallback -PathType Leaf) { $exePath = $fallback }
    }

    return [pscustomobject]@{
        GameId               = $meta.Id
        GameName             = $meta.Name
        SteamAppId           = $meta.SteamAppId
        SteamStoreAppId      = $meta.SteamStoreAppId
        InstallPath          = $InstallPath
        ServerExecutablePath = $exePath
        RequiredFiles        = @($meta.RequiredFiles)
        InstallMarkers       = @($meta.InstallMarkers)
        ConfigRootPath       = Join-Path $InstallPath $meta.ConfigRootRelative
        SaveRootPath         = Join-Path $InstallPath $meta.SaveRootRelative
        LogRootPath          = Join-Path $InstallPath $meta.LogRootRelative
    }
}

function Test-UGSMGameConanExilesInstall {
    [CmdletBinding()]
    param([string]$InstallPath,[object]$Instance)
    try {
        $def = Get-UGSMGameConanExilesInstallDefinition -InstallPath $InstallPath -Instance $Instance
        $exeExists = Test-Path -LiteralPath $def.ServerExecutablePath -PathType Leaf
        return [pscustomobject]@{ Success = [bool]$exeExists; IsInstalled = [bool]$exeExists; InstallPath = $def.InstallPath; ServerExecutablePath = $def.ServerExecutablePath; Message = $(if ($exeExists) { 'Conan Exiles server install found.' } else { 'Conan Exiles server executable was not found.' }) }
    } catch {
        Write-UGSMGameConanExilesLog -Level ERROR -Message 'Install test failed.' -Exception $_.Exception
        return [pscustomobject]@{ Success = $false; IsInstalled = $false; Message = $_.Exception.Message }
    }
}

function Get-UGSMGameConanExilesProfileRoot {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$ProfileName)
    if (Get-Command -Name Get-UGSMDefaultInstanceProfilePath -ErrorAction SilentlyContinue) {
        try { return [string](Get-UGSMDefaultInstanceProfilePath -GameId 'ConanExiles' -Name $ProfileName) } catch {}
    }
    $settings = $null
    if (Get-Command -Name Get-UGSMGlobalSettings -ErrorAction SilentlyContinue) { try { $settings = Get-UGSMGlobalSettings -CreateIfMissing } catch {} }
    $base = [string](Get-UGSMGameConanExilesObjectValue $settings @('ProfileBaseRoot') '')
    if ([string]::IsNullOrWhiteSpace($base)) { $base = Join-Path (Join-Path $env:LOCALAPPDATA 'UGSM') 'Profiles' }
    return (Join-Path (Join-Path $base 'ConanExiles') $ProfileName)
}

function Get-UGSMGameConanExilesProfilePaths {
    [CmdletBinding()]
    param([Parameter(Mandatory)][object]$Instance)
    $name = [string](Get-UGSMGameConanExilesObjectValue $Instance @('Name','Id','InstanceId') 'ConanServer')
    $profileRoot = [string](Get-UGSMGameConanExilesObjectValue $Instance @('ProfilePath') '')
    if ([string]::IsNullOrWhiteSpace($profileRoot)) { $profileRoot = Get-UGSMGameConanExilesProfileRoot -ProfileName $name }
    $runtimeRoot = $profileRoot
    $sandboxRoot = Join-Path $runtimeRoot 'ConanSandbox'
    return [pscustomobject]@{
        ProfileRoot    = $profileRoot
        RuntimeRoot    = $runtimeRoot
        SandboxRoot    = $sandboxRoot
        ConfigRoot     = Join-Path $sandboxRoot 'Saved\Config\WindowsServer'
        SaveRoot       = Join-Path $sandboxRoot 'Saved\SaveGames'
        LogRoot        = Join-Path $sandboxRoot 'Saved\Logs'
        ModsRoot       = Join-Path $sandboxRoot 'Mods'
        ManagedMods    = Join-Path $profileRoot 'UGSM_ManagedMods.json'
        SettingsJson   = Join-Path $profileRoot 'UGSM_ConanExilesSettings.json'
        EngineIni      = Join-Path (Join-Path $sandboxRoot 'Saved\Config\WindowsServer') 'Engine.ini'
        ServerSettings = Join-Path (Join-Path $sandboxRoot 'Saved\Config\WindowsServer') 'ServerSettings.ini'
    }
}

function New-UGSMGameConanExilesJunction {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Target,[Parameter(Mandatory)][string]$Link)
    if (-not (Test-Path -LiteralPath $Target -PathType Container)) { return $false }
    if (Test-Path -LiteralPath $Link) { return $true }
    New-UGSMGameConanExilesDirectory -Path (Split-Path -Parent $Link) | Out-Null
    try { [void](New-Item -ItemType Junction -Path $Link -Target $Target -ErrorAction Stop); return $true }
    catch { Write-UGSMGameConanExilesLog -Level WARN -Message ("Failed to create junction. Link={0}; Target={1}" -f $Link,$Target) -Exception $_.Exception; return $false }
}

function Get-UGSMGameConanExilesAssignedPort {
    [CmdletBinding()]
    param([object]$Instance,[Parameter(Mandatory)][string]$Name,[int]$Default)

    $direct = Get-UGSMGameConanExilesObjectValue $Instance @($Name) $null
    if ($direct -as [int]) { return [int]$direct }
    $ports = Get-UGSMGameConanExilesObjectValue $Instance @('Ports') $null
    $value = Get-UGSMGameConanExilesObjectValue $ports @($Name) $null
    if ($value -as [int]) { return [int]$value }

    $instanceId = [string](Get-UGSMGameConanExilesObjectValue $Instance @('Id','InstanceId','Name') '')
    foreach ($path in @(
        (Join-Path (Join-Path $env:LOCALAPPDATA 'UGSM') 'ports.json'),
        (Join-Path (Join-Path $env:LOCALAPPDATA 'UGSM') 'Data\ports.json')
    )) {
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { continue }
        try {
            $json = Get-Content -LiteralPath $path -Raw | ConvertFrom-Json
            foreach ($assignment in @($json.Assignments)) {
                if ([string]$assignment.InstanceId -ieq $instanceId -and [string]$assignment.GameId -ieq 'ConanExiles') {
                    $p = Get-UGSMGameConanExilesObjectValue $assignment.Ports @($Name) $null
                    if ($p -as [int]) { return [int]$p }
                }
            }
        } catch {}
    }
    return $Default
}


function Ensure-UGSMGameConanExilesServerSettingsTemplate {
    [CmdletBinding()]
    param(
        [object]$Instance,
        [object]$InstallDefinition,
        [object]$Paths
    )

    if (-not $Paths) { $Paths = Get-UGSMGameConanExilesProfilePaths -Instance $Instance }
    New-UGSMGameConanExilesDirectory -Path $Paths.ConfigRoot | Out-Null

    $source = $null
    if ($InstallDefinition -and -not [string]::IsNullOrWhiteSpace([string]$InstallDefinition.InstallPath)) {
        $candidate = Join-Path ([string]$InstallDefinition.InstallPath) 'ConanSandbox\Saved\Config\WindowsServer\ServerSettings.ini'
        if (Test-Path -LiteralPath $candidate -PathType Leaf) { $source = $candidate }
    }

    if ((Test-Path -LiteralPath $Paths.ServerSettings -PathType Leaf) -and $source) {
        try {
            $templateEntries = @(Get-UGSMGameConanExilesIniSectionEntries -Path $source -Section 'ServerSettings')
            $profileEntries = @(Get-UGSMGameConanExilesIniSectionEntries -Path $Paths.ServerSettings -Section 'ServerSettings')
            $existing = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
            foreach ($entry in $profileEntries) { if ($entry -and -not [string]::IsNullOrWhiteSpace([string]$entry.Key)) { [void]$existing.Add([string]$entry.Key) } }
            $missing = @{}
            foreach ($entry in $templateEntries) {
                $key = [string]$entry.Key
                if ([string]::IsNullOrWhiteSpace($key)) { continue }
                if (-not $existing.Contains($key)) { $missing[$key] = [string]$entry.Value }
            }
            if ($missing.Count -gt 0) {
                Save-UGSMGameConanExilesIniSectionEntries -Path $Paths.ServerSettings -Section 'ServerSettings' -Values $missing
                Write-UGSMGameConanExilesLog -Level INFO -Message ("Merged missing Conan ServerSettings.ini keys into profile. MissingCount={0}; Source={1}; Destination={2}" -f $missing.Count,$source,$Paths.ServerSettings)
            }
        } catch {
            Write-UGSMGameConanExilesLog -Level WARN -Message 'Failed to merge missing Conan ServerSettings.ini keys from template.' -Exception $_.Exception
        }
        return $Paths.ServerSettings
    }

    if (Test-Path -LiteralPath $Paths.ServerSettings -PathType Leaf) { return $Paths.ServerSettings }

    if ($source) {
        Copy-Item -LiteralPath $source -Destination $Paths.ServerSettings -Force
        Write-UGSMGameConanExilesLog -Level INFO -Message ("Copied Conan ServerSettings.ini template to profile. Source={0}; Destination={1}" -f $source,$Paths.ServerSettings)
    } else {
        @(
            '; Conan Exiles ServerSettings.ini generated by UGSM',
            '[ServerSettings]',
            'AdminPassword=changeme',
            'MaxPlayers=40',
            'ServerCommunity=0',
            'PVPEnabled=False'
        ) | Set-Content -LiteralPath $Paths.ServerSettings -Encoding UTF8
        Write-UGSMGameConanExilesLog -Level WARN -Message ("Conan ServerSettings.ini template was not found in the Steam install. Generated a minimal profile config. Path={0}" -f $Paths.ServerSettings)
    }
    return $Paths.ServerSettings
}

function Get-UGSMGameConanExilesIniSectionEntries {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Path,
        [string]$Section = 'ServerSettings'
    )

    $entries = New-Object System.Collections.ArrayList
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return @() }

    $inSection = $false
    $sectionHeader = '[' + $Section + ']'
    foreach ($rawLine in [string[]](Get-Content -LiteralPath $Path)) {
        $line = [string]$rawLine
        $trim = $line.Trim()
        if ($trim -match '^\[(.+)\]$') {
            $inSection = ($trim -ieq $sectionHeader)
            continue
        }
        if (-not $inSection) { continue }
        if ([string]::IsNullOrWhiteSpace($trim)) { continue }
        if ($trim.StartsWith(';') -or $trim.StartsWith('#')) { continue }
        $eq = $line.IndexOf('=')
        if ($eq -lt 1) { continue }
        $key = $line.Substring(0,$eq).Trim()
        $value = ''
        if ($eq -lt ($line.Length - 1)) { $value = $line.Substring($eq + 1).Trim() }
        if ([string]::IsNullOrWhiteSpace($key)) { continue }
        [void]$entries.Add([pscustomobject]@{ Key = $key; Value = $value })
    }
    return [object[]]$entries.ToArray()
}

function Save-UGSMGameConanExilesIniSectionEntries {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Path,
        [string]$Section = 'ServerSettings',
        [Parameter(Mandatory)][hashtable]$Values
    )

    New-UGSMGameConanExilesDirectory -Path (Split-Path -Parent $Path) | Out-Null
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        @('[' + $Section + ']') | Set-Content -LiteralPath $Path -Encoding UTF8
    }

    $lines = New-Object System.Collections.ArrayList
    [void]$lines.AddRange([string[]](Get-Content -LiteralPath $Path))
    $sectionHeader = '[' + $Section + ']'
    $sectionIndex = -1
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ([string]$lines[$i] -ieq $sectionHeader) { $sectionIndex = $i; break }
    }
    if ($sectionIndex -lt 0) {
        if ($lines.Count -gt 0) { [void]$lines.Add('') }
        [void]$lines.Add($sectionHeader)
        $sectionIndex = $lines.Count - 1
    }

    $endIndex = $lines.Count
    for ($i = $sectionIndex + 1; $i -lt $lines.Count; $i++) {
        if ([string]$lines[$i] -match '^\s*\[.+\]\s*$') { $endIndex = $i; break }
    }

    $seen = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
    for ($i = $sectionIndex + 1; $i -lt $endIndex; $i++) {
        $line = [string]$lines[$i]
        $eq = $line.IndexOf('=')
        if ($eq -lt 1) { continue }
        $key = $line.Substring(0,$eq).Trim()
        if ($Values.ContainsKey($key)) {
            $lines[$i] = ('{0}={1}' -f $key, [string]$Values[$key])
            [void]$seen.Add($key)
        }
    }

    foreach ($key in $Values.Keys) {
        if (-not $seen.Contains([string]$key)) {
            $lines.Insert($endIndex, ('{0}={1}' -f $key, [string]$Values[$key]))
            $endIndex++
        }
    }

    Set-Content -LiteralPath $Path -Value ([string[]]$lines) -Encoding UTF8
}

function Save-UGSMGameConanExilesAdvancedSettingsFromControls {
    [CmdletBinding()]
    param(
        [object]$Instance,
        [hashtable]$Controls
    )
    if ($null -eq $Controls -or $Controls.Count -eq 0) { return 0 }
    $paths = Get-UGSMGameConanExilesProfilePaths -Instance $Instance
    $values = @{}
    foreach ($key in $Controls.Keys) {
        $control = $Controls[$key]
        if ($null -eq $control) { continue }
        $values[[string]$key] = [string]$control.Text
    }
    Save-UGSMGameConanExilesIniSectionEntries -Path $paths.ServerSettings -Section 'ServerSettings' -Values $values
    return $values.Count
}

function Get-UGSMGameConanExilesSettings {
    [CmdletBinding()]
    param([object]$Instance)
    $paths = Get-UGSMGameConanExilesProfilePaths -Instance $Instance
    $name = [string](Get-UGSMGameConanExilesObjectValue $Instance @('Name','Id','InstanceId') 'ConanServer')
    $settings = [ordered]@{
        ServerName        = $name
        ServerPassword    = ''
        AdminPassword     = 'changeme'
        MaxPlayers        = 40
        GamePort          = Get-UGSMGameConanExilesAssignedPort -Instance $Instance -Name 'GamePort' -Default 7777
        QueryPort         = Get-UGSMGameConanExilesAssignedPort -Instance $Instance -Name 'QueryPort' -Default 27015
        RconPort          = Get-UGSMGameConanExilesAssignedPort -Instance $Instance -Name 'RconPort' -Default 25575
        MultiHome         = '0.0.0.0'
        ActiveMods        = ''
        UseVAC            = $true
        NoBattlEye        = $false
    }

    # UGSM JSON is retained as a small app/editor model, but the actual server values are read from the real Conan INI files when present.
    if (Test-Path -LiteralPath $paths.SettingsJson -PathType Leaf) {
        try {
            $saved = Get-Content -LiteralPath $paths.SettingsJson -Raw | ConvertFrom-Json
            foreach ($prop in $saved.PSObject.Properties) { if ($settings.Contains($prop.Name)) { $settings[$prop.Name] = $prop.Value } }
        } catch { Write-UGSMGameConanExilesLog -Level WARN -Message 'Failed to read Conan settings JSON; defaults will be used.' -Exception $_.Exception }
    }

    if (Test-Path -LiteralPath $paths.ServerSettings -PathType Leaf) {
        $iniServerName = Get-UGSMGameConanExilesIniValue -Path $paths.ServerSettings -Section 'ServerSettings' -Key 'ServerName' -Default ''
        if (-not [string]::IsNullOrWhiteSpace($iniServerName)) { $settings.ServerName = $iniServerName }

        $iniServerPassword = Get-UGSMGameConanExilesIniValue -Path $paths.ServerSettings -Section 'ServerSettings' -Key 'ServerPassword' -Default $null
        if ($null -ne $iniServerPassword) { $settings.ServerPassword = $iniServerPassword }

        $iniAdminPassword = Get-UGSMGameConanExilesIniValue -Path $paths.ServerSettings -Section 'ServerSettings' -Key 'AdminPassword' -Default ''
        if (-not [string]::IsNullOrWhiteSpace($iniAdminPassword)) { $settings.AdminPassword = $iniAdminPassword }

        $iniMaxPlayers = Get-UGSMGameConanExilesIniValue -Path $paths.ServerSettings -Section 'ServerSettings' -Key 'MaxPlayers' -Default ''
        if ($iniMaxPlayers -as [int]) { $settings.MaxPlayers = [int]$iniMaxPlayers }

        $battleEye = Get-UGSMGameConanExilesIniValue -Path $paths.ServerSettings -Section 'ServerSettings' -Key 'IsBattlEyeEnabled' -Default ''
        if (-not [string]::IsNullOrWhiteSpace($battleEye)) {
            $settings.NoBattlEye = -not ($battleEye -match '^(1|true|yes|on|enabled)$')
        }
    }

    if (Test-Path -LiteralPath $paths.EngineIni -PathType Leaf) {
        $engineName = Get-UGSMGameConanExilesIniValue -Path $paths.EngineIni -Section 'OnlineSubsystem' -Key 'ServerName' -Default ''
        if (-not [string]::IsNullOrWhiteSpace($engineName)) { $settings.ServerName = $engineName }
        $enginePassword = Get-UGSMGameConanExilesIniValue -Path $paths.EngineIni -Section 'OnlineSubsystem' -Key 'ServerPassword' -Default $null
        if ($null -ne $enginePassword) { $settings.ServerPassword = $enginePassword }
        $multiHome = Get-UGSMGameConanExilesIniValue -Path $paths.EngineIni -Section 'URL' -Key 'Multihome' -Default ''
        if (-not [string]::IsNullOrWhiteSpace($multiHome)) { $settings.MultiHome = $multiHome }
    }

    # ports.json stays the source of truth for profile ports.
    $settings.GamePort = Get-UGSMGameConanExilesAssignedPort -Instance $Instance -Name 'GamePort' -Default ([int]$settings.GamePort)
    $settings.QueryPort = Get-UGSMGameConanExilesAssignedPort -Instance $Instance -Name 'QueryPort' -Default ([int]$settings.QueryPort)
    $settings.RconPort = Get-UGSMGameConanExilesAssignedPort -Instance $Instance -Name 'RconPort' -Default ([int]$settings.RconPort)
    return [pscustomobject]$settings
}

function Save-UGSMGameConanExilesSettings {
    [CmdletBinding()]
    param([object]$Instance,[Parameter(Mandatory)][object]$Settings)
    $paths = Get-UGSMGameConanExilesProfilePaths -Instance $Instance
    New-UGSMGameConanExilesDirectory -Path (Split-Path -Parent $paths.SettingsJson) | Out-Null
    $Settings | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $paths.SettingsJson -Encoding UTF8
}

function Set-UGSMGameConanExilesIniValue {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Path,[Parameter(Mandatory)][string]$Section,[Parameter(Mandatory)][string]$Key,[string]$Value)
    New-UGSMGameConanExilesDirectory -Path (Split-Path -Parent $Path) | Out-Null
    $lines = New-Object System.Collections.ArrayList
    if (Test-Path -LiteralPath $Path -PathType Leaf) { [void]$lines.AddRange([string[]](Get-Content -LiteralPath $Path)) }
    $sectionHeader = "[$Section]"
    $sectionIndex = -1
    for ($i=0; $i -lt $lines.Count; $i++) { if ([string]$lines[$i] -ieq $sectionHeader) { $sectionIndex = $i; break } }
    if ($sectionIndex -lt 0) { if ($lines.Count -gt 0) { [void]$lines.Add('') }; [void]$lines.Add($sectionHeader); $sectionIndex = $lines.Count - 1 }
    $insertIndex = $lines.Count
    $keyIndex = -1
    for ($i=$sectionIndex+1; $i -lt $lines.Count; $i++) {
        $line = [string]$lines[$i]
        if ($line -match '^\s*\[.+\]\s*$') { $insertIndex = $i; break }
        if ($line -match ('^\s*' + [regex]::Escape($Key) + '\s*=')) { $keyIndex = $i; break }
    }
    $entry = ('{0}={1}' -f $Key, $Value)
    if ($keyIndex -ge 0) { $lines[$keyIndex] = $entry } else { $lines.Insert($insertIndex, $entry) }
    Set-Content -LiteralPath $Path -Value ([string[]]$lines) -Encoding UTF8
}


function Get-UGSMGameConanExilesIniValue {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Section,
        [Parameter(Mandatory)][string]$Key,
        [string]$Default = ''
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $Default }
    try {
        $sectionHeader = '[' + $Section + ']'
        $inSection = $false
        foreach ($rawLine in [string[]](Get-Content -LiteralPath $Path)) {
            $line = [string]$rawLine
            $trim = $line.Trim()
            if ($trim -match '^\[(.+)\]$') {
                $inSection = ($trim -ieq $sectionHeader)
                continue
            }
            if (-not $inSection) { continue }
            if ([string]::IsNullOrWhiteSpace($trim) -or $trim.StartsWith(';') -or $trim.StartsWith('#')) { continue }
            $eq = $line.IndexOf('=')
            if ($eq -lt 1) { continue }
            $foundKey = $line.Substring(0,$eq).Trim()
            if ($foundKey -ieq $Key) {
                if ($eq -ge ($line.Length - 1)) { return '' }
                return [string]($line.Substring($eq + 1).Trim())
            }
        }
    } catch {
        Write-UGSMGameConanExilesLog -Level WARN -Message ("Failed to read Conan INI value. Path={0}; Section={1}; Key={2}" -f $Path,$Section,$Key) -Exception $_.Exception
    }
    return $Default
}

function ConvertTo-UGSMGameConanExilesBoolText {
    [CmdletBinding()]
    param([object]$Value,[bool]$Default = $false)
    if ($null -eq $Value) { return $(if ($Default) { 'True' } else { 'False' }) }
    $text = ([string]$Value).Trim()
    if ([string]::IsNullOrWhiteSpace($text)) { return $(if ($Default) { 'True' } else { 'False' }) }
    if ($text -match '^(1|true|yes|on|enabled)$') { return 'True' }
    if ($text -match '^(0|false|no|off|disabled)$') { return 'False' }
    return $(if ($Default) { 'True' } else { 'False' })
}

function Update-UGSMGameConanExilesConfigFiles {
    [CmdletBinding()]
    param([object]$Instance,[object]$Settings)
    $paths = Get-UGSMGameConanExilesProfilePaths -Instance $Instance
    New-UGSMGameConanExilesDirectory -Path $paths.ConfigRoot | Out-Null
    Ensure-UGSMGameConanExilesServerSettingsTemplate -Instance $Instance -Paths $paths | Out-Null

    $gamePort = [int]$Settings.GamePort
    $queryPort = [int]$Settings.QueryPort
    $rconPort = [int]$Settings.RconPort
    $battleEyeEnabled = ConvertTo-UGSMGameConanExilesBoolText -Value (-not [bool]$Settings.NoBattlEye) -Default $true

    # Engine.ini carries launch/network values used by Unreal/Conan.
    Set-UGSMGameConanExilesIniValue -Path $paths.EngineIni -Section 'OnlineSubsystem' -Key 'ServerName' -Value ([string]$Settings.ServerName)
    Set-UGSMGameConanExilesIniValue -Path $paths.EngineIni -Section 'OnlineSubsystem' -Key 'ServerPassword' -Value ([string]$Settings.ServerPassword)
    Set-UGSMGameConanExilesIniValue -Path $paths.EngineIni -Section 'URL' -Key 'Port' -Value ([string]$gamePort)
    Set-UGSMGameConanExilesIniValue -Path $paths.EngineIni -Section 'OnlineSubsystemNull' -Key 'GameServerQueryPort' -Value ([string]$queryPort)
    if (-not [string]::IsNullOrWhiteSpace([string]$Settings.MultiHome) -and [string]$Settings.MultiHome -ne '0.0.0.0') {
        Set-UGSMGameConanExilesIniValue -Path $paths.EngineIni -Section 'URL' -Key 'Multihome' -Value ([string]$Settings.MultiHome)
    }
    Set-UGSMGameConanExilesIniValue -Path $paths.EngineIni -Section '/Script/ConanSandbox.SystemSettings' -Key 'ModFileDownload.DownloadPortOffset' -Value '2'

    # ServerSettings.ini is the real Conan server settings file. Keep common UGSM fields mirrored here too.
    Set-UGSMGameConanExilesIniValue -Path $paths.ServerSettings -Section 'ServerSettings' -Key 'ServerName' -Value ([string]$Settings.ServerName)
    Set-UGSMGameConanExilesIniValue -Path $paths.ServerSettings -Section 'ServerSettings' -Key 'ServerPassword' -Value ([string]$Settings.ServerPassword)
    Set-UGSMGameConanExilesIniValue -Path $paths.ServerSettings -Section 'ServerSettings' -Key 'AdminPassword' -Value ([string]$Settings.AdminPassword)
    Set-UGSMGameConanExilesIniValue -Path $paths.ServerSettings -Section 'ServerSettings' -Key 'MaxPlayers' -Value ([string]$Settings.MaxPlayers)
    Set-UGSMGameConanExilesIniValue -Path $paths.ServerSettings -Section 'ServerSettings' -Key 'IsBattlEyeEnabled' -Value $battleEyeEnabled

    Write-UGSMGameConanExilesLog -Level DEBUG -Message ("Conan config files updated. ServerSettings={0}; EngineIni={1}; GamePort={2}; QueryPort={3}; RconPort={4}" -f $paths.ServerSettings,$paths.EngineIni,$gamePort,$queryPort,$rconPort)
}

function Initialize-UGSMGameConanExilesRuntimeLayout {
    [CmdletBinding()]
    param([object]$Instance,[object]$InstallDefinition)
    $paths = Get-UGSMGameConanExilesProfilePaths -Instance $Instance
    New-UGSMGameConanExilesDirectory -Path $paths.ProfileRoot | Out-Null
    New-UGSMGameConanExilesDirectory -Path $paths.ConfigRoot | Out-Null
    New-UGSMGameConanExilesDirectory -Path $paths.SaveRoot | Out-Null
    New-UGSMGameConanExilesDirectory -Path $paths.LogRoot | Out-Null
    New-UGSMGameConanExilesDirectory -Path $paths.ModsRoot | Out-Null

    $sharedSandbox = Join-Path $InstallDefinition.InstallPath 'ConanSandbox'
    foreach ($child in @('Binaries','Content','Plugins')) {
        $target = Join-Path $sharedSandbox $child
        $link = Join-Path $paths.SandboxRoot $child
        [void](New-UGSMGameConanExilesJunction -Target $target -Link $link)
    }
    foreach ($child in @('Engine')) {
        $target = Join-Path $InstallDefinition.InstallPath $child
        $link = Join-Path $paths.RuntimeRoot $child
        [void](New-UGSMGameConanExilesJunction -Target $target -Link $link)
    }

    Ensure-UGSMGameConanExilesServerSettingsTemplate -Instance $Instance -InstallDefinition $InstallDefinition -Paths $paths | Out-Null
    $settings = Get-UGSMGameConanExilesSettings -Instance $Instance
    Save-UGSMGameConanExilesSettings -Instance $Instance -Settings $settings
    Update-UGSMGameConanExilesConfigFiles -Instance $Instance -Settings $settings

    return [pscustomobject]@{
        Paths      = $paths
        RuntimeExe = Join-Path $paths.RuntimeRoot 'ConanSandbox\Binaries\Win64\ConanSandboxServer-Win64-Shipping.exe'
    }
}

function Initialize-UGSMGameConanExilesProfile {
    [CmdletBinding()]
    param([Parameter(Mandatory)][object]$Instance,[string]$InstallPath,[int]$BootstrapSeconds = 0,[switch]$Force)
    $id = [string](Get-UGSMGameConanExilesObjectValue $Instance @('Id','InstanceId','Name') '')
    Write-UGSMGameConanExilesLog -Level INFO -Message ("Profile initialization requested. InstanceId={0}" -f $id)
    $install = Get-UGSMGameConanExilesInstallDefinition -InstallPath $InstallPath -Instance $Instance
    $runtime = Initialize-UGSMGameConanExilesRuntimeLayout -Instance $Instance -InstallDefinition $install
    $paths = $runtime.Paths
    Set-UGSMGameConanExilesObjectValue -InputObject $Instance -Name 'ProfilePath' -Value $paths.ProfileRoot
    Set-UGSMGameConanExilesObjectValue -InputObject $Instance -Name 'InstallPath' -Value $install.InstallPath
    Write-UGSMGameConanExilesLog -Level INFO -Message ("Profile initialized. InstanceId={0}; ProfilePath={1}" -f $id,$paths.ProfileRoot)
    return [pscustomobject]@{ Success = $true; Instance = $Instance; ProfilePath = $paths.ProfileRoot }
}

function Ensure-UGSMGameConanExilesTemplate {
    [CmdletBinding()]
    param([object]$Instance,[string]$InstallPath,[int]$BootstrapSeconds = 0,[switch]$Force,[switch]$ForceRefresh)
    if ($Instance) { return Initialize-UGSMGameConanExilesProfile -Instance $Instance -InstallPath $InstallPath -BootstrapSeconds $BootstrapSeconds -Force:$Force }
    return [pscustomobject]@{ Success = $true }
}

function Test-UGSMGameConanExilesInstance {
    [CmdletBinding()]
    param([Parameter(Mandatory)][object]$Instance)
    $paths = Get-UGSMGameConanExilesProfilePaths -Instance $Instance
    return [pscustomobject]@{ Success = (Test-Path -LiteralPath $paths.ConfigRoot -PathType Container); ProfilePath = $paths.ProfileRoot }
}

function ConvertTo-UGSMGameConanExilesModIds {
    [CmdletBinding()]
    param([string]$Text)
    $ids = New-Object System.Collections.Generic.List[string]
    if ([string]::IsNullOrWhiteSpace($Text)) { return @() }
    foreach ($part in ($Text -split '[,;\r\n\t ]+')) {
        $p = [string]$part
        if ([string]::IsNullOrWhiteSpace($p)) { continue }
        $matches = [regex]::Matches($p, '(?i)(?:id=)?(\d{5,})')
        foreach ($m in $matches) {
            $id = [string]$m.Groups[1].Value
            if (-not $ids.Contains($id)) { $ids.Add($id) }
        }
    }
    return [string[]]$ids.ToArray()
}

function Get-UGSMGameConanExilesManagedMods {
    [CmdletBinding()]
    param([object]$Instance)
    $paths = Get-UGSMGameConanExilesProfilePaths -Instance $Instance
    if (-not (Test-Path -LiteralPath $paths.ManagedMods -PathType Leaf)) { return @() }
    try { return @((Get-Content -LiteralPath $paths.ManagedMods -Raw | ConvertFrom-Json)) } catch { return @() }
}

function Save-UGSMGameConanExilesManagedMods {
    [CmdletBinding()]
    param([object]$Instance,[AllowEmptyCollection()][object[]]$Mods)
    $paths = Get-UGSMGameConanExilesProfilePaths -Instance $Instance
    New-UGSMGameConanExilesDirectory -Path (Split-Path -Parent $paths.ManagedMods) | Out-Null
    @($Mods) | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $paths.ManagedMods -Encoding UTF8
}

function Get-UGSMGameConanExilesSteamWorkshopRoot {
    [CmdletBinding()]
    param([object]$InstallDefinition)
    $root = Split-Path -Parent (Split-Path -Parent $InstallDefinition.InstallPath)
    return (Join-Path $root 'workshop\content\440900')
}

function Invoke-UGSMGameConanExilesWorkshopDownload {
    [CmdletBinding()]
    param([Parameter(Mandatory)][object]$InstallDefinition,[Parameter(Mandatory)][string]$WorkshopId)
    if (Get-Command -Name Invoke-UGSMSteamCMDCommand -ErrorAction SilentlyContinue) {
        return Invoke-UGSMSteamCMDCommand -Arguments @('+login','anonymous','+workshop_download_item','440900',$WorkshopId,'validate','+quit') -ShowWindow -TimeoutSeconds 7200
    }
    if (Get-Command -Name Install-UGSMSteamWorkshopItem -ErrorAction SilentlyContinue) {
        return Install-UGSMSteamWorkshopItem -AppId '440900' -WorkshopItemId $WorkshopId -Anonymous -ShowWindow
    }
    throw 'No SteamCMD command helper was available for Conan Exiles workshop download.'
}

function Sync-UGSMGameConanExilesMods {
    [CmdletBinding()]
    param([Parameter(Mandatory)][object]$Instance,[string[]]$ModIds,[switch]$Download)
    $id = [string](Get-UGSMGameConanExilesObjectValue $Instance @('Id','InstanceId','Name') '')
    $install = Get-UGSMGameConanExilesInstallDefinition -Instance $Instance
    $paths = Get-UGSMGameConanExilesProfilePaths -Instance $Instance
    New-UGSMGameConanExilesDirectory -Path $paths.ModsRoot | Out-Null
    $workshopRoot = Get-UGSMGameConanExilesSteamWorkshopRoot -InstallDefinition $install
    $managed = New-Object System.Collections.Generic.List[object]
    $modListLines = New-Object System.Collections.Generic.List[string]

    foreach ($modId in @($ModIds)) {
        if ([string]::IsNullOrWhiteSpace($modId)) { continue }
        if ($Download) {
            Write-UGSMGameConanExilesLog -Level INFO -Message ("Conan workshop download requested. InstanceId={0}; WorkshopId={1}" -f $id,$modId)
            [void](Invoke-UGSMGameConanExilesWorkshopDownload -InstallDefinition $install -WorkshopId $modId)
        }
        $itemRoot = Join-Path $workshopRoot $modId
        $pak = $null
        if (Test-Path -LiteralPath $itemRoot -PathType Container) {
            $pak = Get-ChildItem -LiteralPath $itemRoot -Filter '*.pak' -File -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
        }
        if (-not $pak) {
            Write-UGSMGameConanExilesLog -Level WARN -Message ("Conan mod pak not found after sync. InstanceId={0}; WorkshopId={1}; Folder={2}" -f $id,$modId,$itemRoot)
            continue
        }
        $destName = ('{0}_{1}' -f $modId,$pak.Name)
        $dest = Join-Path $paths.ModsRoot $destName
        if (Test-Path -LiteralPath $dest -PathType Leaf) { Remove-Item -LiteralPath $dest -Force -ErrorAction SilentlyContinue }
        try { New-Item -ItemType HardLink -Path $dest -Target $pak.FullName -ErrorAction Stop | Out-Null }
        catch { Copy-Item -LiteralPath $pak.FullName -Destination $dest -Force }
        $modListLines.Add(('*{0}' -f $destName)) | Out-Null
        $managed.Add([pscustomobject]@{ WorkshopId = $modId; PakFile = $destName; SourcePak = $pak.FullName; InstalledUtc = [DateTime]::UtcNow.ToString('o') }) | Out-Null
    }

    $modList = Join-Path $paths.ModsRoot 'modlist.txt'
    Set-Content -LiteralPath $modList -Value ([string[]]$modListLines.ToArray()) -Encoding ASCII
    Save-UGSMGameConanExilesManagedMods -Instance $Instance -Mods ([object[]]$managed.ToArray())
    Write-UGSMGameConanExilesLog -Level INFO -Message ("Conan mod sync completed. InstanceId={0}; Requested={1}; Installed={2}" -f $id,(@($ModIds).Count),$managed.Count)
    return [pscustomobject]@{ Success = $true; InstalledCount = $managed.Count; ModListPath = $modList }
}

function Start-UGSMGameConanExilesInstance {
    [CmdletBinding()]
    param([Parameter(Mandatory)][object]$Instance)
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    $id = [string](Get-UGSMGameConanExilesObjectValue $Instance @('Id','InstanceId','Name') '')
    Write-UGSMGameConanExilesLog -Level INFO -Message ("Start requested. InstanceId={0}" -f $id)
    $install = Get-UGSMGameConanExilesInstallDefinition -Instance $Instance
    $runtime = Initialize-UGSMGameConanExilesRuntimeLayout -Instance $Instance -InstallDefinition $install
    $paths = $runtime.Paths
    $settings = Get-UGSMGameConanExilesSettings -Instance $Instance
    $modIds = ConvertTo-UGSMGameConanExilesModIds -Text ([string]$settings.ActiveMods)
    if (@($modIds).Count -gt 0) { [void](Sync-UGSMGameConanExilesMods -Instance $Instance -ModIds $modIds -Download:$false) }

    $exe = $runtime.RuntimeExe
    if (-not (Test-Path -LiteralPath $exe -PathType Leaf)) { $exe = $install.ServerExecutablePath }
    if (-not (Test-Path -LiteralPath $exe -PathType Leaf)) { throw "Conan server executable was not found: $exe" }

    $args = @('-log',("-Port={0}" -f [int]$settings.GamePort),("-QueryPort={0}" -f [int]$settings.QueryPort))
    if (-not [string]::IsNullOrWhiteSpace([string]$settings.MultiHome) -and [string]$settings.MultiHome -ne '0.0.0.0') { $args += ("-MULTIHOME={0}" -f [string]$settings.MultiHome) }
    if ($settings.NoBattlEye) { $args += '-NoBattlEye' }

    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $exe
    $psi.WorkingDirectory = $paths.RuntimeRoot
    $psi.UseShellExecute = $true
    $psi.Arguments = ($args -join ' ')

    Write-UGSMGameConanExilesLog -Level INFO -Message ("Launching process. InstanceId={0}; Exe={1}; Args={2}" -f $id,$exe,$psi.Arguments)
    $proc = [System.Diagnostics.Process]::Start($psi)
    Start-Sleep -Seconds 3
    if ($proc.HasExited) { throw ("Conan server process exited immediately. ExitCode={0}" -f $proc.ExitCode) }
    Set-UGSMGameConanExilesObjectValue -InputObject $Instance -Name 'Pid' -Value ([int]$proc.Id)
    Set-UGSMGameConanExilesObjectValue -InputObject $Instance -Name 'Status' -Value 'Running'
    $sw.Stop()
    Write-UGSMGameConanExilesLog -Level INFO -Message ("Start completed. InstanceId={0}; Pid={1}; DurationMs={2}" -f $id,$proc.Id,$sw.ElapsedMilliseconds)
    return [pscustomobject]@{ Instance = $Instance; Status = 'Running'; Pid = [int]$proc.Id }
}

function Stop-UGSMGameConanExilesInstance {
    [CmdletBinding()]
    param([Parameter(Mandatory)][object]$Instance)
    $id = [string](Get-UGSMGameConanExilesObjectValue $Instance @('Id','InstanceId','Name') '')
    $pidValue = Get-UGSMGameConanExilesObjectValue $Instance @('Pid') $null
    Write-UGSMGameConanExilesLog -Level INFO -Message ("Stop requested. InstanceId={0}; Pid={1}" -f $id,$pidValue)
    $stopped = $true
    if ($pidValue -as [int]) {
        $procId = [int]$pidValue
        if (Get-Command -Name Stop-UGSMProcessTree -ErrorAction SilentlyContinue) {
            $result = Stop-UGSMProcessTree -ProcessId $procId -TimeoutSeconds 25
            $stopped = [bool]$result.Stopped
        } else {
            try { Stop-Process -Id $procId -Force -ErrorAction Stop; Start-Sleep -Seconds 2 } catch {}
            try { $p = Get-Process -Id $procId -ErrorAction Stop; $stopped = $p.HasExited } catch { $stopped = $true }
        }
    }
    Set-UGSMGameConanExilesObjectValue -InputObject $Instance -Name 'Pid' -Value $null
    Set-UGSMGameConanExilesObjectValue -InputObject $Instance -Name 'Status' -Value 'Stopped'
    Write-UGSMGameConanExilesLog -Level INFO -Message ("Stop completed. InstanceId={0}; Stopped={1}" -f $id,$stopped)
    return [pscustomobject]@{ Instance = $Instance; Status = 'Stopped'; Stopped = $stopped }
}



function Get-UGSMGameConanExilesUIColor {
    [CmdletBinding()]
    param(
        [object[]]$Names,
        [object]$Fallback = '#0B1728'
    )

    $fallbackText = '#0B1728'
    if ($null -ne $Fallback) {
        if ($Fallback -is [System.Drawing.Color]) { return $Fallback }
        $fallbackText = [string]$Fallback
    }
    if ([string]::IsNullOrWhiteSpace($fallbackText)) { $fallbackText = '#0B1728' }

    foreach ($nameObj in @($Names)) {
        if ($null -eq $nameObj) { continue }
        $name = [string]$nameObj
        if ([string]::IsNullOrWhiteSpace($name)) { continue }
        if ($name -like '#*') {
            $fallbackText = $name
            continue
        }
        try {
            $var = Get-Variable -Name $name -Scope Global -ErrorAction SilentlyContinue
            if ($null -eq $var -or $null -eq $var.Value) { continue }
            if ($var.Value -is [System.Drawing.Color]) { return $var.Value }
            $valueText = [string]$var.Value
            if (-not [string]::IsNullOrWhiteSpace($valueText)) {
                return [System.Drawing.ColorTranslator]::FromHtml($valueText)
            }
        } catch { }
    }

    try { return [System.Drawing.ColorTranslator]::FromHtml($fallbackText) } catch { return [System.Drawing.Color]::FromArgb(7,17,32) }
}

function New-UGSMGameConanExilesLabel {
    param([string]$Text,[int]$X,[int]$Y,[int]$W=160,[int]$H=22)
    $l = New-Object System.Windows.Forms.Label
    $l.Text = $Text
    $l.Location = New-Object System.Drawing.Point($X,$Y)
    $l.Size = New-Object System.Drawing.Size($W,$H)
    $l.ForeColor = (Get-UGSMGameConanExilesUIColor -Names @('UGSM_ColorText') -Fallback '#FFFFFF')
    $l.BackColor = [System.Drawing.Color]::Transparent
    return $l
}
function New-UGSMGameConanExilesTextBox {
    param([string]$Text,[int]$X,[int]$Y,[int]$W=280,[bool]$Password=$false)
    $t = New-Object System.Windows.Forms.TextBox
    $t.Text = $Text
    $t.Location = New-Object System.Drawing.Point($X,$Y)
    $t.Size = New-Object System.Drawing.Size($W,24)
    $t.BackColor = (Get-UGSMGameConanExilesUIColor -Names @('UGSM_ColorInputBackground','UGSM_ColorInput','UGSM_ColorSurface') -Fallback '#0A1320')
    $t.ForeColor = (Get-UGSMGameConanExilesUIColor -Names @('UGSM_ColorText') -Fallback '#FFFFFF')
    if ($Password) { $t.UseSystemPasswordChar = $true }
    return $t
}
function New-UGSMGameConanExilesButton {
    param([string]$Text,[int]$X,[int]$Y,[int]$W=130,[int]$H=30)
    $b = New-Object System.Windows.Forms.Button
    $b.Text = $Text
    $b.Location = New-Object System.Drawing.Point($X,$Y)
    $b.Size = New-Object System.Drawing.Size($W,$H)
    $b.FlatStyle = 'Flat'
    $b.BackColor = (Get-UGSMGameConanExilesUIColor -Names @('UGSM_ColorNeutral','UGSM_ColorButton','UGSM_ColorSurface') -Fallback '#334155')
    $b.ForeColor = (Get-UGSMGameConanExilesUIColor -Names @('UGSM_ColorText') -Fallback '#FFFFFF')
    return $b
}
function New-UGSMGameConanExilesCheckBox {
    param([string]$Text,[bool]$Checked,[int]$X,[int]$Y,[int]$W=240)
    $c = New-Object System.Windows.Forms.CheckBox
    $c.Text = $Text
    $c.Checked = [bool]$Checked
    $c.Location = New-Object System.Drawing.Point($X,$Y)
    $c.Size = New-Object System.Drawing.Size($W,24)
    $c.ForeColor = (Get-UGSMGameConanExilesUIColor -Names @('UGSM_ColorText') -Fallback '#FFFFFF')
    $c.BackColor = [System.Drawing.Color]::Transparent
    return $c
}

function New-UGSMGameConanExilesInstanceEditor {
    [CmdletBinding()]
    param([Parameter(Mandatory)][object]$Instance,[object]$AppState,[object]$Theme,[object]$HostPanel,[object]$StatusLabel)
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    $id = [string](Get-UGSMGameConanExilesObjectValue $Instance @('Id','InstanceId','Name') '')
    Write-UGSMGameConanExilesLog -Level INFO -Message ("Editor creation started. InstanceId={0}" -f $id)
    $settings = Get-UGSMGameConanExilesSettings -Instance $Instance

    $editorHost = $HostPanel
    $createdOwnHost = $false
    if (-not $editorHost) {
        $editorHost = New-Object System.Windows.Forms.Panel
        $editorHost.Dock = 'Fill'
        $createdOwnHost = $true
    }

    $editorHost.SuspendLayout()
    $editorHost.Controls.Clear()
    $editorHost.AutoScroll = $true
    $editorHost.BackColor = (Get-UGSMGameConanExilesUIColor -Names @('UGSM_ColorBackground','UGSM_ColorPageBackground','UGSM_ColorCanvas') -Fallback '#071120')

    $tabs = New-Object System.Windows.Forms.TabControl
    $tabs.Dock = 'Fill'
    $tabs.BackColor = (Get-UGSMGameConanExilesUIColor -Names @('UGSM_ColorBackground','UGSM_ColorPageBackground','UGSM_ColorCanvas') -Fallback '#071120')
    $editorHost.Controls.Add($tabs)

    $serverTab = New-Object System.Windows.Forms.TabPage; $serverTab.Text='Server'; $serverTab.BackColor=(Get-UGSMGameConanExilesUIColor -Names @('UGSM_ColorBackground','UGSM_ColorPageBackground','UGSM_ColorCanvas') -Fallback '#071120'); $tabs.TabPages.Add($serverTab) | Out-Null
    $networkTab = New-Object System.Windows.Forms.TabPage; $networkTab.Text='Network'; $networkTab.BackColor=(Get-UGSMGameConanExilesUIColor -Names @('UGSM_ColorBackground','UGSM_ColorPageBackground','UGSM_ColorCanvas') -Fallback '#071120'); $tabs.TabPages.Add($networkTab) | Out-Null
    $settingsTab = New-Object System.Windows.Forms.TabPage; $settingsTab.Text='ServerSettings.ini'; $settingsTab.BackColor=(Get-UGSMGameConanExilesUIColor -Names @('UGSM_ColorBackground','UGSM_ColorPageBackground','UGSM_ColorCanvas') -Fallback '#071120'); $tabs.TabPages.Add($settingsTab) | Out-Null
    $modsTab = New-Object System.Windows.Forms.TabPage; $modsTab.Text='Mods'; $modsTab.BackColor=(Get-UGSMGameConanExilesUIColor -Names @('UGSM_ColorBackground','UGSM_ColorPageBackground','UGSM_ColorCanvas') -Fallback '#071120'); $tabs.TabPages.Add($modsTab) | Out-Null
    $discordTab = New-Object System.Windows.Forms.TabPage; $discordTab.Text='Discord'; $discordTab.BackColor=(Get-UGSMGameConanExilesUIColor -Names @('UGSM_ColorBackground','UGSM_ColorPageBackground','UGSM_ColorCanvas') -Fallback '#071120'); $tabs.TabPages.Add($discordTab) | Out-Null

    $txtName = New-UGSMGameConanExilesTextBox -Text ([string]$settings.ServerName) -X 190 -Y 24 -W 320
    $txtPass = New-UGSMGameConanExilesTextBox -Text ([string]$settings.ServerPassword) -X 190 -Y 60 -W 320 -Password $true
    $txtAdmin = New-UGSMGameConanExilesTextBox -Text ([string]$settings.AdminPassword) -X 190 -Y 96 -W 320 -Password $true
    $txtMax = New-UGSMGameConanExilesTextBox -Text ([string]$settings.MaxPlayers) -X 190 -Y 132 -W 100
    $serverTab.Controls.Add((New-UGSMGameConanExilesLabel 'Server Name' 24 27)); $serverTab.Controls.Add($txtName)
    $serverTab.Controls.Add((New-UGSMGameConanExilesLabel 'Server Password' 24 63)); $serverTab.Controls.Add($txtPass)
    $serverTab.Controls.Add((New-UGSMGameConanExilesLabel 'Admin Password' 24 99)); $serverTab.Controls.Add($txtAdmin)
    $serverTab.Controls.Add((New-UGSMGameConanExilesLabel 'Max Players' 24 135)); $serverTab.Controls.Add($txtMax)

    $txtGamePort = New-UGSMGameConanExilesTextBox -Text ([string]$settings.GamePort) -X 190 -Y 24 -W 100
    $txtQueryPort = New-UGSMGameConanExilesTextBox -Text ([string]$settings.QueryPort) -X 190 -Y 60 -W 100
    $txtRconPort = New-UGSMGameConanExilesTextBox -Text ([string]$settings.RconPort) -X 190 -Y 96 -W 100
    $txtMulti = New-UGSMGameConanExilesTextBox -Text ([string]$settings.MultiHome) -X 190 -Y 132 -W 160
    $chkNoBattlEye = New-UGSMGameConanExilesCheckBox -Text 'Disable BattlEye' -Checked ([bool]$settings.NoBattlEye) -X 190 -Y 168
    $networkTab.Controls.Add((New-UGSMGameConanExilesLabel 'Game Port' 24 27)); $networkTab.Controls.Add($txtGamePort)
    $networkTab.Controls.Add((New-UGSMGameConanExilesLabel 'Query Port' 24 63)); $networkTab.Controls.Add($txtQueryPort)
    $networkTab.Controls.Add((New-UGSMGameConanExilesLabel 'RCON Port' 24 99)); $networkTab.Controls.Add($txtRconPort)
    $networkTab.Controls.Add((New-UGSMGameConanExilesLabel 'Bind IP / MultiHome' 24 135)); $networkTab.Controls.Add($txtMulti); $networkTab.Controls.Add($chkNoBattlEye)

    $advancedControlMap = @{}
    $advancedPanel = New-Object System.Windows.Forms.Panel
    $advancedPanel.Dock = 'Fill'
    $advancedPanel.AutoScroll = $true
    $advancedPanel.BackColor = (Get-UGSMGameConanExilesUIColor -Names @('UGSM_ColorBackground','UGSM_ColorPageBackground','UGSM_ColorCanvas') -Fallback '#071120')
    $settingsTab.Controls.Add($advancedPanel)
    $pathsForAdvanced = Get-UGSMGameConanExilesProfilePaths -Instance $Instance
    $advancedEntries = @(Get-UGSMGameConanExilesIniSectionEntries -Path $pathsForAdvanced.ServerSettings -Section 'ServerSettings')
    $advY = 18
    foreach ($entry in $advancedEntries) {
        $keyText = [string]$entry.Key
        if ([string]::IsNullOrWhiteSpace($keyText)) { continue }
        $lbl = New-UGSMGameConanExilesLabel -Text $keyText -X 24 -Y ($advY + 3) -W 260 -H 22
        $txt = New-UGSMGameConanExilesTextBox -Text ([string]$entry.Value) -X 300 -Y $advY -W 520
        $advancedPanel.Controls.Add($lbl)
        $advancedPanel.Controls.Add($txt)
        $advancedControlMap[$keyText] = $txt
        $advY += 34
    }
    $lblAdvancedInfo = New-UGSMGameConanExilesLabel -Text 'All values from [ServerSettings] are editable here. Ports and common settings are also shown on the simpler tabs.' -X 24 -Y ($advY + 8) -W 780 -H 22
    $advancedPanel.Controls.Add($lblAdvancedInfo)
    $btnSaveAdvanced = New-UGSMGameConanExilesButton -Text 'Save ServerSettings.ini' -X 24 -Y ($advY + 40) -W 190
    $lblAdvancedStatus = New-UGSMGameConanExilesLabel -Text '' -X 230 -Y ($advY + 46) -W 600 -H 22
    $advancedPanel.Controls.Add($btnSaveAdvanced)
    $advancedPanel.Controls.Add($lblAdvancedStatus)

    $txtMods = New-UGSMGameConanExilesTextBox -Text ([string]$settings.ActiveMods) -X 24 -Y 42 -W 620
    $modsTab.Controls.Add((New-UGSMGameConanExilesLabel 'Active Workshop IDs / URLs' 24 18 260)); $modsTab.Controls.Add($txtMods)
    $btnDownloadMods = New-UGSMGameConanExilesButton -Text 'Download Active Mods' -X 24 -Y 78 -W 180
    $modsTab.Controls.Add($btnDownloadMods)
    $lblModsStatus = New-UGSMGameConanExilesLabel '' 220 84 520 24
    $modsTab.Controls.Add($lblModsStatus)
    $lstMods = New-Object System.Windows.Forms.ListBox; $lstMods.Location=New-Object System.Drawing.Point(24,120); $lstMods.Size=New-Object System.Drawing.Size(620,220); $lstMods.BackColor=(Get-UGSMGameConanExilesUIColor -Names @('UGSM_ColorInputBackground','UGSM_ColorInput','UGSM_ColorSurface') -Fallback '#0A1320'); $lstMods.ForeColor=(Get-UGSMGameConanExilesUIColor -Names @('UGSM_ColorText') -Fallback '#FFFFFF'); $modsTab.Controls.Add($lstMods)

    $refreshModsList = {
        $lstMods.Items.Clear()
        foreach ($m in @(Get-UGSMGameConanExilesManagedMods -Instance $Instance)) {
            $name = [string](Get-UGSMGameConanExilesObjectValue $m @('WorkshopId','PakFile') '')
            if (-not [string]::IsNullOrWhiteSpace($name)) { [void]$lstMods.Items.Add($name) }
        }
    }
    $null = $refreshModsList.Invoke()

    $webhook = [string](Get-UGSMGameConanExilesObjectValue $Instance @('DiscordWebhookUrl','WebhookUrl') '')
    $chkStart = New-UGSMGameConanExilesCheckBox -Text 'Notify on Start' -Checked ([bool](Get-UGSMGameConanExilesObjectValue $Instance @('NotifyOnStart') $false)) -X 24 -Y 24
    $chkStop = New-UGSMGameConanExilesCheckBox -Text 'Notify on Stop' -Checked ([bool](Get-UGSMGameConanExilesObjectValue $Instance @('NotifyOnStop') $false)) -X 24 -Y 54
    $chkDash = New-UGSMGameConanExilesCheckBox -Text 'Show in Discord Dashboard' -Checked ([bool](Get-UGSMGameConanExilesObjectValue $Instance @('ShowInDashboard') $false)) -X 24 -Y 84 -W 260
    $txtWebhook = New-UGSMGameConanExilesTextBox -Text $webhook -X 24 -Y 140 -W 620
    $btnSaveDiscord = New-UGSMGameConanExilesButton -Text 'Save Discord' -X 24 -Y 176 -W 140
    $btnTestDiscord = New-UGSMGameConanExilesButton -Text 'Test Discord' -X 180 -Y 176 -W 140
    $lblDiscord = New-UGSMGameConanExilesLabel 'Blank webhook uses the global webhook from Settings.' 24 116 600 22
    $lblDiscordStatus = New-UGSMGameConanExilesLabel '' 340 182 600 22
    foreach ($c in @($chkStart,$chkStop,$chkDash,$lblDiscord,$txtWebhook,$btnSaveDiscord,$btnTestDiscord,$lblDiscordStatus)) { $discordTab.Controls.Add($c) }

    $state = [pscustomobject]@{ Instance=$Instance; Settings=$settings; Name=$txtName; Password=$txtPass; Admin=$txtAdmin; Max=$txtMax; GamePort=$txtGamePort; QueryPort=$txtQueryPort; RconPort=$txtRconPort; Multi=$txtMulti; NoBattlEye=$chkNoBattlEye; ActiveMods=$txtMods; ModsStatus=$lblModsStatus; RefreshMods=$refreshModsList; DiscordWebhook=$txtWebhook; NotifyStart=$chkStart; NotifyStop=$chkStop; Dashboard=$chkDash; DiscordStatus=$lblDiscordStatus; AdvancedControls=$advancedControlMap; AdvancedStatus=$lblAdvancedStatus }

    $btnSaveAdvanced.Tag = $state
    $btnSaveAdvanced.Add_Click({
        param($sender,$eventArgs)
        $s = $sender.Tag
        try {
            $count = Save-UGSMGameConanExilesAdvancedSettingsFromControls -Instance $s.Instance -Controls $s.AdvancedControls
            if ($s.AdvancedStatus) { $s.AdvancedStatus.Text = ('Saved ServerSettings.ini values: {0}' -f $count) }
            Write-UGSMGameConanExilesLog -Level INFO -Message ("Advanced ServerSettings.ini saved from editor. InstanceId={0}; Count={1}" -f (Get-UGSMGameConanExilesObjectValue $s.Instance @('Id','InstanceId','Name') ''), $count)
        } catch {
            if ($s -and $s.AdvancedStatus) { $s.AdvancedStatus.Text = ('Save failed: {0}' -f $_.Exception.Message) }
            Write-UGSMGameConanExilesLog -Level ERROR -Message 'Advanced ServerSettings.ini save failed from editor.' -Exception $_.Exception
        }
    })

    $btnSave = New-UGSMGameConanExilesButton -Text 'Save Settings' -X 24 -Y 180 -W 140
    $serverTab.Controls.Add($btnSave)
    $btnSave.Tag = $state
    $btnSave.Add_Click({
        param($sender,$eventArgs)
        $s = $sender.Tag
        try {
            $obj = [pscustomobject]@{
                ServerName = [string]$s.Name.Text; ServerPassword = [string]$s.Password.Text; AdminPassword = [string]$s.Admin.Text; MaxPlayers = [int]$s.Max.Text
                GamePort = [int]$s.GamePort.Text; QueryPort = [int]$s.QueryPort.Text; RconPort = [int]$s.RconPort.Text; MultiHome = [string]$s.Multi.Text; NoBattlEye = [bool]$s.NoBattlEye.Checked; ActiveMods = [string]$s.ActiveMods.Text; UseVAC = $true
            }
            Save-UGSMGameConanExilesSettings -Instance $s.Instance -Settings $obj
            # Save the advanced ServerSettings.ini controls first, then write common UGSM fields after so Server/Network tab values win.
            $advancedCount = Save-UGSMGameConanExilesAdvancedSettingsFromControls -Instance $s.Instance -Controls $s.AdvancedControls
            Update-UGSMGameConanExilesConfigFiles -Instance $s.Instance -Settings $obj
            if ($s.AdvancedStatus) { $s.AdvancedStatus.Text = ('Saved ServerSettings.ini values: {0}' -f $advancedCount) }
            Write-UGSMGameConanExilesLog -Level INFO -Message ("Editor settings saved. InstanceId={0}; AdvancedSettings={1}" -f (Get-UGSMGameConanExilesObjectValue $s.Instance @('Id','InstanceId','Name') ''), $advancedCount)
            # Popup suppressed; save result is logged.
        } catch { Write-UGSMGameConanExilesLog -Level ERROR -Message 'Editor save failed.' -Exception $_.Exception }
    })

    $btnDownloadMods.Tag = $state
    $btnDownloadMods.Add_Click({
        param($sender,$eventArgs)
        $s = $sender.Tag
        try {
            $ids = ConvertTo-UGSMGameConanExilesModIds -Text ([string]$s.ActiveMods.Text)
            if (@($ids).Count -eq 0) { $s.ModsStatus.Text = 'No mod IDs found.'; return }
            $s.ModsStatus.Text = 'Downloading mods...'
            [void](Sync-UGSMGameConanExilesMods -Instance $s.Instance -ModIds $ids -Download)
            $s.RefreshMods.Invoke() | Out-Null
            $s.ModsStatus.Text = ('Mods synced: {0}' -f @($ids).Count)
        } catch { Write-UGSMGameConanExilesLog -Level ERROR -Message 'Mod sync from editor failed.' -Exception $_.Exception; $s.ModsStatus.Text = $_.Exception.Message }
    })

    $btnSaveDiscord.Tag = $state
    $btnSaveDiscord.Add_Click({
        param($sender,$eventArgs)
        $s = $sender.Tag
        try {
            if (Get-Command -Name Save-UGSMDiscordInstanceSettings -ErrorAction SilentlyContinue) {
                Save-UGSMDiscordInstanceSettings -Instance $s.Instance -WebhookUrl ([string]$s.DiscordWebhook.Text) -NotifyOnStart:([bool]$s.NotifyStart.Checked) -NotifyOnStop:([bool]$s.NotifyStop.Checked) -ShowInDashboard:([bool]$s.Dashboard.Checked) | Out-Null
            } else {
                Set-UGSMGameConanExilesObjectValue -InputObject $s.Instance -Name 'DiscordWebhookUrl' -Value ([string]$s.DiscordWebhook.Text)
                Set-UGSMGameConanExilesObjectValue -InputObject $s.Instance -Name 'NotifyOnStart' -Value ([bool]$s.NotifyStart.Checked)
                Set-UGSMGameConanExilesObjectValue -InputObject $s.Instance -Name 'NotifyOnStop' -Value ([bool]$s.NotifyStop.Checked)
                Set-UGSMGameConanExilesObjectValue -InputObject $s.Instance -Name 'ShowInDashboard' -Value ([bool]$s.Dashboard.Checked)
            }
            Write-UGSMGameConanExilesLog -Level INFO -Message ("Discord settings saved from editor. InstanceId={0}; HasInstanceWebhook={1}; NotifyOnStart={2}; NotifyOnStop={3}; ShowInDashboard={4}" -f (Get-UGSMGameConanExilesObjectValue $s.Instance @('Id','InstanceId','Name') ''), (-not [string]::IsNullOrWhiteSpace([string]$s.DiscordWebhook.Text)), [bool]$s.NotifyStart.Checked, [bool]$s.NotifyStop.Checked, [bool]$s.Dashboard.Checked)
            if ($s.DiscordStatus) { $s.DiscordStatus.Text = 'Discord settings saved.' }
            # Popup suppressed; Discord save result is logged.
        } catch { if ($s -and $s.DiscordStatus) { $s.DiscordStatus.Text = ('Discord save failed: {0}' -f $_.Exception.Message) }; Write-UGSMGameConanExilesLog -Level ERROR -Message 'Discord settings save failed from editor.' -Exception $_.Exception }
    })

    $btnTestDiscord.Tag = $state
    $btnTestDiscord.Add_Click({
        param($sender,$eventArgs)
        $s = $sender.Tag
        try {
            $resolvedWebhook = Get-UGSMGameConanExilesEffectiveDiscordWebhookUrl -InstanceWebhookUrl ([string]$s.DiscordWebhook.Text)
            if ([string]::IsNullOrWhiteSpace([string]$resolvedWebhook.WebhookUrl)) {
                throw 'Discord webhook URL is required for test. Enter a private webhook or set a global webhook in Settings.'
            }

            if (Get-Command -Name Test-UGSMDiscordWebhook -ErrorAction SilentlyContinue) {
                Test-UGSMDiscordWebhook -WebhookUrl ([string]$resolvedWebhook.WebhookUrl) -Label 'Conan Exiles test' | Out-Null
            } elseif (Get-Command -Name Send-UGSMDiscordNotification -ErrorAction SilentlyContinue) {
                $oldWebhook = Get-UGSMGameConanExilesObjectValue $s.Instance @('DiscordWebhookUrl','WebhookUrl') ''
                try {
                    Set-UGSMGameConanExilesObjectValue -InputObject $s.Instance -Name 'DiscordWebhookUrl' -Value ([string]$resolvedWebhook.WebhookUrl)
                    Send-UGSMDiscordNotification -Instance $s.Instance -Event 'Test' | Out-Null
                }
                finally {
                    Set-UGSMGameConanExilesObjectValue -InputObject $s.Instance -Name 'DiscordWebhookUrl' -Value $oldWebhook
                }
            } else { throw 'Discord service is not loaded.' }
            Write-UGSMGameConanExilesLog -Level INFO -Message ("Discord test sent from editor. InstanceId={0}; WebhookSource={1}; UsesInstanceWebhook={2}" -f (Get-UGSMGameConanExilesObjectValue $s.Instance @('Id','InstanceId','Name') ''), [string]$resolvedWebhook.Source, ([string]$resolvedWebhook.Source -eq 'Instance'))
            if ($s.DiscordStatus) { $s.DiscordStatus.Text = ('Discord test sent using {0} webhook.' -f [string]$resolvedWebhook.Source) }
            # Popup suppressed; Discord test result is logged.
        } catch { if ($s -and $s.DiscordStatus) { $s.DiscordStatus.Text = ('Discord test failed: {0}' -f $_.Exception.Message) }; Write-UGSMGameConanExilesLog -Level ERROR -Message 'Discord webhook test failed from editor.' -Exception $_.Exception }
    })

    $editorHost.ResumeLayout($true)
    $sw.Stop()
    Write-UGSMGameConanExilesLog -Level INFO -Message ("Editor creation finished. InstanceId={0}; DurationMs={1}; UsedHostPanel={2}; CreatedOwnHost={3}; Tabs={4}" -f $id,$sw.ElapsedMilliseconds,[bool]$HostPanel,[bool]$createdOwnHost,$tabs.TabPages.Count)
    if ($createdOwnHost) { return $editorHost }
    return $null
}

function Save-UGSMGameConanExilesInstanceEditor {
    [CmdletBinding()]
    param([object]$Instance,[object]$Editor)
    return [pscustomobject]@{ Success = $true; Instance = $Instance }
}

function Register-UGSMGameConanExilesModule {
    [CmdletBinding()]
    param()
    $metadata = Get-UGSMGameConanExilesMetadata
    return [pscustomobject]@{
        Id       = [string]$metadata.Id
        Metadata = $metadata
        Handlers = [pscustomobject]@{
            GetMetadata       = 'Get-UGSMGameConanExilesMetadata'
            TestInstall       = 'Test-UGSMGameConanExilesInstall'
            TestInstance      = 'Test-UGSMGameConanExilesInstance'
            EnsureTemplate    = 'Ensure-UGSMGameConanExilesTemplate'
            InitializeProfile = 'Initialize-UGSMGameConanExilesProfile'
            Start             = 'Start-UGSMGameConanExilesInstance'
            Stop              = 'Stop-UGSMGameConanExilesInstance'
            BuildEditor       = 'New-UGSMGameConanExilesInstanceEditor'
            SaveEditor        = 'Save-UGSMGameConanExilesInstanceEditor'
        }
    }
}
