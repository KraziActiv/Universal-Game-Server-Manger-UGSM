# Discord module


function Write-UGSMDiscordLog {
    [CmdletBinding()]
    param(
        [ValidateSet('TRACE','DEBUG','INFO','WARN','ERROR','FATAL')]
        [string]$Level = 'INFO',
        [string]$Message,
        [System.Exception]$Exception
    )

    if (Get-Command Write-UGSMLog -ErrorAction SilentlyContinue) {
        if ($Exception) {
            Write-UGSMLog -Level $Level -Category 'Discord' -Message $Message -Exception $Exception
        }
        else {
            Write-UGSMLog -Level $Level -Category 'Discord' -Message $Message
        }
        return
    }

    if (Get-Command Write-UGSMTrace -ErrorAction SilentlyContinue) {
        Write-UGSMTrace -Component 'Discord' -Message ("[$Level] $Message")
        return
    }

    Write-Host ("[$Level] [Discord] $Message")
}

function Get-UGSMDiscordObjectValue {
    [CmdletBinding()]
    param(
        [AllowNull()]
        [object]$Object,
        [string[]]$Names,
        [AllowNull()]
        [object]$DefaultValue = $null
    )

    if (-not $Object) { return $DefaultValue }

    foreach ($name in @($Names)) {
        if ([string]::IsNullOrWhiteSpace($name)) { continue }
        if ($Object -is [hashtable] -and $Object.ContainsKey($name)) {
            return $Object[$name]
        }
        if ($Object.PSObject.Properties[$name]) {
            return $Object.$name
        }
    }

    return $DefaultValue
}

function Get-UGSMDiscordInstanceId {
    [CmdletBinding()]
    param([AllowNull()][object]$Instance)

    $value = Get-UGSMDiscordObjectValue -Object $Instance -Names @('Id','InstanceId','ProfileId','Name') -DefaultValue ''
    return [string]$value
}

function Get-UGSMDiscordWebhookTargetLabel {
    [CmdletBinding()]
    param(
        [string]$WebhookUrl,
        [AllowNull()]
        [object]$DiscordModel
    )

    $source = 'unknown'
    if ($DiscordModel -and $DiscordModel.PSObject.Properties['UsesGlobalWebhook'] -and [bool]$DiscordModel.UsesGlobalWebhook) {
        $source = 'global-secret'
    }
    elseif ($DiscordModel -and $DiscordModel.PSObject.Properties['WebhookUrl'] -and -not [string]::IsNullOrWhiteSpace([string]$DiscordModel.WebhookUrl)) {
        $source = 'instance'
    }

    $webhookHost = 'unknown-host'
    try {
        $uri = [System.Uri]$WebhookUrl
        if (-not [string]::IsNullOrWhiteSpace($uri.Host)) { $webhookHost = $uri.Host }
    }
    catch {}

    return ('{0}:{1}' -f $source, $webhookHost)
}

function ConvertTo-UGSMDiscordFieldValue {
    [CmdletBinding()]
    param([AllowNull()][object]$Value)

    if ($null -eq $Value) { return '' }
    $text = [string]$Value
    if ([string]::IsNullOrWhiteSpace($text)) { return '' }
    return $text
}

function Send-UGSMDiscordWebhookMessage {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$WebhookUrl,

        [string]$Content,
        [string]$Username = 'UGSM',
        [string]$AvatarUrl,
        [hashtable[]]$Embeds,
        [switch]$Wait
    )

    $WebhookUrl = ([string]$WebhookUrl).Trim()
    if ([string]::IsNullOrWhiteSpace($WebhookUrl)) {
        throw 'Discord webhook URL is required.'
    }

    $payload = [ordered]@{}
    if (-not [string]::IsNullOrWhiteSpace([string]$Content)) {
        $payload.content = [string]$Content   
    }
    if (-not [string]::IsNullOrWhiteSpace([string]$Username)) {
        $payload.username = [string]$Username  
    }
    if (-not [string]::IsNullOrWhiteSpace([string]$AvatarUrl)) {
        $payload.avatar_url = [string]$AvatarUrl 
    }
    if ($Embeds -and $Embeds.Count -gt 0) {
        $payload.embeds = @($Embeds)  
    }

    if ($payload.Count -eq 0) {
        throw 'Discord webhook payload is empty.'
    }

    $uriText = ([string]$WebhookUrl).Trim()
    $uriText = $uriText.Trim('"', "'")
    $uriText = $uriText -replace '[\r\n\t]', ''

    if ($Wait.IsPresent -and $uriText -notmatch '\?') {
        $uriText = $uriText + '?wait=true'
    }
    elseif ($Wait.IsPresent -and $uriText -notmatch 'wait=') {
        $uriText = $uriText + '&wait=true'
    }

    $parsedUri = $null
    if (-not [System.Uri]::TryCreate($uriText, [System.UriKind]::Absolute, [ref]$parsedUri)) {
        return [pscustomobject]@{
            Success    = $false
            WebhookUrl = $WebhookUrl
            Response   = $null
            Error      = "Webhook URL failed URI validation: [$uriText]"
        }
    }

    if ([string]::IsNullOrWhiteSpace($parsedUri.Host)) {
        return [pscustomobject]@{
            Success    = $false
            WebhookUrl = $WebhookUrl
            Response   = $null
            Error      = "Webhook URL parsed without a valid host: [$uriText]"
        }
    }

    if ($parsedUri.Scheme -notin @('http', 'https')) {
        return [pscustomobject]@{
            Success    = $false
            WebhookUrl = $WebhookUrl
            Response   = $null
            Error      = "Webhook URL has an invalid scheme: [$($parsedUri.Scheme)]"
        }
    }

    $json = $payload | ConvertTo-Json -Depth 8 -Compress

    try {
        try {
            $tls12 = [Net.SecurityProtocolType]::Tls12
            if (([Net.ServicePointManager]::SecurityProtocol -band $tls12) -ne $tls12) {
                [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor $tls12
            }
        }
        catch {}

        Write-UGSMDiscordLog -Level 'DEBUG' -Message ('Discord webhook POST started. TargetHost={0}; PayloadBytes={1}; Wait={2}' -f $parsedUri.Host, ([System.Text.Encoding]::UTF8.GetByteCount($json)), [bool]$Wait.IsPresent)

        $response = Invoke-RestMethod -Uri $parsedUri.AbsoluteUri -Method Post -ContentType 'application/json; charset=utf-8' -Body $json -ErrorAction Stop -TimeoutSec 30

        Write-UGSMDiscordLog -Level 'DEBUG' -Message ('Discord webhook POST succeeded. TargetHost={0}; Wait={1}' -f $parsedUri.Host, [bool]$Wait.IsPresent)

        return [pscustomobject]@{
            Success    = $true
            WebhookUrl = $WebhookUrl
            Response   = $response
            Error      = $null
        }
    }
    catch {
        Write-UGSMDiscordLog -Level 'WARN' -Message ('Discord webhook POST failed. TargetHost={0}; Error={1}' -f $parsedUri.Host, [string]$_.Exception.Message) -Exception $_.Exception

        return [pscustomobject]@{
            Success    = $false
            WebhookUrl = $WebhookUrl
            Response   = $null
            Error      = $_.Exception.Message
        }
    }
}

function Test-UGSMDiscordWebhook {
    [CmdletBinding()]
    param(
        [string]$WebhookUrl,
        [string]$Label = 'UGSM test'
    )

    $WebhookUrl = ([string]$WebhookUrl).Trim()
    if ([string]::IsNullOrWhiteSpace($WebhookUrl)) {
        throw 'Discord webhook URL is required for test.'
    }
    
    $content = "[$Label] Discord webhook test sent at $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')."
    Write-UGSMDiscordLog -Level 'INFO' -Message ('Discord webhook test requested. Label={0}' -f [string]$Label)
    $result = Send-UGSMDiscordWebhookMessage -WebhookUrl $WebhookUrl -Content $content -Username 'UGSM' -Wait
    if ($result -and $result.Success) {
        Write-UGSMDiscordLog -Level 'INFO' -Message ('Discord webhook test succeeded. Label={0}' -f [string]$Label)
    }
    else {
        $errorText = if ($result) { [string]$result.Error } else { 'No result returned.' }
        Write-UGSMDiscordLog -Level 'WARN' -Message ('Discord webhook test failed. Label={0}; Error={1}' -f [string]$Label, $errorText)
    }
    return $result
}

