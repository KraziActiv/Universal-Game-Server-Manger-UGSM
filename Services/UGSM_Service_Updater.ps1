# ============================================================
# UGSM App Updater Service
# Release-support updater:
# - checks a small remote manifest for the latest app version
# - logs every update check through the normal UGSM logger
# - opens the download page when the user chooses to update
#
# Expected manifest shape:
# {
#   "version": "2.0.1",
#   "downloadUrl": "https://example.com/UGSM.zip",
#   "releaseNotes": ["Fixed logging", "Improved UI startup"],
#   "mandatory": false
# }
#
# Supported aliases:
#   latestVersion, tag_name, name
#   url, html_url, releaseUrl
#   notes, body, changelog
# ============================================================

if (-not (Get-Variable -Name 'UGSM_UpdateManifestUrl' -Scope Script -ErrorAction SilentlyContinue)) {
    $script:UGSM_UpdateManifestUrl = ''
}

if (-not (Get-Variable -Name 'UGSM_CheckUpdatesOnStartup' -Scope Script -ErrorAction SilentlyContinue)) {
    # Keep off by default until the release manifest URL is finalized.
    $script:UGSM_CheckUpdatesOnStartup = $false
}

function Write-UGSMUpdaterLog {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Message,

        [ValidateSet('TRACE', 'DEBUG', 'INFO', 'WARN', 'ERROR', 'FATAL')]
        [string]$Level = 'INFO',

        [System.Exception]$Exception,

        [object]$Data
    )

    if (Get-Command Write-UGSMLog -ErrorAction SilentlyContinue) {
        Write-UGSMLog -Level $Level -Category 'Updater' -Message $Message -Exception $Exception -Data $Data
    }
    else {
        try { Write-Host ("[Updater] {0}" -f $Message) } catch { }
    }
}


function Get-UGSMUpdateStatePath {
    [CmdletBinding()]
    param()

    try {
        $localAppData = [Environment]::GetFolderPath('LocalApplicationData')
        if ([string]::IsNullOrWhiteSpace($localAppData)) {
            $localAppData = Join-Path $env:USERPROFILE 'AppData\Local'
        }

        $root = Join-Path $localAppData 'UGSM'
        if (-not (Test-Path -LiteralPath $root)) {
            New-Item -ItemType Directory -Path $root -Force | Out-Null
        }

        return (Join-Path $root 'UpdateState.json')
    }
    catch {
        $fallbackRoot = Join-Path (Get-Location).Path 'UGSM'
        if (-not (Test-Path -LiteralPath $fallbackRoot)) {
            New-Item -ItemType Directory -Path $fallbackRoot -Force | Out-Null
        }
        return (Join-Path $fallbackRoot 'UpdateState.json')
    }
}

function Get-UGSMUpdateState {
    [CmdletBinding()]
    param()

    try {
        $path = Get-UGSMUpdateStatePath
        if (-not (Test-Path -LiteralPath $path)) { return $null }

        $json = Get-Content -LiteralPath $path -Raw -ErrorAction Stop
        if ([string]::IsNullOrWhiteSpace($json)) { return $null }

        return ($json | ConvertFrom-Json -ErrorAction Stop)
    }
    catch {
        Write-UGSMUpdaterLog -Level 'WARN' -Message 'Could not read update state file.' -Exception $_.Exception
        return $null
    }
}

function Save-UGSMUpdateState {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$State
    )

    try {
        $path = Get-UGSMUpdateStatePath
        $State | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $path -Encoding UTF8 -Force
        Write-UGSMUpdaterLog -Level 'DEBUG' -Message ('Update state saved: {0}' -f $path)
        return $path
    }
    catch {
        Write-UGSMUpdaterLog -Level 'WARN' -Message 'Could not save update state file.' -Exception $_.Exception
        return $null
    }
}

