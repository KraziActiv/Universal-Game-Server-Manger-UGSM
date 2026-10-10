# Game Services
function ConvertTo-UGSMGamesSafeLogText {
    [CmdletBinding()]
    param(
        [AllowNull()]
        [object]$Value
    )

    if ($null -eq $Value) { return $null }

    $text = [string]$Value

    try {
        $local = [Environment]::GetFolderPath('LocalApplicationData')
        if (-not [string]::IsNullOrWhiteSpace($local)) {
            $escaped = [regex]::Escape($local.TrimEnd('\'))
            $text = [regex]::Replace($text, $escaped, '%LOCALAPPDATA%', 'IgnoreCase')
        }

        $profile = [Environment]::GetFolderPath('UserProfile')
        if (-not [string]::IsNullOrWhiteSpace($profile)) {
            $escapedProfile = [regex]::Escape($profile.TrimEnd('\'))
            $text = [regex]::Replace($text, $escapedProfile, '%USERPROFILE%', 'IgnoreCase')
        }

        if (Get-Command Get-UGSMGlobalSettings -ErrorAction SilentlyContinue) {
            $settings = Get-UGSMGlobalSettings
            if ($settings) {
                $steamRoot = ''
                if ($settings.PSObject.Properties['SteamCmdPath']) { $steamRoot = [string]$settings.SteamCmdPath }
                if (-not [string]::IsNullOrWhiteSpace($steamRoot)) {
                    $escapedSteam = [regex]::Escape($steamRoot.TrimEnd('\'))
                    $text = [regex]::Replace($text, $escapedSteam, '%UGSM_STEAM%', 'IgnoreCase')
                }

                foreach ($propName in @('ProfilesPath','ProfilePath','ProfilesRoot','ProfileRoot','ServerProfilesPath','ServerProfilesRoot')) {
                    if ($settings.PSObject.Properties[$propName]) {
                        $profileRoot = [string]$settings.$propName
                        if (-not [string]::IsNullOrWhiteSpace($profileRoot)) {
                            $escapedRoot = [regex]::Escape($profileRoot.TrimEnd('\'))
                            $text = [regex]::Replace($text, $escapedRoot, '%UGSM_PROFILES%', 'IgnoreCase')
                        }
                    }
                }
            }
        }

# Generic fallback for the normal UGSM layout: <root>\Steam and <root>\Profiles.
        $text = [regex]::Replace($text, '(?i)([A-Z]:\\[^;\r\n]*?)\\Steam(?=\\|$)', '%UGSM_STEAM%')
        $text = [regex]::Replace($text, '(?i)([A-Z]:\\[^;\r\n]*?)\\Profiles(?=\\|$)', '%UGSM_PROFILES%')

        $text = [regex]::Replace($text, '(?i)(https://discord(?:app)?\.com/api/webhooks/)[^\s''"`<>]+', '$1<redacted>')
        $text = [regex]::Replace($text, '(?i)(\b(password|passwd|pwd|token|gslt|secret|apikey|api_key|login_token)\b\s*[:=]\s*)[^;\s,}]+', '$1<redacted>')
        $text = [regex]::Replace($text, '(?i)(\+login\s+)(?!anonymous\b)\S+\s+\S+', '$1<redacted> <redacted>')
    }
    catch {
# Redaction must never break game actions.
    }

    return $text
}

function ConvertTo-UGSMGamesSafeException {
    [CmdletBinding()]
    param(
        [AllowNull()]
        [System.Exception]$Exception
    )

    if (-not $Exception) { return $null }

    try {
        $safeMessage = ConvertTo-UGSMGamesSafeLogText -Value $Exception.Message
        return [System.Exception]::new($safeMessage)
    }
    catch {
        return $Exception
    }
}


function Write-UGSMGamesLog {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Message,

        [ValidateSet('TRACE', 'DEBUG', 'INFO', 'WARN', 'ERROR', 'FATAL')]
        [string]$Level = 'INFO',

        [System.Exception]$Exception,

        [object]$Data
    )

    try {
        $safeMessage = ConvertTo-UGSMGamesSafeLogText -Value $Message
        $safeException = ConvertTo-UGSMGamesSafeException -Exception $Exception

        if (Get-Command Write-UGSMLog -ErrorAction SilentlyContinue) {
            $params = @{
                Level    = $Level
                Category = 'Games'
                Message  = $safeMessage
            }
            if ($safeException) { $params.Exception = $safeException }
            if ($null -ne $Data) { $params.Data = $Data }
            Write-UGSMLog @params
            return
        }

        Write-Host ('[{0}] [Games] {1}' -f $Level, $safeMessage)
    }
    catch {
    }
}

function Write-UGSMGameActionLog {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Message
    )

    Write-UGSMGamesLog -Level 'INFO' -Message $Message
}

function Initialize-UGSMGamesServiceCaches {
    [CmdletBinding()]
    param()

    if (-not (Get-Variable -Name 'UGSM_InstalledGamesCache' -Scope Script -ErrorAction SilentlyContinue) -or -not $script:UGSM_InstalledGamesCache) {
        $script:UGSM_InstalledGamesCache = [pscustomobject]@{
            Data          = $null
            CapturedAtUtc = [datetime]::MinValue
            TtlSeconds    = 10
        }
    }

    if (-not (Get-Variable -Name 'UGSM_GamesPageDataCache' -Scope Script -ErrorAction SilentlyContinue) -or -not $script:UGSM_GamesPageDataCache) {
        $script:UGSM_GamesPageDataCache = [pscustomobject]@{
            Data          = $null
            CapturedAtUtc = [datetime]::MinValue
            TtlSeconds    = 5
        }
    }

    if (-not (Get-Variable -Name 'UGSM_GamesServiceCache' -Scope Script -ErrorAction SilentlyContinue) -or -not $script:UGSM_GamesServiceCache) {
        $script:UGSM_GamesServiceCache = @{}
    }
}

function Request-UGSMGamesDiskRefresh {
    [CmdletBinding()]
    param(
        [string]$Reason = 'Game binaries changed.'
    )

    try {
        if (Get-Command Request-UGSMMachineDiskRefresh -ErrorAction SilentlyContinue) {
            Request-UGSMMachineDiskRefresh -Reason $Reason
            Write-UGSMGamesLog -Level 'DEBUG' -Message "Requested machine disk refresh. Reason=$Reason"
        }
    }
    catch {
        Write-UGSMGamesLog -Level 'WARN' -Message 'Failed to request machine disk refresh after game action.' -Exception $_.Exception
    }
}



function Get-UGSMGamesObjectValue {
    [CmdletBinding()]
    param(
        [AllowNull()]
        [object]$Object,

        [Parameter(Mandatory)]
        [string[]]$Names,

        [AllowNull()]
        [object]$Default = $null
    )

    if ($null -eq $Object) { return $Default }

    foreach ($name in @($Names)) {
        if ([string]::IsNullOrWhiteSpace($name)) { continue }

        try {
            if ($Object.PSObject.Properties[$name]) {
                $value = $Object.$name
                if ($null -ne $value) {
                    return $value
                }
            }
        }
        catch {
            continue
        }
    }

    return $Default
}

function ConvertTo-UGSMGamesInstallState {
    [CmdletBinding()]
    param(
        [AllowNull()]
        [object]$State,

        [string]$GameId,

        [string]$InstallPath
    )

    $missingItems = @()
    if ($null -ne $State) {
        $rawMissing = Get-UGSMGamesObjectValue -Object $State -Names @('MissingItems','MissingFiles','Missing','Errors') -Default @()
        if ($null -ne $rawMissing) {
            $missingItems = @($rawMissing | Where-Object { $null -ne $_ } | ForEach-Object { [string]$_ })
        }
    }

    $isInstalledRaw = Get-UGSMGamesObjectValue -Object $State -Names @('IsInstalled','Installed','ServerExecutableExists','Exists') -Default $false
    $isInstalled = [bool]$isInstalledRaw

    $hasValidityProperty = $false
    if ($null -ne $State) {
        foreach ($validName in @('IsValid','Valid')) {
            if ($State.PSObject.Properties[$validName]) {
                $hasValidityProperty = $true
                break
            }
        }
    }

    if ($hasValidityProperty) {
        $isValid = [bool](Get-UGSMGamesObjectValue -Object $State -Names @('IsValid','Valid') -Default $false)
    }
    else {
        # Some older game modules only report IsInstalled. Treat installed as valid
        # until that game module is updated to report a richer validation shape.
        $isValid = $isInstalled
    }

    $needsRepairRaw = Get-UGSMGamesObjectValue -Object $State -Names @('NeedsRepair') -Default $null
    if ($null -ne $needsRepairRaw) {
        $needsRepair = [bool]$needsRepairRaw
    }
    else {
        $needsRepair = ($isInstalled -and -not $isValid)
    }

    $resolvedGameId = [string](Get-UGSMGamesObjectValue -Object $State -Names @('GameId','Id') -Default $GameId)
    $resolvedInstallPath = [string](Get-UGSMGamesObjectValue -Object $State -Names @('InstallPath','Path') -Default $InstallPath)
    $serverExecutablePath = [string](Get-UGSMGamesObjectValue -Object $State -Names @('ServerExecutablePath','ExecutablePath','ExePath') -Default '')

    return [pscustomobject]@{
        GameId               = $resolvedGameId
        InstallPath          = $resolvedInstallPath
        ServerExecutablePath = $serverExecutablePath
        IsInstalled          = $isInstalled
        Installed            = $isInstalled
        IsValid              = $isValid
        Valid                = $isValid
        NeedsRepair          = $needsRepair
        MissingItems         = @($missingItems)
        MissingFiles         = @($missingItems)
        RawState             = $State
    }
}


function Get-UGSMGameServiceModule {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$GameId
    )

    if (-not (Get-Command Get-UGSMGameModuleById -ErrorAction SilentlyContinue)) {
        return $null
    }

    return (Get-UGSMGameModuleById -GameId $GameId)
}

function Resolve-UGSMGameModuleMetadata {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$GameId
    )

    Write-UGSMGamesLog -Level 'DEBUG' -Message ("Resolving game metadata. GameId={0}" -f $GameId)

    $module = Get-UGSMGameServiceModule -GameId $GameId
    if ($module -and $module.PSObject.Properties['Metadata'] -and $module.Metadata) {
        return $module.Metadata
    }

    return $null
}

function Invoke-UGSMGameHandler {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$GameId,

        [Parameter(Mandatory)]
        [string]$HandlerName,

        [hashtable]$Arguments
    )

    

    $module = Get-UGSMGameServiceModule -GameId $GameId
    if (-not $module) {
        throw "No game module was registered for GameId '$GameId'."
    }

    $handlers = if ($module.Handlers) { $module.Handlers } elseif ($module.Metadata -and $module.Metadata.PSObject.Properties['Handlers']) { $module.Metadata.Handlers } else { $null }
    if (-not $handlers -or -not $handlers.PSObject.Properties[$HandlerName]) {
        throw "No '$HandlerName' handler exists for GameId '$GameId'."
    }

    $commandName = [string]$handlers.$HandlerName
    if ([string]::IsNullOrWhiteSpace($commandName) -or -not (Get-Command $commandName -ErrorAction SilentlyContinue)) {
        throw "Handler '$HandlerName' for GameId '$GameId' points to missing command '$commandName'."
    }

    $resolved = Get-Command $commandName -ErrorAction SilentlyContinue

    Write-UGSMGamesLog -Level 'DEBUG' -Message (
        "Resolved game handler. GameId={0}; Handler={1}; CommandName={2}; Resolved={3}" -f
        $GameId,
        $HandlerName,
        $commandName,
        $(if ($resolved) { $resolved.Name } else { '<missing>' })
    )

    if ($Arguments) {
        return (& $commandName @Arguments)
    }
    
    return (& $commandName)
}


function Test-UGSMGameHandlerAvailable {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$GameId,

        [Parameter(Mandatory)]
        [string]$HandlerName
    )

    $module = Get-UGSMGameServiceModule -GameId $GameId
    if (-not $module) {
        return $false
    }

    $handlers = if ($module.Handlers) { $module.Handlers } elseif ($module.Metadata -and $module.Metadata.PSObject.Properties['Handlers']) { $module.Metadata.Handlers } else { $null }
    if (-not $handlers -or -not $handlers.PSObject.Properties[$HandlerName]) {
        return $false
    }

    $commandName = [string]$handlers.$HandlerName
    return (-not [string]::IsNullOrWhiteSpace($commandName) -and [bool](Get-Command $commandName -ErrorAction SilentlyContinue))
}

function Test-UGSMGameInstall {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$GameId,

        [Parameter(Mandatory)]
        [string]$InstallPath
    )

    try {
        $rawState = Invoke-UGSMGameHandler -GameId $GameId -HandlerName 'TestInstall' -Arguments @{ InstallPath = $InstallPath }
        return (ConvertTo-UGSMGamesInstallState -State $rawState -GameId $GameId -InstallPath $InstallPath)
    }
    catch {
        Write-UGSMGamesLog -Level 'WARN' -Message ("Game install test failed. GameId={0}; InstallPath={1}" -f $GameId, $InstallPath) -Exception $_.Exception
        return [pscustomobject]@{
            GameId       = $GameId
            InstallPath  = $InstallPath
            IsInstalled  = $false
            Installed    = $false
            IsValid      = $false
            Valid        = $false
            NeedsRepair  = $false
            MissingItems = @($_.Exception.Message)
            MissingFiles = @($_.Exception.Message)
            RawState     = $null
        }
    }
}

function Test-UGSMGameInstance {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Instance
    )

    return (Invoke-UGSMGameHandler -GameId ([string]$Instance.GameId) -HandlerName 'TestInstance' -Arguments @{ Instance = $Instance })
}