function Send-UGSMInstanceDiscordNotification {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Instance,

        [Parameter(Mandatory)]
        [ValidateSet('Start', 'Stop', 'Test')]
        [string]$Event,

        [AllowNull()]
        [object]$GlobalSettingsModel,

        [string]$Message,
        [string]$Status,
        [hashtable]$ExtraFields
    )

    $discord = Get-UGSMInstanceDiscordSettingsModel -Instance $Instance -GlobalSettingsModel $GlobalSettingsModel
    $instanceIdForLog = Get-UGSMDiscordInstanceId -Instance $Instance

    if (-not $discord.HasWebhook) {
        Write-UGSMDiscordLog -Level 'DEBUG' -Message ('Instance Discord notification skipped. Event={0}; InstanceId={1}; Reason=NoWebhook' -f $Event, $instanceIdForLog)
        return [pscustomobject]@{
            Success = $false
            Skipped = $true
            Reason  = 'No effective Discord webhook is configured.'
        }
    }

    switch ($Event) {
        'Start' {
            if (-not $discord.NotifyOnStart) {
                Write-UGSMDiscordLog -Level 'DEBUG' -Message ('Instance Discord notification skipped. Event=Start; InstanceId={0}; Reason=NotifyOnStartDisabled' -f $instanceIdForLog)
                return [pscustomobject]@{ Success = $false; Skipped = $true; Reason = 'NotifyOnStart is disabled.' }
            }
            $title = 'Server Started'
            $defaultStatus = 'Running'
            $color = 5763719
        }
        'Stop' {
            if (-not $discord.NotifyOnStop) {
                Write-UGSMDiscordLog -Level 'DEBUG' -Message ('Instance Discord notification skipped. Event=Stop; InstanceId={0}; Reason=NotifyOnStopDisabled' -f $instanceIdForLog)
                return [pscustomobject]@{ Success = $false; Skipped = $true; Reason = 'NotifyOnStop is disabled.' }
            }
            $title = 'Server Stopped'
            $defaultStatus = 'Stopped'
            $color = 15548997
        }
        default {
            $title = 'Server Webhook Test'
            $defaultStatus = 'Test'
            $color = 3447003
        }
    }

    $instanceName = ''
    if ($Instance.PSObject.Properties['Name']) { $instanceName = [string]$Instance.Name }
    if ([string]::IsNullOrWhiteSpace($instanceName) -and $Instance.PSObject.Properties['Id']) { $instanceName = [string]$Instance.Id }

    $gameId = ''
    if ($Instance.PSObject.Properties['GameId']) { $gameId = [string]$Instance.GameId }
    $profilePath = ''
    if ($Instance.PSObject.Properties['ProfilePath']) { $profilePath = [string]$Instance.ProfilePath }
    $statusValue = if ([string]::IsNullOrWhiteSpace([string]$Status)) { $defaultStatus } else { [string]$Status }

    $serverFieldValue = if ([string]::IsNullOrWhiteSpace($instanceName)) { 'Unknown' } else { $instanceName }
    $gameFieldValue = if ([string]::IsNullOrWhiteSpace($gameId)) { 'Unknown' } else { $gameId }

    $fields = @(
        @{ name = 'Server'; value = $serverFieldValue; inline = $true }
        @{ name = 'Game'; value = $gameFieldValue; inline = $true }
        @{ name = 'Status'; value = $statusValue; inline = $true }
    )

    $playersText = Get-UGSMDiscordPlayerStatusText -Instance $Instance -ExtraFields $ExtraFields
    if (-not [string]::IsNullOrWhiteSpace($playersText)) {
        $fields += @{ name = 'Players'; value = $playersText; inline = $true }
    }

    if ($ExtraFields) {
        foreach ($key in $ExtraFields.Keys) {
            if ($key -in @('PlayerCount','CurrentPlayers','OnlinePlayers','PlayersOnline','Players','MaxPlayers','ServerMaxPlayers','Slots')) {
                continue
            }
            $fieldValue = ConvertTo-UGSMDiscordFieldValue -Value $ExtraFields[$key]
            if ([string]::IsNullOrWhiteSpace($fieldValue)) { continue }
            $fields += @{ name = [string]$key; value = $fieldValue; inline = $false }
        }
    }

    $description = if ([string]::IsNullOrWhiteSpace([string]$Message)) {
        switch ($Event) {
            'Start' { 'UGSM detected that this server started successfully.' }
            'Stop' { 'UGSM detected that this server stopped.' }
            default { 'UGSM webhook test notification.' }
        }
    }
    else {
        [string]$Message
    }

    $embed = @{
        title       = $title
        description = $description
        color       = $color
        fields      = $fields
        timestamp   = (Get-Date).ToUniversalTime().ToString('o')
        footer      = @{ text = 'UGSM' }
    }

    $targetLabel = Get-UGSMDiscordWebhookTargetLabel -WebhookUrl $discord.EffectiveWebhookUrl -DiscordModel $discord
    Write-UGSMDiscordLog -Level 'INFO' -Message ('Sending instance Discord notification. Event={0}; InstanceId={1}; Target={2}; Players={3}' -f $Event, $instanceIdForLog, $targetLabel, $(if ([string]::IsNullOrWhiteSpace($playersText)) { 'n/a' } else { $playersText }))

    $sendResult = Send-UGSMDiscordWebhookMessage -WebhookUrl $discord.EffectiveWebhookUrl -Username 'UGSM' -Embeds @($embed) -Wait
    if ($sendResult -and $sendResult.Success) {
        Write-UGSMDiscordLog -Level 'INFO' -Message ('Instance Discord notification sent. Event={0}; InstanceId={1}; Target={2}' -f $Event, $instanceIdForLog, $targetLabel)
    }
    else {
        $errorText = if ($sendResult) { [string]$sendResult.Error } else { 'No result returned.' }
        Write-UGSMDiscordLog -Level 'WARN' -Message ('Instance Discord notification failed. Event={0}; InstanceId={1}; Target={2}; Error={3}' -f $Event, $instanceIdForLog, $targetLabel, $errorText)
    }

    return $sendResult
}

function Get-UGSMDefaultInstanceDiscordData {
    [CmdletBinding()]
    param()

    return [ordered]@{
        WebhookUrl      = ''
        NotifyOnStart   = $false
        NotifyOnStop    = $false
        ShowInDashboard = $false
    }
}

function Merge-UGSMInstanceDiscordData {
    [CmdletBinding()]
    param(
        [AllowNull()]
        [object]$InstanceObject
    )

    $defaults = Get-UGSMDefaultInstanceDiscordData

    $discordSource = $null
    if ($InstanceObject -and $InstanceObject.PSObject.Properties['Discord']) {
        $discordSource = $InstanceObject.Discord
    }

    $webhookUrl = ''
    if ($discordSource -and $discordSource.PSObject.Properties['WebhookUrl'] -and -not [string]::IsNullOrWhiteSpace([string]$discordSource.WebhookUrl)) {
        $webhookUrl = [string]$discordSource.WebhookUrl
    }
    elseif ($InstanceObject -and $InstanceObject.PSObject.Properties['DiscordWebhookUrl'] -and -not [string]::IsNullOrWhiteSpace([string]$InstanceObject.DiscordWebhookUrl)) {
        $webhookUrl = [string]$InstanceObject.DiscordWebhookUrl
    }

    $notifyOnStart = $defaults.NotifyOnStart
    if ($discordSource -and $discordSource.PSObject.Properties['NotifyOnStart']) {
        $notifyOnStart = [bool]$discordSource.NotifyOnStart
    }
    elseif ($InstanceObject -and $InstanceObject.PSObject.Properties['DiscordNotifyStart']) {
        $notifyOnStart = [bool]$InstanceObject.DiscordNotifyStart
    }

    $notifyOnStop = $defaults.NotifyOnStop
    if ($discordSource -and $discordSource.PSObject.Properties['NotifyOnStop']) {
        $notifyOnStop = [bool]$discordSource.NotifyOnStop
    }
    elseif ($InstanceObject -and $InstanceObject.PSObject.Properties['DiscordNotifyStop']) {
        $notifyOnStop = [bool]$InstanceObject.DiscordNotifyStop
    }

    $showInDashboard = $defaults.ShowInDashboard
    if ($discordSource -and $discordSource.PSObject.Properties['ShowInDashboard']) {
        $showInDashboard = [bool]$discordSource.ShowInDashboard
    }
    elseif ($InstanceObject -and $InstanceObject.PSObject.Properties['DiscordVisible']) {
        $showInDashboard = [bool]$InstanceObject.DiscordVisible
    }

    return [pscustomobject]@{
        WebhookUrl      = $webhookUrl
        NotifyOnStart   = $notifyOnStart
        NotifyOnStop    = $notifyOnStop
        ShowInDashboard = $showInDashboard
    }
}

# Later 


function Update-UGSMDiscordWebhookMessage {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$WebhookUrl,

        [Parameter(Mandatory)]
        [string]$MessageId,

        [string]$Content,
        [hashtable[]]$Embeds
    )

    $baseUrl = ([string]$WebhookUrl).Trim()
    $baseUrl = $baseUrl.Trim('"', "'")
    $baseUrl = $baseUrl -replace '[\r\n\t]', ''
    if ([string]::IsNullOrWhiteSpace($baseUrl)) {
        return $false
    }

    $baseUri = $null
    if (-not [System.Uri]::TryCreate($baseUrl, [System.UriKind]::Absolute, [ref]$baseUri)) {
        Write-UGSMDiscordLog -Level 'WARN' -Message 'Dashboard webhook URL failed URI validation for update.'
        return $false
    }

    $editUrl = $baseUri.AbsoluteUri.TrimEnd('/') + '/messages/' + ([string]$MessageId)

    $payload = [ordered]@{}
    if (-not [string]::IsNullOrWhiteSpace([string]$Content)) {
        $payload.content = [string]$Content
    }
    if ($Embeds -and $Embeds.Count -gt 0) {
        $payload.embeds = @($Embeds)
    }
    if ($payload.Count -eq 0) {
        Write-UGSMDiscordLog -Level 'WARN' -Message 'Dashboard update payload was empty.'
        return $false
    }

    $json = $payload | ConvertTo-Json -Depth 8 -Compress

    try {
        try {
            $tls12 = [Net.SecurityProtocolType]::Tls12
            if (([Net.ServicePointManager]::SecurityProtocol -band $tls12) -ne $tls12) {
                [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor $tls12
            }
        }
        catch {}

        Invoke-RestMethod -Uri $editUrl -Method Patch -ContentType 'application/json; charset=utf-8' -Body $json -ErrorAction Stop -TimeoutSec 30 | Out-Null
        Write-UGSMDiscordLog -Level 'DEBUG' -Message ('Dashboard message updated successfully. MessageId={0}' -f [string]$MessageId)
        return $true
    }
    catch {
        Write-UGSMDiscordLog -Level 'WARN' -Message ('Failed to update dashboard message. MessageId={0}; Error={1}' -f [string]$MessageId, [string]$_.Exception.Message) -Exception $_.Exception
        return $false
    }
}


