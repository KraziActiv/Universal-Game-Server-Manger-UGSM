# KraziActiv's Universal Game Server Manager

# ============================================================
# POWERSHELL RUNTIME REQUIREMENT
# UGSM v2 scripting target: Windows PowerShell 5.1+
#
# Keep this guard before all normal bootstrap/module loading so older
# PowerShell versions fail with a clear message instead of random parser,
# strict-mode, WinForms, or service errors later.
#
# Do not use PowerShell 7-only syntax in UGSM core/template code unless
# that code is explicitly guarded and tested.
# ============================================================
function Test-UGSMPowerShellRuntime {
    try {
        if ($null -eq $PSVersionTable -or $null -eq $PSVersionTable.PSVersion) {
            return $false
        }

        $version = $PSVersionTable.PSVersion

        if ($version.Major -gt 5) {
            return $true
        }

        if ($version.Major -eq 5 -and $version.Minor -ge 1) {
            return $true
        }

        return $false
    }
    catch {
        return $false
    }
}

function Show-UGSMPowerShellRuntimeRequirement {
    $detected = 'Unknown'
    try {
        if ($null -ne $PSVersionTable -and $null -ne $PSVersionTable.PSVersion) {
            $detected = [string]$PSVersionTable.PSVersion
        }
    }
    catch {
        $detected = 'Unknown'
    }

    $message = @"
UGSM requires Windows PowerShell 5.1 or newer.

Detected PowerShell version:
$detected

Please install Windows Management Framework 5.1 from Microsoft, then restart UGSM.

To avoid stale download links, go to Microsoft.com and search for:
Windows Management Framework 5.1 download
"@

    try {
        Add-Type -AssemblyName System.Windows.Forms -ErrorAction Stop
        [System.Windows.Forms.MessageBox]::Show(
            $message,
            'UGSM Requirement Missing',
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Error
        ) | Out-Null
    }
    catch {
        try {
            Write-Host ''
            Write-Host 'UGSM Requirement Missing'
            Write-Host $message
            Write-Host ''
        }
        catch {}
    }
}

if (-not (Test-UGSMPowerShellRuntime)) {
    Show-UGSMPowerShellRuntimeRequirement
    exit 1
}


# =========================
# DEV MODE / LIVE RELOAD
# Source/dev mode uses this switch for F12 app reload.
# Set to $false while testing source mode if you want F12 reload disabled.
# Build-Release.ps1 injects $script:UGSM_IsReleaseBuild = $true into compiled EXEs,
# and release builds always force dev reload off.
# =========================
if (-not (Get-Variable -Name 'UGSM_IsReleaseBuild' -Scope Script -ErrorAction SilentlyContinue)) {
    $script:UGSM_IsReleaseBuild = $false
}

# =========================
# BUILD MODE
# Build-Release.ps1 injects 'Release' and Build-Test.ps1 injects 'Test' before this file runs.
# Source/dev runs (loose .ps1) default to 'Dev'. Used by the logger to pick a default level threshold.
# =========================
if (-not (Get-Variable -Name 'UGSM_BuildMode' -Scope Script -ErrorAction SilentlyContinue)) {
    $script:UGSM_BuildMode = 'Dev'
}

if ([bool]$script:UGSM_IsReleaseBuild) {
    $script:UGSM_EnableDevReload = $false
}
elseif (-not (Get-Variable -Name 'UGSM_EnableDevReload' -Scope Script -ErrorAction SilentlyContinue)) {
    $script:UGSM_EnableDevReload = $true
}

# =========================
# APP VERSION
# Source/dev default is used only when running loose .ps1 files.
# Build-Release injects the real build version into compiled EXEs before this file runs.
# Keep this synced with the current dev/test release when testing the updater from source.
# =========================
if (-not (Get-Variable -Name 'AppVersion' -Scope Script -ErrorAction SilentlyContinue)) {
    $script:AppVersion = '2.0.2.167'
}

$script:UGSM_EnableEmergencyBootstrapLog = ([bool]$script:UGSM_EnableDevReload -and -not [bool]$script:UGSM_IsReleaseBuild)

# =========================
# LOGGING RETENTION
# Normal app logs and dev emergency logs use one file per run.
# Keep this low so support logs stay short and easy to send.
# =========================
$script:UGSM_LogKeepCount = 5
$script:UGSM_BootstrapLogKeepCount = 1

