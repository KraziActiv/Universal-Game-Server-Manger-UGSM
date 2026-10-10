# SteamCMD Service


function ConvertTo-UGSMSafeSteamCMDLogText {
    [CmdletBinding()]
    param(
        [AllowNull()]
        [string]$Text
    )

    if ($null -eq $Text) {
        return ''
    }

    $safe = [string]$Text

    try {
        $localAppData = [Environment]::GetFolderPath('LocalApplicationData')
        if (-not [string]::IsNullOrWhiteSpace($localAppData)) {
            $safe = $safe -replace [regex]::Escape($localAppData), '%LOCALAPPDATA%'
        }

        $userProfile = [Environment]::GetFolderPath('UserProfile')
        if (-not [string]::IsNullOrWhiteSpace($userProfile)) {
            $safe = $safe -replace [regex]::Escape($userProfile), '%USERPROFILE%'
        }

        $steamRoots = New-Object System.Collections.Generic.List[string]
        try {
            if (Get-Command Get-UGSMSettings -ErrorAction SilentlyContinue) {
                $settings = Get-UGSMSettings
                foreach ($propName in @('SteamCmdPath','SteamPath','SteamRoot','SteamInstallPath')) {
                    if ($settings -and ($settings.PSObject.Properties.Name -contains $propName)) {
                        $candidate = [string]$settings.$propName
                        if (-not [string]::IsNullOrWhiteSpace($candidate)) {
                            $steamRoots.Add($candidate.TrimEnd('\'))
                        }
                    }
                }
            }
        }
        catch {
            # Do not let optional path display cleanup affect SteamCMD logging.
        }

        foreach ($steamRoot in ($steamRoots | Select-Object -Unique)) {
            if (-not [string]::IsNullOrWhiteSpace($steamRoot)) {
                $safe = $safe -replace [regex]::Escape($steamRoot), '%UGSM_STEAM%'
            }
        }

        # Fallback for the default UGSM layout. This is display-only redaction and does not affect real paths.
        $safe = $safe -replace '(?i)[A-Z]:\\GameServers\\Steam', '%UGSM_STEAM%'

        $safe = $safe -replace 'C:\\Users\\[^\\\s;"]+', '%USERPROFILE%'
        $safe = $safe -replace 'https://discord(?:app)?\.com/api/webhooks/[^\s;"]+', '<redacted-webhook>'
        $safe = $safe -replace '(?i)(password|pass|token|secret|apikey|api_key|gslt|login_token)\s*=\s*[^;\s"]+', '$1=<redacted>'
        $safe = $safe -replace '(?i)("?(password|pass|token|secret|apikey|api_key|gslt|login_token)"?\s*:\s*")[^"]*(")', '$1<redacted>$3'
        $safe = $safe -replace '(?i)(\+(?:login)\s+)(?!anonymous\b)([^\s]+)(?:\s+[^\s]+)?', '$1<redacted> <redacted>'
    }
    catch {
        # If redaction itself ever fails, do not block logging. Return the original message.
        return [string]$Text
    }

    return $safe
}

function New-UGSMSafeSteamCMDException {
    [CmdletBinding()]
    param(
        [AllowNull()]
        [System.Exception]$Exception
    )

    if (-not $Exception) {
        return $null
    }

    $safeMessage = ConvertTo-UGSMSafeSteamCMDLogText -Text $Exception.Message
    return [System.Exception]::new($safeMessage)
}

function Write-UGSMSteamCMDLog {
    [CmdletBinding()]
    param(
        [string]$Level = 'INFO',
        [string]$Message,
        [System.Exception]$Exception
    )

    $safeMessage = ConvertTo-UGSMSafeSteamCMDLogText -Text $Message
    $safeException = New-UGSMSafeSteamCMDException -Exception $Exception

    if (Get-Command Write-UGSMLog -ErrorAction SilentlyContinue) {
        if ($safeException) {
            Write-UGSMLog -Level $Level -Category 'SteamCMD' -Message $safeMessage -Exception $safeException
        }
        else {
            Write-UGSMLog -Level $Level -Category 'SteamCMD' -Message $safeMessage
        }
    }
}

function ConvertTo-UGSMSafeSteamCMDArgsText {
    [CmdletBinding()]
    param(
        [string[]]$ArgumentList
    )

    if (-not $ArgumentList) {
        return ''
    }

    $safe = New-Object System.Collections.Generic.List[string]

    for ($i = 0; $i -lt $ArgumentList.Count; $i++) {
        $item = [string]$ArgumentList[$i]

        if ($item -eq '+login') {
            $safe.Add($item)

            $next = if (($i + 1) -lt $ArgumentList.Count) { [string]$ArgumentList[$i + 1] } else { '' }
            if ($next -eq 'anonymous') {
                $safe.Add('anonymous')
                $i++
                continue
            }

            if (($i + 1) -lt $ArgumentList.Count) {
                $safe.Add('<redacted>')
                $i++
            }

            if (($i + 1) -lt $ArgumentList.Count) {
                $possiblePassword = [string]$ArgumentList[$i + 1]
                if (-not [string]::IsNullOrWhiteSpace($possiblePassword) -and -not $possiblePassword.StartsWith('+')) {
                    $safe.Add('<redacted>')
                    $i++
                }
            }

            continue
        }

        $safe.Add((ConvertTo-UGSMSafeSteamCMDLogText -Text $item))
    }

    return ($safe.ToArray() -join ' ')
}

function Get-UGSMSteamCMDDownloadUrl {
    [CmdletBinding()]
    param()

    return 'https://steamcdn-a.akamaihd.net/client/installer/steamcmd.zip'
}

function Get-UGSMSteamCMDExePath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$InstallPath
    )

    return (Join-Path $InstallPath 'steamcmd.exe')
}

