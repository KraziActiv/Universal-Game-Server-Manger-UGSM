# Shared service helper logic.

function Write-UGSMServiceHelperLog {
    [CmdletBinding()]
    param(
        [ValidateSet('TRACE', 'DEBUG', 'INFO', 'WARN', 'ERROR', 'FATAL')]
        [string]$Level = 'INFO',

        [string]$Message,

        [System.Exception]$Exception = $null
    )

    if (Get-Command Write-UGSMLog -ErrorAction SilentlyContinue) {
        if ($Exception) {
            Write-UGSMLog -Level $Level -Category 'ServiceHelpers' -Message $Message -Exception $Exception
        }
        else {
            Write-UGSMLog -Level $Level -Category 'ServiceHelpers' -Message $Message
        }
    }
}


function Initialize-UGSMInstancePageCompatibility {
    [CmdletBinding()]
    param()

    # These scriptblocks are compatibility fallbacks for older page/service
    # closures that may still reference page-local variables after refresh,
    # selection, or remove-profile operations. They are intentionally no-op
    # defaults and do not replace real page handlers when those already exist.
    if (-not (Get-Variable -Name 'ResolveLiveInstancesPageControl' -Scope Script -ErrorAction SilentlyContinue)) {
        $script:ResolveLiveInstancesPageControl = { param([object]$Control) return $Control }.GetNewClosure()
    }
    if (-not (Get-Variable -Name 'ResolveLiveInstancesPageControl' -Scope Global -ErrorAction SilentlyContinue)) {
        $global:ResolveLiveInstancesPageControl = $script:ResolveLiveInstancesPageControl
    }

    if (-not (Get-Variable -Name 'UpdateSelectedInstanceContextUI' -Scope Script -ErrorAction SilentlyContinue)) {
        $script:UpdateSelectedInstanceContextUI = { param([AllowNull()][object]$Instance) }.GetNewClosure()
    }
    if (-not (Get-Variable -Name 'UpdateSelectedInstanceContextUI' -Scope Global -ErrorAction SilentlyContinue)) {
        $global:UpdateSelectedInstanceContextUI = $script:UpdateSelectedInstanceContextUI
    }

    if (-not (Get-Variable -Name 'UpdateStatusBarUI' -Scope Script -ErrorAction SilentlyContinue)) {
        $script:UpdateStatusBarUI = { param([string]$Message) }.GetNewClosure()
    }
    if (-not (Get-Variable -Name 'UpdateStatusBarUI' -Scope Global -ErrorAction SilentlyContinue)) {
        $global:UpdateStatusBarUI = $script:UpdateStatusBarUI
    }
}

Initialize-UGSMInstancePageCompatibility

function Get-UGSMObjectValue {
    [CmdletBinding()]
    param(
        [AllowNull()]
        [object]$InputObject,

        [Parameter(Mandatory)]
        [string]$Name,

        [object]$Default = $null
    )

    if ($null -eq $InputObject) { return $Default }

    if ($InputObject -is [hashtable]) {
        if ($InputObject.ContainsKey($Name)) { return $InputObject[$Name] }
        return $Default
    }

    $property = $InputObject.PSObject.Properties[$Name]
    if ($property) { return $property.Value }

    return $Default
}

function Set-UGSMObjectValue {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$InputObject,

        [Parameter(Mandatory)]
        [string]$Name,

        [AllowNull()]
        [object]$Value
    )

    if ($InputObject -is [hashtable]) {
        $InputObject[$Name] = $Value
        return
    }

    if ($InputObject.PSObject.Properties[$Name]) {
        $InputObject.$Name = $Value
    }
    else {
        Add-Member -InputObject $InputObject -NotePropertyName $Name -NotePropertyValue $Value -Force
    }
}