function Get-UGSMDiscordDashboardStateFilePath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$WebhookUrl
    )

    $ugsmRoot = Join-Path $env:LOCALAPPDATA 'UGSM'
    if (-not (Test-Path -LiteralPath $ugsmRoot -PathType Container)) {
        New-Item -Path $ugsmRoot -ItemType Directory -Force | Out-Null
    }

    $discordRoot = Join-Path $ugsmRoot 'Discord'
    if (-not (Test-Path -LiteralPath $discordRoot -PathType Container)) {
        New-Item -Path $discordRoot -ItemType Directory -Force | Out-Null
    }

    $normalized = ([string]$WebhookUrl).Trim().ToLowerInvariant()
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($normalized)
        $hashBytes = $sha.ComputeHash($bytes)
        $hash = ([System.BitConverter]::ToString($hashBytes)).Replace('-', '').ToLowerInvariant()
    }
    finally {
        $sha.Dispose()
    }

    $fileName = 'discord_dashboard_msg_' + $hash + '.json'
    $newPath = Join-Path $discordRoot $fileName
    $legacyPath = Join-Path $ugsmRoot $fileName

    if ((-not (Test-Path -LiteralPath $newPath)) -and (Test-Path -LiteralPath $legacyPath -PathType Leaf)) {
        try {
            Move-Item -LiteralPath $legacyPath -Destination $newPath -Force
        }
        catch {
            try {
                Copy-Item -LiteralPath $legacyPath -Destination $newPath -Force
            }
            catch {}
        }
    }

    return $newPath
}



function Update-UGSMDiscordInstanceRuntimeInfo {
    [CmdletBinding()]
    param([AllowNull()][object]$Instance)

    if (-not $Instance) { return $Instance }

    $statusText = [string](Get-UGSMDiscordPropertyValueSafe -Object $Instance -Names @('Status','State') -DefaultValue '')
    if ($statusText.Trim().ToLowerInvariant() -notin @('running','online','started')) {
        return $Instance
    }

    $gameId = Get-UGSMDiscordObjectValue -Object $Instance -Names @('GameId','Game','GameKey') -DefaultValue ''
    if ([string]::IsNullOrWhiteSpace([string]$gameId)) { return $Instance }

    $handlerName = 'Update-UGSMGame' + ([string]$gameId) + 'DiscordRuntimeInfo'
    $handler = Get-Command -Name $handlerName -ErrorAction SilentlyContinue
    if (-not $handler) { return $Instance }

    try {
        $result = & $handler.Name -Instance $Instance
        if ($result) { return $result }
    }
    catch {
        Write-UGSMDiscordLog -Level 'DEBUG' -Message ('Dashboard runtime info update skipped. GameId={0}; InstanceId={1}; Error={2}' -f [string]$gameId, [string](Get-UGSMDiscordInstanceId -Instance $Instance), [string]$_.Exception.Message)
    }

    return $Instance
}

function Start-UGSMDiscordDashboardRuntimePolling {
    [CmdletBinding()]
    param(
        [object]$GlobalSettingsModel,
        [int]$IntervalMinutes = 5
    )

    if ($IntervalMinutes -lt 1) { $IntervalMinutes = 5 }

    if (-not (Get-Variable -Name 'UGSM_DiscordDashboardRuntimeTimer' -Scope Script -ErrorAction SilentlyContinue)) {
        $script:UGSM_DiscordDashboardRuntimeTimer = $null
    }

    if ($script:UGSM_DiscordDashboardRuntimeTimer) {
        try { $script:UGSM_DiscordDashboardRuntimeTimer.Interval = [Math]::Max(60000, $IntervalMinutes * 60000) } catch {}
        return $script:UGSM_DiscordDashboardRuntimeTimer
    }

    try {
        $timer = New-Object System.Windows.Forms.Timer
        $timer.Interval = [Math]::Max(60000, $IntervalMinutes * 60000)
        $timer.Add_Tick({
            try {
                Publish-UGSMDiscordDashboard -GlobalSettingsModel $null -ForceUpdate | Out-Null
            }
            catch {
                Write-UGSMDiscordLog -Level 'DEBUG' -Message ('Discord dashboard runtime polling tick failed. Error={0}' -f [string]$_.Exception.Message)
            }
        })
        $timer.Start()
        $script:UGSM_DiscordDashboardRuntimeTimer = $timer
        Write-UGSMDiscordLog -Level 'DEBUG' -Message ('Discord dashboard runtime polling started. IntervalMinutes={0}' -f [int]$IntervalMinutes)
        return $timer
    }
    catch {
        Write-UGSMDiscordLog -Level 'DEBUG' -Message ('Discord dashboard runtime polling could not start. Error={0}' -f [string]$_.Exception.Message)
        return $null
    }
}

function Publish-UGSMDiscordDashboard {
    [CmdletBinding()]
    param(
        [object]$GlobalSettingsModel,
        [switch]$ForceUpdate
    )

    Write-UGSMDiscordLog -Level 'DEBUG' -Message ('Discord dashboard publish requested. ForceUpdate={0}' -f [bool]$ForceUpdate.IsPresent)

    if (-not $GlobalSettingsModel -and (Get-Command Get-UGSMGlobalSettingsModel -ErrorAction SilentlyContinue)) {
        try {
            $GlobalSettingsModel = Get-UGSMGlobalSettingsModel
        }
        catch {
            $GlobalSettingsModel = $null
        }
    }

    Start-UGSMDiscordDashboardRuntimePolling -GlobalSettingsModel $GlobalSettingsModel -IntervalMinutes 5 | Out-Null

    if (-not (Get-Command Get-UGSMInstances -ErrorAction SilentlyContinue)) {
        Write-UGSMDiscordLog -Level 'DEBUG' -Message 'Dashboard publish skipped: Get-UGSMInstances not available.'
        return $false
    }

    $globalWebhookUrl = ''
    if ($GlobalSettingsModel -and $GlobalSettingsModel.PSObject.Properties['GlobalDiscordWebhookUrl']) {
        $globalWebhookUrl = [string]$GlobalSettingsModel.GlobalDiscordWebhookUrl
    }
    $globalWebhookUrl = ([string]$globalWebhookUrl).Trim()

    $groupsByWebhook = @{}

    foreach ($inst in @(Get-UGSMInstances)) {
        $runtimeInst = Update-UGSMDiscordInstanceRuntimeInfo -Instance $inst
        if ($runtimeInst) { $inst = $runtimeInst }

        $discord = Get-UGSMInstanceDiscordSettingsModel -Instance $inst -GlobalSettingsModel $GlobalSettingsModel

        if (-not $discord.ShowInDashboard) {
            continue
        }

        $targetWebhook = ([string]$discord.EffectiveWebhookUrl).Trim()

        if ([string]::IsNullOrWhiteSpace($targetWebhook)) {
            Write-UGSMDiscordLog -Level 'DEBUG' -Message ('Skipping dashboard entry for instance without effective webhook. Instance={0}' -f [string]$inst.Name)
            continue
        }

        if (-not $groupsByWebhook.ContainsKey($targetWebhook)) {
            $groupsByWebhook[$targetWebhook] = @()
        }

        $groupsByWebhook[$targetWebhook] += , $inst
    }

    if ($groupsByWebhook.Count -eq 0) {
        Write-UGSMDiscordLog -Level 'DEBUG' -Message 'Dashboard publish skipped: no dashboard-visible instances with an effective webhook.'
        return $false
    }

    $overallSuccess = $true

    foreach ($webhookUrl in @($groupsByWebhook.Keys)) {
        $instancesForWebhook = @($groupsByWebhook[$webhookUrl])
        $embed = New-UGSMDiscordDashboardEmbed -Instances $instancesForWebhook
        $msgFile = Get-UGSMDiscordDashboardStateFilePath -WebhookUrl $webhookUrl

        $storedData = $null
        if (Test-Path -LiteralPath $msgFile) {
            try {
                $storedData = Get-Content -LiteralPath $msgFile -Raw | ConvertFrom-Json
            }
            catch {
                $storedData = $null
            }
        }

        $webhookFingerprint = ([string]$webhookUrl).Trim().ToLowerInvariant()
        if ($storedData -and $storedData.PSObject.Properties['WebhookFingerprint']) {
            if ([string]$storedData.WebhookFingerprint -ne $webhookFingerprint) {
                Write-UGSMDiscordLog -Level 'DEBUG' -Message 'Dashboard webhook changed. Clearing saved message id.'
                $storedData = $null
            }
        }

        $lastUpdate = [DateTime]::MinValue
        if ($storedData -and $storedData.PSObject.Properties['LastUpdateUtc'] -and -not [string]::IsNullOrWhiteSpace([string]$storedData.LastUpdateUtc)) {
            try { $lastUpdate = [DateTime]::Parse([string]$storedData.LastUpdateUtc) } catch { $lastUpdate = [DateTime]::MinValue }
        }

        $minutesSinceUpdate = ([DateTime]::UtcNow - $lastUpdate.ToUniversalTime()).TotalMinutes
        if (-not $ForceUpdate -and $storedData -and $storedData.PSObject.Properties['MessageId'] -and -not [string]::IsNullOrWhiteSpace([string]$storedData.MessageId) -and $minutesSinceUpdate -lt 5) {
            Write-UGSMDiscordLog -Level 'DEBUG' -Message ('Skipping scheduled dashboard update for webhook target. MinutesSinceUpdate={0}' -f [Math]::Round($minutesSinceUpdate, 1))
            continue
        }

        $updated = $false
        if ($storedData -and $storedData.PSObject.Properties['MessageId'] -and -not [string]::IsNullOrWhiteSpace([string]$storedData.MessageId)) {
            $updated = Update-UGSMDiscordWebhookMessage -WebhookUrl $webhookUrl -MessageId ([string]$storedData.MessageId) -Embeds @($embed)
        }

        if (-not $updated) {
            Write-UGSMDiscordLog -Level 'INFO' -Message ('Publishing new Discord dashboard message. ServerCount={0}' -f [string]$instancesForWebhook.Count)
            $response = Send-UGSMDiscordWebhookMessage -WebhookUrl $webhookUrl -Username 'UGSM Dashboard' -Embeds @($embed) -Wait
            if (-not $response.Success) {
                Write-UGSMDiscordLog -Level 'WARN' -Message ('Dashboard publish failed. Error={0}' -f [string]$response.Error)
                $overallSuccess = $false
                continue
            }

            if (-not $response.Response -or -not $response.Response.id) {
                Write-UGSMDiscordLog -Level 'WARN' -Message 'Dashboard publish succeeded but no message id was returned.'
                $overallSuccess = $false
                continue
            }

            $storedData = [pscustomobject]@{
                MessageId          = [string]$response.Response.id
                LastUpdateUtc      = [DateTime]::UtcNow.ToString('o')
                WebhookFingerprint = $webhookFingerprint
            }
        }
        else {
            $storedData = [pscustomobject]@{
                MessageId          = [string]$storedData.MessageId
                LastUpdateUtc      = [DateTime]::UtcNow.ToString('o')
                WebhookFingerprint = $webhookFingerprint
            }
        }

        $storedData | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $msgFile -Encoding UTF8
        $targetLabel = if ($webhookUrl -eq $globalWebhookUrl -and -not [string]::IsNullOrWhiteSpace($globalWebhookUrl)) { 'global' } else { 'private' }
        Write-UGSMDiscordLog -Level 'INFO' -Message ('Discord dashboard updated successfully. Target={0}; MessageId={1}; ServerCount={2}' -f $targetLabel, [string]$storedData.MessageId, [string]$instancesForWebhook.Count)
    }

    return $overallSuccess
}