function Start-UGSMGameInstance {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Instance
    )

    return (Invoke-UGSMGameHandler -GameId ([string]$Instance.GameId) -HandlerName 'Start' -Arguments @{ Instance = $Instance })
}

function Stop-UGSMGameInstance {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Instance
    )

    return (Invoke-UGSMGameHandler -GameId ([string]$Instance.GameId) -HandlerName 'Stop' -Arguments @{ Instance = $Instance })
}


function Ensure-UGSMGameTemplate {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$GameId,

        [Parameter(Mandatory)]
        [string]$InstallPath,

        [switch]$ForceRefresh,

        [int]$BootstrapSeconds = 30
    )

    return (Invoke-UGSMGameHandler -GameId $GameId -HandlerName 'EnsureTemplate' -Arguments @{
            InstallPath      = $InstallPath
            ForceRefresh     = $ForceRefresh
            BootstrapSeconds = $BootstrapSeconds
        })
}

function Initialize-UGSMGameProfile {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Instance,

        [switch]$Force,

        [int]$BootstrapSeconds = 30
    )

    return (Invoke-UGSMGameHandler -GameId ([string]$Instance.GameId) -HandlerName 'InitializeProfile' -Arguments @{
            Instance         = $Instance
            Force            = $Force
            BootstrapSeconds = $BootstrapSeconds
        })
}

