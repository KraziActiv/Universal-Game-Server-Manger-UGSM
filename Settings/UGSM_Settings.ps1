# Settings

# Global settings for UGSM

function Get-UGSMAppDataRoot {
    $basePath = [Environment]::GetFolderPath([Environment+SpecialFolder]::LocalApplicationData)
    if ([string]::IsNullOrWhiteSpace($basePath)) {
        throw 'Unable to resolve LocalApplicationData path.'
    }

    $appRoot = Join-Path $basePath 'UGSM'
    if (-not (Test-Path -LiteralPath $appRoot)) {
        $null = New-Item -Path $appRoot -ItemType Directory -Force
    }

    return $appRoot
}


$script:UGSM_GlobalSettingsCache = $null
$script:UGSM_GlobalSettingsCacheLoadedAt = [datetime]::MinValue
$script:UGSM_GlobalSettingsCacheTtlSeconds = 10

function Clear-UGSMGlobalSettingsCache {
    [CmdletBinding()]
    param()

    $script:UGSM_GlobalSettingsCache = $null
    $script:UGSM_GlobalSettingsCacheLoadedAt = [datetime]::MinValue
}

function Get-UGSMGlobalSettingsPath {
    return (Join-Path (Get-UGSMAppDataRoot) 'settings.json')
}

function Get-UGSMSecretsPath {
    return (Join-Path (Get-UGSMAppDataRoot) 'secrets.json')
}

function New-UGSMDefaultGlobalSettings {
    return [pscustomobject]@{
        SchemaVersion           = 1
        Theme                   = 'Dark'
        SteamCmdPath            = ''
        SteamCmdExePath         = ''
        SteamCmdIsInstalled     = $false
        SteamUsername           = ''
        HasSteamPassword        = $false
        GlobalDiscordWebhookUrl = ''
        HasGlobalDiscordWebhook = $false
        ProfileBaseRoot         = ''
        BackupRoot              = ''
        RefreshSeconds          = 2
    }
}

function Merge-UGSMGlobalSettingsWithDefaults {
    param(
        [Parameter(Mandatory)]
        [object]$Settings
    )

    $defaults = New-UGSMDefaultGlobalSettings
    $merged = [ordered]@{}

    foreach ($property in $defaults.PSObject.Properties.Name) {
        $propertyRef = $Settings.PSObject.Properties[$property]

        if ($null -ne $propertyRef) {
            $value = $propertyRef.Value
        }
        else {
            $value = $null
        }

        if ($null -eq $value) {
            $value = $defaults.$property
        }

        $merged[$property] = $value
    }

    return [pscustomobject]$merged
}

function Test-UGSMGlobalSettings {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Settings
    )

    $errors = New-Object System.Collections.Generic.List[string]

    if ([string]::IsNullOrWhiteSpace([string]$Settings.Theme)) {
        [void]$errors.Add('Theme is required.')
    }

    $refreshSeconds = [int]$Settings.RefreshSeconds
    if ($refreshSeconds -lt 1) {
        [void]$errors.Add('RefreshSeconds must be 1 or greater.')
    }

    foreach ($pathValue in @([string]$Settings.SteamCmdPath, [string]$Settings.ProfileBaseRoot, [string]$Settings.BackupRoot)) {
        if (-not [string]::IsNullOrWhiteSpace($pathValue)) {
            try { $null = [System.IO.Path]::GetFullPath($pathValue) }
            catch { [void]$errors.Add("Invalid path: $pathValue") }
        }
    }

    return [pscustomobject]@{
        IsValid = ($errors.Count -eq 0)
        Errors  = @($errors)
    }
}