function Get-UGSMCurrentAppVersion {
    [CmdletBinding()]
    param()

    $versionCandidates = @()

    $scriptVersion = Get-Variable -Name 'AppVersion' -Scope Script -ErrorAction SilentlyContinue
    if ($scriptVersion -and -not [string]::IsNullOrWhiteSpace([string]$scriptVersion.Value)) {
        $versionCandidates += [string]$scriptVersion.Value
    }

    $globalVersion = Get-Variable -Name 'AppVersion' -Scope Global -ErrorAction SilentlyContinue
    if ($globalVersion -and -not [string]::IsNullOrWhiteSpace([string]$globalVersion.Value)) {
        $versionCandidates += [string]$globalVersion.Value
    }

    if (-not [string]::IsNullOrWhiteSpace([string]$env:UGSM_APP_VERSION)) {
        $versionCandidates += [string]$env:UGSM_APP_VERSION
    }

    # Last-resort fallback only. The running executable/source AppVersion is the source of truth.
    # The state file exists for support/display/history and for early update testing.
    if ($versionCandidates.Count -eq 0) {
        $state = Get-UGSMUpdateState
        if ($state) {
            foreach ($name in @('CurrentVersion', 'InstalledVersion', 'AppVersion')) {
                $prop = $state.PSObject.Properties[$name]
                if ($prop -and -not [string]::IsNullOrWhiteSpace([string]$prop.Value)) {
                    $versionCandidates += [string]$prop.Value
                    break
                }
            }
        }
    }

    if ($versionCandidates.Count -gt 0) {
        return (($versionCandidates[0] -replace '^[vV]', '').Trim())
    }

    return '0.0.0'
}

function Get-UGSMUpdateManifestUrl {
    [CmdletBinding()]
    param()

    $configured = ''

    $scriptValue = Get-Variable -Name 'UGSM_UpdateManifestUrl' -Scope Script -ErrorAction SilentlyContinue
    if ($scriptValue -and -not [string]::IsNullOrWhiteSpace([string]$scriptValue.Value)) {
        $configured = [string]$scriptValue.Value
    }

    if ([string]::IsNullOrWhiteSpace($configured) -and -not [string]::IsNullOrWhiteSpace([string]$env:UGSM_UPDATE_MANIFEST_URL)) {
        $configured = [string]$env:UGSM_UPDATE_MANIFEST_URL
    }

    # Dev/source convenience: when running from source and no release URL has been injected yet,
    # default to the local Flask update server so the App Update button can be tested.
    if ([string]::IsNullOrWhiteSpace($configured)) {
        $isRelease = $false
        $releaseVar = Get-Variable -Name 'UGSM_IsReleaseBuild' -Scope Script -ErrorAction SilentlyContinue
        if ($releaseVar) { $isRelease = [bool]$releaseVar.Value }

        if (-not $isRelease) {
            $configured = 'http://localhost:9000/UGSM_Update/manifest.json'
        }
    }

    return $configured.Trim()
}

function ConvertTo-UGSMComparableVersion {
    [CmdletBinding()]
    param(
        [string]$Version
    )

    $text = ([string]$Version).Trim()
    $text = $text -replace '^[vV]', ''
    $text = $text -replace '[^0-9\.]', '.'
    $parts = @($text -split '\.' | Where-Object { $_ -match '^\d+$' } | Select-Object -First 4)

    while ($parts.Count -lt 4) {
        $parts += '0'
    }

    try {
        return [version]::new([int]$parts[0], [int]$parts[1], [int]$parts[2], [int]$parts[3])
    }
    catch {
        return [version]::new(0, 0, 0, 0)
    }
}

function Compare-UGSMAppVersion {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$CurrentVersion,

        [Parameter(Mandatory)]
        [string]$LatestVersion
    )

    $current = ConvertTo-UGSMComparableVersion -Version $CurrentVersion
    $latest = ConvertTo-UGSMComparableVersion -Version $LatestVersion
    return $latest.CompareTo($current)
}



function ConvertTo-UGSMCleanJsonText {
    [CmdletBinding()]
    param(
        [AllowNull()]
        [object]$Value
    )

    if ($null -eq $Value) { return '' }

    $text = [string]$Value

    # PowerShell 5 / Invoke-WebRequest can sometimes decode a UTF-8 BOM as the visible
    # three-character sequence "ï»¿" instead of the single U+FEFF BOM character.
    # Remove both forms before JSON validation/parsing.
    $text = $text.Trim()
    $text = $text.TrimStart([char]0xFEFF)
    $text = $text -replace '^(ï»¿)+', ''
    $text = $text -replace '^([\xEF][\xBB][\xBF])+', ''
    $text = $text.Trim()

    return $text
}