function Get-UGSMGameInstallRoot {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$GameId
    )

    if (Test-UGSMGameHandlerAvailable -GameId $GameId -HandlerName 'GetInstallDefinition') {
       
        $definition = Invoke-UGSMGameHandler -GameId $GameId -HandlerName 'GetInstallDefinition' -Arguments @{}
        if ($definition -and -not [string]::IsNullOrWhiteSpace([string]$definition.InstallPath)) {
            return [string]$definition.InstallPath
        }
    }

    $settings = Get-UGSMGlobalSettings
    $steamRoot = [string]$settings.SteamCmdPath

    if ([string]::IsNullOrWhiteSpace($steamRoot)) {
        throw 'SteamCMD path is not configured in Settings.'
    }

    $commonRoot = Join-Path (Join-Path $steamRoot 'steamapps') 'common'
    return (Join-Path $commonRoot $GameId)
}

function Install-UGSMGameServer {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$GameId,

        [switch]$Validate
    )

    Write-UGSMGamesLog -Level 'INFO' -Message ("Install requested. GameId={0}; Validate={1}" -f $GameId, [bool]$Validate)

    $meta = Resolve-UGSMGameModuleMetadata -GameId $GameId
    if (-not $meta) {
        throw "No game metadata found for '$GameId'."
    }

    if ([string]$meta.InstallProvider -ne 'SteamCMD') {
        throw "Game '$GameId' does not use SteamCMD installs."
    }

    $steam = Ensure-UGSMSteamCMDInstalled
    if (-not $steam.Success -or -not $steam.IsInstalled) {
        throw 'SteamCMD is not available.'
    }

    $installPath = Get-UGSMGameInstallRoot -GameId $GameId
    if (-not (Test-Path -LiteralPath $installPath -PathType Container)) {
        New-Item -Path $installPath -ItemType Directory -Force | Out-Null
    }