function Get-UGSMGlobalSettings {
    [CmdletBinding()]
    param(
        [switch]$CreateIfMissing,
        [switch]$ForceRefresh
    )

    $now = [datetime]::UtcNow
    if (-not $ForceRefresh -and $script:UGSM_GlobalSettingsCache -and $script:UGSM_GlobalSettingsCacheLoadedAt -ne [datetime]::MinValue) {
        $cacheAgeSeconds = ($now - $script:UGSM_GlobalSettingsCacheLoadedAt).TotalSeconds
        if ($cacheAgeSeconds -ge 0 -and $cacheAgeSeconds -lt $script:UGSM_GlobalSettingsCacheTtlSeconds) {
            return $script:UGSM_GlobalSettingsCache.PSObject.Copy()
        }
    }

    $settingsPath = Get-UGSMGlobalSettingsPath

    if (-not (Test-Path -LiteralPath $settingsPath)) {
        $defaults = New-UGSMDefaultGlobalSettings
        if ($CreateIfMissing) {
            Save-UGSMGlobalSettingsFile -Settings $defaults
        }
        $mergedDefaults = Merge-UGSMGlobalSettingsWithDefaults -Settings $defaults
        $script:UGSM_GlobalSettingsCache = $mergedDefaults
        $script:UGSM_GlobalSettingsCacheLoadedAt = $now
        return $mergedDefaults.PSObject.Copy()
    }

    $rawJson = Get-Content -LiteralPath $settingsPath -Raw -ErrorAction Stop
    if ([string]::IsNullOrWhiteSpace($rawJson)) {
        $defaults = New-UGSMDefaultGlobalSettings
        if ($CreateIfMissing) {
            Save-UGSMGlobalSettingsFile -Settings $defaults
        }
        $mergedDefaults = Merge-UGSMGlobalSettingsWithDefaults -Settings $defaults
        $script:UGSM_GlobalSettingsCache = $mergedDefaults
        $script:UGSM_GlobalSettingsCacheLoadedAt = $now
        return $mergedDefaults.PSObject.Copy()
    }

    $parsed = $rawJson | ConvertFrom-Json -ErrorAction Stop
    $merged = Merge-UGSMGlobalSettingsWithDefaults -Settings $parsed
    $script:UGSM_GlobalSettingsCache = $merged
    $script:UGSM_GlobalSettingsCacheLoadedAt = $now
    return $merged.PSObject.Copy()
}

function Save-UGSMGlobalSettingsFile {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [psobject]$Settings
    )

    $settingsPath = Get-UGSMGlobalSettingsPath
    $settingsDir = Split-Path -Path $settingsPath -Parent

    if (-not (Test-Path -LiteralPath $settingsDir)) {
        New-Item -Path $settingsDir -ItemType Directory -Force | Out-Null
    }

    $Settings |
    ConvertTo-Json -Depth 10 |
    Set-Content -LiteralPath $settingsPath -Encoding UTF8

    $script:UGSM_GlobalSettingsCache = Merge-UGSMGlobalSettingsWithDefaults -Settings $Settings
    $script:UGSM_GlobalSettingsCacheLoadedAt = [datetime]::UtcNow
}



function New-UGSMDefaultDiscordSettings {
    return [pscustomobject]@{
        WebhookUrl         = ''
        NotifyOnStart      = $false
        NotifyOnStop       = $false
        ShowInDashboard    = $false
    }
}

function Merge-UGSMDiscordSettingsWithDefaults {
    [CmdletBinding()]
    param(
        [AllowNull()]
        [object]$Discord
    )

    $defaults = New-UGSMDefaultDiscordSettings
    if ($null -eq $Discord) {
        return $defaults
    }

    $merged = [ordered]@{}
    foreach ($property in $defaults.PSObject.Properties.Name) {
        $propertyRef = $Discord.PSObject.Properties[$property]
        if ($null -ne $propertyRef) {
            $value = $propertyRef.Value
        }
        else {
            $value = $defaults.$property
        }

        if ($null -eq $value) {
            $value = $defaults.$property
        }

        $merged[$property] = $value
    }

    return [pscustomobject]$merged
}

function Get-UGSMNormalizedInstanceDiscordSettings {
    [CmdletBinding()]
    param(
        [AllowNull()]
        [object]$Instance
    )

    $sourceDiscord = $null
    if ($null -ne $Instance) {
        if ($Instance.PSObject.Properties['Discord'] -and $null -ne $Instance.Discord) {
            $sourceDiscord = $Instance.Discord
        }
        else {
            $sourceDiscord = [pscustomobject]@{
                WebhookUrl      = if ($Instance.PSObject.Properties['DiscordWebhookUrl']) { [string]$Instance.DiscordWebhookUrl } else { '' }
                NotifyOnStart   = if ($Instance.PSObject.Properties['DiscordNotifyStart']) { [bool]$Instance.DiscordNotifyStart } else { $false }
                NotifyOnStop    = if ($Instance.PSObject.Properties['DiscordNotifyStop']) { [bool]$Instance.DiscordNotifyStop } else { $false }
                ShowInDashboard = if ($Instance.PSObject.Properties['DiscordVisible']) { [bool]$Instance.DiscordVisible } else { $false }
            }
        }
    }

    $normalized = Merge-UGSMDiscordSettingsWithDefaults -Discord $sourceDiscord

    return [pscustomobject]@{
        WebhookUrl         = ([string]$normalized.WebhookUrl).Trim()
        NotifyOnStart      = [bool]$normalized.NotifyOnStart
        NotifyOnStop       = [bool]$normalized.NotifyOnStop
        ShowInDashboard    = [bool]$normalized.ShowInDashboard
    }
}