# -----------------------------------------------------------------------------
# Secret-safe Discord overrides
# Private per-instance webhook URLs must never be persisted into instance/profile
# JSON. They are stored in %LOCALAPPDATA%\UGSM\secrets.json under
# InstanceDiscordWebhooks, protected with the same Windows-user secret mechanism
# as the global Discord webhook and Steam password.
# -----------------------------------------------------------------------------
function Get-UGSMDiscordInstanceSecretId {
    [CmdletBinding()]
    param([AllowNull()][object]$Instance)

    $gameId = Get-UGSMDiscordObjectValue -Object $Instance -Names @('GameId','Game','GameKey') -DefaultValue 'UnknownGame'
    $instanceId = Get-UGSMDiscordInstanceId -Instance $Instance
    if ([string]::IsNullOrWhiteSpace([string]$instanceId)) {
        $instanceId = Get-UGSMDiscordObjectValue -Object $Instance -Names @('ProfileName','DisplayName','Name') -DefaultValue 'UnknownInstance'
    }

    $stableText = ([string]$gameId).Trim().ToLowerInvariant() + '|' + ([string]$instanceId).Trim().ToLowerInvariant()
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($stableText)
        $hashBytes = $sha.ComputeHash($bytes)
        return ([System.BitConverter]::ToString($hashBytes)).Replace('-', '').ToLowerInvariant()
    }
    finally {
        $sha.Dispose()
    }
}

function Get-UGSMDiscordRawSecretsObject {
    [CmdletBinding()]
    param()

    $path = Get-UGSMSecretsPath
    if (Test-Path -LiteralPath $path -PathType Leaf) {
        try {
            $rawText = Get-Content -LiteralPath $path -Raw -ErrorAction Stop
            if (-not [string]::IsNullOrWhiteSpace($rawText)) {
                return ($rawText | ConvertFrom-Json -ErrorAction Stop)
            }
        }
        catch {}
    }

    return [pscustomobject]@{}
}

function Save-UGSMDiscordRawSecretsObject {
    [CmdletBinding()]
    param([Parameter(Mandatory)][object]$Secrets)

    $path = Get-UGSMSecretsPath
    $dir = Split-Path -Path $path -Parent
    if (-not (Test-Path -LiteralPath $dir -PathType Container)) {
        New-Item -Path $dir -ItemType Directory -Force | Out-Null
    }

    $Secrets | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $path -Encoding UTF8
}

function Save-UGSMDiscordInstanceWebhookSecret {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$Instance,
        [AllowNull()][string]$WebhookUrl
    )

    $secretId = Get-UGSMDiscordInstanceSecretId -Instance $Instance
    $trimmedWebhook = ([string]$WebhookUrl).Trim()

    # A masked webhook value means the editor loaded an existing private secret.
    # Preserve it instead of clearing or overwriting the stored secret.
    if ($trimmedWebhook -match '^\*{4,}$') {
        $existingSecret = Get-UGSMDiscordInstanceWebhookSecret -Instance $Instance
        return [pscustomobject]@{
            SecretId = $secretId
            HasPrivateWebhook = [bool](-not [string]::IsNullOrWhiteSpace([string]$existingSecret))
        }
    }

    $raw = Get-UGSMDiscordRawSecretsObject

    if (-not $raw.PSObject.Properties['SteamPassword']) {
        $raw | Add-Member -NotePropertyName 'SteamPassword' -NotePropertyValue $null -Force
    }
    if (-not $raw.PSObject.Properties['DiscordWebhook']) {
        $raw | Add-Member -NotePropertyName 'DiscordWebhook' -NotePropertyValue $null -Force
    }
    if (-not $raw.PSObject.Properties['InstanceDiscordWebhooks'] -or $null -eq $raw.InstanceDiscordWebhooks) {
        $raw | Add-Member -NotePropertyName 'InstanceDiscordWebhooks' -NotePropertyValue ([pscustomobject]@{}) -Force
    }

    if ([string]::IsNullOrWhiteSpace($trimmedWebhook)) {
        try {
            if ($raw.InstanceDiscordWebhooks.PSObject.Properties[$secretId]) {
                $raw.InstanceDiscordWebhooks.PSObject.Properties.Remove($secretId)
            }
        }
        catch {}
        Save-UGSMDiscordRawSecretsObject -Secrets $raw
        return [pscustomobject]@{ SecretId = $secretId; HasPrivateWebhook = $false }
    }

    $protectedWebhook = Protect-UGSMSecret -Value $trimmedWebhook
    if ($raw.InstanceDiscordWebhooks.PSObject.Properties[$secretId]) {
        $raw.InstanceDiscordWebhooks.$secretId = $protectedWebhook
    }
    else {
        $raw.InstanceDiscordWebhooks | Add-Member -NotePropertyName $secretId -NotePropertyValue $protectedWebhook -Force
    }

    Save-UGSMDiscordRawSecretsObject -Secrets $raw
    return [pscustomobject]@{ SecretId = $secretId; HasPrivateWebhook = $true }
}

function Clear-UGSMInstanceDiscordPlainTextSecrets {
    [CmdletBinding()]
    param([Parameter(Mandatory)][object]$Instance)

    if ($Instance.PSObject.Properties['Discord'] -and $null -ne $Instance.Discord) {
        if ($Instance.Discord.PSObject.Properties['WebhookUrl']) { $Instance.Discord.WebhookUrl = '' }
        else { $Instance.Discord | Add-Member -NotePropertyName 'WebhookUrl' -NotePropertyValue '' -Force }
    }

    foreach ($legacyName in @('DiscordWebhookUrl','PrivateDiscordWebhookUrl','InstanceDiscordWebhookUrl','WebhookUrl','PrivateWebhookUrl')) {
        if ($Instance.PSObject.Properties[$legacyName]) {
            $Instance.($legacyName) = ''
        }
    }

    return $Instance
}

function ConvertTo-UGSMDiscordStrictBoolean {
    [CmdletBinding()]
    param([AllowNull()][object]$Value)

    if ($null -eq $Value) { return $false }
    if ($Value -is [bool]) { return [bool]$Value }

    $text = ([string]$Value).Trim()
    if ([string]::IsNullOrWhiteSpace($text)) { return $false }

    switch -Regex ($text.ToLowerInvariant()) {
        '^(true|1|yes|y|on|checked)$' { return $true }
        '^(false|0|no|n|off|unchecked)$' { return $false }
        default { return $false }
    }
}

function Convert-UGSMDiscordStrictBoolean { param([AllowNull()][object]$Value) return (ConvertTo-UGSMDiscordStrictBoolean -Value $Value) }
function Covert-UGSMDiscordStrictBoolean { param([AllowNull()][object]$Value) return (ConvertTo-UGSMDiscordStrictBoolean -Value $Value) }