function Test-UGSMSteamCMDInstall {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$InstallPath
    )

    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    try {
        $exePath = Get-UGSMSteamCMDExePath -InstallPath $InstallPath
        $isInstalled = (Test-Path -LiteralPath $InstallPath -PathType Container) -and (Test-Path -LiteralPath $exePath -PathType Leaf)
        $sw.Stop()

        Write-UGSMSteamCMDLog -Level 'DEBUG' -Message "SteamCMD install check completed. Installed=$isInstalled; Path=$InstallPath; DurationMs=$($sw.ElapsedMilliseconds)"

        return [pscustomobject]@{
            Success     = $true
            IsInstalled = $isInstalled
            InstallPath = $InstallPath
            ExePath     = $exePath
            Verified    = $isInstalled
            Message     = if ($isInstalled) { 'SteamCMD is installed.' } else { 'SteamCMD is not installed.' }
        }
    }
    catch {
        $sw.Stop()
        Write-UGSMSteamCMDLog -Level 'ERROR' -Message "SteamCMD install check failed. Path=$InstallPath; DurationMs=$($sw.ElapsedMilliseconds)" -Exception $_.Exception
        throw
    }
}

function Install-UGSMSteamCMD {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$InstallPath
    )

    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    Write-UGSMSteamCMDLog -Level 'INFO' -Message "SteamCMD install requested. Path=$InstallPath"

    try {
        Ensure-UGSMDirectory -Path $InstallPath | Out-Null

        $tempZip = Join-Path ([System.IO.Path]::GetTempPath()) 'ugsm-steamcmd.zip'
        Write-UGSMSteamCMDLog -Level 'INFO' -Message "Downloading SteamCMD bootstrap package. OutFile=$tempZip"
        $download = Invoke-UGSMDownloadFile -Uri (Get-UGSMSteamCMDDownloadUrl) -OutFile $tempZip
        if (-not $download.Success) {
            throw 'Failed to download SteamCMD.'
        }

        Write-UGSMSteamCMDLog -Level 'INFO' -Message "Extracting SteamCMD package. Destination=$InstallPath"
        Expand-UGSMZipArchive -ZipPath $tempZip -DestinationPath $InstallPath | Out-Null

        $exePath = Get-UGSMSteamCMDExePath -InstallPath $InstallPath
        if (-not (Test-Path -LiteralPath $exePath -PathType Leaf)) {
            throw 'SteamCMD install did not produce steamcmd.exe.'
        }

        Write-UGSMSteamCMDLog -Level 'INFO' -Message 'Starting SteamCMD bootstrap process. WindowVisible=True; Args=+quit'
        $bootstrap = Invoke-UGSMProcess -FilePath $exePath -ArgumentList @('+quit') -WorkingDirectory $InstallPath -ShowWindow -TimeoutSeconds 1200
        if (-not $bootstrap.Success) {
            $sw.Stop()
            Write-UGSMSteamCMDLog -Level 'ERROR' -Message "SteamCMD bootstrap failed. ExitCode=$($bootstrap.ExitCode); DurationMs=$($sw.ElapsedMilliseconds)"
            return [pscustomobject]@{
                Success     = $false
                IsInstalled = $false
                InstallPath = $InstallPath
                ExePath     = $exePath
                Verified    = $false
                Message     = 'SteamCMD bootstrap failed.'
                ExitCode    = $bootstrap.ExitCode
            }
        }

        $sw.Stop()
        Write-UGSMSteamCMDLog -Level 'INFO' -Message "SteamCMD installed successfully. ExitCode=$($bootstrap.ExitCode); DurationMs=$($sw.ElapsedMilliseconds)"
        return [pscustomobject]@{
            Success     = $true
            IsInstalled = $true
            InstallPath = $InstallPath
            ExePath     = $exePath
            Verified    = $true
            Message     = 'SteamCMD installed successfully.'
            ExitCode    = $bootstrap.ExitCode
        }
    }
    catch {
        $sw.Stop()
        Write-UGSMSteamCMDLog -Level 'ERROR' -Message "SteamCMD install failed. Path=$InstallPath; DurationMs=$($sw.ElapsedMilliseconds)" -Exception $_.Exception
        throw
    }
}