# Determine login mode
    $useCredentials = $false

    if ($meta.PSObject.Properties['RequiresSteamLogin']) {
        $useCredentials = [bool]$meta.RequiresSteamLogin
    }

    $settings = Get-UGSMGlobalSettings
    $secrets = Get-UGSMSecrets

    if ($useCredentials -and
        -not [string]::IsNullOrWhiteSpace([string]$settings.SteamUsername) -and
        -not [string]::IsNullOrWhiteSpace([string]$secrets.SteamPassword)) {

# Write-Host "[GamesService] Using Steam credentials for install"

        $loginArgs = @('+login', [string]$settings.SteamUsername, [string]$secrets.SteamPassword)
    }
    else {
# Write-Host "[GamesService] Using anonymous Steam login"

        $loginArgs = @('+login', 'anonymous')
    }

    $args = @(
        '+force_install_dir', $installPath
    ) + $loginArgs + @(
        '+app_update', [string]$meta.SteamAppId
    )

    if ($Validate) {
        $args += 'validate'
    }

    $args += '+quit'

    Write-UGSMGamesLog -Level 'INFO' -Message ("Starting SteamCMD install/update. GameId={0}; AppId={1}; InstallPath={2}; Validate={3}" -f $GameId, [string]$meta.SteamAppId, $installPath, [bool]$Validate)

    $proc = Invoke-UGSMProcess -FilePath $steam.ExePath -ArgumentList $args -WorkingDirectory $steam.InstallPath -ShowWindow -TimeoutSeconds 7200

    if ([int]$proc.ExitCode -eq 8) {
        Write-UGSMGamesLog -Level 'WARN' -Message ("SteamCMD returned exit code 8. Retrying once. GameId={0}" -f $GameId)
        Start-Sleep -Seconds 2
        $proc = Invoke-UGSMProcess -FilePath $steam.ExePath -ArgumentList $args -WorkingDirectory $steam.InstallPath -ShowWindow -TimeoutSeconds 7200
    }
    $validation = Test-UGSMGameInstall -GameId $GameId -InstallPath $installPath

    $templateResult = $null
    $templateBootstrapWarning = $null
    if ([bool]$proc.Success -and [bool]$validation.IsValid) {
        try {
            if (Test-UGSMGameHandlerAvailable -GameId $GameId -HandlerName 'EnsureTemplate') {
                $templateResult = Ensure-UGSMGameTemplate -GameId $GameId -InstallPath $installPath
            }
        }
        catch {
# Template bootstrapping is legacy/optional for some games. Do not fail a successful
# SteamCMD install/update just because post-install template copy logic needs cleanup.
            $templateBootstrapWarning = ConvertTo-UGSMGamesSafeLogText -Value $_.Exception.Message
            Write-UGSMGamesLog -Level 'WARN' -Message ("Post-install template bootstrap skipped/failed but install remains valid. GameId={0}; Error={1}" -f $GameId, $templateBootstrapWarning)
        }
    }

    $installResult = [pscustomobject]@{
        Success              = ([bool]$proc.Success -and [bool]$validation.IsValid)
        Action               = if ($validation.IsValid) { 'Installed' } else { 'Failed' }
        GameId               = $GameId
        InstallPath          = $installPath
        AppId                = [string]$meta.SteamAppId
        ExitCode             = $proc.ExitCode
        IsInstalled          = [bool]$validation.IsInstalled
        IsValid              = [bool]$validation.IsValid
        NeedsRepair          = [bool]$validation.NeedsRepair
        MissingItems         = @($validation.MissingItems)
        TemplateBootstrapped = [bool]($templateResult -and $templateResult.PSObject.Properties['TemplateRoot'])
        TemplateWarning      = $templateBootstrapWarning
        Message              = if ($validation.IsValid) { "$GameId server files are ready." } else { "$GameId install did not validate cleanly." }
    }

    Clear-UGSMGamesCaches
    if ($installResult.Success) {
        Request-UGSMGamesDiskRefresh -Reason ("Game install/update completed. GameId=$GameId")
        Write-UGSMGamesLog -Level 'INFO' -Message ("Install completed. GameId={0}; Success={1}; ExitCode={2}; IsValid={3}" -f $GameId, [bool]$installResult.Success, $installResult.ExitCode, [bool]$installResult.IsValid)
    }
    else {
        Write-UGSMGamesLog -Level 'WARN' -Message ("Install completed with validation issues. GameId={0}; Success={1}; ExitCode={2}; IsValid={3}" -f $GameId, [bool]$installResult.Success, $installResult.ExitCode, [bool]$installResult.IsValid)
    }

    return $installResult
}