function Set-UGSMInstanceDiscordSettings {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$Instance,
        [AllowNull()][object]$Discord
    )

    $inputWebhookUrl = ''
    if ($Discord -and $Discord.PSObject.Properties['WebhookUrl']) {
        $inputWebhookUrl = ([string]$Discord.WebhookUrl).Trim()
    }

    $notifyOnStart = if ($Discord -and $Discord.PSObject.Properties['NotifyOnStart']) { ConvertTo-UGSMDiscordStrictBoolean -Value $Discord.NotifyOnStart } else { $false }
    $notifyOnStop = if ($Discord -and $Discord.PSObject.Properties['NotifyOnStop']) { ConvertTo-UGSMDiscordStrictBoolean -Value $Discord.NotifyOnStop } else { $false }
    $showInDashboard = if ($Discord -and $Discord.PSObject.Properties['ShowInDashboard']) { ConvertTo-UGSMDiscordStrictBoolean -Value $Discord.ShowInDashboard } else { $false }

    $secretResult = Save-UGSMDiscordInstanceWebhookSecret -Instance $Instance -WebhookUrl $inputWebhookUrl
    $hasPrivate = [bool]$secretResult.HasPrivateWebhook
    $secretId = if ($hasPrivate) { [string]$secretResult.SecretId } else { '' }

    $safeDiscord = [pscustomobject]@{
        WebhookUrl             = ''
        NotifyOnStart          = [bool]$notifyOnStart
        NotifyOnStop           = [bool]$notifyOnStop
        ShowInDashboard        = [bool]$showInDashboard
        PrivateWebhookSecretId = $secretId
        WebhookSecretId        = $secretId
        HasPrivateWebhook      = $hasPrivate
        WebhookIsSecret        = $hasPrivate
    }

    if ($Instance.PSObject.Properties['Discord']) { $Instance.Discord = $safeDiscord }
    else { $Instance | Add-Member -NotePropertyName 'Discord' -NotePropertyValue $safeDiscord -Force }

    foreach ($entry in @(
        @{ Name = 'DiscordWebhookUrl'; Value = '' },
        @{ Name = 'PrivateDiscordWebhookUrl'; Value = '' },
        @{ Name = 'InstanceDiscordWebhookUrl'; Value = '' },
        @{ Name = 'PrivateWebhookUrl'; Value = '' },
        @{ Name = 'WebhookUrl'; Value = '' },
        @{ Name = 'DiscordNotifyStart'; Value = [bool]$notifyOnStart },
        @{ Name = 'DiscordNotifyStop'; Value = [bool]$notifyOnStop },
        @{ Name = 'DiscordVisible'; Value = [bool]$showInDashboard },
        @{ Name = 'DiscordWebhookSecretId'; Value = $secretId },
        @{ Name = 'PrivateDiscordWebhookSecretId'; Value = $secretId },
        @{ Name = 'InstanceDiscordWebhookSecretId'; Value = $secretId },
        @{ Name = 'HasPrivateDiscordWebhook'; Value = $hasPrivate }
    )) {
        if ($Instance.PSObject.Properties[$entry.Name]) { $Instance.($entry.Name) = $entry.Value }
        else { $Instance | Add-Member -NotePropertyName $entry.Name -NotePropertyValue $entry.Value -Force }
    }

    return (Clear-UGSMInstanceDiscordPlainTextSecrets -Instance $Instance)
}

function Get-UGSMNormalizedInstanceDiscordSettings {
    [CmdletBinding()]
    param([AllowNull()][object]$Instance)

    $notifyOnStart = $false
    $notifyOnStop = $false
    $showInDashboard = $false

    if ($Instance -and $Instance.PSObject.Properties['Discord'] -and $Instance.Discord) {
        if ($Instance.Discord.PSObject.Properties['NotifyOnStart']) { $notifyOnStart = ConvertTo-UGSMDiscordStrictBoolean -Value $Instance.Discord.NotifyOnStart }
        if ($Instance.Discord.PSObject.Properties['NotifyOnStop']) { $notifyOnStop = ConvertTo-UGSMDiscordStrictBoolean -Value $Instance.Discord.NotifyOnStop }
        if ($Instance.Discord.PSObject.Properties['ShowInDashboard']) { $showInDashboard = ConvertTo-UGSMDiscordStrictBoolean -Value $Instance.Discord.ShowInDashboard }
    }
    else {
        if ($Instance -and $Instance.PSObject.Properties['DiscordNotifyStart']) { $notifyOnStart = ConvertTo-UGSMDiscordStrictBoolean -Value $Instance.DiscordNotifyStart }
        if ($Instance -and $Instance.PSObject.Properties['DiscordNotifyStop']) { $notifyOnStop = ConvertTo-UGSMDiscordStrictBoolean -Value $Instance.DiscordNotifyStop }
        if ($Instance -and $Instance.PSObject.Properties['DiscordVisible']) { $showInDashboard = ConvertTo-UGSMDiscordStrictBoolean -Value $Instance.DiscordVisible }
    }

    return [pscustomobject]@{
        WebhookUrl      = ''
        NotifyOnStart   = [bool]$notifyOnStart
        NotifyOnStop    = [bool]$notifyOnStop
        ShowInDashboard = [bool]$showInDashboard
    }
}

function Save-UGSMInstanceDiscordSettingsModel {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$Instance,
        [Parameter(Mandatory)][object]$InputObject,
        [scriptblock]$PersistInstance
    )

    $webhookText = ''
    if ($InputObject.PSObject.Properties['WebhookUrl']) {
        $webhookText = ([string]$InputObject.WebhookUrl).Trim()
    }

    $discord = [pscustomobject]@{
        WebhookUrl      = $webhookText
        NotifyOnStart   = if ($InputObject.PSObject.Properties['NotifyOnStart']) { ConvertTo-UGSMDiscordStrictBoolean -Value $InputObject.NotifyOnStart } else { $false }
        NotifyOnStop    = if ($InputObject.PSObject.Properties['NotifyOnStop']) { ConvertTo-UGSMDiscordStrictBoolean -Value $InputObject.NotifyOnStop } else { $false }
        ShowInDashboard = if ($InputObject.PSObject.Properties['ShowInDashboard']) { ConvertTo-UGSMDiscordStrictBoolean -Value $InputObject.ShowInDashboard } else { $false }
    }

    $updatedInstance = Set-UGSMInstanceDiscordSettings -Instance $Instance -Discord $discord

    if ($PersistInstance) {
        & $PersistInstance $updatedInstance | Out-Null
    }
    elseif (Get-Command -Name Save-UGSMInstance -ErrorAction SilentlyContinue) {
        $updatedInstance = Save-UGSMInstance -Instance $updatedInstance
    }

    # Safety pass: make sure stale plaintext from another save path cannot survive
    # after this Discord save has completed.
    try {
        $definitionPath = $null
        if ($updatedInstance.PSObject.Properties['DefinitionPath'] -and -not [string]::IsNullOrWhiteSpace([string]$updatedInstance.DefinitionPath)) {
            $definitionPath = [string]$updatedInstance.DefinitionPath
        }
        elseif ($updatedInstance.PSObject.Properties['ProfilePath'] -and -not [string]::IsNullOrWhiteSpace([string]$updatedInstance.ProfilePath)) {
            $candidate = Join-Path ([string]$updatedInstance.ProfilePath) 'instance.json'
            if (Test-Path -LiteralPath $candidate -PathType Leaf) { $definitionPath = $candidate }
        }
        if (-not [string]::IsNullOrWhiteSpace([string]$definitionPath) -and (Test-Path -LiteralPath $definitionPath -PathType Leaf)) {
            $stored = Get-Content -LiteralPath $definitionPath -Raw | ConvertFrom-Json

            $hasPrivate = $false
            $secretId = ''
            if ($updatedInstance.PSObject.Properties['HasPrivateDiscordWebhook']) { $hasPrivate = [bool]$updatedInstance.HasPrivateDiscordWebhook }
            if ($updatedInstance.PSObject.Properties['DiscordWebhookSecretId']) { $secretId = [string]$updatedInstance.DiscordWebhookSecretId }

            $safeDiscord = [pscustomobject]@{
                WebhookUrl             = ''
                NotifyOnStart          = [bool]$discord.NotifyOnStart
                NotifyOnStop           = [bool]$discord.NotifyOnStop
                ShowInDashboard        = [bool]$discord.ShowInDashboard
                PrivateWebhookSecretId = if ($hasPrivate) { $secretId } else { '' }
                WebhookSecretId        = if ($hasPrivate) { $secretId } else { '' }
                HasPrivateWebhook      = [bool]$hasPrivate
                WebhookIsSecret        = [bool]$hasPrivate
            }
            if ($stored.PSObject.Properties['Discord']) { $stored.Discord = $safeDiscord }
            else { $stored | Add-Member -NotePropertyName 'Discord' -NotePropertyValue $safeDiscord -Force }

            foreach ($entry in @(
                @{ Name = 'DiscordWebhookUrl'; Value = '' },
                @{ Name = 'PrivateDiscordWebhookUrl'; Value = '' },
                @{ Name = 'InstanceDiscordWebhookUrl'; Value = '' },
                @{ Name = 'PrivateWebhookUrl'; Value = '' },
                @{ Name = 'WebhookUrl'; Value = '' },
                @{ Name = 'DiscordNotifyStart'; Value = [bool]$discord.NotifyOnStart },
                @{ Name = 'DiscordNotifyStop'; Value = [bool]$discord.NotifyOnStop },
                @{ Name = 'DiscordVisible'; Value = [bool]$discord.ShowInDashboard },
                @{ Name = 'DiscordWebhookSecretId'; Value = if ($hasPrivate) { $secretId } else { '' } },
                @{ Name = 'PrivateDiscordWebhookSecretId'; Value = if ($hasPrivate) { $secretId } else { '' } },
                @{ Name = 'InstanceDiscordWebhookSecretId'; Value = if ($hasPrivate) { $secretId } else { '' } },
                @{ Name = 'HasPrivateDiscordWebhook'; Value = [bool]$hasPrivate }
            )) {
                if ($stored.PSObject.Properties[$entry.Name]) { $stored.($entry.Name) = $entry.Value }
                else { $stored | Add-Member -NotePropertyName $entry.Name -NotePropertyValue $entry.Value -Force }
            }

            $stored = Clear-UGSMInstanceDiscordPlainTextSecrets -Instance $stored
            $stored | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $definitionPath -Encoding UTF8
        }
    }
    catch { }

    $instanceId = Get-UGSMDiscordInstanceId -Instance $updatedInstance
    Write-UGSMDiscordLog -Level 'INFO' -Message ('Instance Discord settings saved. InstanceId={0}; HasInstanceWebhook={1}; WebhookStoredAsSecret={2}; NotifyOnStart={3}; NotifyOnStop={4}; ShowInDashboard={5}' -f $instanceId, [bool]$updatedInstance.HasPrivateDiscordWebhook, [bool]$updatedInstance.HasPrivateDiscordWebhook, [bool]$discord.NotifyOnStart, [bool]$discord.NotifyOnStop, [bool]$discord.ShowInDashboard)

    return [pscustomobject]@{
        Instance = $updatedInstance
        Discord  = Get-UGSMInstanceDiscordSettingsModel -Instance $updatedInstance -GlobalSettingsModel $null
    }
}