function ConvertFrom-UGSMManifestPayload {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Payload
    )

    if ($null -eq $Payload) { return $null }

    if ($Payload -is [string]) {
        $text = ConvertTo-UGSMCleanJsonText -Value $Payload
        if ([string]::IsNullOrWhiteSpace($text)) { return $null }
        try {
            return ($text | ConvertFrom-Json -ErrorAction Stop)
        }
        catch {
            throw "Update manifest response was text but not valid JSON. $($_.Exception.Message)"
        }
    }

    return $Payload
}

function Get-UGSMManifestPropertyValue {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Manifest,

        [Parameter(Mandatory)]
        [string[]]$Names
    )

    foreach ($name in $Names) {
        if ($null -eq $Manifest) { continue }

        if ($Manifest -is [hashtable] -and $Manifest.ContainsKey($name)) {
            $value = $Manifest[$name]
            if ($null -ne $value -and -not [string]::IsNullOrWhiteSpace([string]$value)) { return $value }
        }

        $prop = $Manifest.PSObject.Properties[$name]
        if ($prop) {
            $value = $prop.Value
            if ($null -ne $value -and -not [string]::IsNullOrWhiteSpace([string]$value)) { return $value }
        }
    }

    return $null
}

function ConvertFrom-UGSMUpdateManifest {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Manifest,

        [string]$ManifestUrl
    )

    $Manifest = ConvertFrom-UGSMManifestPayload -Payload $Manifest

    $latestVersionValue = Get-UGSMManifestPropertyValue -Manifest $Manifest -Names @('version', 'latestVersion', 'tag_name', 'name')
    $latestVersion = ''
    if ($null -ne $latestVersionValue) {
        $latestVersion = ([string]$latestVersionValue -replace '^[vV]', '').Trim()
    }

    $downloadUrlValue = Get-UGSMManifestPropertyValue -Manifest $Manifest -Names @('downloadUrl', 'download_url', 'url', 'html_url', 'releaseUrl', 'release_url')
    $downloadUrl = ''
    if ($null -ne $downloadUrlValue) {
        $downloadUrl = ([string]$downloadUrlValue).Trim()
    }

    # GitHub-style assets support. Prefer the first browser_download_url if present.
    if ([string]::IsNullOrWhiteSpace($downloadUrl) -and $Manifest -and $Manifest.PSObject.Properties['assets'] -and $Manifest.assets) {
        $asset = @($Manifest.assets | Where-Object { $_.PSObject.Properties['browser_download_url'] -and -not [string]::IsNullOrWhiteSpace([string]$_.browser_download_url) } | Select-Object -First 1)
        if ($asset) {
            $downloadUrl = [string]$asset.browser_download_url
        }
    }

    $releaseNotes = @()
    $notesValue = Get-UGSMManifestPropertyValue -Manifest $Manifest -Names @('releaseNotes', 'release_notes', 'notes', 'body', 'changelog')
    if ($null -ne $notesValue) {
        if ($notesValue -is [array]) {
            $releaseNotes = @($notesValue | ForEach-Object { [string]$_ } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
        }
        else {
            $releaseNotes = @(([string]$notesValue -split "(\r?\n)+") | ForEach-Object { $_.Trim() } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
        }
    }

    $mandatory = $false
    $mandatoryValue = Get-UGSMManifestPropertyValue -Manifest $Manifest -Names @('mandatory')
    if ($null -ne $mandatoryValue) {
        $mandatory = [bool]$mandatoryValue
    }

    $sha256 = ''
    $shaValue = Get-UGSMManifestPropertyValue -Manifest $Manifest -Names @('sha256', 'sha_256', 'checksum', 'fileHash', 'file_hash')
    if ($null -ne $shaValue) {
        $sha256 = ([string]$shaValue).Trim()
    }

    return [pscustomobject]@{
        LatestVersion = $latestVersion
        DownloadUrl   = $downloadUrl
        Sha256        = $sha256
        ReleaseNotes  = @($releaseNotes)
        Mandatory     = $mandatory
        ManifestUrl   = $ManifestUrl
        RawManifest   = $Manifest
        PublishedUtc  = [string](Get-UGSMManifestPropertyValue -Manifest $Manifest -Names @('publishedUtc', 'published_utc', 'publishedAt', 'published_at'))
    }
}

function Test-UGSMAppUpdate {
    [CmdletBinding()]
    param(
        [string]$ManifestUrl,
        [int]$TimeoutSeconds = 10
    )

    if ([string]::IsNullOrWhiteSpace($ManifestUrl)) {
        $ManifestUrl = Get-UGSMUpdateManifestUrl
    }

    $currentVersion = Get-UGSMCurrentAppVersion

    if ([string]::IsNullOrWhiteSpace($ManifestUrl)) {
        return [pscustomobject]@{
            Configured      = $false
            UpdateAvailable = $false
            CurrentVersion  = $currentVersion
            LatestVersion   = $currentVersion
            DownloadUrl     = ''
            ReleaseNotes    = @()
            Mandatory       = $false
            Message         = 'No update manifest URL is configured.'
        }
    }

    Write-UGSMUpdaterLog -Level 'INFO' -Message ('Checking for app updates. CurrentVersion={0}; Manifest={1}' -f $currentVersion, $ManifestUrl)

    try {
        $response = Invoke-WebRequest -Uri $ManifestUrl -Method Get -UseBasicParsing -ErrorAction Stop -TimeoutSec $TimeoutSeconds
        $rawContent = ''

        if ($response -and $response.PSObject.Properties['Content']) {
            $rawContent = [string]$response.Content
        }

        if ([string]::IsNullOrWhiteSpace($rawContent) -and $response -and $response.PSObject.Properties['RawContent']) {
            $rawContent = [string]$response.RawContent
        }

        $rawContent = ConvertTo-UGSMCleanJsonText -Value $rawContent

        # Some servers/routes send manifest.json as an attachment or with a generic content-type.
        # Invoke-WebRequest gives us the raw body so we can validate/parse it ourselves.
        if (-not ($rawContent.StartsWith('{') -or $rawContent.StartsWith('['))) {
            $preview = $rawContent
            if ($preview.Length -gt 300) { $preview = $preview.Substring(0, 300) }
            Write-UGSMUpdaterLog -Level 'ERROR' -Message ('Manifest response was not JSON. Prefix={0}' -f $preview) -Data ([pscustomobject]@{ ManifestUrl = $ManifestUrl })
            throw ('Update manifest response was not JSON. First characters: {0}' -f $preview)
        }

        $manifest = $rawContent | ConvertFrom-Json -ErrorAction Stop
        $normalized = ConvertFrom-UGSMUpdateManifest -Manifest $manifest -ManifestUrl $ManifestUrl

        if ([string]::IsNullOrWhiteSpace([string]$normalized.LatestVersion)) {
            throw 'Update manifest did not include a version/latestVersion/tag_name value.'
        }

        $comparison = Compare-UGSMAppVersion -CurrentVersion $currentVersion -LatestVersion ([string]$normalized.LatestVersion)
        $updateAvailable = ($comparison -gt 0)

        $message = if ($updateAvailable) {
            'Update available.'
        }
        else {
            'UGSM is up to date.'
        }

        $result = [pscustomobject]@{
            Configured      = $true
            UpdateAvailable = $updateAvailable
            CurrentVersion  = $currentVersion
            LatestVersion   = [string]$normalized.LatestVersion
            DownloadUrl     = [string]$normalized.DownloadUrl
            Sha256          = [string]$normalized.Sha256
            ReleaseNotes    = @($normalized.ReleaseNotes)
            Mandatory       = [bool]$normalized.Mandatory
            Message         = $message
            ManifestUrl     = $ManifestUrl
        }

        $stateObject = [pscustomobject]@{
            AppName         = 'UGSM'
            CurrentVersion  = $result.CurrentVersion
            InstalledVersion = $result.CurrentVersion
            LatestVersion   = $result.LatestVersion
            UpdateAvailable = $result.UpdateAvailable
            Mandatory       = $result.Mandatory
            LastCheckUtc    = (Get-Date).ToUniversalTime().ToString('o')
            PublishedUtc    = [string]$normalized.PublishedUtc
        }
        [void](Save-UGSMUpdateState -State $stateObject)

        Write-UGSMUpdaterLog -Level 'INFO' -Message ('Update check complete. Current={0}; Latest={1}; Available={2}' -f $result.CurrentVersion, $result.LatestVersion, [string]$result.UpdateAvailable) -Data ([pscustomobject]@{ Mandatory = $result.Mandatory })
        return $result
    }
    catch {
        Write-UGSMUpdaterLog -Level 'ERROR' -Message 'Update check failed.' -Exception $_.Exception -Data ([pscustomobject]@{ ManifestUrl = $ManifestUrl })
        throw
    }
}

function Open-UGSMUpdateDownload {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$UpdateResult
    )

    $url = ''
    if ($UpdateResult.PSObject.Properties['DownloadUrl']) {
        $url = [string]$UpdateResult.DownloadUrl
    }

    if ([string]::IsNullOrWhiteSpace($url)) {
        throw 'Update result did not include a download URL.'
    }

    Write-UGSMUpdaterLog -Level 'INFO' -Message 'Opening update download URL.'
    Start-Process $url | Out-Null
    return $true
}

