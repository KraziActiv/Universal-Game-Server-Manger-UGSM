# UGSM_Core_State.ps1

function New-UGSMAppState {
    [CmdletBinding()]
    param()

    return [pscustomobject]@{
        SelectedGameId        = $null
        SelectedInstanceId    = $null
        SelectedInstance      = $null
        LoadedModules         = @()
        CachedSystemMetrics   = $null
        CurrentDashboardModel = $null
        CurrentPage           = 'Home'
        GameDisplayMap        = @{}

        AnalyticsHistory      = [pscustomobject]@{
            Cpu         = @()
            Memory      = @()
            Disk        = @()
            MaxPoints   = 24
            LastUpdated = $null
        }

        MachineStatus         = [pscustomobject]@{
            CpuPercent          = 0.0
            MemoryPercent       = 0.0
            DiskPercent         = 0.0
            HealthState         = 'Unknown'
            HealthMessage       = 'Machine monitoring not started.'
            CanStartMoreServers = $true
            LastUpdated         = $null
            Cpu                 = $null
            Memory              = $null
            Disk                = $null
        }

        MachineMonitor        = [pscustomobject]@{
            RefreshSeconds = 5
            Timer          = $null
            IsRunning      = $false
        }
    }
}