function Set-UGSMGamesResultValue {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Result,

        [Parameter(Mandatory)]
        [string]$Name,

        [AllowNull()]
        [object]$Value
    )

    if (-not $Result) {
        return $null
    }

    if ($Result.PSObject.Properties[$Name]) {
        $Result.$Name = $Value
    }
    else {
        $Result | Add-Member -NotePropertyName $Name -NotePropertyValue $Value -Force
    }

    return $Result
}

function Ensure-UGSMGameServerInstalled {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$GameId
    )

    Write-UGSMGamesLog -Level 'INFO' -Message ("Ensure installed requested. GameId={0}" -f $GameId)
    $installPath = Get-UGSMGameInstallRoot -GameId $GameId
    $current = Test-UGSMGameInstall -GameId $GameId -InstallPath $installPath

    if ($current.IsValid) {
        Write-UGSMGamesLog -Level 'INFO' -Message ("Install skipped; already valid. GameId={0}; InstallPath={1}" -f $GameId, $installPath)
        return [pscustomobject]@{
            Success      = $true
            Action       = 'Skipped'
            GameId       = $GameId
            InstallPath  = $installPath
            IsInstalled  = $true
            IsValid      = $true
            NeedsRepair  = $false
            MissingItems = @()
            Message      = "$GameId is already installed."
        }
    }

    $needsRepair = ($current.IsInstalled -and -not $current.IsValid)
    $result = Install-UGSMGameServer -GameId $GameId -Validate:$needsRepair

    if ($result.Success -and $needsRepair) {
        [void](Set-UGSMGamesResultValue -Result $result -Name 'Action' -Value 'Repaired')
        [void](Set-UGSMGamesResultValue -Result $result -Name 'Message' -Value "$GameId install was repaired.")
    }

    return $result
}