function Get-UGSMUpdateWorkRoot {
    [CmdletBinding()]
    param()

    try {
        $localAppData = [Environment]::GetFolderPath('LocalApplicationData')
        if ([string]::IsNullOrWhiteSpace($localAppData)) {
            $localAppData = Join-Path $env:USERPROFILE 'AppData\Local'
        }

        $root = Join-Path $localAppData 'UGSM\Updates'
        if (-not (Test-Path -LiteralPath $root)) {
            New-Item -ItemType Directory -Path $root -Force | Out-Null
        }
        return $root
    }
    catch {
        $fallback = Join-Path (Get-Location).Path 'UGSM_Updates'
        if (-not (Test-Path -LiteralPath $fallback)) {
            New-Item -ItemType Directory -Path $fallback -Force | Out-Null
        }
        return $fallback
    }
}


function Remove-UGSMOldUpdateArtifacts {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$WorkRoot,
        [int]$KeepPerType = 2
    )

    if ([string]::IsNullOrWhiteSpace($WorkRoot)) { return }
    if (-not (Test-Path -LiteralPath $WorkRoot)) { return }

    if ($KeepPerType -lt 1) { $KeepPerType = 1 }

    $patterns = @(
        'UGSM_Update_*.exe',
        'UGSM_Backup_*.exe',
        'UGSM_UpdatePlan_*.json',
        'Apply-UGSMUpdate_*.ps1',
        'Apply-UGSMUpdate_*.log'
    )

    foreach ($pattern in $patterns) {
        try {
            $items = @(Get-ChildItem -LiteralPath $WorkRoot -Filter $pattern -File -ErrorAction SilentlyContinue | Sort-Object LastWriteTimeUtc -Descending)
            if ($items.Count -le $KeepPerType) { continue }

            $removeItems = @($items | Select-Object -Skip $KeepPerType)
            foreach ($item in $removeItems) {
                try {
                    Remove-Item -LiteralPath $item.FullName -Force -ErrorAction Stop
                    Write-UGSMUpdaterLog -Level 'DEBUG' -Message ('Removed old update artifact: {0}' -f $item.Name)
                }
                catch {
                    Write-UGSMUpdaterLog -Level 'WARN' -Message ('Could not remove old update artifact: {0}' -f $item.FullName) -Exception $_.Exception
                }
            }
        }
        catch {
            Write-UGSMUpdaterLog -Level 'WARN' -Message ('Update artifact cleanup failed for pattern: {0}' -f $pattern) -Exception $_.Exception
        }
    }
}