function Resolve-UGSMSelectedInstanceFromCollection {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$AppState,

        [AllowNull()]
        [object[]]$Instances
    )

    if (-not $Instances) { return $null }

    $selectedId = ''
    $selectedGameId = ''

    if ($AppState -is [hashtable]) {
        if ($AppState.ContainsKey('SelectedInstanceId')) { $selectedId = [string]$AppState['SelectedInstanceId'] }
        if ($AppState.ContainsKey('SelectedGameId')) { $selectedGameId = [string]$AppState['SelectedGameId'] }
    }
    else {
        if ($AppState.PSObject.Properties['SelectedInstanceId']) { $selectedId = [string]$AppState.SelectedInstanceId }
        if ($AppState.PSObject.Properties['SelectedGameId']) { $selectedGameId = [string]$AppState.SelectedGameId }
    }

    $candidates = @($Instances)
    if (-not [string]::IsNullOrWhiteSpace($selectedGameId)) {
        $candidates = @($candidates | Where-Object { [string]$_.GameId -eq $selectedGameId })
    }

    $selected = $null
    if (-not [string]::IsNullOrWhiteSpace($selectedId)) {
        $selected = @($candidates | Where-Object { [string]$_.Id -eq $selectedId } | Select-Object -First 1)
    }

    if (-not $selected) {
        $selectedName = ''
        if ($AppState -is [hashtable]) {
            if ($AppState.ContainsKey('SelectedInstance') -and $AppState['SelectedInstance']) {
                $selectedName = [string]$AppState['SelectedInstance'].Name
            }
        }
        elseif ($AppState.PSObject.Properties['SelectedInstance'] -and $AppState.SelectedInstance) {
            $selectedName = [string]$AppState.SelectedInstance.Name
        }

        if (-not [string]::IsNullOrWhiteSpace($selectedName)) {
            $selected = @($candidates | Where-Object { [string]$_.Name -eq $selectedName } | Select-Object -First 1)
        }
    }

    return $selected
}

function Sync-UGSMSelectedInstanceState {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$AppState,

        [object[]]$Instances = $null
    )

    if (-not $AppState) {
        throw 'AppState is required.'
    }

    $resolvedInstances = if ($null -ne $Instances) {
        @($Instances)
    }
    elseif (Get-Command Get-UGSMInstances -ErrorAction SilentlyContinue) {
        @(Get-UGSMInstances)
    }
    else {
        @()
    }

    $selected = Resolve-UGSMSelectedInstanceFromCollection -AppState $AppState -Instances $resolvedInstances

    if ($selected) {
        Set-UGSMObjectValue -InputObject $AppState -Name 'SelectedInstance' -Value $selected
        Set-UGSMObjectValue -InputObject $AppState -Name 'SelectedInstanceId' -Value ([string]$selected.Id)
        Write-UGSMServiceHelperLog -Level 'DEBUG' -Message ('Selected instance synced: {0}' -f [string]$selected.Id)
    }
    else {
        Set-UGSMObjectValue -InputObject $AppState -Name 'SelectedInstance' -Value $null
        Set-UGSMObjectValue -InputObject $AppState -Name 'SelectedInstanceId' -Value $null
        Write-UGSMServiceHelperLog -Level 'DEBUG' -Message 'Selected instance sync found no matching instance.'
    }

    return (Get-UGSMObjectValue -InputObject $AppState -Name 'SelectedInstance')
}


function Set-UGSMSelectedInstanceState {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$AppState,

        [AllowNull()]
        [object]$Instance
    )

    Initialize-UGSMInstancePageCompatibility

    if (-not $AppState) {
        throw 'AppState is required.'
    }

    if ($Instance) {
        Set-UGSMObjectValue -InputObject $AppState -Name 'SelectedInstance' -Value $Instance
        Set-UGSMObjectValue -InputObject $AppState -Name 'SelectedInstanceId' -Value ([string]$Instance.Id)

        if ($Instance.PSObject.Properties['GameId'] -and -not [string]::IsNullOrWhiteSpace([string]$Instance.GameId)) {
            Set-UGSMObjectValue -InputObject $AppState -Name 'SelectedGameId' -Value ([string]$Instance.GameId)
        }

        Write-UGSMServiceHelperLog -Level 'DEBUG' -Message ('Selected instance set: {0}' -f [string]$Instance.Id)
    }
    else {
        Set-UGSMObjectValue -InputObject $AppState -Name 'SelectedInstance' -Value $null
        Set-UGSMObjectValue -InputObject $AppState -Name 'SelectedInstanceId' -Value $null
        Write-UGSMServiceHelperLog -Level 'DEBUG' -Message 'Selected instance cleared.'
    }

    return (Get-UGSMObjectValue -InputObject $AppState -Name 'SelectedInstance')
}