function Remove-UGSMGameServer {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$GameId
    )

    Write-UGSMGamesLog -Level 'INFO' -Message ("Remove binaries requested. GameId={0}" -f $GameId)

    $meta = Resolve-UGSMGameModuleMetadata -GameId $GameId
    if (-not $meta) {
        throw "No game metadata found for '$GameId'."
    }

    if ([string]$meta.InstallProvider -ne 'SteamCMD') {
        throw "Game '$GameId' does not support binary removal through the Games page."
    }

    $installPath = Get-UGSMGameInstallRoot -GameId $GameId
    $validation = Test-UGSMGameInstall -GameId $GameId -InstallPath $installPath

    if (-not $validation.IsInstalled -and -not (Test-Path -LiteralPath $installPath)) {
        Write-UGSMGamesLog -Level 'INFO' -Message ("Remove skipped; binaries already removed. GameId={0}; InstallPath={1}" -f $GameId, $installPath)
        return [pscustomobject]@{
            Success     = $true
            Action      = 'Skipped'
            GameId      = $GameId
            InstallPath = $installPath
            IsInstalled = $false
            Message     = "$GameId binaries are already removed."
        }
    }

    if (Get-Command Get-UGSMInstances -ErrorAction SilentlyContinue) {
        $activeInstances = @(
            Get-UGSMInstances -GameId $GameId | Where-Object {
                $_ -and $_.PSObject.Properties['Status'] -and [string]$_.Status -in @('Running', 'Starting', 'Stopping')
            }
        )

        if (@($activeInstances).Count -gt 0) {
            $names = @($activeInstances | ForEach-Object {
                    if ($_.PSObject.Properties['Name']) { [string]$_.Name } else { [string]$_.Id }
                }) -join ', '

            throw "Stop all $GameId profiles before removing binaries. Active profiles: $names"
        }
    }

    if (Test-Path -LiteralPath $installPath) {
        Write-UGSMGamesLog -Level 'INFO' -Message ("Removing game binaries. GameId={0}; InstallPath={1}" -f $GameId, $installPath)
        Remove-Item -LiteralPath $installPath -Recurse -Force -ErrorAction Stop
    }

    $postValidation = Test-UGSMGameInstall -GameId $GameId -InstallPath $installPath

    $removeResult = [pscustomobject]@{
        Success     = (-not [bool]$postValidation.IsInstalled)
        Action      = 'Removed'
        GameId      = $GameId
        InstallPath = $installPath
        IsInstalled = [bool]$postValidation.IsInstalled
        Message     = if (-not [bool]$postValidation.IsInstalled) {
            "$GameId binaries were removed. Profiles were left intact."
        }
        else {
            "$GameId binaries could not be removed completely."
        }
    }

    Clear-UGSMGamesCaches
    if ($removeResult.Success) {
        Request-UGSMGamesDiskRefresh -Reason ("Game binaries removed. GameId=$GameId")
        Write-UGSMGamesLog -Level 'INFO' -Message ("Remove completed. GameId={0}; Success={1}; IsInstalled={2}" -f $GameId, [bool]$removeResult.Success, [bool]$removeResult.IsInstalled)
    }
    else {
        Write-UGSMGamesLog -Level 'WARN' -Message ("Remove completed but binaries still appear installed. GameId={0}; IsInstalled={1}" -f $GameId, [bool]$removeResult.IsInstalled)
    }

    return $removeResult
}


Initialize-UGSMGamesServiceCaches

function Clear-UGSMGamesCaches {
    [CmdletBinding()]
    param()

    Initialize-UGSMGamesServiceCaches

    if ($script:UGSM_InstalledGamesCache) {
        $script:UGSM_InstalledGamesCache.Data = $null
        $script:UGSM_InstalledGamesCache.CapturedAtUtc = [datetime]::MinValue
    }
    if ($script:UGSM_GamesPageDataCache) {
        $script:UGSM_GamesPageDataCache.Data = $null
        $script:UGSM_GamesPageDataCache.CapturedAtUtc = [datetime]::MinValue
    }
    if ($script:UGSM_GamesServiceCache) {
        $script:UGSM_GamesServiceCache.Clear()
    }

    Write-UGSMGamesLog -Level 'DEBUG' -Message 'Game service caches cleared.'
}