# =========================
# APP UPDATE DEFAULTS
# Build-Release injects the release manifest URL into compiled builds.
# Source/dev mode can override this in Services\UGSM_Service_Updater.ps1.
# =========================
if (-not (Get-Variable -Name 'UGSM_UpdateManifestUrl' -Scope Script -ErrorAction SilentlyContinue)) {
    $script:UGSM_UpdateManifestUrl = ''
}

if (-not (Get-Variable -Name 'UGSM_CheckUpdatesOnStartup' -Scope Script -ErrorAction SilentlyContinue)) {
    $script:UGSM_CheckUpdatesOnStartup = $false
}

if ([string]::IsNullOrWhiteSpace($global:UGSM_RunId)) {
    $global:UGSM_RunId = Get-Date -Format 'yyyyMMdd_HHmmss_fff'
}
$script:UGSM_RunId = [string]$global:UGSM_RunId
$script:UGSM_EarlyLogFile = $null
$script:UGSM_EarlyLogCleanupDone = $false

# ============================================================
# Emergency bootstrap logger
# Dev/bootstrap logs keep only the newest 1 file and do not count against normal app logs.
# This runs before elevation, Add-Type, module loading, or the normal logger.
# In dev mode it creates one bootstrap file per run and keeps only the newest 5.
# If UGSM fails before UGSM_Logging.ps1 loads, check:
#   $env:LOCALAPPDATA\UGSM\Logs\UGSM\UGSM_Bootstrap_<RunId>.log
# ============================================================
function Get-UGSMEarlyLogRoot {
    try {
        $localAppData = [Environment]::GetFolderPath('LocalApplicationData')
        if ([string]::IsNullOrWhiteSpace($localAppData)) {
            $localAppData = Join-Path $env:USERPROFILE 'AppData\Local'
        }
        return (Join-Path $localAppData 'UGSM\Logs\UGSM')
    }
    catch {
        return (Join-Path (Get-Location).Path 'Logs')
    }
}

function Remove-UGSMOldEarlyLogs {
    param(
        [Parameter(Mandatory)]
        [string]$LogRootPath,

        [int]$Keep = 5,

        [string]$CurrentFileName
    )

    try {
        if ($Keep -lt 1) { $Keep = 1 }
        if (-not (Test-Path -LiteralPath $LogRootPath -PathType Container)) { return }

        $files = @(Get-ChildItem -LiteralPath $LogRootPath -Filter 'UGSM_Bootstrap_*.log' -File -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -ne $CurrentFileName } |
            Sort-Object LastWriteTimeUtc -Descending)

        if ($files.Count -lt $Keep) { return }

        $files | Select-Object -Skip ($Keep - 1) | ForEach-Object {
            try { Remove-Item -LiteralPath $_.FullName -Force -ErrorAction Stop } catch {}
        }
    }
    catch {
        # Emergency cleanup should never stop UGSM startup.
    }
}

function Get-UGSMEarlyLogFile {
    param([string]$Root)

    if (-not [string]::IsNullOrWhiteSpace($script:UGSM_EarlyLogFile)) {
        return $script:UGSM_EarlyLogFile
    }

    if ([string]::IsNullOrWhiteSpace($script:UGSM_RunId)) {
        if ([string]::IsNullOrWhiteSpace($global:UGSM_RunId)) {
            $global:UGSM_RunId = Get-Date -Format 'yyyyMMdd_HHmmss_fff'
        }
        $script:UGSM_RunId = [string]$global:UGSM_RunId
    }

    $script:UGSM_EarlyLogFile = Join-Path $Root ("UGSM_Bootstrap_{0}.log" -f $script:UGSM_RunId)
    return $script:UGSM_EarlyLogFile
}