# -----------------------------------------------------------------------------
# Final override: dashboard/webhook resolution repair
# Keep this block at the end so it wins over earlier duplicate definitions.
# Scope: Discord only. Private instance webhook secret must win over global.
# -----------------------------------------------------------------------------
function Get-UGSMDiscordPropertyValueSafe {
    [CmdletBinding()]
    param(
        [AllowNull()][object]$Object,
        [string[]]$Names,
        [AllowNull()][object]$DefaultValue = $null
    )

    if ($null -eq $Object) { return $DefaultValue }

    foreach ($name in @($Names)) {
        if ([string]::IsNullOrWhiteSpace([string]$name)) { continue }
        try {
            if ($Object -is [hashtable] -and $Object.ContainsKey($name)) { return $Object[$name] }
            $prop = $Object.PSObject.Properties[[string]$name]
            if ($prop) { return $prop.Value }
        }
        catch { }
    }

    return $DefaultValue
}

function Add-UGSMDiscordCandidateSecretId {
    [CmdletBinding()]
    param(
        [AllowNull()][object]$List,
        [AllowNull()][object]$Value
    )

    if ($null -eq $List) { return }

    $text = ([string]$Value).Trim()
    if ([string]::IsNullOrWhiteSpace($text)) { return }

    try {
        if (-not $List.Contains($text)) { [void]$List.Add($text) }
    }
    catch { }
}


function Get-UGSMDiscordInstanceDefinitionCandidates {
    [CmdletBinding()]
    param([AllowNull()][object]$Instance)

    $paths = New-Object System.Collections.Generic.List[string]
    if (-not $Instance) { return @() }

    $definitionPath = [string](Get-UGSMDiscordPropertyValueSafe -Object $Instance -Names @('DefinitionPath','InstancePath','JsonPath','FilePath') -DefaultValue '')
    if (-not [string]::IsNullOrWhiteSpace($definitionPath)) { [void]$paths.Add($definitionPath) }

    if (Get-Command -Name Get-UGSMInstanceDefinitionFilePath -ErrorAction SilentlyContinue) {
        try {
            $resolved = [string](Get-UGSMInstanceDefinitionFilePath -Instance $Instance)
            if (-not [string]::IsNullOrWhiteSpace($resolved) -and -not $paths.Contains($resolved)) { [void]$paths.Add($resolved) }
        }
        catch { }
    }

    $profilePath = [string](Get-UGSMDiscordPropertyValueSafe -Object $Instance -Names @('ProfilePath') -DefaultValue '')
    if (-not [string]::IsNullOrWhiteSpace($profilePath)) {
        foreach ($fileName in @('instance.json','custom.instance.json','UGSM_CustomProfile.json')) {
            try {
                $candidate = Join-Path $profilePath $fileName
                if (-not $paths.Contains($candidate)) { [void]$paths.Add($candidate) }
            }
            catch { }
        }
    }

    return @($paths)
}

function Get-UGSMDiscordInstanceWebhookSecret {
    [CmdletBinding()]
    param([AllowNull()][object]$Instance)

    if (-not $Instance) { return '' }

    $candidateSecretIds = New-Object System.Collections.Generic.List[string]

    $discordSource = Get-UGSMDiscordPropertyValueSafe -Object $Instance -Names @('Discord') -DefaultValue $null
    foreach ($name in @('PrivateWebhookSecretId','WebhookSecretId','DiscordWebhookSecretId','PrivateDiscordWebhookSecretId','InstanceDiscordWebhookSecretId')) {
        Add-UGSMDiscordCandidateSecretId -List $candidateSecretIds -Value (Get-UGSMDiscordPropertyValueSafe -Object $discordSource -Names @($name) -DefaultValue '')
        Add-UGSMDiscordCandidateSecretId -List $candidateSecretIds -Value (Get-UGSMDiscordPropertyValueSafe -Object $Instance -Names @($name) -DefaultValue '')
    }

    foreach ($path in @(Get-UGSMDiscordInstanceDefinitionCandidates -Instance $Instance)) {
        try {
            if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { continue }
            $stored = Get-Content -LiteralPath $path -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
            $storedDiscord = Get-UGSMDiscordPropertyValueSafe -Object $stored -Names @('Discord') -DefaultValue $null
            foreach ($name in @('PrivateWebhookSecretId','WebhookSecretId','DiscordWebhookSecretId','PrivateDiscordWebhookSecretId','InstanceDiscordWebhookSecretId')) {
                Add-UGSMDiscordCandidateSecretId -List $candidateSecretIds -Value (Get-UGSMDiscordPropertyValueSafe -Object $storedDiscord -Names @($name) -DefaultValue '')
                Add-UGSMDiscordCandidateSecretId -List $candidateSecretIds -Value (Get-UGSMDiscordPropertyValueSafe -Object $stored -Names @($name) -DefaultValue '')
            }
        }
        catch { }
    }

    Add-UGSMDiscordCandidateSecretId -List $candidateSecretIds -Value (Get-UGSMDiscordInstanceSecretId -Instance $Instance)

    $raw = Get-UGSMDiscordRawSecretsObject
    $bag = Get-UGSMDiscordPropertyValueSafe -Object $raw -Names @('InstanceDiscordWebhooks') -DefaultValue $null
    if ($null -eq $bag) { return '' }

    foreach ($secretId in @($candidateSecretIds)) {
        if ([string]::IsNullOrWhiteSpace([string]$secretId)) { continue }
        try {
            $protected = Get-UGSMDiscordPropertyValueSafe -Object $bag -Names @([string]$secretId) -DefaultValue ''
            if (-not [string]::IsNullOrWhiteSpace([string]$protected)) {
                $plain = Unprotect-UGSMSecret ([string]$protected)
                if (-not [string]::IsNullOrWhiteSpace([string]$plain)) { return ([string]$plain).Trim() }
            }
        }
        catch {
            Write-UGSMDiscordLog -Level 'WARN' -Message 'Failed to read private instance Discord webhook secret. Re-save the private webhook if needed.'
            return ''
        }
    }

    return ''
}

function Get-UGSMDiscordGlobalWebhookUrl {
    [CmdletBinding()]
    param([AllowNull()][object]$GlobalSettingsModel)

    if ($null -ne $GlobalSettingsModel) {
        $fromModel = [string](Get-UGSMDiscordPropertyValueSafe -Object $GlobalSettingsModel -Names @('GlobalDiscordWebhookUrl','DiscordWebhookUrl') -DefaultValue '')
        if (-not [string]::IsNullOrWhiteSpace($fromModel)) { return $fromModel.Trim() }
    }

    if (Get-Command -Name Get-UGSMGlobalSettings -ErrorAction SilentlyContinue) {
        try {
            $settings = Get-UGSMGlobalSettings -CreateIfMissing
            $fromSettings = [string](Get-UGSMDiscordPropertyValueSafe -Object $settings -Names @('GlobalDiscordWebhookUrl','DiscordWebhookUrl') -DefaultValue '')
            if (-not [string]::IsNullOrWhiteSpace($fromSettings)) { return $fromSettings.Trim() }
        }
        catch { }
    }

    if (Get-Command -Name Get-UGSMSecrets -ErrorAction SilentlyContinue) {
        try {
            $secrets = Get-UGSMSecrets
            $fromSecrets = [string](Get-UGSMDiscordPropertyValueSafe -Object $secrets -Names @('DiscordWebhook') -DefaultValue '')
            if (-not [string]::IsNullOrWhiteSpace($fromSecrets)) { return $fromSecrets.Trim() }
        }
        catch { }
    }

    return ''
}