function Get-UGSMInstalledGames {
    [CmdletBinding()]
    param(
        [Alias('ForceRefresh')]
        [switch]$Refresh
    )

    Initialize-UGSMGamesServiceCaches

    $cacheKey = 'InstalledGames'
    if (-not $Refresh -and $script:UGSM_GamesServiceCache.ContainsKey($cacheKey)) {
        return @($script:UGSM_GamesServiceCache[$cacheKey])
    }

    Write-UGSMGamesLog -Level 'DEBUG' -Message ("Refreshing installed games cache. ForceRefresh={0}" -f [bool]$Refresh)

    $games = @(Get-UGSMGameCatalog -Refresh:$Refresh)
    $resolvedGames = @()

    foreach ($game in $games) {
        $gameId = [string]$game.Id
        $meta = $null
        $installRoot = $null
        $installState = $null
        $instanceCount = 0

        try {
            $meta = Resolve-UGSMGameModuleMetadata -GameId $gameId
        } catch {
            $meta = $null
        }

        if ($meta) {
            try {
                $installRoot = Get-UGSMGameInstallRoot -GameId $gameId
            } catch {
                $installRoot = $null
            }
        }

        if (-not [string]::IsNullOrWhiteSpace($installRoot)) {
            try {
                $installState = Test-UGSMGameInstall -GameId $gameId -InstallPath $installRoot
            } catch {
                $installState = $null
            }
        }

        if (Get-Command Get-UGSMInstances -ErrorAction SilentlyContinue) {
            try {
                $instanceCount = @((Get-UGSMInstances -GameId $gameId)).Count
            } catch {
                $instanceCount = 0
            }
        }

        $statusText = if (-not $meta) {
            'Module not ready'
        }
        elseif ($installState -and $installState.IsValid) {
            'Installed'
        }
        elseif ($installState -and $installState.NeedsRepair) {
            'Needs repair'
        }
        elseif ($installState -and $installState.IsInstalled) {
            'Installed'
        }
        else {
            'Not installed'
        }

        $resolvedGames += [pscustomobject]@{
            Id             = $game.Id
            Name           = $game.Name
            Category       = $game.Category
            SteamAppId     = $game.SteamAppId
            Installed      = [bool]($installState -and $installState.IsInstalled)
            IsInstalled    = [bool]($installState -and $installState.IsInstalled)
            IsValid        = [bool]($installState -and $installState.IsValid)
            NeedsRepair    = [bool]($installState -and $installState.NeedsRepair)
            StatusText     = $statusText
            InstallPath    = if ($installState -and $installState.IsInstalled) { $installRoot } else { $null }
            InstanceCount  = $instanceCount
            IsCustom       = [bool]$game.IsCustom
            SupportsRemove = [bool]($meta -and [string]$meta.InstallProvider -eq 'SteamCMD')
            HeaderArtPath  = $game.HeaderArtPath
            LibraryArtPath = $game.LibraryArtPath
            CapsuleArtPath = $game.CapsuleArtPath
            IconArtPath    = $game.IconArtPath
        }
    }

    $result = @($resolvedGames)
    $script:UGSM_GamesServiceCache[$cacheKey] = $result
    return $result
}

function Get-UGSMGamesPageData {
    [CmdletBinding()]
    param(
        [switch]$ForceRefresh
    )

    Initialize-UGSMGamesServiceCaches

    $nowUtc = [datetime]::UtcNow
    if (-not $ForceRefresh -and $script:UGSM_GamesPageDataCache -and $script:UGSM_GamesPageDataCache.Data -and (($nowUtc - $script:UGSM_GamesPageDataCache.CapturedAtUtc).TotalSeconds -lt [double]$script:UGSM_GamesPageDataCache.TtlSeconds)) {
        return $script:UGSM_GamesPageDataCache.Data
    }

    $gamesRaw = Get-UGSMInstalledGames -ForceRefresh:$ForceRefresh

    $games = @(
        foreach ($item in @($gamesRaw)) {
            if ($null -eq $item) {
                continue
            }

            if ($item -is [System.Array]) {
                foreach ($nested in @($item)) {
                    if ($null -ne $nested) {
                        $nested
                    }
                }
                continue
            }

            $item
        }
    )

    $games = @(
        $games | Where-Object {
            $_ -and $_.PSObject.Properties['Id']
        }
    )
    $steamCmd = $null
    $statusMessage = 'Games page loaded.'

    try {
        $settings = Get-UGSMGlobalSettings
        $installPath = [string]$settings.SteamCmdPath

        if (-not [string]::IsNullOrWhiteSpace($installPath) -and (Get-Command Test-UGSMSteamCMDInstall -ErrorAction SilentlyContinue)) {
            $steamCmd = Test-UGSMSteamCMDInstall -InstallPath $installPath
            $statusMessage = if ($steamCmd.IsInstalled) { 'SteamCMD is installed and ready.' } else { 'SteamCMD is not installed yet.' }
        }
        else {
            $statusMessage = 'Configure a SteamCMD install folder in Settings first.'
        }
    }
    catch {
        $statusMessage = $_.Exception.Message
    }

    $pageData = [pscustomobject]@{
        TotalInstalled = @(
            $games | Where-Object {
                ($_.PSObject.Properties['IsInstalled'] -and $_.IsInstalled) -or
                ($_.PSObject.Properties['Installed'] -and $_.Installed)
            }
        ).Count
        Games          = $games
        StatusMessage  = $statusMessage
        SteamCmd       = $steamCmd
    }

    if ($script:UGSM_GamesPageDataCache) {
        $script:UGSM_GamesPageDataCache.Data = $pageData
        $script:UGSM_GamesPageDataCache.CapturedAtUtc = [datetime]::UtcNow
    }

    return $pageData
}


function Update-UGSMGameServer {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$GameId
    )

    Write-UGSMGamesLog -Level 'INFO' -Message ("Update requested. GameId={0}" -f $GameId)
    $installPath = Get-UGSMGameInstallRoot -GameId $GameId
    $current = Test-UGSMGameInstall -GameId $GameId -InstallPath $installPath

    if (-not $current.IsInstalled) {
        return [pscustomobject]@{
            Success      = $false
            Action       = 'Skipped'
            GameId       = $GameId
            InstallPath  = $installPath
            IsInstalled  = $false
            IsValid      = $false
            NeedsRepair  = $false
            MissingItems = @($current.MissingItems)
            Message      = "$GameId is not installed. Use Install first."
        }
    }

    $result = Install-UGSMGameServer -GameId $GameId
    if ($result -and $result.Success) {
        [void](Set-UGSMGamesResultValue -Result $result -Name 'Action' -Value 'Updated')
        [void](Set-UGSMGamesResultValue -Result $result -Name 'Message' -Value "$GameId server files were updated.")
    }

    return $result
}

