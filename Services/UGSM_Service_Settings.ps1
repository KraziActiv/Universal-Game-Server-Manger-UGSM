function Write-UGSMSettingsLog {
    [CmdletBinding()]
    param(
        [ValidateSet('TRACE','DEBUG','INFO','WARN','ERROR','FATAL')]
        [string]$Level = 'INFO',
        [Parameter(Mandatory)]
        [string]$Message,
        [System.Exception]$Exception
    )

    try {
        if (Get-Command Write-UGSMLog -ErrorAction SilentlyContinue) {
            if ($Exception) {
                Write-UGSMLog -Level $Level -Category 'Settings' -Message $Message -Exception $Exception
            }
            else {
                Write-UGSMLog -Level $Level -Category 'Settings' -Message $Message
            }
        }
    }
    catch {}
}

function Get-UGSMSettingsPropertyValue {
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

function Get-UGSMGlobalSettingsModel {
    [CmdletBinding()]
    param()

    try {
        Write-UGSMSettingsLog -Level 'DEBUG' -Message 'Loading global settings model.'

        $settings = Get-UGSMGlobalSettings -CreateIfMissing
        $secrets = Get-UGSMSecrets

        $schemaVersion = Get-UGSMSettingsPropertyValue -Object $settings -Name 'SchemaVersion' -Default 1
        $theme = [string](Get-UGSMSettingsPropertyValue -Object $settings -Name 'Theme' -Default 'Dark')
        $steamCmdPath = [string](Get-UGSMSettingsPropertyValue -Object $settings -Name 'SteamCmdPath' -Default '')
        $steamCmdExePath = [string](Get-UGSMSettingsPropertyValue -Object $settings -Name 'SteamCmdExePath' -Default '')
        $steamCmdIsInstalled = [bool](Get-UGSMSettingsPropertyValue -Object $settings -Name 'SteamCmdIsInstalled' -Default $false)
        $steamUsername = [string](Get-UGSMSettingsPropertyValue -Object $settings -Name 'SteamUsername' -Default '')
        $hasSteamPasswordSetting = [bool](Get-UGSMSettingsPropertyValue -Object $settings -Name 'HasSteamPassword' -Default $false)
        $legacyDiscordWebhook = [string](Get-UGSMSettingsPropertyValue -Object $settings -Name 'GlobalDiscordWebhookUrl' -Default '')
        $hasGlobalDiscordSetting = [bool](Get-UGSMSettingsPropertyValue -Object $settings -Name 'HasGlobalDiscordWebhook' -Default $false)
        $profileBaseRoot = [string](Get-UGSMSettingsPropertyValue -Object $settings -Name 'ProfileBaseRoot' -Default '')
        $backupRoot = [string](Get-UGSMSettingsPropertyValue -Object $settings -Name 'BackupRoot' -Default '')
        $refreshSeconds = [int](Get-UGSMSettingsPropertyValue -Object $settings -Name 'RefreshSeconds' -Default 2)

        $steamPassword = [string](Get-UGSMSettingsPropertyValue -Object $secrets -Name 'SteamPassword' -Default '')
        $secretDiscordWebhook = [string](Get-UGSMSettingsPropertyValue -Object $secrets -Name 'DiscordWebhook' -Default '')
        $effectiveDiscordWebhook = if (-not [string]::IsNullOrWhiteSpace($secretDiscordWebhook)) { $secretDiscordWebhook } elseif (-not [string]::IsNullOrWhiteSpace($legacyDiscordWebhook)) { $legacyDiscordWebhook } else { '' }

        $model = [pscustomobject]@{
            SchemaVersion           = [int]$schemaVersion
            Theme                   = if ([string]::IsNullOrWhiteSpace($theme)) { 'Dark' } else { $theme }
            SteamCmdPath            = $steamCmdPath
            SteamCmdExePath         = $steamCmdExePath
            SteamCmdIsInstalled     = $steamCmdIsInstalled
            SteamUsername           = $steamUsername
            SteamPassword           = $steamPassword
            GlobalDiscordWebhookUrl = $effectiveDiscordWebhook
            HasSteamPassword        = ($hasSteamPasswordSetting -or -not [string]::IsNullOrWhiteSpace($steamPassword))
            HasGlobalDiscordWebhook = ($hasGlobalDiscordSetting -or -not [string]::IsNullOrWhiteSpace($effectiveDiscordWebhook))
            ProfileBaseRoot         = $profileBaseRoot
            BackupRoot              = $backupRoot
            RefreshSeconds          = $refreshSeconds
        }

        Write-UGSMSettingsLog -Level 'DEBUG' -Message ('Global settings model loaded. RefreshSeconds={0}; SteamCmdInstalled={1}' -f $model.RefreshSeconds, $model.SteamCmdIsInstalled)
        return $model
    }
    catch {
        Write-UGSMSettingsLog -Level 'ERROR' -Message 'Failed to load global settings model.' -Exception $_.Exception
        throw
    }
}


function Save-UGSMGlobalSecretsPreserveInstances {
    [CmdletBinding()]
    param(
        [string]$SteamPassword,
        [string]$DiscordWebhook
    )

    $path = Get-UGSMSecretsPath
    $dir = Split-Path -Path $path -Parent
    if (-not (Test-Path -LiteralPath $dir -PathType Container)) {
        New-Item -Path $dir -ItemType Directory -Force | Out-Null
    }

    $raw = [pscustomobject]@{}
    if (Test-Path -LiteralPath $path -PathType Leaf) {
        try {
            $existingText = Get-Content -LiteralPath $path -Raw -ErrorAction Stop
            if (-not [string]::IsNullOrWhiteSpace($existingText)) {
                $raw = $existingText | ConvertFrom-Json -ErrorAction Stop
            }
        }
        catch {
            $raw = [pscustomobject]@{}
        }
    }

    if (-not $raw.PSObject.Properties['SteamPassword']) {
        $raw | Add-Member -NotePropertyName 'SteamPassword' -NotePropertyValue $null -Force
    }
    if (-not $raw.PSObject.Properties['DiscordWebhook']) {
        $raw | Add-Member -NotePropertyName 'DiscordWebhook' -NotePropertyValue $null -Force
    }
    if (-not $raw.PSObject.Properties['InstanceDiscordWebhooks']) {
        $raw | Add-Member -NotePropertyName 'InstanceDiscordWebhooks' -NotePropertyValue ([pscustomobject]@{}) -Force
    }

    # Important: this function updates only global secrets.
    # It must preserve InstanceDiscordWebhooks so Settings Save does not wipe private per-instance webhooks.
    if (-not [string]::IsNullOrWhiteSpace([string]$SteamPassword)) {
        $raw.SteamPassword = Protect-UGSMSecret -Value ([string]$SteamPassword)
    }

    if (-not [string]::IsNullOrWhiteSpace([string]$DiscordWebhook)) {
        $raw.DiscordWebhook = Protect-UGSMSecret -Value ([string]$DiscordWebhook)
    }

    $raw | ConvertTo-Json -Depth 50 | Set-Content -LiteralPath $path -Encoding UTF8

    return [pscustomobject]@{
        HasSteamPassword  = -not [string]::IsNullOrWhiteSpace([string]$raw.SteamPassword)
        HasDiscordWebhook = -not [string]::IsNullOrWhiteSpace([string]$raw.DiscordWebhook)
    }
}

function Save-UGSMGlobalSettings {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [psobject]$InputObject
    )

    try {
        Write-UGSMSettingsLog -Level 'INFO' -Message 'Saving global settings.'

        $refreshSeconds = [int]$InputObject.RefreshSeconds
        if ($refreshSeconds -lt 1) {
            throw 'RefreshSeconds must be 1 or greater.'
        }

        $steamCmdPath = ([string]$InputObject.SteamCmdPath).Trim()
        $steamCmdExePath = ([string]$InputObject.SteamCmdExePath).Trim()
        $steamCmdIsInstalled = [bool]$InputObject.SteamCmdIsInstalled
        $theme = if ([string]::IsNullOrWhiteSpace([string]$InputObject.Theme)) { 'Dark' } else { [string]$InputObject.Theme }

        if ([string]::IsNullOrWhiteSpace($steamCmdExePath) -and -not [string]::IsNullOrWhiteSpace($steamCmdPath)) {
            $steamCmdExePath = Join-Path $steamCmdPath 'steamcmd.exe'
        }

        $secretSaveResult = Save-UGSMGlobalSecretsPreserveInstances `
            -SteamPassword ([string]$InputObject.SteamPassword) `
            -DiscordWebhook ([string]$InputObject.GlobalDiscordWebhookUrl)

        $settingsObject = [pscustomobject]@{
            SchemaVersion           = 1
            Theme                   = $theme
            SteamCmdPath            = $steamCmdPath
            SteamCmdExePath         = $steamCmdExePath
            SteamCmdIsInstalled     = $steamCmdIsInstalled
            SteamUsername           = [string]$InputObject.SteamUsername
            HasSteamPassword        = [bool]$secretSaveResult.HasSteamPassword
            GlobalDiscordWebhookUrl = ''
            HasGlobalDiscordWebhook = [bool]$secretSaveResult.HasDiscordWebhook
            ProfileBaseRoot         = [string]$InputObject.ProfileBaseRoot
            BackupRoot              = [string]$InputObject.BackupRoot
            RefreshSeconds          = $refreshSeconds
        }

        Save-UGSMGlobalSettingsFile -Settings $settingsObject

        Write-UGSMSettingsLog -Level 'INFO' -Message ('Global settings saved. RefreshSeconds={0}; SteamCmdInstalled={1}; HasSteamPassword={2}; HasDiscordWebhook={3}' -f $settingsObject.RefreshSeconds, $settingsObject.SteamCmdIsInstalled, $settingsObject.HasSteamPassword, $settingsObject.HasGlobalDiscordWebhook)

        return [pscustomobject]@{
            Settings = $settingsObject
        }
    }
    catch {
        Write-UGSMSettingsLog -Level 'ERROR' -Message 'Failed to save global settings.' -Exception $_.Exception
        throw
    }
}

