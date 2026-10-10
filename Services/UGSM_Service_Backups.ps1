# UGSM Service Backups
# Shared backup service for UGSM-managed files only.
#
# Design:
# - Uses global BackupRoot from UGSM settings.
# - Stores backups as: <BackupRoot>\<GameId>\<InstanceName>\<Timestamp>\...
# - Copies only explicit file targets passed by game modules.
# - Keeps latest 3 backup folders per game instance by default.
# - Logs safe summaries only; no full personal paths or secrets.

$script:UGSM_BackupDefaultRetention = 3

function ConvertTo-UGSMBackupSafeLogText {
    [CmdletBinding()]
    param(
        [AllowNull()][object]$Value
    )

    if ($null -eq $Value) { return '' }
    $text = [string]$Value
    if ([string]::IsNullOrWhiteSpace($text)) { return $text }

    try {
        if (Get-Command -Name ConvertTo-UGSMDisplayPath -ErrorAction SilentlyContinue) {
            $text = ConvertTo-UGSMDisplayPath -Path $text
        }

        $roots = @(
            @{ Value = [Environment]::GetFolderPath('LocalApplicationData'); Token = '%LOCALAPPDATA%' },
            @{ Value = $env:USERPROFILE; Token = '%USERPROFILE%' }
        )

        foreach ($root in $roots) {
            $rootValue = [string]$root.Value
            if (-not [string]::IsNullOrWhiteSpace($rootValue)) {
                $text = [regex]::Replace($text, [regex]::Escape($rootValue.TrimEnd('\')), [string]$root.Token, 'IgnoreCase')
            }
        }

        if (-not [string]::IsNullOrWhiteSpace($env:SystemDrive)) {
            $usersPrefix = [regex]::Escape(($env:SystemDrive.TrimEnd('\') + '\Users\'))
            $text = [regex]::Replace($text, "(?i)$usersPrefix[^`r`n]+", '%USERPROFILE%')
        }

        $settings = $null
        if (Get-Command -Name Get-UGSMGlobalSettings -ErrorAction SilentlyContinue) {
            try { $settings = Get-UGSMGlobalSettings -CreateIfMissing } catch { $settings = $null }
        }

        $knownRoots = @(
            @{ Value = $(if ($settings -and $settings.PSObject.Properties['BackupRoot']) { [string]$settings.BackupRoot } else { '' }); Token = '%UGSM_BACKUPS%' },
            @{ Value = $(if ($settings -and $settings.PSObject.Properties['ProfileBaseRoot']) { [string]$settings.ProfileBaseRoot } else { '' }); Token = '%UGSM_PROFILES%' },
            @{ Value = $(if ($settings -and $settings.PSObject.Properties['SteamCmdPath']) { [string]$settings.SteamCmdPath } else { '' }); Token = '%UGSM_STEAM%' }
        )

        foreach ($root in $knownRoots) {
            $rootValue = [string]$root.Value
            if (-not [string]::IsNullOrWhiteSpace($rootValue)) {
                $text = [regex]::Replace($text, [regex]::Escape($rootValue.TrimEnd('\')), [string]$root.Token, 'IgnoreCase')
            }
        }

        $text = [regex]::Replace($text, '(?i)https://(?:canary\.|ptb\.)?discord(?:app)?\.com/api/webhooks/[^\s''"<>]+', '<redacted-discord-webhook>')
        $text = [regex]::Replace($text, '(?i)(\+login\s+)(?!anonymous\b)\S+(\s+)\S+', '$1<redacted>$2<redacted>')
        $text = [regex]::Replace(
            $text,
            '(?i)\b(password|passwd|pass|token|api[_-]?key|apikey|secret|gslt|login[_-]?token|private[_-]?token|webhook(?:url)?)\b\s*[:=]\s*("[^"]*"|''[^'']*''|[^\s;,]+)',
            '$1=<redacted>'
        )
    }
    catch {
        # Redaction must never break backup operations.
    }

    return $text
}

function Write-UGSMBackupLog {
    [CmdletBinding()]
    param(
        [ValidateSet('TRACE','DEBUG','INFO','WARN','ERROR')]
        [string]$Level = 'INFO',

        [Parameter(Mandatory)][string]$Message,

        [System.Exception]$Exception
    )

    $safeMessage = ConvertTo-UGSMBackupSafeLogText -Value $Message
    if ($Exception) {
        $exceptionType = $Exception.GetType().Name
        $exceptionMessage = ConvertTo-UGSMBackupSafeLogText -Value $Exception.Message
        $safeMessage = "$safeMessage Exception=$exceptionType`: $exceptionMessage"
    }

    if (Get-Command -Name Write-UGSMLog -ErrorAction SilentlyContinue) {
        Write-UGSMLog -Level $Level -Category 'Service:Backups' -Message $safeMessage
    }
}

function Get-UGSMBackupRoot {
    [CmdletBinding()]
    param()

    $backupRoot = ''
    if (Get-Command -Name Get-UGSMGlobalSettings -ErrorAction SilentlyContinue) {
        try {
            $settings = Get-UGSMGlobalSettings -CreateIfMissing
            if ($settings -and $settings.PSObject.Properties['BackupRoot']) {
                $backupRoot = [string]$settings.BackupRoot
            }
        }
        catch {
            Write-UGSMBackupLog -Level 'WARN' -Message 'Unable to read global BackupRoot for backup service.' -Exception $_.Exception
        }
    }

    if ([string]::IsNullOrWhiteSpace($backupRoot)) {
        Write-UGSMBackupLog -Level 'WARN' -Message 'Backup skipped because global BackupRoot is not configured.'
        return $null
    }

    try { return [System.IO.Path]::GetFullPath($backupRoot) }
    catch {
        Write-UGSMBackupLog -Level 'WARN' -Message 'Backup skipped because global BackupRoot is invalid.' -Exception $_.Exception
        return $null
    }
}

function ConvertTo-UGSMSafeBackupPathSegment {
    [CmdletBinding()]
    param(
        [AllowNull()][object]$Value,
        [string]$Fallback = 'Unknown'
    )

    $segment = [string]$Value
    if ([string]::IsNullOrWhiteSpace($segment)) { $segment = $Fallback }

    foreach ($c in [System.IO.Path]::GetInvalidFileNameChars()) {
        $segment = $segment.Replace([string]$c, '_')
    }

    $segment = $segment.Trim()
    if ([string]::IsNullOrWhiteSpace($segment)) { $segment = $Fallback }
    return $segment
}

function Get-UGSMBackupInstanceName {
    [CmdletBinding()]
    param(
        [AllowNull()][object]$Instance,
        [AllowNull()][string]$Fallback
    )

    foreach ($propertyName in @('Name','InstanceName','ProfileName','Id')) {
        try {
            if ($Instance -and $Instance.PSObject.Properties[$propertyName]) {
                $value = [string]$Instance.$propertyName
                if (-not [string]::IsNullOrWhiteSpace($value)) { return $value }
            }
        }
        catch {}
    }

    if (-not [string]::IsNullOrWhiteSpace($Fallback)) { return $Fallback }
    return 'Default'
}

function Resolve-UGSMBackupTargetList {
    [CmdletBinding()]
    param(
        [AllowNull()][object[]]$Targets
    )

    $resolved = New-Object System.Collections.Generic.List[object]
    foreach ($target in @($Targets)) {
        if ($null -eq $target) { continue }

        $sourcePath = ''
        $relativePath = ''
        $label = ''

        if ($target -is [string]) {
            $sourcePath = [string]$target
        }
        else {
            foreach ($name in @('SourcePath','Path','FullName')) {
                try {
                    if ($target.PSObject.Properties[$name] -and -not [string]::IsNullOrWhiteSpace([string]$target.$name)) {
                        $sourcePath = [string]$target.$name
                        break
                    }
                } catch {}
            }
            foreach ($name in @('RelativePath','BackupRelativePath','Name')) {
                try {
                    if ($target.PSObject.Properties[$name] -and -not [string]::IsNullOrWhiteSpace([string]$target.$name)) {
                        $relativePath = [string]$target.$name
                        break
                    }
                } catch {}
            }
            try { if ($target.PSObject.Properties['Label']) { $label = [string]$target.Label } } catch {}
        }

        if ([string]::IsNullOrWhiteSpace($sourcePath)) { continue }
        if (-not (Test-Path -LiteralPath $sourcePath -PathType Leaf)) { continue }

        if ([string]::IsNullOrWhiteSpace($relativePath)) {
            $relativePath = Split-Path -Leaf $sourcePath
        }

        $relativePath = $relativePath.TrimStart('\','/')
        if ([string]::IsNullOrWhiteSpace($relativePath)) { $relativePath = Split-Path -Leaf $sourcePath }

        [void]$resolved.Add([pscustomobject]@{
            SourcePath   = [System.IO.Path]::GetFullPath($sourcePath)
            RelativePath = $relativePath
            Label        = $label
        })
    }

    return @($resolved.ToArray())
}

function Invoke-UGSMBackupRetention {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$InstanceBackupRoot,
        [int]$KeepLatest = $script:UGSM_BackupDefaultRetention
    )

    if ($KeepLatest -lt 1) { $KeepLatest = 1 }
    if (-not (Test-Path -LiteralPath $InstanceBackupRoot -PathType Container)) { return }

    try {
        $backups = @(Get-ChildItem -LiteralPath $InstanceBackupRoot -Directory -ErrorAction SilentlyContinue | Sort-Object Name -Descending)
        if (@($backups).Count -le $KeepLatest) { return }

        foreach ($old in @($backups | Select-Object -Skip $KeepLatest)) {
            try {
                Remove-Item -LiteralPath $old.FullName -Recurse -Force -ErrorAction Stop
                Write-UGSMBackupLog -Level 'INFO' -Message ('Backup retention removed old backup folder. InstanceBackupRoot=' + $InstanceBackupRoot + '; Removed=' + $old.Name)
            }
            catch {
                Write-UGSMBackupLog -Level 'WARN' -Message ('Backup retention could not remove old backup folder. InstanceBackupRoot=' + $InstanceBackupRoot + '; Folder=' + $old.Name) -Exception $_.Exception
            }
        }
    }
    catch {
        Write-UGSMBackupLog -Level 'WARN' -Message ('Backup retention failed. InstanceBackupRoot=' + $InstanceBackupRoot) -Exception $_.Exception
    }
}

function Invoke-UGSMManagedFileBackup {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$GameId,
        [AllowNull()][object]$Instance,
        [AllowNull()][object[]]$Targets,
        [string]$Reason = 'UGSM managed file change',
        [int]$KeepLatest = $script:UGSM_BackupDefaultRetention
    )

    $backupRoot = Get-UGSMBackupRoot
    if ([string]::IsNullOrWhiteSpace($backupRoot)) {
        return [pscustomobject]@{ Success = $false; Skipped = $true; Reason = 'BackupRootMissing'; Copied = 0; BackupPath = $null }
    }

    $resolvedTargets = @(Resolve-UGSMBackupTargetList -Targets $Targets)
    if (@($resolvedTargets).Count -eq 0) {
        Write-UGSMBackupLog -Level 'DEBUG' -Message ('Backup skipped; no existing managed files matched. GameId=' + $GameId + '; Reason=' + $Reason)
        return [pscustomobject]@{ Success = $true; Skipped = $true; Reason = 'NoExistingTargets'; Copied = 0; BackupPath = $null }
    }

    $safeGameId = ConvertTo-UGSMSafeBackupPathSegment -Value $GameId -Fallback 'UnknownGame'
    $safeInstance = ConvertTo-UGSMSafeBackupPathSegment -Value (Get-UGSMBackupInstanceName -Instance $Instance) -Fallback 'Default'
    $timestamp = (Get-Date).ToString('yyyyMMdd_HHmmss_fff')
    $instanceBackupRoot = Join-Path (Join-Path $backupRoot $safeGameId) $safeInstance
    $backupPath = Join-Path $instanceBackupRoot $timestamp

    $copied = 0
    $errors = New-Object System.Collections.Generic.List[string]

    try {
        if (-not (Test-Path -LiteralPath $backupPath -PathType Container)) {
            New-Item -ItemType Directory -Path $backupPath -Force | Out-Null
        }

        foreach ($target in @($resolvedTargets)) {
            try {
                $destination = Join-Path $backupPath ([string]$target.RelativePath)
                $destinationParent = Split-Path -Path $destination -Parent
                if (-not [string]::IsNullOrWhiteSpace($destinationParent) -and -not (Test-Path -LiteralPath $destinationParent -PathType Container)) {
                    New-Item -ItemType Directory -Path $destinationParent -Force | Out-Null
                }

                Copy-Item -LiteralPath ([string]$target.SourcePath) -Destination $destination -Force -ErrorAction Stop
                $copied++
            }
            catch {
                [void]$errors.Add($_.Exception.Message)
                Write-UGSMBackupLog -Level 'WARN' -Message ('Failed to copy managed file backup. GameId=' + $GameId + '; Instance=' + $safeInstance + '; File=' + [string]$target.RelativePath) -Exception $_.Exception
            }
        }

        if ($copied -eq 0) {
            try { Remove-Item -LiteralPath $backupPath -Recurse -Force -ErrorAction SilentlyContinue } catch {}
            return [pscustomobject]@{ Success = $false; Skipped = $true; Reason = 'CopyFailed'; Copied = 0; BackupPath = $null; Errors = @($errors.ToArray()) }
        }

        $manifest = [pscustomobject]@{
            Version      = 1
            GameId       = $GameId
            InstanceName = $safeInstance
            CreatedAtUtc = [DateTime]::UtcNow.ToString('o')
            Reason       = $Reason
            Retention    = $KeepLatest
            Files        = @($resolvedTargets | ForEach-Object { [pscustomobject]@{ RelativePath = [string]$_.RelativePath; Label = [string]$_.Label } })
        }
        $manifest | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $backupPath 'UGSM_BackupManifest.json') -Encoding UTF8

        Invoke-UGSMBackupRetention -InstanceBackupRoot $instanceBackupRoot -KeepLatest $KeepLatest
        Write-UGSMBackupLog -Level 'INFO' -Message ('Managed file backup created. GameId=' + $GameId + '; Instance=' + $safeInstance + '; Files=' + $copied + '; Reason=' + $Reason)

        return [pscustomobject]@{ Success = $true; Skipped = $false; Copied = $copied; BackupPath = $backupPath; Errors = @($errors.ToArray()) }
    }
    catch {
        Write-UGSMBackupLog -Level 'WARN' -Message ('Managed file backup failed. GameId=' + $GameId + '; Instance=' + $safeInstance + '; Reason=' + $Reason) -Exception $_.Exception
        return [pscustomobject]@{ Success = $false; Skipped = $true; Reason = 'Exception'; Copied = $copied; BackupPath = $null; Error = $_.Exception.Message }
    }
}

function Get-UGSMManagedBackupFolders {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$GameId,
        [AllowNull()][object]$Instance
    )

    $backupRoot = Get-UGSMBackupRoot
    if ([string]::IsNullOrWhiteSpace($backupRoot)) { return @() }

    $safeGameId = ConvertTo-UGSMSafeBackupPathSegment -Value $GameId -Fallback 'UnknownGame'
    $safeInstance = ConvertTo-UGSMSafeBackupPathSegment -Value (Get-UGSMBackupInstanceName -Instance $Instance) -Fallback 'Default'
    $instanceBackupRoot = Join-Path (Join-Path $backupRoot $safeGameId) $safeInstance
    if (-not (Test-Path -LiteralPath $instanceBackupRoot -PathType Container)) { return @() }

    return @(Get-ChildItem -LiteralPath $instanceBackupRoot -Directory -ErrorAction SilentlyContinue | Sort-Object Name -Descending)
}