function Verify-UGSMGameServer {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$GameId
    )

    Write-UGSMGamesLog -Level 'INFO' -Message ("Verify requested. GameId={0}" -f $GameId)
    $installPath = Get-UGSMGameInstallRoot -GameId $GameId
    $current = Test-UGSMGameInstall -GameId $GameId -InstallPath $installPath

    if (-not $current.IsInstalled) {
        return [pscustomobject]@{
            Success      = $false
            Action       = 'Skipped'
            GameId       = $GameId
            InstallPath  = $installPath
            IsInstalled  = $false
            IsValid      = $false
            NeedsRepair  = $false
            MissingItems = @($current.MissingItems)
            Message      = "$GameId is not installed. Use Install first."
        }
    }

    $result = Install-UGSMGameServer -GameId $GameId -Validate
    if ($result -and $result.Success) {
        [void](Set-UGSMGamesResultValue -Result $result -Name 'Action' -Value 'Verified')
        [void](Set-UGSMGamesResultValue -Result $result -Name 'Message' -Value "$GameId server files verified successfully.")
    }
    elseif ($result) {
        [void](Set-UGSMGamesResultValue -Result $result -Name 'Action' -Value 'Verified')
    }

    return $result
}


function Resolve-UGSMGamesActionResult {
    [CmdletBinding()]
    param(
        [AllowNull()]
        [object]$Result
    )

    if ($null -eq $Result) {
        return $null
    }

    if ($Result -is [array]) {
        $items = @($Result | Where-Object { $null -ne $_ })
        if (@($items).Count -eq 0) {
            return $null
        }

        $best = @($items | Where-Object {
                $_.PSObject.Properties['Success'] -or
                $_.PSObject.Properties['Action'] -or
                $_.PSObject.Properties['Message'] -or
                $_.PSObject.Properties['GameId']
            } | Select-Object -Last 1)

        if (@($best).Count -gt 0) {
            return $best[-1]
        }

        return $items[-1]
    }

    return $Result
}

function Invoke-UGSMGameBinaryAction {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('Install', 'Repair', 'Remove', 'Update', 'Verify')]
        [string]$Action,

        [Parameter(Mandatory)]
        [string]$GameId
    )

    Write-UGSMGamesLog -Level 'INFO' -Message ("Game binary action requested. Action={0}; GameId={1}" -f $Action, $GameId)

    try {
        $rawActionResult = switch ($Action) {
            'Install' { Ensure-UGSMGameServerInstalled -GameId $GameId }
            'Repair' { Install-UGSMGameServer -GameId $GameId -Validate }
            'Remove' { Remove-UGSMGameServer -GameId $GameId }
            'Update' { Update-UGSMGameServer -GameId $GameId }
            'Verify' { Verify-UGSMGameServer -GameId $GameId }
        }

        $actionResult = Resolve-UGSMGamesActionResult -Result $rawActionResult

        Clear-UGSMGamesCaches

        $pageData = Get-UGSMGamesPageData -ForceRefresh
        $message = if ($actionResult -and $actionResult.PSObject.Properties['Message']) { [string]$actionResult.Message } else { '' }
        $successText = if ($actionResult -and $actionResult.PSObject.Properties['Success']) { [string]([bool]$actionResult.Success) } else { 'Unknown' }
        $resultActionText = if ($actionResult -and $actionResult.PSObject.Properties['Action']) { [string]$actionResult.Action } else { 'Unknown' }

        Write-UGSMGamesLog -Level 'INFO' -Message (
            "Game binary action completed. Action={0}; GameId={1}; Success={2}; ResultAction={3}" -f
            $Action,
            $GameId,
            $successText,
            $resultActionText
        )

        $successValue = if ($actionResult -and $actionResult.PSObject.Properties['Success']) {
            [bool]$actionResult.Success
        }
        elseif ($actionResult -and $actionResult.PSObject.Properties['IsValid']) {
            [bool]$actionResult.IsValid
        }
        else {
            $false
        }

        return [pscustomobject]@{
            Success      = $successValue
            Action       = $Action
            GameId       = $GameId
            ActionResult = $actionResult
            PageData     = $pageData
            Message      = $message
        }
    }
    catch {
        Write-UGSMGamesLog -Level 'ERROR' -Message ("Game binary action failed. Action={0}; GameId={1}" -f $Action, $GameId) -Exception $_.Exception
        throw
    }
}