function Get-UGSMEffectiveDiscordWebhookUrl {
    [CmdletBinding()]
    param(
        [AllowNull()][object]$Instance,
        [AllowNull()][object]$GlobalSettingsModel
    )

    $privateWebhook = Get-UGSMDiscordInstanceWebhookSecret -Instance $Instance
    if (-not [string]::IsNullOrWhiteSpace([string]$privateWebhook)) {
        return ([string]$privateWebhook).Trim()
    }

    return (Get-UGSMDiscordGlobalWebhookUrl -GlobalSettingsModel $GlobalSettingsModel)
}

function Get-UGSMInstanceDiscordSettingsModel {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$Instance,
        [AllowNull()][object]$GlobalSettingsModel
    )

    $discord = Get-UGSMNormalizedInstanceDiscordSettings -Instance $Instance
    $privateWebhook = Get-UGSMDiscordInstanceWebhookSecret -Instance $Instance
    $globalWebhook = Get-UGSMDiscordGlobalWebhookUrl -GlobalSettingsModel $GlobalSettingsModel
    $effectiveWebhookUrl = if (-not [string]::IsNullOrWhiteSpace([string]$privateWebhook)) { ([string]$privateWebhook).Trim() } else { ([string]$globalWebhook).Trim() }
    $displayWebhookUrl = if (-not [string]::IsNullOrWhiteSpace([string]$privateWebhook)) { '********' } else { '' }

    return [pscustomobject]@{
        WebhookUrl          = [string]$displayWebhookUrl
        NotifyOnStart       = [bool]$discord.NotifyOnStart
        NotifyOnStop        = [bool]$discord.NotifyOnStop
        ShowInDashboard     = [bool]$discord.ShowInDashboard
        EffectiveWebhookUrl = [string]$effectiveWebhookUrl
        UsesGlobalWebhook   = [bool]([string]::IsNullOrWhiteSpace([string]$privateWebhook) -and -not [string]::IsNullOrWhiteSpace([string]$effectiveWebhookUrl))
        HasWebhook          = [bool](-not [string]::IsNullOrWhiteSpace([string]$effectiveWebhookUrl))
        HasPrivateWebhook   = [bool](-not [string]::IsNullOrWhiteSpace([string]$privateWebhook))
        UsesSecretWebhook   = [bool](-not [string]::IsNullOrWhiteSpace([string]$privateWebhook))
    }
}

function Get-UGSMDiscordProjectZomboidIniPath {
    [CmdletBinding()]
    param([AllowNull()][object]$Instance)

    $gameId = [string](Get-UGSMDiscordPropertyValueSafe -Object $Instance -Names @('GameId') -DefaultValue '')
    if ($gameId -notin @('ProjectZomboid','Project Zomboid','PZ')) { return '' }

    $profilePath = [string](Get-UGSMDiscordPropertyValueSafe -Object $Instance -Names @('ProfilePath') -DefaultValue '')
    $name = [string](Get-UGSMDiscordPropertyValueSafe -Object $Instance -Names @('Name','Id') -DefaultValue '')
    if ([string]::IsNullOrWhiteSpace($profilePath) -or [string]::IsNullOrWhiteSpace($name)) { return '' }

    try { return (Join-Path (Join-Path $profilePath 'Server') ($name + '.ini')) } catch { return '' }
}

function Get-UGSMDiscordIniValue {
    [CmdletBinding()]
    param(
        [string]$Path,
        [string[]]$Keys
    )

    if ([string]::IsNullOrWhiteSpace($Path) -or -not (Test-Path -LiteralPath $Path -PathType Leaf)) { return '' }

    try {
        foreach ($line in @(Get-Content -LiteralPath $Path -ErrorAction Stop)) {
            foreach ($key in @($Keys)) {
                if ([string]::IsNullOrWhiteSpace([string]$key)) { continue }
                if ($line -match ('^\s*' + [regex]::Escape([string]$key) + '\s*=\s*(.*?)\s*$')) {
                    return ([string]$Matches[1]).Trim()
                }
            }
        }
    }
    catch { }

    return ''
}


function Get-UGSMDiscord7D2DServerConfigPath {
    [CmdletBinding()]
    param([AllowNull()][object]$Instance)

    $gameId = [string](Get-UGSMDiscordPropertyValueSafe -Object $Instance -Names @('GameId') -DefaultValue '')
    if ($gameId -notin @('7D2D','7 Days to Die','7DaysToDie')) { return '' }

    foreach ($propName in @('ServerConfigPath','ConfigPath','RuntimeConfigPath')) {
        $candidate = [string](Get-UGSMDiscordPropertyValueSafe -Object $Instance -Names @($propName) -DefaultValue '')
        if (-not [string]::IsNullOrWhiteSpace($candidate) -and (Test-Path -LiteralPath $candidate -PathType Leaf)) { return $candidate }
    }

    $profilePath = [string](Get-UGSMDiscordPropertyValueSafe -Object $Instance -Names @('ProfilePath','InstancePath') -DefaultValue '')
    if ([string]::IsNullOrWhiteSpace($profilePath)) { return '' }

    try {
        $candidate = Join-Path $profilePath 'serverconfig.xml'
        if (Test-Path -LiteralPath $candidate -PathType Leaf) { return $candidate }
    }
    catch { }

    return ''
}

function Get-UGSMDiscordXmlPropertyValue {
    [CmdletBinding()]
    param(
        [string]$Path,
        [string[]]$Names
    )

    if ([string]::IsNullOrWhiteSpace($Path) -or -not (Test-Path -LiteralPath $Path -PathType Leaf)) { return '' }

    try {
        [xml]$xml = Get-Content -LiteralPath $Path -Raw -ErrorAction Stop
        foreach ($name in @($Names)) {
            if ([string]::IsNullOrWhiteSpace([string]$name)) { continue }
            $node = $xml.SelectSingleNode("//property[@name='$name']")
            if ($node -and $node.Attributes['value']) { return ([string]$node.Attributes['value'].Value).Trim() }
        }
    }
    catch { }

    return ''
}



function Get-UGSMDiscordVRisingHostSettingsPath {
    [CmdletBinding()]
    param([AllowNull()][object]$Instance)

    $gameId = [string](Get-UGSMDiscordPropertyValueSafe -Object $Instance -Names @('GameId','Game','GameKey') -DefaultValue '')
    if ($gameId -notin @('VRising','V Rising')) { return '' }

    foreach ($propName in @('ServerHostSettingsPath','HostSettingsPath')) {
        $candidate = [string](Get-UGSMDiscordPropertyValueSafe -Object $Instance -Names @($propName) -DefaultValue '')
        if (-not [string]::IsNullOrWhiteSpace($candidate) -and (Test-Path -LiteralPath $candidate -PathType Leaf)) { return $candidate }
    }

    $profilePath = [string](Get-UGSMDiscordPropertyValueSafe -Object $Instance -Names @('ProfilePath','InstancePath') -DefaultValue '')
    if ([string]::IsNullOrWhiteSpace($profilePath)) { return '' }

    try {
        $candidate = Join-Path (Join-Path $profilePath 'Settings') 'ServerHostSettings.json'
        if (Test-Path -LiteralPath $candidate -PathType Leaf) { return $candidate }
    }
    catch { }

    return ''
}

function Get-UGSMDiscordJsonFileValue {
    [CmdletBinding()]
    param(
        [string]$Path,
        [string[]]$Names
    )

    if ([string]::IsNullOrWhiteSpace($Path) -or -not (Test-Path -LiteralPath $Path -PathType Leaf)) { return '' }

    try {
        $json = Get-Content -LiteralPath $Path -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
        foreach ($name in @($Names)) {
            if ([string]::IsNullOrWhiteSpace([string]$name)) { continue }
            $value = Get-UGSMDiscordPropertyValueSafe -Object $json -Names @([string]$name) -DefaultValue $null
            if ($null -ne $value -and -not [string]::IsNullOrWhiteSpace([string]$value)) { return [string]$value }
        }
    }
    catch { }

    return ''
}


function Get-UGSMDiscordTheForestServerConfigPath {
    [CmdletBinding()]
    param([AllowNull()][object]$Instance)

    $gameId = [string](Get-UGSMDiscordPropertyValueSafe -Object $Instance -Names @('GameId','Game','GameKey') -DefaultValue '')
    if ($gameId -notin @('TheForest','The Forest')) { return '' }

    foreach ($propName in @('ServerConfigPath','ConfigPath','RuntimeConfigPath')) {
        $candidate = [string](Get-UGSMDiscordPropertyValueSafe -Object $Instance -Names @($propName) -DefaultValue '')
        if (-not [string]::IsNullOrWhiteSpace($candidate) -and (Test-Path -LiteralPath $candidate -PathType Leaf)) { return $candidate }
    }

    $profilePath = [string](Get-UGSMDiscordPropertyValueSafe -Object $Instance -Names @('ProfilePath','InstancePath') -DefaultValue '')
    if ([string]::IsNullOrWhiteSpace($profilePath)) { return '' }

    try {
        $candidate = Join-Path $profilePath 'Server.cfg'
        if (Test-Path -LiteralPath $candidate -PathType Leaf) { return $candidate }
    }
    catch { }

    return ''
}

