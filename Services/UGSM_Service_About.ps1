# About Services

function Write-UGSMAboutLog {
    [CmdletBinding()]
    param(
        [ValidateSet('TRACE','DEBUG','INFO','WARN','ERROR','FATAL')]
        [string]$Level = 'INFO',

        [Parameter(Mandatory)]
        [string]$Message,

        [AllowNull()]
        [System.Exception]$Exception
    )

    if (Get-Command Write-UGSMLog -ErrorAction SilentlyContinue) {
        if ($Exception) {
            Write-UGSMLog -Level $Level -Category 'About' -Message $Message -Exception $Exception
        }
        else {
            Write-UGSMLog -Level $Level -Category 'About' -Message $Message
        }
        return
    }

    try { Write-Verbose ("[About] $Message") } catch {}
}

function Get-UGSMSafeScriptString {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Name,

        [string]$Default = ''
    )

    $variable = Get-Variable -Name $Name -Scope Script -ErrorAction SilentlyContinue
    if (-not $variable) { return $Default }

    $value = [string]$variable.Value
    if ([string]::IsNullOrWhiteSpace($value)) { return $Default }

    return $value
}

function Get-UGSMAboutData {
    [CmdletBinding()]
    param()

    $sw = [System.Diagnostics.Stopwatch]::StartNew()

    try {
        $defaultReleaseNotes = @(
            'Real per-run logging has been added for startup, UI pages, services, updater, games, and instances.',
            'The app updater can check, download, verify, apply, and restart UGSM from the same EXE path.',
            'Home, Games, Instances, Analytics, Tasks, Settings, and About pages are now split into page/service files.',
            'Machine monitor startup no longer blocks the UI and disk refreshes are deferred/throttled.',
            'Instances page now avoids rebuilding heavy game-specific editors during simple status refreshes.'
        )

        $releaseNotes = @($defaultReleaseNotes)
        $scriptReleaseNotes = Get-UGSMSafeScriptString -Name 'ReleaseNotes'
        if (-not [string]::IsNullOrWhiteSpace($scriptReleaseNotes)) {
            $parsedNotes = @(
                ($scriptReleaseNotes -split "(\r?\n){2,}") |
                ForEach-Object { $_.Trim() } |
                Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
                Select-Object -First 8
            )

            if ($parsedNotes.Count -gt 0) {
                $releaseNotes = @($parsedNotes)
            }
        }

        $versionRaw = Get-UGSMSafeScriptString -Name 'AppVersion' -Default '2 Preview'
        $versionText = if ($versionRaw -match '^v') { $versionRaw } else { 'v' + $versionRaw }

        $buildDate = Get-UGSMSafeScriptString -Name 'BuildDate'
        $buildText = if (-not [string]::IsNullOrWhiteSpace($buildDate)) {
            'Build Date: ' + $buildDate
        }
        else {
            'Development Build'
        }

        $data = [pscustomobject]@{
            AppName        = 'Universal Game Server Manager'
            ShortName      = 'UGSM'
            Version        = $versionText
            Build          = $buildText
            Author         = 'KraziActiv'
            Tagline        = 'A modular game server manager focused on clean workflows, isolated profiles, and safer server operations.'
            Description    = 'UGSM keeps game binaries, server profiles, logs, update checks, analytics, tasks, and game-aware workflows organized without burying users in clutter.'
            DiscordUrl     = 'https://discord.gg/XdV4qzgJ4Q'
            ReleaseNotes   = @($releaseNotes)
            SupportMessage = @"
Thank you so much for clicking the button and for wanting to support UGSM. ♥

Right now I am not accepting donations, and I have not decided if I ever will.

Honestly, knowing that you wanted to contribute already means a lot. The best support right now is simply using the app, sharing feedback, and telling other people about it if you enjoy it.

That kind of support helps more than you probably realize.

Thank you for the kindness and for being part of the journey.
"@
        }

        $sw.Stop()
        if ($sw.ElapsedMilliseconds -gt 250) {
            Write-UGSMAboutLog -Level 'WARN' -Message ("About data build was slow. DurationMs={0}" -f $sw.ElapsedMilliseconds)
        }
        else {
            Write-UGSMAboutLog -Level 'DEBUG' -Message ("About data built. DurationMs={0}; Notes={1}" -f $sw.ElapsedMilliseconds, @($data.ReleaseNotes).Count)
        }

        return $data
    }
    catch {
        $sw.Stop()
        Write-UGSMAboutLog -Level 'ERROR' -Message 'Failed to build About data.' -Exception $_.Exception
        throw
    }
}