function Get-UGSMRunningExecutablePath {
    [CmdletBinding()]
    param()

    try {
        $path = [System.Diagnostics.Process]::GetCurrentProcess().MainModule.FileName
        if (-not [string]::IsNullOrWhiteSpace($path)) { return [string]$path }
    }
    catch { }

    try {
        if (-not [string]::IsNullOrWhiteSpace([string]$PSCommandPath)) { return [string]$PSCommandPath }
    }
    catch { }

    return ''
}

function Test-UGSMUpdateHash {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$FilePath,
        [string]$ExpectedSha256
    )

    if ([string]::IsNullOrWhiteSpace($ExpectedSha256)) {
        Write-UGSMUpdaterLog -Level 'WARN' -Message 'Update manifest did not include SHA256. Skipping hash verification.'
        return $true
    }

    $expected = ($ExpectedSha256 -replace '[^a-fA-F0-9]', '').ToUpperInvariant()
    if ([string]::IsNullOrWhiteSpace($expected)) {
        Write-UGSMUpdaterLog -Level 'WARN' -Message 'Update manifest SHA256 was empty after cleanup. Skipping hash verification.'
        return $true
    }

    $actual = (Get-FileHash -LiteralPath $FilePath -Algorithm SHA256 -ErrorAction Stop).Hash.ToUpperInvariant()
    if ($actual -ne $expected) {
        throw ('Downloaded update hash did not match manifest. Expected={0}; Actual={1}' -f $expected, $actual)
    }

    Write-UGSMUpdaterLog -Level 'INFO' -Message 'Downloaded update SHA256 verification passed.'
    return $true
}