function Invoke-UGSMInstanceAction {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('Start', 'Stop', 'Restart')]
        [string]$Action,

        [Parameter(Mandatory)]
        [object]$AppState,

        [Alias('Id')]
        [string]$InstanceId
    )

    if (-not $AppState) {
        throw 'AppState is required.'
    }

    $targetInstanceId = [string]$InstanceId
    $currentSelectedInstance = Get-UGSMObjectValue -InputObject $AppState -Name 'SelectedInstance'
    if ([string]::IsNullOrWhiteSpace($targetInstanceId) -and $currentSelectedInstance) {
        $targetInstanceId = [string]$currentSelectedInstance.Id
    }

    if ([string]::IsNullOrWhiteSpace($targetInstanceId)) {
        throw 'Select an instance first.'
    }

    $updatedInstance = $null
    Write-UGSMServiceHelperLog -Level 'INFO' -Message ('Instance action requested. Action={0}; InstanceId={1}' -f $Action, $targetInstanceId)

    switch ($Action) {
        'Start' {
            if (-not (Get-Command -Name 'Start-UGSMInstance' -ErrorAction SilentlyContinue)) {
                throw 'Start-UGSMInstance is not available.'
            }

            $updatedInstance = Start-UGSMInstance -Id $targetInstanceId
        }
        'Stop' {
            if (-not (Get-Command -Name 'Stop-UGSMInstance' -ErrorAction SilentlyContinue)) {
                throw 'Stop-UGSMInstance is not available.'
            }

            $updatedInstance = Stop-UGSMInstance -Id $targetInstanceId
        }
        'Restart' {
            if (-not (Get-Command -Name 'Stop-UGSMInstance' -ErrorAction SilentlyContinue)) {
                throw 'Stop-UGSMInstance is not available.'
            }
            if (-not (Get-Command -Name 'Start-UGSMInstance' -ErrorAction SilentlyContinue)) {
                throw 'Start-UGSMInstance is not available.'
            }

            $null = Stop-UGSMInstance -Id $targetInstanceId
            $updatedInstance = Start-UGSMInstance -Id $targetInstanceId
        }
    }

    $refreshState = Get-UGSMRefreshedInstancesPageData -AppState $AppState
    $selectedInstance = $refreshState.SelectedInstance
    Write-UGSMServiceHelperLog -Level 'INFO' -Message ('Instance action completed. Action={0}; InstanceId={1}' -f $Action, $targetInstanceId)

    if (-not $selectedInstance -and $updatedInstance) {
        $selectedInstance = Set-UGSMSelectedInstanceState -AppState $AppState -Instance $updatedInstance
    }

    return [pscustomobject]@{
        Action           = $Action
        UpdatedInstance  = $updatedInstance
        PageData         = $refreshState.PageData
        SelectedInstance = $selectedInstance
    }
}

function Get-UGSMRefreshedInstancesPageData {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$AppState
    )

    $pageData = if (Get-Command Get-UGSMInstancesPageData -ErrorAction SilentlyContinue) {
        Get-UGSMInstancesPageData
    }
    else {
        [pscustomobject]@{
            TotalCount    = 0
            RunningCount  = 0
            StartingCount = 0
            StoppedCount  = 0
            Instances     = @()
        }
    }

    $selected = Sync-UGSMSelectedInstanceState -AppState $AppState -Instances @($pageData.Instances)
    Write-UGSMServiceHelperLog -Level 'DEBUG' -Message ('Instances page data refreshed. Total={0}; Running={1}; Selected={2}' -f $pageData.TotalCount, $pageData.RunningCount, $(if ($selected) { [string]$selected.Id } else { '' }))

    return [pscustomobject]@{
        PageData         = $pageData
        SelectedInstance = $selected
    }
}

function Remove-UGSMProfileAndRefresh {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$AppState,

        [Parameter(Mandatory)]
        [string]$Id
    )

    Initialize-UGSMInstancePageCompatibility

    if (-not (Get-Command Remove-UGSMInstance -ErrorAction SilentlyContinue)) {
        throw 'Remove-UGSMInstance is not available.'
    }

    Write-UGSMServiceHelperLog -Level 'INFO' -Message ('Remove profile requested. InstanceId={0}' -f $Id)
    $removed = Remove-UGSMInstance -Id $Id
    $refresh = Get-UGSMRefreshedInstancesPageData -AppState $AppState
    Write-UGSMServiceHelperLog -Level 'INFO' -Message ('Remove profile completed. InstanceId={0}' -f $Id)

    return [pscustomobject]@{
        Removed          = $removed
        PageData         = $refresh.PageData
        SelectedInstance = $refresh.SelectedInstance
    }
}