function Set-UGSMInstanceDiscordSettings {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Instance,

        [AllowNull()]
        [object]$Discord
    )

    $normalized = Merge-UGSMDiscordSettingsWithDefaults -Discord $Discord
    $normalizedObject = [pscustomobject]@{
        WebhookUrl         = ([string]$normalized.WebhookUrl).Trim()
        NotifyOnStart      = [bool]$normalized.NotifyOnStart
        NotifyOnStop       = [bool]$normalized.NotifyOnStop
        ShowInDashboard    = [bool]$normalized.ShowInDashboard
    }

    if ($Instance.PSObject.Properties['Discord']) {
        $Instance.Discord = $normalizedObject
    }
    else {
        $Instance | Add-Member -NotePropertyName 'Discord' -NotePropertyValue $normalizedObject -Force
    }

    if ($Instance.PSObject.Properties['DiscordWebhookUrl']) {
        $Instance.DiscordWebhookUrl = [string]$normalizedObject.WebhookUrl
    }
    else {
        $Instance | Add-Member -NotePropertyName 'DiscordWebhookUrl' -NotePropertyValue ([string]$normalizedObject.WebhookUrl) -Force
    }

    if ($Instance.PSObject.Properties['DiscordNotifyStart']) {
        $Instance.DiscordNotifyStart = [bool]$normalizedObject.NotifyOnStart
    }
    else {
        $Instance | Add-Member -NotePropertyName 'DiscordNotifyStart' -NotePropertyValue ([bool]$normalizedObject.NotifyOnStart) -Force
    }

    if ($Instance.PSObject.Properties['DiscordNotifyStop']) {
        $Instance.DiscordNotifyStop = [bool]$normalizedObject.NotifyOnStop
    }
    else {
        $Instance | Add-Member -NotePropertyName 'DiscordNotifyStop' -NotePropertyValue ([bool]$normalizedObject.NotifyOnStop) -Force
    }

    if ($Instance.PSObject.Properties['DiscordVisible']) {
        $Instance.DiscordVisible = [bool]$normalizedObject.ShowInDashboard
    }
    else {
        $Instance | Add-Member -NotePropertyName 'DiscordVisible' -NotePropertyValue ([bool]$normalizedObject.ShowInDashboard) -Force
    }

    return $Instance
}

function Get-UGSMEffectiveDiscordWebhookUrl {
    [CmdletBinding()]
    param(
        [AllowNull()]
        [object]$Instance,

        [AllowNull()]
        [object]$GlobalSettingsModel
    )

    $instanceDiscord = Get-UGSMNormalizedInstanceDiscordSettings -Instance $Instance
    if (-not [string]::IsNullOrWhiteSpace([string]$instanceDiscord.WebhookUrl)) {
        return ([string]$instanceDiscord.WebhookUrl).Trim()
    }

    if ($null -eq $GlobalSettingsModel) {
        if (Get-Command -Name Get-UGSMGlobalSettingsModel -ErrorAction SilentlyContinue) {
            try {
                $GlobalSettingsModel = Get-UGSMGlobalSettingsModel
            }
            catch {
                $GlobalSettingsModel = $null
            }
        }
        elseif (Get-Command -Name Get-UGSMSecrets -ErrorAction SilentlyContinue) {
            try {
                $secrets = Get-UGSMSecrets
                if ($secrets) {
                    return ([string]$secrets.DiscordWebhook).Trim()
                }
            }
            catch {}
        }
    }

    if ($null -ne $GlobalSettingsModel -and $GlobalSettingsModel.PSObject.Properties['GlobalDiscordWebhookUrl']) {
        return ([string]$GlobalSettingsModel.GlobalDiscordWebhookUrl).Trim()
    }

    return ''
}

# Secrets

try {
    Add-Type -AssemblyName System.Security -ErrorAction Stop
}
catch {
    throw "Unable to load System.Security assembly required for secret protection."
}

function Protect-UGSMSecret {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Value
    )

    $bytes = [System.Text.Encoding]::UTF8.GetBytes($Value)

    $protectedBytes = [System.Security.Cryptography.ProtectedData]::Protect(
        $bytes,
        $null,
        [System.Security.Cryptography.DataProtectionScope]::CurrentUser
    )

    return [Convert]::ToBase64String($protectedBytes)
}

function Unprotect-UGSMSecret {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Value
    )

    $protectedBytes = [Convert]::FromBase64String($Value)

    $bytes = [System.Security.Cryptography.ProtectedData]::Unprotect(
        $protectedBytes,
        $null,
        [System.Security.Cryptography.DataProtectionScope]::CurrentUser
    )

    return [System.Text.Encoding]::UTF8.GetString($bytes)
}