function New-UGSMApplyUpdateScript {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$ScriptPath
    )

    $script = @'
param(
    [Parameter(Mandatory)][string]$PlanPath
)

$ErrorActionPreference = 'Stop'

function Write-ApplyLog {
    param([string]$Message)
    try {
        $stamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff'
        Add-Content -LiteralPath $script:LogPath -Value ("[{0}] {1}" -f $stamp, $Message) -Encoding UTF8
    }
    catch { }
}

try {
    $plan = Get-Content -LiteralPath $PlanPath -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
    $script:LogPath = [string]$plan.LogPath
    Write-ApplyLog 'UGSM update apply started.'

    $targetPath = [string]$plan.TargetPath
    $downloadPath = [string]$plan.DownloadPath
    $backupPath = [string]$plan.BackupPath
    $processId = [int]$plan.ProcessId

    if (-not (Test-Path -LiteralPath $downloadPath)) { throw "Downloaded update not found: $downloadPath" }
    if ([string]::IsNullOrWhiteSpace($targetPath)) { throw 'Target EXE path was empty.' }

    Write-ApplyLog ("Waiting for UGSM process to exit. PID={0}" -f $processId)
    for ($i = 0; $i -lt 120; $i++) {
        try {
            $p = Get-Process -Id $processId -ErrorAction SilentlyContinue
            if ($null -eq $p) { break }
        }
        catch { break }
        Start-Sleep -Seconds 1
    }

    try {
        $p = Get-Process -Id $processId -ErrorAction SilentlyContinue
        if ($p) { Write-ApplyLog 'UGSM process still appears to be running after wait timeout.' }
    }
    catch { }

    $targetDir = Split-Path -Path $targetPath -Parent
    if (-not (Test-Path -LiteralPath $targetDir)) { throw "Target directory not found: $targetDir" }

    if (Test-Path -LiteralPath $targetPath) {
        Write-ApplyLog ("Backing up old EXE to: {0}" -f $backupPath)
        Copy-Item -LiteralPath $targetPath -Destination $backupPath -Force -ErrorAction Stop
    }

    Write-ApplyLog ("Replacing EXE: {0}" -f $targetPath)
    Copy-Item -LiteralPath $downloadPath -Destination $targetPath -Force -ErrorAction Stop

    Write-ApplyLog 'Starting updated UGSM.'
    Start-Process -FilePath $targetPath -WorkingDirectory $targetDir | Out-Null
    Write-ApplyLog 'UGSM update apply completed.'
}
catch {
    Write-ApplyLog ("UGSM update apply failed: {0}" -f $_.Exception.Message)
    try {
        if ($backupPath -and (Test-Path -LiteralPath $backupPath) -and $targetPath) {
            Copy-Item -LiteralPath $backupPath -Destination $targetPath -Force -ErrorAction SilentlyContinue
            Write-ApplyLog 'Backup restored after failure.'
        }
    }
    catch { }
    exit 1
}
'@

    Set-Content -LiteralPath $ScriptPath -Value $script -Encoding UTF8 -Force
    return $ScriptPath
}