function Save-UGSMGlobalSettingsValidated {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Settings
    )

    try {
        Write-UGSMSettingsLog -Level 'DEBUG' -Message 'Validating global settings before save.'

        $normalized = [pscustomobject]@{
            SchemaVersion           = 1
            Theme                   = if ([string]::IsNullOrWhiteSpace([string]$Settings.Theme)) { 'Dark' } else { [string]$Settings.Theme }
            SteamCmdPath            = ([string]$Settings.SteamCmdPath).Trim()
            SteamCmdExePath         = ([string]$Settings.SteamCmdExePath).Trim()
            SteamCmdIsInstalled     = [bool]$Settings.SteamCmdIsInstalled
            SteamUsername           = ([string]$Settings.SteamUsername).Trim()
            SteamPassword           = [string]$Settings.SteamPassword
            GlobalDiscordWebhookUrl = ([string]$Settings.GlobalDiscordWebhookUrl).Trim()
            ProfileBaseRoot         = ([string]$Settings.ProfileBaseRoot).Trim()
            BackupRoot              = ([string]$Settings.BackupRoot).Trim()
            RefreshSeconds          = [int]$Settings.RefreshSeconds
        }

        $validation = Test-UGSMGlobalSettings -Settings $normalized
        if (-not $validation.IsValid) {
            $message = ($validation.Errors -join [Environment]::NewLine)
            Write-UGSMSettingsLog -Level 'WARN' -Message ('Global settings validation failed: {0}' -f ($validation.Errors -join '; '))
            throw $message
        }

        Write-UGSMSettingsLog -Level 'DEBUG' -Message 'Global settings validation passed.'
        return (Save-UGSMGlobalSettings -InputObject $normalized)
    }
    catch {
        Write-UGSMSettingsLog -Level 'ERROR' -Message 'Global settings validation/save failed.' -Exception $_.Exception
        throw
    }
}