function Save-UGSMSecrets {
    [CmdletBinding()]
    param(
        [string]$SteamPassword,
        [string]$DiscordWebhook
    )

    $path = Get-UGSMSecretsPath

    $rawExisting = $null
    if (Test-Path -LiteralPath $path -PathType Leaf) {
        try {
            $rawText = Get-Content -LiteralPath $path -Raw -ErrorAction Stop
            if (-not [string]::IsNullOrWhiteSpace($rawText)) {
                $rawExisting = $rawText | ConvertFrom-Json -ErrorAction Stop
            }
        }
        catch {
            $rawExisting = $null
        }
    }

    $existing = Get-UGSMSecrets

    $finalSteamPassword = if (-not [string]::IsNullOrWhiteSpace($SteamPassword)) {
        $SteamPassword
    }
    elseif ($null -ne $existing) {
        $existing.SteamPassword
    }
    else {
        $null
    }

    $finalDiscordWebhook = if (-not [string]::IsNullOrWhiteSpace($DiscordWebhook)) {
        $DiscordWebhook
    }
    elseif ($null -ne $existing) {
        $existing.DiscordWebhook
    }
    else {
        $null
    }

    $instanceDiscordWebhooks = [pscustomobject]@{}
    if ($rawExisting -and $rawExisting.PSObject.Properties['InstanceDiscordWebhooks'] -and $null -ne $rawExisting.InstanceDiscordWebhooks) {
        $instanceDiscordWebhooks = $rawExisting.InstanceDiscordWebhooks
    }

    $secretObject = [pscustomobject]@{
        SteamPassword            = $null
        DiscordWebhook           = $null
        InstanceDiscordWebhooks  = $instanceDiscordWebhooks
    }

    if (-not [string]::IsNullOrWhiteSpace($finalSteamPassword)) {
        $secretObject.SteamPassword = Protect-UGSMSecret -Value $finalSteamPassword
    }

    if (-not [string]::IsNullOrWhiteSpace($finalDiscordWebhook)) {
        $secretObject.DiscordWebhook = Protect-UGSMSecret -Value $finalDiscordWebhook
    }

    $secretObject |
        ConvertTo-Json -Depth 20 |
        Set-Content -Path $path -Encoding UTF8

    return [pscustomobject]@{
        HasSteamPassword  = -not [string]::IsNullOrWhiteSpace($finalSteamPassword)
        HasDiscordWebhook = -not [string]::IsNullOrWhiteSpace($finalDiscordWebhook)
    }
}

function Get-UGSMObjectPropertyValue {
    [CmdletBinding()]
    param(
        [object]$Object,
        [Parameter(Mandatory)]
        [string]$Name,
        [object]$Default = $null
    )

    if ($null -eq $Object) {
        return $Default
    }

    try {
        $property = $Object.PSObject.Properties[$Name]
        if ($null -ne $property) {
            return $property.Value
        }
    }
    catch {}

    return $Default
}

function Get-UGSMSecrets {
    $path = Get-UGSMSecretsPath

    if (-not (Test-Path -LiteralPath $path)) {
        return [pscustomobject]@{
            SteamPassword           = $null
            DiscordWebhook          = $null
            InstanceDiscordWebhooks = [pscustomobject]@{}
        }
    }

    try {
        $raw = Get-Content -LiteralPath $path -Raw | ConvertFrom-Json
    }
    catch {
        Write-Warning "Failed to read UGSM secrets file: $path"
        return [pscustomobject]@{
            SteamPassword           = $null
            DiscordWebhook          = $null
            InstanceDiscordWebhooks = [pscustomobject]@{}
        }
    }

    $protectedSteamPassword = Get-UGSMObjectPropertyValue -Object $raw -Name 'SteamPassword' -Default $null
    $protectedDiscordWebhook = Get-UGSMObjectPropertyValue -Object $raw -Name 'DiscordWebhook' -Default $null
    $instanceDiscordWebhooks = Get-UGSMObjectPropertyValue -Object $raw -Name 'InstanceDiscordWebhooks' -Default ([pscustomobject]@{})

    $steamPassword = $null
    $discordWebhook = $null

    if (-not [string]::IsNullOrWhiteSpace([string]$protectedSteamPassword)) {
        try { $steamPassword = Unprotect-UGSMSecret ([string]$protectedSteamPassword) }
        catch { $steamPassword = $null }
    }

    if (-not [string]::IsNullOrWhiteSpace([string]$protectedDiscordWebhook)) {
        try { $discordWebhook = Unprotect-UGSMSecret ([string]$protectedDiscordWebhook) }
        catch { $discordWebhook = $null }
    }

    if ($null -eq $instanceDiscordWebhooks) {
        $instanceDiscordWebhooks = [pscustomobject]@{}
    }

    return [pscustomobject]@{
        SteamPassword           = $steamPassword
        DiscordWebhook          = $discordWebhook
        InstanceDiscordWebhooks = $instanceDiscordWebhooks
    }
}