function Get-UGSMDiscordCfgValue {
    [CmdletBinding()]
    param(
        [string]$Path,
        [string[]]$Keys
    )

    if ([string]::IsNullOrWhiteSpace($Path) -or -not (Test-Path -LiteralPath $Path -PathType Leaf)) { return '' }

    try {
        $wanted = @{}
        foreach ($key in @($Keys)) {
            if (-not [string]::IsNullOrWhiteSpace([string]$key)) {
                $wanted[[string]$key] = $true
            }
        }

        foreach ($line in @(Get-Content -LiteralPath $Path -ErrorAction Stop)) {
            $text = [string]$line
            if ([string]::IsNullOrWhiteSpace($text)) { continue }
            $trimmed = $text.Trim()
            if ($trimmed.StartsWith('//') -or $trimmed.StartsWith('#') -or $trimmed.StartsWith(';')) { continue }

            if ($trimmed -match '^\s*([^\s=]+)\s*(?:=|\s)\s*(.*)$') {
                $key = [string]$Matches[1]
                if ($wanted.ContainsKey($key)) {
                    return ([string]$Matches[2]).Trim().Trim('"')
                }
            }
        }
    }
    catch { }

    return ''
}


function Get-UGSMDiscordResolvedServerDisplayName {
    [CmdletBinding()]
    param(
        [AllowNull()][object]$Instance,
        [AllowNull()][hashtable]$ExtraFields
    )

    $name = $null

    if ($ExtraFields) {
        $name = Get-UGSMDiscordObjectValue -Object $ExtraFields -Names @(
            'ServerName',
            'PublicServerName',
            'ServerDisplayName',
            'DisplayName',
            'PublicName',
            'HostName',
            'Hostname'
        ) -DefaultValue $null
    }

    if ($null -eq $name -or [string]::IsNullOrWhiteSpace([string]$name)) {
        $name = Get-UGSMDiscordPropertyValueSafe -Object $Instance -Names @(
            'ServerName',
            'PublicServerName',
            'ServerDisplayName',
            'DisplayName',
            'PublicName',
            'HostName',
            'Hostname'
        ) -DefaultValue $null
    }

    if ($null -eq $name -or [string]::IsNullOrWhiteSpace([string]$name)) {
        $iniPath = Get-UGSMDiscordProjectZomboidIniPath -Instance $Instance
        $name = Get-UGSMDiscordIniValue -Path $iniPath -Keys @(
            'PublicName',
            'ServerName',
            'Name'
        )
    }

    if ($null -eq $name -or [string]::IsNullOrWhiteSpace([string]$name)) {
        $xmlPath = Get-UGSMDiscord7D2DServerConfigPath -Instance $Instance
        $name = Get-UGSMDiscordXmlPropertyValue -Path $xmlPath -Names @(
            'ServerName'
        )
    }

    if ($null -eq $name -or [string]::IsNullOrWhiteSpace([string]$name)) {
        $vrisingHostPath = Get-UGSMDiscordVRisingHostSettingsPath -Instance $Instance
        $name = Get-UGSMDiscordJsonFileValue -Path $vrisingHostPath -Names @('Name')
    }

    if ($null -eq $name -or [string]::IsNullOrWhiteSpace([string]$name)) {
        $forestCfgPath = Get-UGSMDiscordTheForestServerConfigPath -Instance $Instance
        $name = Get-UGSMDiscordCfgValue -Path $forestCfgPath -Keys @('serverName')
    }

    if ($null -eq $name -or [string]::IsNullOrWhiteSpace([string]$name)) {
        $name = Get-UGSMDiscordPropertyValueSafe -Object $Instance -Names @('Name','Id') -DefaultValue ''
    }

    if ([string]::IsNullOrWhiteSpace([string]$name)) { return 'Unknown Server' }
    return ([string]$name).Trim()
}

function Get-UGSMDiscordResolvedPlayerStatusText {
    [CmdletBinding()]
    param(
        [AllowNull()][object]$Instance,
        [AllowNull()][hashtable]$ExtraFields
    )

    $current = $null
    $max = $null
    $statusText = [string](Get-UGSMDiscordPropertyValueSafe -Object $Instance -Names @('Status','State') -DefaultValue '')
    $isStopped = ($statusText.Trim().ToLowerInvariant() -in @('stopped','offline','stopping','not running','notrunning'))

    if ($ExtraFields) {
        $current = Get-UGSMDiscordObjectValue -Object $ExtraFields -Names @('PlayerCount','CurrentPlayers','OnlinePlayers','PlayersOnline','Players') -DefaultValue $null
        $max = Get-UGSMDiscordObjectValue -Object $ExtraFields -Names @('MaxPlayers','ServerMaxPlayers','Slots') -DefaultValue $null
    }

    if ($null -eq $current -or [string]::IsNullOrWhiteSpace([string]$current)) {
        $current = Get-UGSMDiscordPropertyValueSafe -Object $Instance -Names @('PlayerCount','CurrentPlayers','OnlinePlayers','PlayersOnline','Players') -DefaultValue $null
    }
    if ($null -eq $max -or [string]::IsNullOrWhiteSpace([string]$max)) {
        $max = Get-UGSMDiscordPropertyValueSafe -Object $Instance -Names @('MaxPlayers','ServerMaxPlayers','Slots') -DefaultValue $null
    }
    if ($null -eq $max -or [string]::IsNullOrWhiteSpace([string]$max)) {
        $iniPath = Get-UGSMDiscordProjectZomboidIniPath -Instance $Instance
        $max = Get-UGSMDiscordIniValue -Path $iniPath -Keys @('MaxPlayers')
    }
    if ($null -eq $max -or [string]::IsNullOrWhiteSpace([string]$max)) {
        $xmlPath = Get-UGSMDiscord7D2DServerConfigPath -Instance $Instance
        $max = Get-UGSMDiscordXmlPropertyValue -Path $xmlPath -Names @('ServerMaxPlayerCount')
    }
    if ($null -eq $max -or [string]::IsNullOrWhiteSpace([string]$max)) {
        $vrisingHostPath = Get-UGSMDiscordVRisingHostSettingsPath -Instance $Instance
        $max = Get-UGSMDiscordJsonFileValue -Path $vrisingHostPath -Names @('MaxConnectedUsers')
    }

    if ($null -eq $max -or [string]::IsNullOrWhiteSpace([string]$max)) {
        $forestCfgPath = Get-UGSMDiscordTheForestServerConfigPath -Instance $Instance
        $max = Get-UGSMDiscordCfgValue -Path $forestCfgPath -Keys @('serverPlayers')
    }

    if ($isStopped) {
        $current = 0
    }

    $hasCurrent = ($null -ne $current -and -not [string]::IsNullOrWhiteSpace([string]$current))
    $hasMax = ($null -ne $max -and -not [string]::IsNullOrWhiteSpace([string]$max))

    if ($hasCurrent -and $hasMax) { return ([string]$current + '/' + [string]$max) }
    if ($hasCurrent) { return ([string]$current) }
    if ($hasMax) { return ('0/' + [string]$max) }
    return ''
}

function Get-UGSMDiscordPlayerStatusText {
    [CmdletBinding()]
    param(
        [AllowNull()][object]$Instance,
        [AllowNull()][hashtable]$ExtraFields
    )

    return (Get-UGSMDiscordResolvedPlayerStatusText -Instance $Instance -ExtraFields $ExtraFields)
}

function New-UGSMDiscordDashboardEmbed {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object[]]$Instances
    )

    $sortedInstances = @($Instances | Sort-Object @{ Expression = { [string]$_.GameId } }, @{ Expression = { [string]$_.Name } })
    $lines = New-Object System.Collections.Generic.List[string]

    foreach ($inst in $sortedInstances) {
        $name = [string](Get-UGSMDiscordResolvedServerDisplayName -Instance $inst -ExtraFields $null)

        $game = [string](Get-UGSMDiscordPropertyValueSafe -Object $inst -Names @('GameId') -DefaultValue '')
        if ([string]::IsNullOrWhiteSpace($game)) { $game = 'Unknown Game' }

        $statusText = [string](Get-UGSMDiscordPropertyValueSafe -Object $inst -Names @('Status') -DefaultValue '')
        if ([string]::IsNullOrWhiteSpace($statusText)) { $statusText = 'Unknown' }

        $statusKey = $statusText.Trim().ToLowerInvariant()
        switch ($statusKey) {
            'running' { $emoji = '🟢'; $statusLabel = 'Running' }
            'online' { $emoji = '🟢'; $statusLabel = 'Running' }
            'started' { $emoji = '🟢'; $statusLabel = 'Running' }
            'stopped' { $emoji = '🔴'; $statusLabel = 'Stopped' }
            'offline' { $emoji = '🔴'; $statusLabel = 'Stopped' }
            'starting' { $emoji = '🟡'; $statusLabel = 'Starting' }
            'stopping' { $emoji = '🟡'; $statusLabel = 'Stopping' }
            default { $emoji = '⚪'; $statusLabel = $statusText }
        }

        $playersText = Get-UGSMDiscordResolvedPlayerStatusText -Instance $inst -ExtraFields $null
        if ([string]::IsNullOrWhiteSpace($playersText)) { $playersText = '—' }

        $lines.Add(($emoji + ' **' + $name + '** (' + $game + ') — ' + $statusLabel + ' — Players: ' + $playersText))
    }

    if ($lines.Count -eq 0) {
        $lines.Add('No servers are currently marked for dashboard display.')
    }

    return @{
        title       = '🖥️ Server Status Rack'
        description = ($lines -join [Environment]::NewLine)
        color       = 3447003
        footer      = @{ text = ('Last Updated: ' + (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')) }
    }
}
