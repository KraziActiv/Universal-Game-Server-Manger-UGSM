# Core Process Helpers

function Invoke-UGSMProcess {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$FilePath,

        [string[]]$ArgumentList,

        [string]$WorkingDirectory,

        [switch]$ShowWindow,

        [int]$TimeoutSeconds = 0
    )

    if (-not (Test-Path -LiteralPath $FilePath -PathType Leaf)) {
        throw "Process target not found: $FilePath"
    }

    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $FilePath
    $psi.Arguments = ($ArgumentList -join ' ')

    if (-not [string]::IsNullOrWhiteSpace($WorkingDirectory)) {
        $psi.WorkingDirectory = $WorkingDirectory
    }

    if ($ShowWindow) {
        $psi.UseShellExecute = $true
    }
    else {
        $psi.UseShellExecute = $false
        $psi.CreateNoWindow = $true
        $psi.RedirectStandardOutput = $true
        $psi.RedirectStandardError = $true
    }

    $proc = New-Object System.Diagnostics.Process
    $proc.StartInfo = $psi

    $stdout = ''
    $stderr = ''

    [void]$proc.Start()

    if ($ShowWindow) {
        if ($TimeoutSeconds -gt 0) {
            $finished = $proc.WaitForExit($TimeoutSeconds * 1000)
            if (-not $finished) {
                try { $proc.Kill() } catch {}
                return [pscustomobject]@{
                    ExitCode = -1
                    Success  = $false
                    TimedOut = $true
                    StdOut   = ''
                    StdErr   = 'Process timed out.'
                }
            }
        }
        else {
            $proc.WaitForExit()
        }
    }
    else {
        if ($TimeoutSeconds -gt 0) {
            $stdoutTask = $proc.StandardOutput.ReadToEndAsync()
            $stderrTask = $proc.StandardError.ReadToEndAsync()
            $finished = $proc.WaitForExit($TimeoutSeconds * 1000)
            if (-not $finished) {
                try { $proc.Kill() } catch {}
                return [pscustomobject]@{
                    ExitCode = -1
                    Success  = $false
                    TimedOut = $true
                    StdOut   = ''
                    StdErr   = 'Process timed out.'
                }
            }
            $stdout = $stdoutTask.Result
            $stderr = $stderrTask.Result
        }
        else {
            $stdout = $proc.StandardOutput.ReadToEnd()
            $stderr = $proc.StandardError.ReadToEnd()
            $proc.WaitForExit()
        }
    }

    return [pscustomobject]@{
        ExitCode = $proc.ExitCode
        Success  = ($proc.ExitCode -eq 0)
        TimedOut = $false
        StdOut   = $stdout
        StdErr   = $stderr
    }
}


function Get-UGSMProcessByIdSafe {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [int]$ProcessId
    )

    try {
        return (Get-Process -Id $ProcessId -ErrorAction Stop)
    }
    catch {
        return $null
    }
}

function Test-UGSMProcessIsRunning {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [int]$ProcessId
    )

    $proc = Get-UGSMProcessByIdSafe -ProcessId $ProcessId
    return ($null -ne $proc -and -not $proc.HasExited)
}

function Stop-UGSMProcessTree {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [int]$ProcessId,

        [int]$TimeoutSeconds = 15
    )

    $targetPid = [int]$ProcessId

    #Write-Host "[PROCESS STOP] Received ProcessId: $ProcessId"
   # Write-Host "[PROCESS STOP] Target PID: $targetPid"

    $wasRunning = Test-UGSMProcessIsRunning -ProcessId $targetPid
    if (-not $wasRunning) {
        return [pscustomobject]@{
            Pid        = $targetPid
            WasRunning = $false
            Stopped    = $true
            TimedOut   = $false
            Method     = 'AlreadyExited'
        }
    }

    #Write-Host "[PROCESS STOP] Executing taskkill on PID: $targetPid"
    
    $method = 'TaskKill'
    try {
        Start-Process -FilePath 'taskkill.exe' -ArgumentList @('/PID', [string]$targetPid, '/T', '/F') -WindowStyle Hidden -Wait | Out-Null
    }
    catch {
        $method = 'StopProcess'
        try {
            Stop-Process -Id $targetPid -Force -ErrorAction Stop
        }
        catch {
        }
    }

    $deadline = [DateTime]::UtcNow.AddSeconds([Math]::Max(1, $TimeoutSeconds))
    while ([DateTime]::UtcNow -lt $deadline) {
        if (-not (Test-UGSMProcessIsRunning -ProcessId $targetPid)) {
            return [pscustomobject]@{
                Pid        = $targetPid
                WasRunning = $true
                Stopped    = $true
                TimedOut   = $false
                Method     = $method
            }
        }

        Start-Sleep -Milliseconds 300
    }

    return [pscustomobject]@{
        Pid        = $targetPid
        WasRunning = $true
        Stopped    = (-not (Test-UGSMProcessIsRunning -ProcessId $targetPid))
        TimedOut   = (Test-UGSMProcessIsRunning -ProcessId $targetPid)
        Method     = $method
    }
}