function Ensure-UGSMSteamCMDInstalled {
    [CmdletBinding()]
    param()

    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    try {
        $settings = Get-UGSMGlobalSettings
        $installPath = [string]$settings.SteamCmdPath
        if ([string]::IsNullOrWhiteSpace($installPath)) {
            throw 'SteamCMD path is not configured in Settings.'
        }

        $state = Test-UGSMSteamCMDInstall -InstallPath $installPath
        if ($state.IsInstalled) {
            $sw.Stop()
            Write-UGSMSteamCMDLog -Level 'DEBUG' -Message "SteamCMD already installed. Path=$($state.InstallPath); DurationMs=$($sw.ElapsedMilliseconds)"
            return [pscustomobject]@{
                Success     = $true
                IsInstalled = $true
                InstallPath = $state.InstallPath
                ExePath     = $state.ExePath
                Verified    = $true
                Action      = 'Skipped'
                Message     = 'SteamCMD is already installed.'
            }
        }

        Write-UGSMSteamCMDLog -Level 'INFO' -Message "SteamCMD missing. Installing now. Path=$installPath"
        $result = Install-UGSMSteamCMD -InstallPath $installPath
        $result | Add-Member -NotePropertyName Action -NotePropertyValue 'Installed' -Force
        $sw.Stop()
        return $result
    }
    catch {
        $sw.Stop()
        Write-UGSMSteamCMDLog -Level 'ERROR' -Message "Ensure SteamCMD installed failed. DurationMs=$($sw.ElapsedMilliseconds)" -Exception $_.Exception
        throw
    }
}

function Remove-UGSMSteamCMD {
    [CmdletBinding()]
    param(
        [string]$InstallPath
    )

    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    try {
        if ([string]::IsNullOrWhiteSpace($InstallPath)) {
            $settings = Get-UGSMGlobalSettings
            $InstallPath = [string]$settings.SteamCmdPath
        }

        if ([string]::IsNullOrWhiteSpace($InstallPath)) {
            throw 'SteamCMD path is not configured.'
        }

        Write-UGSMSteamCMDLog -Level 'WARN' -Message "SteamCMD remove requested. Path=$InstallPath"
        if (Test-Path -LiteralPath $InstallPath) {
            Remove-Item -LiteralPath $InstallPath -Recurse -Force
        }

        $sw.Stop()
        Write-UGSMSteamCMDLog -Level 'INFO' -Message "SteamCMD removed. Path=$InstallPath; DurationMs=$($sw.ElapsedMilliseconds)"
        return [pscustomobject]@{
            Success     = $true
            IsInstalled = $false
            InstallPath = $InstallPath
            ExePath     = (Join-Path $InstallPath 'steamcmd.exe')
            Verified    = $false
            Action      = 'Removed'
            Message     = 'SteamCMD was removed.'
        }
    }
    catch {
        $sw.Stop()
        Write-UGSMSteamCMDLog -Level 'ERROR' -Message "SteamCMD remove failed. Path=$InstallPath; DurationMs=$($sw.ElapsedMilliseconds)" -Exception $_.Exception
        throw
    }
}