function Install-UGSMAppUpdate {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$UpdateResult
    )

    $url = ''
    if ($UpdateResult.PSObject.Properties['DownloadUrl']) { $url = [string]$UpdateResult.DownloadUrl }
    if ([string]::IsNullOrWhiteSpace($url)) { throw 'Update result did not include a download URL.' }

    $latestVersion = 'unknown'
    if ($UpdateResult.PSObject.Properties['LatestVersion'] -and -not [string]::IsNullOrWhiteSpace([string]$UpdateResult.LatestVersion)) {
        $latestVersion = ([string]$UpdateResult.LatestVersion -replace '[^0-9A-Za-z\._-]', '_')
    }

    $expectedSha = ''
    if ($UpdateResult.PSObject.Properties['Sha256']) { $expectedSha = [string]$UpdateResult.Sha256 }

    $targetPath = Get-UGSMRunningExecutablePath
    if ([string]::IsNullOrWhiteSpace($targetPath)) { throw 'Could not resolve the running UGSM executable path.' }

    $targetName = [System.IO.Path]::GetFileNameWithoutExtension($targetPath)
    $targetExt = [System.IO.Path]::GetExtension($targetPath)
    if ($targetExt -ne '.exe' -or $targetName -match '^(powershell|pwsh)$') {
        throw 'Automatic apply is only available from the built UGSM.exe. Source/dev mode can check updates, but cannot replace PowerShell.'
    }

    $workRoot = Get-UGSMUpdateWorkRoot
    # Keep one previous update attempt before creating the new one. After this install starts,
    # the Updates folder normally contains the current attempt plus the previous attempt.
    Remove-UGSMOldUpdateArtifacts -WorkRoot $workRoot -KeepPerType 1

    $stamp = Get-Date -Format 'yyyyMMdd_HHmmss_fff'
    $downloadPath = Join-Path $workRoot ('UGSM_Update_{0}_{1}.exe' -f $latestVersion, $stamp)
    $backupPath = Join-Path $workRoot ('UGSM_Backup_{0}_{1}.exe' -f $latestVersion, $stamp)
    $planPath = Join-Path $workRoot ('UGSM_UpdatePlan_{0}.json' -f $stamp)
    $scriptPath = Join-Path $workRoot ('Apply-UGSMUpdate_{0}.ps1' -f $stamp)
    $applyLogPath = Join-Path $workRoot ('Apply-UGSMUpdate_{0}.log' -f $stamp)

    Write-UGSMUpdaterLog -Level 'INFO' -Message ('Downloading UGSM update v{0}.' -f $latestVersion)
    Invoke-WebRequest -Uri $url -OutFile $downloadPath -UseBasicParsing -ErrorAction Stop -TimeoutSec 120

    if (-not (Test-Path -LiteralPath $downloadPath)) { throw 'Update download did not create the expected file.' }
    [void](Test-UGSMUpdateHash -FilePath $downloadPath -ExpectedSha256 $expectedSha)

    [void](New-UGSMApplyUpdateScript -ScriptPath $scriptPath)

    $plan = [pscustomobject]@{
        AppName      = 'UGSM'
        Version      = $latestVersion
        TargetPath   = $targetPath
        DownloadPath = $downloadPath
        BackupPath   = $backupPath
        ProcessId    = [System.Diagnostics.Process]::GetCurrentProcess().Id
        LogPath      = $applyLogPath
        CreatedUtc   = (Get-Date).ToUniversalTime().ToString('o')
    }
    $plan | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $planPath -Encoding UTF8 -Force

    Write-UGSMUpdaterLog -Level 'INFO' -Message ('Starting external update apply script for v{0}.' -f $latestVersion)
    $arguments = @(
        '-NoProfile',
        '-ExecutionPolicy', 'Bypass',
        '-File', $scriptPath,
        '-PlanPath', $planPath
    )
    Start-Process -FilePath 'powershell.exe' -ArgumentList $arguments -WindowStyle Hidden | Out-Null

    return [pscustomobject]@{
        Started      = $true
        Version      = $latestVersion
        TargetPath   = $targetPath
        DownloadPath = $downloadPath
        PlanPath     = $planPath
        ScriptPath   = $scriptPath
        LogPath      = $applyLogPath
    }
}