function ConvertTo-UGSMMainDisplayPath {
    [CmdletBinding()]
    param([string]$Path)

    if ([string]::IsNullOrWhiteSpace($Path)) { return $Path }

    $display = [string]$Path

    try {
        $appRoot = $null
        if (Get-Variable -Name 'ScriptRoot' -Scope 1 -ErrorAction SilentlyContinue) {
            $appRoot = [string](Get-Variable -Name 'ScriptRoot' -Scope 1 -ValueOnly -ErrorAction SilentlyContinue)
        }
        if ([string]::IsNullOrWhiteSpace($appRoot) -and -not [string]::IsNullOrWhiteSpace($PSScriptRoot)) {
            $appRoot = [string]$PSScriptRoot
        }
        if (-not [string]::IsNullOrWhiteSpace($appRoot)) {
            $escaped = [regex]::Escape($appRoot.TrimEnd('\'))
            $display = [regex]::Replace($display, "^$escaped", '%UGSM_ROOT%', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
        }

        $localAppData = [Environment]::GetFolderPath('LocalApplicationData')
        if (-not [string]::IsNullOrWhiteSpace($localAppData)) {
            $escaped = [regex]::Escape($localAppData.TrimEnd('\'))
            $display = [regex]::Replace($display, "^$escaped", '%LOCALAPPDATA%', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
        }

        $userProfile = [Environment]::GetFolderPath('UserProfile')
        if (-not [string]::IsNullOrWhiteSpace($userProfile)) {
            $escaped = [regex]::Escape($userProfile.TrimEnd('\'))
            $display = [regex]::Replace($display, "^$escaped", '%USERPROFILE%', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
        }
    }
    catch {
        # Display-path redaction should never block startup.
    }

    return $display
}

function Write-UGSMEarlyLog {
    param(
        [string]$Message,
        [string]$Level = 'INFO'
    )

    # In normal/release mode this stays quiet unless startup hits a fatal error.
    # In dev mode it is enabled automatically by $script:UGSM_EnableDevReload.
    if (-not $script:UGSM_EnableEmergencyBootstrapLog -and $Level -ne 'FATAL') {
        return
    }

    try {
        $root = Get-UGSMEarlyLogRoot
        if (-not (Test-Path -LiteralPath $root -PathType Container)) {
            New-Item -Path $root -ItemType Directory -Force | Out-Null
        }

        $file = Get-UGSMEarlyLogFile -Root $root
        $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff'
        Add-Content -LiteralPath $file -Value ('[{0}] [{1}] {2}' -f $timestamp, $Level.ToUpperInvariant(), $Message) -Encoding UTF8

        if (-not $script:UGSM_EarlyLogCleanupDone) {
            $script:UGSM_EarlyLogCleanupDone = $true
            Remove-UGSMOldEarlyLogs -LogRootPath $root -Keep $script:UGSM_BootstrapLogKeepCount -CurrentFileName (Split-Path -Leaf $file)
        }
    }
    catch {
        try { Write-Host "[$Level] $Message" } catch {}
    }
}

Write-UGSMEarlyLog -Message 'UGSM_Main.ps1 entered.'

try {
    Add-Type -AssemblyName System.Drawing -ErrorAction Stop
    Add-Type -AssemblyName System.Windows.Forms -ErrorAction Stop
    Write-UGSMEarlyLog -Message 'WinForms assemblies loaded.'
}
catch {
    Write-UGSMEarlyLog -Level 'FATAL' -Message "Failed to load WinForms assemblies: $($_.Exception.Message)"
    throw
}

# Prevent recursive bootstrap if this script gets dot-sourced or discovered by the loader.
if ($script:UGSM_Main_BootstrapRunning) {
    return
}
$script:UGSM_Main_BootstrapRunning = $true

function Get-UGSMInvocationScriptPath {
    [CmdletBinding()]
    param(
        [object]$Invocation = $MyInvocation
    )

    # Some hosts / strict-mode sessions do not expose MyCommand.Path.
    # Always check PSObject.Properties before reading it.
    if (-not [string]::IsNullOrWhiteSpace($PSCommandPath)) {
        return [string]$PSCommandPath
    }

    try {
        if ($Invocation -and $Invocation.MyCommand) {
            $pathProperty = $Invocation.MyCommand.PSObject.Properties['Path']
            if ($pathProperty -and -not [string]::IsNullOrWhiteSpace([string]$pathProperty.Value)) {
                return [string]$pathProperty.Value
            }

            $sourceProperty = $Invocation.MyCommand.PSObject.Properties['Source']
            if ($sourceProperty -and -not [string]::IsNullOrWhiteSpace([string]$sourceProperty.Value)) {
                return [string]$sourceProperty.Value
            }
        }
    }
    catch {
    }

    return $null
}

$script:UGSM_EntryScript = Get-UGSMInvocationScriptPath

function Write-UGSMBootstrapLog {
    param(
        [string]$Message,
        [string]$Level = 'INFO',
        [string]$Category = 'Bootstrap'
    )

    if (Get-Command Write-UGSMLog -ErrorAction SilentlyContinue) {
        Write-UGSMLog -Level $Level -Category $Category -Message $Message
        return
    }

    # In no-console PS2EXE builds, Write-Host can surface as popup windows.
    # Use the early file logger instead so release builds stay quiet.
    try {
        Write-UGSMEarlyLog -Level $Level -Message "[$Category] $Message"
    }
    catch {
    }
}

function Test-UGSMIsAdministrator {
    try {
        $currentIdentity = [Security.Principal.WindowsIdentity]::GetCurrent()
        $principal = [Security.Principal.WindowsPrincipal]::new($currentIdentity)
        return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    }
    catch {
        return $false
    }
}

function Get-UGSMPowerShellHostPath {
    [CmdletBinding()]
    param()

    try {
        $processPath = (Get-Process -Id $PID -ErrorAction Stop).Path
        if (-not [string]::IsNullOrWhiteSpace($processPath) -and (Test-Path -LiteralPath $processPath -PathType Leaf)) {
            return $processPath
        }
    }
    catch {
    }

    foreach ($candidateName in @('powershell.exe', 'pwsh.exe')) {
        $candidatePath = Join-Path $PSHOME $candidateName
        if (Test-Path -LiteralPath $candidatePath -PathType Leaf) {
            return $candidatePath
        }
    }

    return $null
}

function Start-UGSMElevatedHost {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ScriptPath
    )

    $resolvedScriptPath = [System.IO.Path]::GetFullPath($ScriptPath)
    $hostExecutablePath = Get-UGSMPowerShellHostPath

    if ([string]::IsNullOrWhiteSpace($hostExecutablePath)) {
        throw 'Unable to locate the current PowerShell host executable for elevation.'
    }

    $argumentList = @(
        '-NoProfile'
        '-ExecutionPolicy', 'Bypass'
        '-File', ('"{0}"' -f $resolvedScriptPath)
    )

    Write-UGSMBootstrapLog -Level 'WARN' -Message 'UGSM requires administrator rights. Restarting elevated.'
    Start-Process -FilePath $hostExecutablePath -Verb RunAs -ArgumentList $argumentList | Out-Null
}

function Restart-UGSMApplication {
    try {
        $entryScript = $script:UGSM_EntryScript
        if ([string]::IsNullOrWhiteSpace($entryScript)) {
            $entryScript = Get-UGSMInvocationScriptPath
        }

        if ([string]::IsNullOrWhiteSpace($entryScript)) {
            throw 'UGSM entry script path is not available.'
        }

        $entryScript = [System.IO.Path]::GetFullPath($entryScript)
        if (-not (Test-Path -LiteralPath $entryScript -PathType Leaf)) {
            throw "Entry script was not found: $entryScript"
        }

        $hostExecutablePath = Get-UGSMPowerShellHostPath
        if ([string]::IsNullOrWhiteSpace($hostExecutablePath)) {
            throw 'Unable to locate the PowerShell host executable for reload.'
        }

        $argumentList = @(
            '-NoProfile'
            '-ExecutionPolicy', 'Bypass'
            '-File', ('"{0}"' -f $entryScript)
        )

        Write-UGSMLog -Level 'INFO' -Category 'Reload' -Message "Restarting UGSM from $entryScript"
        Start-Process -FilePath $hostExecutablePath -ArgumentList $argumentList | Out-Null

        if ($script:MainForm -and -not $script:MainForm.IsDisposed) {
            $script:MainForm.Close()
        }
        else {
            [System.Windows.Forms.Application]::Exit()
        }
    }
    catch {
        if (Get-Command Write-UGSMLog -ErrorAction SilentlyContinue) {
            Write-UGSMLog -Level 'ERROR' -Category 'Reload' -Message 'UGSM reload failed.' -Exception $_.Exception
        }

        [System.Windows.Forms.MessageBox]::Show(
            "UGSM reload failed.`n`n$($_.Exception.Message)",
            'UGSM Reload',
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Error
        ) | Out-Null
    }
}

function Get-UGSMScriptRoot {
    [CmdletBinding()]
    param()

    if (-not [string]::IsNullOrWhiteSpace($PSScriptRoot)) {
        return $PSScriptRoot
    }

    $scriptPath = Get-UGSMInvocationScriptPath
    if (-not [string]::IsNullOrWhiteSpace($scriptPath)) {
        return (Split-Path -Parent $scriptPath)
    }

    return (Get-Location).Path
}

function Get-UGSMLoadRank {
    [CmdletBinding()]
    param([string]$Path)

    $normalized = $Path.ToLowerInvariant()
    $name = [System.IO.Path]::GetFileName($normalized)

    if ($name -match 'logging') { return 5 }

    if ($normalized -match '[\\/]core[\\/]') { return 10 }
    if ($normalized -match '[\\/]settings[\\/]') { return 15 }
    if ($normalized -match '[\\/]services[\\/]') { return 20 }
    if ($normalized -match '[\\/]games[\\/]') { return 30 }
    if ($normalized -match '[\\/]modules[\\/]') { return 40 }
    if ($normalized -match '[\\/]ui[\\/]') { return 50 }

    if ($name -match 'core|state|system') { return 10 }
    if ($name -match 'settings|secrets') { return 15 }
    if ($name -match 'service') { return 20 }
    if ($name -match 'game') { return 30 }
    if ($name -match 'module') { return 40 }
    if ($name -match 'ui_') { return 50 }

    return 100
}

function Get-UGSMModuleFiles {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$RootPath,

        [string]$MainScriptPath,

        [string[]]$ExcludePaths = @()
    )

    $releaseRoot = [System.IO.Path]::GetFullPath((Join-Path $RootPath 'Release'))

    return Get-ChildItem -Path $RootPath -Filter '*.ps1' -File -Recurse |
    Where-Object {
        $full = [System.IO.Path]::GetFullPath($_.FullName)
        $name = $_.Name
        $isReleaseArtifact = $full.StartsWith($releaseRoot, [System.StringComparison]::OrdinalIgnoreCase)
        $isBuildScript = ($name -eq 'Build-Release.ps1')
        $isLegacyLogger = ($name -eq 'UGSM_Core_Logs.ps1')
        $isMainScript = ($name -eq 'UGSM_Main.ps1') -or (-not [string]::IsNullOrWhiteSpace($MainScriptPath) -and $full -eq $MainScriptPath)
        $isExcluded = @($ExcludePaths | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | ForEach-Object { [System.IO.Path]::GetFullPath($_) }) -contains $full

        # Do not load scratch/test/backup files that happen to be under the project root.
        $isHiddenOrScratch = $name.StartsWith('.') -or $name.EndsWith('.bak.ps1') -or $name.EndsWith('.backup.ps1')
        $isGeneratedVariant = $name -match '_v\d+\.ps1$' -or $name -match '_refactor\.ps1$'

        (-not $isMainScript) -and
        (-not $isExcluded) -and
        (-not $isReleaseArtifact) -and
        (-not $isBuildScript) -and
        (-not $isLegacyLogger) -and
        (-not $isHiddenOrScratch) -and
        (-not $isGeneratedVariant)
    } 
    Sort-Object @{ Expression = { Get-UGSMLoadRank -Path $_.FullName } }, @{ Expression = { $_.FullName } }
}

function Import-UGSMModuleFiles {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object[]]$Files
    )

    foreach ($file in $Files) {
        $displayName = $file.FullName
        $rank = Get-UGSMLoadRank -Path $file.FullName

        try {
            $escapedModulePath = $file.FullName.Replace("'", "''")
            $loadScript = [scriptblock]::Create(". '$escapedModulePath'")

            if (Get-Command Invoke-UGSMTimedBlock -ErrorAction SilentlyContinue) {
                Invoke-UGSMTimedBlock -Name "Load $($file.Name)" -Category 'ModuleLoad' -ScriptBlock {
                    # Load into the script/global session scope, not this helper function's local scope.
                    $ExecutionContext.InvokeCommand.InvokeScript(
                        $false,
                        $loadScript,
                        $null,
                        $null
                    )
                }.GetNewClosure()
            }
            else {
                Write-UGSMBootstrapLog -Message "Loading: $displayName"
                $ExecutionContext.InvokeCommand.InvokeScript(
                    $false,
                    $loadScript,
                    $null,
                    $null
                )
            }

            Write-UGSMBootstrapLog -Message "Loaded OK: $($file.Name) [Rank $rank]"
        }
        catch {
            if (Get-Command Write-UGSMLog -ErrorAction SilentlyContinue) {
                Write-UGSMLog -Level 'ERROR' -Category 'ModuleLoad' -Message "Failed loading: $displayName" -Exception $_.Exception -Data @{ Rank = $rank }
            }
            else {
                Write-Host "FAILED loading: $displayName"
                Write-Host $_
            }
            throw
        }
    }
}


function Write-UGSMStartupErrorSnapshot {
    [CmdletBinding()]
    param(
        [string]$Phase = 'Startup'
    )

    try {
        if (-not (Get-Command Write-UGSMLog -ErrorAction SilentlyContinue)) { return }
        if (-not $global:Error -or $global:Error.Count -lt 1) { return }

        $interesting = @()
        foreach ($err in @($global:Error | Select-Object -First 25)) {
            if (-not $err) { continue }

            $message = ''
            try { $message = [string]$err.Exception.Message } catch {}
            if ([string]::IsNullOrWhiteSpace($message)) {
                try { $message = [string]$err.ToString() } catch {}
            }

            # Keep this focused so normal historical/non-fatal errors do not spam startup logs.
            $isStartupPopupCandidate =
                ($message -match "The term\s+'?`"?\s*'?`"?\s+is not recognized") -or
                ($message -match "is not recognized as the name of a cmdlet") -or
                ($message -match "Cannot bind argument to parameter 'FilePath'") -or
                ($message -match "Cannot validate argument on parameter 'FilePath'")

            if (-not $isStartupPopupCandidate) { continue }

            $scriptName = ''
            $lineNumber = ''
            $offset = ''
            $lineText = ''
            try {
                if ($err.InvocationInfo) {
                    $scriptName = ConvertTo-UGSMMainDisplayPath -Path ([string]$err.InvocationInfo.ScriptName)
                    $lineNumber = [string]$err.InvocationInfo.ScriptLineNumber
                    $offset = [string]$err.InvocationInfo.OffsetInLine
                    $lineText = [string]$err.InvocationInfo.Line
                }
            }
            catch {}

            $interesting += [pscustomobject]@{
                Message    = $message
                ScriptName = $scriptName
                Line       = $lineNumber
                Offset     = $offset
                Code       = $lineText
            }
        }

        if ($interesting.Count -lt 1) { return }

        foreach ($item in $interesting) {
            Write-UGSMLog -Level 'WARN' -Category 'StartupDiagnostics' -Message "Captured PowerShell startup error candidate during $Phase." -Data @{
                Message    = $item.Message
                ScriptName = $item.ScriptName
                Line       = $item.Line
                Offset     = $item.Offset
                Code       = $item.Code
            }
        }
    }
    catch {
        # Diagnostics must never affect startup.
    }
}


function New-UGSMFallbackAppState {
    [CmdletBinding()]
    param()

    return [pscustomobject]@{
        SelectedGameId      = $null
        SelectedInstanceId  = $null
        SelectedInstance    = $null
        GameDisplayMap      = @{}
        CachedSystemMetrics = $null
        MachineStatus       = $null
        AnalyticsHistory    = $null
        MachineMonitor      = [pscustomobject]@{
            Timer          = $null
            IsRunning      = $false
            RefreshSeconds = 0
        }
    }
}

try {
    Write-UGSMEarlyLog -Message 'Bootstrap try block entered.'

    if (-not (Test-UGSMIsAdministrator)) {
        $currentScriptPath = Get-UGSMInvocationScriptPath
        if ([string]::IsNullOrWhiteSpace($currentScriptPath)) {
            throw 'UGSM must be launched from a script file so it can restart elevated.'
        }

        Write-UGSMEarlyLog -Level 'WARN' -Message "Not running as administrator. Requesting elevation for: $currentScriptPath"
        Start-UGSMElevatedHost -ScriptPath $currentScriptPath
        Write-UGSMEarlyLog -Message 'Elevation request sent. Exiting non-elevated process.'
        return
    }

    Write-UGSMEarlyLog -Message 'Running as administrator.'

    $ScriptRoot = Get-UGSMScriptRoot
    $mainScriptPath = if ($script:UGSM_EntryScript) { [System.IO.Path]::GetFullPath($script:UGSM_EntryScript) } else { $null }
    $displayScriptRoot = ConvertTo-UGSMMainDisplayPath -Path $ScriptRoot
    Write-UGSMEarlyLog -Message "Script root resolved: $displayScriptRoot"

    # Load logging first in source/dev mode.
    # In release builds, Build-Release.ps1 embeds UGSM_Logging.ps1 before this file runs,
    # so we must not scan the EXE/Desktop folder for .ps1 files.
    $preloadedLoggingPath = $null
    if (-not [bool]$script:UGSM_IsReleaseBuild) {
        $loggingPath = Get-ChildItem -Path $ScriptRoot -Filter '*Logging*.ps1' -File -Recurse |
        Where-Object { $_.FullName -notmatch '[\/]Release[\/]' }
        Sort-Object FullName
        Select-Object -First 1

        if ($loggingPath) {
            $preloadedLoggingPath = [System.IO.Path]::GetFullPath($loggingPath.FullName)
            Write-UGSMEarlyLog -Message "Preloading logging file: $preloadedLoggingPath"
            . $preloadedLoggingPath
        }
    }
    else {
        Write-UGSMEarlyLog -Message 'Release build detected. Logging functions should already be embedded; skipping runtime logging-file discovery.'
    }

    if (Get-Command Initialize-UGSMLogging -ErrorAction SilentlyContinue) {
        [void](Initialize-UGSMLogging -LogName 'UGSM' -KeepRunLogs $script:UGSM_LogKeepCount)
        $displayLogFile = ConvertTo-UGSMMainDisplayPath -Path $global:UGSM_LogFile
        Write-UGSMEarlyLog -Message "Normal logging initialized: $displayLogFile"
        Register-UGSMUnhandledExceptionLogging
        Write-UGSMStartupErrorSnapshot -Phase 'after logging init'
    }

    $displayScriptRoot = ConvertTo-UGSMMainDisplayPath -Path $ScriptRoot
    Write-UGSMBootstrapLog -Message "UGSM startup begin. Root: $displayScriptRoot"

    $coreStatePath = Join-Path $ScriptRoot 'Core\UGSM_Core_State.ps1'
    if (-not (Get-Command New-UGSMAppState -ErrorAction SilentlyContinue)) {
        if (Test-Path -LiteralPath $coreStatePath -PathType Leaf) {
            $coreStateStopwatch = [System.Diagnostics.Stopwatch]::StartNew()
            Write-UGSMBootstrapLog -Level 'DEBUG' -Category 'ModuleLoad' -Message 'Starting: Load core state'
            try {
                # Dot-source directly from the script scope. Do not wrap this in a helper/timer scriptblock,
                # or functions defined by the loaded file may be scoped away after the helper returns.
                . $coreStatePath
                $coreStateStopwatch.Stop()
                Write-UGSMBootstrapLog -Level 'DEBUG' -Category 'ModuleLoad' -Message "Finished: Load core state ($($coreStateStopwatch.ElapsedMilliseconds) ms)"
            }
            catch {
                $coreStateStopwatch.Stop()
                Write-UGSMLog -Level 'ERROR' -Category 'ModuleLoad' -Message "FAILED loading core state ($($coreStateStopwatch.ElapsedMilliseconds) ms): $($_.Exception.Message)" -Exception $_.Exception
                throw
            }
        }
    }

    if (-not (Get-Command New-UGSMAppState -ErrorAction SilentlyContinue)) {
        Write-UGSMBootstrapLog -Level 'WARN' -Message 'New-UGSMAppState was not loaded from Core\UGSM_Core_State.ps1. Using temporary fallback app state for this startup pass.'
        Set-Item -Path Function:\New-UGSMAppState -Value ${function:New-UGSMFallbackAppState}
    }

    if ([bool]$script:UGSM_IsReleaseBuild) {
        Write-UGSMBootstrapLog -Message 'Release build detected. UGSM modules are embedded; skipping runtime .ps1 discovery/loading.'
    }
    else {
        $files = if (Get-Command Invoke-UGSMTimedBlock -ErrorAction SilentlyContinue) {
            Invoke-UGSMTimedBlock -Name 'Discover module files' -Category 'Bootstrap' -ScriptBlock {
                @(Get-UGSMModuleFiles -RootPath $ScriptRoot -MainScriptPath $mainScriptPath -ExcludePaths @($preloadedLoggingPath))
            }
        }
        else {
            @(Get-UGSMModuleFiles -RootPath $ScriptRoot -MainScriptPath $mainScriptPath -ExcludePaths @($preloadedLoggingPath))
        }

        if (-not $files) {
            throw "No PowerShell module files were found under $ScriptRoot"
        }

        Write-UGSMBootstrapLog -Message "Module files discovered: $($files.Count)"
        foreach ($file in $files) {
            $displayName = $file.FullName
            $rank = Get-UGSMLoadRank -Path $file.FullName
            $moduleStopwatch = [System.Diagnostics.Stopwatch]::StartNew()

            try {
                Write-UGSMBootstrapLog -Level 'DEBUG' -Category 'ModuleLoad' -Message "Starting: Load $($file.Name)"

                # IMPORTANT:
                # Dot-source directly here at script scope. Loading inside Invoke-UGSMTimedBlock or another helper
                # creates local-scope functions that disappear before New-UGSMMainForm is checked.
                . $file.FullName

                $moduleStopwatch.Stop()
                Write-UGSMBootstrapLog -Level 'DEBUG' -Category 'ModuleLoad' -Message "Finished: Load $($file.Name) ($($moduleStopwatch.ElapsedMilliseconds) ms)"
                Write-UGSMBootstrapLog -Message "Loaded OK: $($file.Name) [Rank $rank]"
            }
            catch {
                $moduleStopwatch.Stop()
                if (Get-Command Write-UGSMLog -ErrorAction SilentlyContinue) {
                    Write-UGSMLog -Level 'ERROR' -Category 'ModuleLoad' -Message "FAILED loading $displayName ($($moduleStopwatch.ElapsedMilliseconds) ms): $($_.Exception.Message)" -Exception $_.Exception -Data @{ Rank = $rank }
                }
                else {
                    Write-Host "FAILED loading: $displayName"
                    Write-Host $_
                }
                throw
            }
        }
    }

    # In merged/release builds, UGSM_Logging.ps1 is embedded with the other modules,
    # so the early file preload may not have found a physical logging script.
    # Initialize the normal logger now if it became available during module loading.
    if ((-not $global:UGSM_LogFile) -and (Get-Command Initialize-UGSMLogging -ErrorAction SilentlyContinue)) {
        [void](Initialize-UGSMLogging -LogName 'UGSM' -KeepRunLogs $script:UGSM_LogKeepCount)
        Register-UGSMUnhandledExceptionLogging
        $displayLogFile = ConvertTo-UGSMMainDisplayPath -Path $global:UGSM_LogFile
        Write-UGSMLog -Level 'INFO' -Category 'Bootstrap' -Message "Normal logging initialized after module load: $displayLogFile"
        Write-UGSMStartupErrorSnapshot -Phase 'after module load'
    }

    if (-not (Get-Command New-UGSMMainForm -ErrorAction SilentlyContinue)) {
        throw 'New-UGSMMainForm was not loaded. Check your UI scripts.'
    }

    $AppState = if (Get-Command Invoke-UGSMTimedBlock -ErrorAction SilentlyContinue) {
        Invoke-UGSMTimedBlock -Name 'Create app state' -Category 'Bootstrap' -ScriptBlock { New-UGSMAppState }
    }
    else {
        New-UGSMAppState
    }

    $global:UGSM_AppState = $AppState

    if (Get-Command Start-UGSMMachineMonitor -ErrorAction SilentlyContinue) {
        [void](Invoke-UGSMTimedBlock -Name 'Start machine monitor' -Category 'Bootstrap' -ScriptBlock {
                Start-UGSMMachineMonitor -AppState $AppState -RefreshSeconds 5 -DiskRefreshSeconds 1800 -InitialDiskDelaySeconds 300
            })
    }

    $form = @(Invoke-UGSMTimedBlock -Name 'Create main form' -Category 'Bootstrap' -ScriptBlock {
            New-UGSMMainForm -AppState $AppState
        })[-1]

    $script:MainForm = $form

    $form.Add_FormClosed({
            try {
                Write-UGSMLog -Level 'INFO' -Category 'Shutdown' -Message 'Main form closed. Stopping services.'

                if (Get-Command Stop-UGSMMachineMonitor -ErrorAction SilentlyContinue) {
                    Stop-UGSMMachineMonitor -AppState $global:UGSM_AppState
                }

                Write-UGSMLog -Level 'INFO' -Category 'Shutdown' -Message 'UGSM shutdown complete.'
            }
            catch {
                if (Get-Command Write-UGSMLog -ErrorAction SilentlyContinue) {
                    Write-UGSMLog -Level 'ERROR' -Category 'Shutdown' -Message 'Error during UGSM shutdown.' -Exception $_.Exception
                }
            }
        }.GetNewClosure())

    Write-UGSMLog -Level 'INFO' -Category 'Bootstrap' -Message 'Showing main form.'
    [void]$form.ShowDialog()
}
catch {
    Write-UGSMEarlyLog -Level 'FATAL' -Message "UGSM startup failed before or during normal bootstrap: $($_.Exception.Message)"

    if (Get-Command Write-UGSMLog -ErrorAction SilentlyContinue) {
        Write-UGSMLog -Level 'FATAL' -Category 'Bootstrap' -Message 'UGSM startup failed.' -Exception $_.Exception
    }

    [System.Windows.Forms.MessageBox]::Show(
        "UGSM failed to start.`n`n$($_.Exception.Message)",
        'UGSM Startup Error',
        [System.Windows.Forms.MessageBoxButtons]::OK,
        [System.Windows.Forms.MessageBoxIcon]::Error
    ) | Out-Null

    throw
}