function Invoke-UGSMSteamCMD {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string[]]$ArgumentList,

        [int]$TimeoutSeconds = 7200
    )

    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    $safeArgs = ConvertTo-UGSMSafeSteamCMDArgsText -ArgumentList $ArgumentList
    Write-UGSMSteamCMDLog -Level 'INFO' -Message "SteamCMD command requested. WindowVisible=True; TimeoutSeconds=$TimeoutSeconds; Args=$safeArgs"

    try {
        $steam = Ensure-UGSMSteamCMDInstalled
        if (-not $steam.Success -or -not $steam.IsInstalled) {
            throw 'SteamCMD is not available.'
        }

        $workDir = [string]$steam.InstallPath
        $exePath = [string]$steam.ExePath

        # Keep -ShowWindow. Users should still see the SteamCMD window while SteamCMD is doing work.
        $result = Invoke-UGSMProcess `
            -FilePath $exePath `
            -ArgumentList $ArgumentList `
            -WorkingDirectory $workDir `
            -ShowWindow `
            -TimeoutSeconds $TimeoutSeconds

        $sw.Stop()
        $level = if ($result.Success) { 'INFO' } else { 'ERROR' }
        Write-UGSMSteamCMDLog -Level $level -Message "SteamCMD command completed. Success=$($result.Success); ExitCode=$($result.ExitCode); DurationMs=$($sw.ElapsedMilliseconds); Args=$safeArgs"

        return [pscustomobject]@{
            Success     = [bool]$result.Success
            ExitCode    = $result.ExitCode
            FilePath    = $exePath
            InstallPath = $workDir
            Message     = if ($result.Success) { 'SteamCMD command completed.' } else { 'SteamCMD command failed.' }
            Result      = $result
        }
    }
    catch {
        $sw.Stop()
        Write-UGSMSteamCMDLog -Level 'ERROR' -Message "SteamCMD command failed before completion. DurationMs=$($sw.ElapsedMilliseconds); Args=$safeArgs" -Exception $_.Exception
        throw
    }
}

function Install-UGSMSteamCMDWorkshopItem {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$AppId,

        [Parameter(Mandatory)]
        [string]$WorkshopId,

        [string]$SteamUser = '',

        [string]$SteamPass = '',

        [int]$TimeoutSeconds = 7200
    )

    Write-UGSMSteamCMDLog -Level 'INFO' -Message "Workshop item install requested. AppId=$AppId; WorkshopId=$WorkshopId; HasUser=$(-not [string]::IsNullOrWhiteSpace($SteamUser)); HasPassword=$(-not [string]::IsNullOrWhiteSpace($SteamPass))"

    $args = New-Object System.Collections.Generic.List[string]

    if (-not [string]::IsNullOrWhiteSpace($SteamUser) -and -not [string]::IsNullOrWhiteSpace($SteamPass)) {
        $args.Add('+login')
        $args.Add($SteamUser)
        $args.Add($SteamPass)
    }
    elseif (-not [string]::IsNullOrWhiteSpace($SteamUser)) {
        $args.Add('+login')
        $args.Add($SteamUser)
    }
    else {
        foreach ($item in (New-UGSMSteamCMDLoginArgs -AllowAnonymous)) {
            $args.Add($item)
        }
    }

    $args.Add('+workshop_download_item')
    $args.Add([string]$AppId)
    $args.Add([string]$WorkshopId)
    $args.Add('validate')
    $args.Add('+quit')

    return (Invoke-UGSMSteamCMD -ArgumentList $args.ToArray() -TimeoutSeconds $TimeoutSeconds)
}

function Get-UGSMSteamCMDCredentials {
    [CmdletBinding()]
    param()

    $settings = Get-UGSMGlobalSettings -CreateIfMissing
    $secrets = Get-UGSMSecrets

    $username = ''
    $password = ''

    if ($settings -and $settings.PSObject.Properties.Name -contains 'SteamUsername') {
        $username = [string]$settings.SteamUsername
    }

    if ($secrets -and $secrets.PSObject.Properties.Name -contains 'SteamPassword') {
        $password = [string]$secrets.SteamPassword
    }

    Write-UGSMSteamCMDLog -Level 'DEBUG' -Message "Steam credentials loaded. HasUsername=$(-not [string]::IsNullOrWhiteSpace($username)); HasPassword=$(-not [string]::IsNullOrWhiteSpace($password))"

    return [pscustomobject]@{
        Username = $username
        Password = $password
    }
}

function New-UGSMSteamCMDLoginArgs {
    [CmdletBinding()]
    param(
        [switch]$AllowAnonymous
    )

    $creds = Get-UGSMSteamCMDCredentials

    if (-not [string]::IsNullOrWhiteSpace($creds.Username) -and -not [string]::IsNullOrWhiteSpace($creds.Password)) {
        Write-UGSMSteamCMDLog -Level 'DEBUG' -Message 'Using configured Steam credentials for SteamCMD login.'
        return @('+login', $creds.Username, $creds.Password)
    }

    if ($AllowAnonymous) {
        Write-UGSMSteamCMDLog -Level 'DEBUG' -Message 'Using anonymous SteamCMD login.'
        return @('+login', 'anonymous')
    }

    Write-UGSMSteamCMDLog -Level 'ERROR' -Message 'Steam credentials are required but were not available.'
    throw 'Steam credentials are required but were not available.'
}
