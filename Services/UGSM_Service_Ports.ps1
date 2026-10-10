# Ports Service
# Owns port reservation, allocation, availability checks, and release logic.

function Write-UGSMPortsLog {
    [CmdletBinding()]
    param(
        [ValidateSet('TRACE','DEBUG','INFO','WARN','ERROR','FATAL')]
        [string]$Level = 'INFO',
        [Parameter(Mandatory)]
        [string]$Message,
        [System.Exception]$Exception
    )

    if (Get-Command -Name Write-UGSMLog -ErrorAction SilentlyContinue) {
        if ($Exception) {
            Write-UGSMLog -Level $Level -Category 'Ports' -Message $Message -Exception $Exception
        }
        else {
            Write-UGSMLog -Level $Level -Category 'Ports' -Message $Message
        }
        return
    }

    $prefix = "[$Level] [Ports]"
    if ($Exception) {
        Write-Host "$prefix $Message $($Exception.Message)"
    }
    else {
        Write-Host "$prefix $Message"
    }
}

function Test-UGSMVerbosePortLogging {
    [CmdletBinding()]
    param()

    try {
        $var = Get-Variable -Name 'UGSM_EnableVerbosePortLogging' -Scope Script -ErrorAction SilentlyContinue
        if ($var -and [bool]$var.Value) { return $true }
    }
    catch { }

    return ($env:UGSM_VERBOSE_PORTS -eq '1')
}


function ConvertTo-UGSMFirewallRuleList {
    [CmdletBinding()]
    param(
        [object]$FirewallRules
    )

    $rules = @()

    if ($null -eq $FirewallRules) {
        return @($rules)
    }

    foreach ($rule in @($FirewallRules)) {
        if ($null -eq $rule) { continue }

        $ruleName = $null
        if ($rule.PSObject.Properties['Name']) { $ruleName = [string]$rule.Name }
        elseif ($rule.PSObject.Properties['RuleName']) { $ruleName = [string]$rule.RuleName }

        if ([string]::IsNullOrWhiteSpace($ruleName)) { continue }

        $rules += [pscustomobject]@{
            Name      = $ruleName
            DisplayName = if ($rule.PSObject.Properties['DisplayName']) { [string]$rule.DisplayName } else { $ruleName }
            GameId    = if ($rule.PSObject.Properties['GameId']) { [string]$rule.GameId } else { $null }
            InstanceId = if ($rule.PSObject.Properties['InstanceId']) { [string]$rule.InstanceId } else { $null }
            PortName  = if ($rule.PSObject.Properties['PortName']) { [string]$rule.PortName } else { $null }
            Port      = if ($rule.PSObject.Properties['Port'] -and $null -ne $rule.Port -and -not [string]::IsNullOrWhiteSpace([string]$rule.Port)) { [int]$rule.Port } else { 0 }
            Protocol  = if ($rule.PSObject.Properties['Protocol'] -and -not [string]::IsNullOrWhiteSpace([string]$rule.Protocol)) { ([string]$rule.Protocol).ToUpperInvariant() } else { $null }
            Direction = if ($rule.PSObject.Properties['Direction'] -and -not [string]::IsNullOrWhiteSpace([string]$rule.Direction)) { [string]$rule.Direction } else { 'Inbound' }
            Profile   = if ($rule.PSObject.Properties['Profile'] -and -not [string]::IsNullOrWhiteSpace([string]$rule.Profile)) { [string]$rule.Profile } else { 'Private' }
        }
    }

    return @($rules)
}

function ConvertTo-UGSMFirewallSafeToken {
    [CmdletBinding()]
    param(
        [string]$Value,
        [int]$MaxLength = 48
    )

    if ([string]::IsNullOrWhiteSpace($Value)) {
        return 'Unknown'
    }

    $safe = ([string]$Value) -replace '[^A-Za-z0-9_-]', '_'
    $safe = $safe.Trim('_')
    if ([string]::IsNullOrWhiteSpace($safe)) { $safe = 'Unknown' }
    if ($safe.Length -gt $MaxLength) { $safe = $safe.Substring(0, $MaxLength).Trim('_') }
    return $safe
}

function Test-UGSMFirewallManagementAvailable {
    [CmdletBinding()]
    param()

    if (-not (Get-Command -Name New-NetFirewallRule -ErrorAction SilentlyContinue)) { return $false }
    if (-not (Get-Command -Name Get-NetFirewallRule -ErrorAction SilentlyContinue)) { return $false }
    if (-not (Get-Command -Name Remove-NetFirewallRule -ErrorAction SilentlyContinue)) { return $false }

    try {
        $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
        $principal = New-Object Security.Principal.WindowsPrincipal($identity)
        return [bool]$principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    }
    catch {
        return $false
    }
}

function Get-UGSMFirewallRuleName {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$GameId,
        [Parameter(Mandatory)][string]$InstanceId,
        [Parameter(Mandatory)][string]$PortName,
        [Parameter(Mandatory)][ValidateSet('TCP','UDP')][string]$Protocol
    )

    $safeGame = ConvertTo-UGSMFirewallSafeToken -Value $GameId -MaxLength 36
    $safeInstance = ConvertTo-UGSMFirewallSafeToken -Value $InstanceId -MaxLength 48
    $safePortName = ConvertTo-UGSMFirewallSafeToken -Value $PortName -MaxLength 36
    return "UGSM_${safeGame}_${safeInstance}_${safePortName}_${Protocol}"
}

function Get-UGSMPortSchemaProtocolMap {
    [CmdletBinding()]
    param(
        [object[]]$PortSchema
    )

    $map = @{}
    foreach ($definition in @($PortSchema)) {
        if ($null -eq $definition) { continue }

        $name = $null
        $protocol = $null

        if ($definition -is [hashtable]) {
            if ($definition.ContainsKey('Name')) { $name = [string]$definition['Name'] }
            if ($definition.ContainsKey('Protocol')) { $protocol = [string]$definition['Protocol'] }
        }
        else {
            if ($definition.PSObject.Properties['Name']) { $name = [string]$definition.Name }
            if ($definition.PSObject.Properties['Protocol']) { $protocol = [string]$definition.Protocol }
        }

        if ([string]::IsNullOrWhiteSpace($name)) { continue }
        if ([string]::IsNullOrWhiteSpace($protocol)) {
            $protocol = switch -Regex ($name) {
                '^(GamePort|QueryPort|SteamPort|PeerPort|BeaconPort|RawPort)$' { 'UDP'; break }
                '^(RconPort|WebPort|TelnetPort)$' { 'TCP'; break }
                default { 'TCP' }
            }
        }

        $map[$name] = $protocol
    }

    return $map
}

function Resolve-UGSMFirewallProtocols {
    [CmdletBinding()]
    param(
        [string]$Protocol
    )

    if ([string]::IsNullOrWhiteSpace($Protocol)) {
        return @('TCP')
    }

    $normalized = ([string]$Protocol).Trim().ToUpperInvariant()
    if ($normalized -in @('BOTH','TCPUDP','TCP/UDP','UDP/TCP','ANY')) {
        return @('TCP','UDP')
    }

    $parts = @($normalized -split '[,;/ ]+' | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    $resolved = @()
    foreach ($part in $parts) {
        if ($part -eq 'TCP' -or $part -eq 'UDP') {
            if ($resolved -notcontains $part) { $resolved += $part }
        }
    }

    if ($resolved.Count -eq 0) { $resolved = @('TCP') }
    return @($resolved)
}

function Set-UGSMInstanceFirewallRules {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$GameId,
        [Parameter(Mandatory)][string]$InstanceId,
        [Parameter(Mandatory)][hashtable]$AssignedPorts,
        [object[]]$PortSchema
    )

    $createdRules = @()

    if (-not (Test-UGSMFirewallManagementAvailable)) {
        Write-UGSMPortsLog -Level 'WARN' -Message "Windows Firewall rule creation skipped. UGSM must be elevated and the NetSecurity module must be available. GameId=$GameId; InstanceId=$InstanceId"
        return @($createdRules)
    }

    $protocolMap = Get-UGSMPortSchemaProtocolMap -PortSchema $PortSchema

    foreach ($portName in @($AssignedPorts.Keys)) {
        $portNumber = [int]$AssignedPorts[$portName]
        if ($portNumber -lt 1 -or $portNumber -gt 65535) { continue }

        $schemaProtocol = if ($protocolMap.ContainsKey($portName)) { [string]$protocolMap[$portName] } else { 'TCP' }
        foreach ($protocol in @(Resolve-UGSMFirewallProtocols -Protocol $schemaProtocol)) {
            $ruleName = Get-UGSMFirewallRuleName -GameId $GameId -InstanceId $InstanceId -PortName $portName -Protocol $protocol
            $description = "UGSM managed inbound firewall rule for game server instance. Game=$GameId; Instance=$InstanceId; Port=$portName. Router port forwarding is not managed by UGSM."

            try {
                $existing = @(Get-NetFirewallRule -Name $ruleName -ErrorAction SilentlyContinue)
                if ($existing.Count -gt 0) {
                    $existing | Remove-NetFirewallRule -ErrorAction SilentlyContinue
                }

                $null = New-NetFirewallRule `
                    -Name $ruleName `
                    -DisplayName $ruleName `
                    -Direction Inbound `
                    -Action Allow `
                    -Protocol $protocol `
                    -LocalPort $portNumber `
                    -Profile Private `
                    -Description $description `
                    -Enabled True `
                    -ErrorAction Stop

                $createdRules += [pscustomobject]@{
                    Name       = $ruleName
                    DisplayName = $ruleName
                    GameId     = $GameId
                    InstanceId = $InstanceId
                    PortName   = [string]$portName
                    Port       = $portNumber
                    Protocol   = $protocol
                    Direction  = 'Inbound'
                    Profile    = 'Private'
                }

                Write-UGSMPortsLog -Level 'INFO' -Message "Windows Firewall rule created. GameId=$GameId; InstanceId=$InstanceId; PortName=$portName; Port=$portNumber; Protocol=$protocol; Profile=Private"
            }
            catch {
                Write-UGSMPortsLog -Level 'WARN' -Message "Windows Firewall rule creation failed. GameId=$GameId; InstanceId=$InstanceId; PortName=$portName; Port=$portNumber; Protocol=$protocol; Profile=Private" -Exception $_.Exception
            }
        }
    }

    return @($createdRules)
}

function Remove-UGSMInstanceFirewallRules {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$InstanceId,
        [object[]]$FirewallRules,
        [string]$GameId
    )

    $removedCount = 0

    if (-not (Get-Command -Name Get-NetFirewallRule -ErrorAction SilentlyContinue) -or -not (Get-Command -Name Remove-NetFirewallRule -ErrorAction SilentlyContinue)) {
        Write-UGSMPortsLog -Level 'WARN' -Message "Windows Firewall rule cleanup skipped. NetSecurity module is not available. InstanceId=$InstanceId"
        return [pscustomobject]@{ InstanceId = $InstanceId; Removed = 0 }
    }

    $rulesToRemove = @()
    foreach ($rule in @(ConvertTo-UGSMFirewallRuleList -FirewallRules $FirewallRules)) {
        if (-not [string]::IsNullOrWhiteSpace([string]$rule.Name)) {
            $found = @(Get-NetFirewallRule -Name ([string]$rule.Name) -ErrorAction SilentlyContinue)
            if ($found.Count -gt 0) { $rulesToRemove += $found }
        }
    }

    if ($rulesToRemove.Count -eq 0) {
        $safeInstance = ConvertTo-UGSMFirewallSafeToken -Value $InstanceId -MaxLength 48
        $pattern = "UGSM_*_${safeInstance}_*"
        $rulesToRemove = @(Get-NetFirewallRule -ErrorAction SilentlyContinue | Where-Object {
            ([string]$_.Name -like $pattern) -or ([string]$_.DisplayName -like $pattern)
        })
    }

    foreach ($rule in @($rulesToRemove | Sort-Object -Property Name -Unique)) {
        try {
            $rule | Remove-NetFirewallRule -ErrorAction Stop
            $removedCount++
        }
        catch {
            Write-UGSMPortsLog -Level 'WARN' -Message "Windows Firewall rule cleanup failed. InstanceId=$InstanceId; Rule=$($rule.Name)" -Exception $_.Exception
        }
    }

    if ($removedCount -gt 0) {
        Write-UGSMPortsLog -Level 'INFO' -Message "Windows Firewall rule cleanup completed. InstanceId=$InstanceId; RulesRemoved=$removedCount"
    }
    else {
        Write-UGSMPortsLog -Level 'DEBUG' -Message "Windows Firewall rule cleanup found no UGSM rules. InstanceId=$InstanceId"
    }

    return [pscustomobject]@{ InstanceId = $InstanceId; Removed = $removedCount }
}

function Get-UGSMPortRegistryPath {
    [CmdletBinding()]
    param()

    if (Get-Command -Name Get-UGSMAppDataRoot -ErrorAction SilentlyContinue) {
        return (Join-Path (Get-UGSMAppDataRoot) 'ports.json')
    }

    $basePath = [Environment]::GetFolderPath([Environment+SpecialFolder]::LocalApplicationData)
    if ([string]::IsNullOrWhiteSpace($basePath)) {
        throw 'Unable to resolve LocalApplicationData path for port registry.'
    }

    $appRoot = Join-Path $basePath 'UGSM'
    if (-not (Test-Path -LiteralPath $appRoot)) {
        $null = New-Item -Path $appRoot -ItemType Directory -Force
    }

    return (Join-Path $appRoot 'ports.json')
}

function New-UGSMEmptyPortRegistry {
    [CmdletBinding()]
    param()

    return [pscustomobject]@{
        Version     = 2
        LastUpdated = $null
        Assignments = @()
    }
}

function ConvertTo-UGSMPortHashtable {
    [CmdletBinding()]
    param(
        [object]$Ports
    )

    $table = @{}

    if ($null -eq $Ports) {
        return $table
    }

    if ($Ports -is [hashtable]) {
        foreach ($key in $Ports.Keys) {
            $value = $Ports[$key]
            if ($null -ne $value -and -not [string]::IsNullOrWhiteSpace([string]$value)) {
                $table[[string]$key] = [int]$value
            }
        }
        return $table
    }

    foreach ($property in $Ports.PSObject.Properties) {
        if ($null -ne $property.Value -and -not [string]::IsNullOrWhiteSpace([string]$property.Value)) {
            $table[[string]$property.Name] = [int]$property.Value
        }
    }

    return $table
}

function Test-UGSMPortAvailable {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateRange(1, 65535)]
        [int]$Port,

        [ValidateSet('TCP','UDP')]
        [string]$Protocol = 'TCP',

        [string]$IPAddress = '127.0.0.1',

        [ValidateRange(50, 10000)]
        [int]$TimeoutMilliseconds = 250
    )

    $started = Get-Date

    if ($Protocol -eq 'TCP') {
        $client = $null
        try {
            $client = New-Object System.Net.Sockets.TcpClient
            $async = $client.BeginConnect($IPAddress, $Port, $null, $null)
            $connected = $async.AsyncWaitHandle.WaitOne($TimeoutMilliseconds, $false)

            if ($connected) {
                try { $client.EndConnect($async) } catch { }
                return [pscustomobject]@{
                    Protocol    = 'TCP'
                    Port        = $Port
                    IPAddress   = $IPAddress
                    IsAvailable = $false
                    Reason      = 'TCP listener accepted connection.'
                    DurationMs  = [int]((Get-Date) - $started).TotalMilliseconds
                }
            }

            return [pscustomobject]@{
                Protocol    = 'TCP'
                Port        = $Port
                IPAddress   = $IPAddress
                IsAvailable = $true
                Reason      = 'No TCP listener responded before timeout.'
                DurationMs  = [int]((Get-Date) - $started).TotalMilliseconds
            }
        }
        catch [System.Net.Sockets.SocketException] {
            return [pscustomobject]@{
                Protocol    = 'TCP'
                Port        = $Port
                IPAddress   = $IPAddress
                IsAvailable = $true
                Reason      = 'TCP connect failed; treating port as available.'
                DurationMs  = [int]((Get-Date) - $started).TotalMilliseconds
            }
        }
        catch {
            Write-UGSMPortsLog -Level 'WARN' -Message "TCP availability check failed. Port=$Port; IPAddress=$IPAddress" -Exception $_.Exception
            return [pscustomobject]@{
                Protocol    = 'TCP'
                Port        = $Port
                IPAddress   = $IPAddress
                IsAvailable = $false
                Reason      = $_.Exception.Message
                DurationMs  = [int]((Get-Date) - $started).TotalMilliseconds
            }
        }
        finally {
            if ($client) { try { $client.Close() } catch { } }
        }
    }

    $udpClient = $null
    try {
        $udpClient = New-Object System.Net.Sockets.UdpClient
        $udpClient.ExclusiveAddressUse = $true
        $endpoint = New-Object System.Net.IPEndPoint([System.Net.IPAddress]::Any, $Port)
        $udpClient.Client.Bind($endpoint)

        return [pscustomobject]@{
            Protocol    = 'UDP'
            Port        = $Port
            IPAddress   = $IPAddress
            IsAvailable = $true
            Reason      = 'UDP bind succeeded.'
            DurationMs  = [int]((Get-Date) - $started).TotalMilliseconds
        }
    }
    catch {
        return [pscustomobject]@{
            Protocol    = 'UDP'
            Port        = $Port
            IPAddress   = $IPAddress
            IsAvailable = $false
            Reason      = $_.Exception.Message
            DurationMs  = [int]((Get-Date) - $started).TotalMilliseconds
        }
    }
    finally {
        if ($udpClient) { try { $udpClient.Close() } catch { } }
    }
}

function Get-UGSMPortRegistry {
    [CmdletBinding()]
    param(
        [switch]$CreateIfMissing
    )

    $path = Get-UGSMPortRegistryPath

    try {
        if (-not (Test-Path -LiteralPath $path)) {
            $empty = New-UGSMEmptyPortRegistry
            if ($CreateIfMissing) {
                Save-UGSMPortRegistry -Registry $empty | Out-Null
                Write-UGSMPortsLog -Level 'INFO' -Message "Created missing port registry. Path=$path"
            }
            return $empty
        }

        $raw = Get-Content -LiteralPath $path -Raw -ErrorAction Stop
        if ([string]::IsNullOrWhiteSpace($raw)) {
            $empty = New-UGSMEmptyPortRegistry
            if ($CreateIfMissing) {
                Save-UGSMPortRegistry -Registry $empty | Out-Null
                Write-UGSMPortsLog -Level 'WARN' -Message "Port registry was empty and was reset. Path=$path"
            }
            return $empty
        }

        $parsed = $raw | ConvertFrom-Json -ErrorAction Stop
        $assignments = @()

        foreach ($item in @($parsed.Assignments)) {
            $assignments += [pscustomobject]@{
                InstanceId    = [string]$item.InstanceId
                GameId        = [string]$item.GameId
                Ports         = ConvertTo-UGSMPortHashtable $item.Ports
                FirewallRules = @(ConvertTo-UGSMFirewallRuleList $item.FirewallRules)
            }
        }

        if (Test-UGSMVerbosePortLogging) {
            Write-UGSMPortsLog -Level 'DEBUG' -Message "Port registry loaded. Assignments=$(@($assignments).Count); Path=$path"
        }

        return [pscustomobject]@{
            Version     = if ($null -ne $parsed.Version) { [int]$parsed.Version } else { 1 }
            LastUpdated = $parsed.LastUpdated
            Assignments = @($assignments)
        }
    }
    catch {
        Write-UGSMPortsLog -Level 'ERROR' -Message "Failed to load port registry. Path=$path" -Exception $_.Exception
        throw
    }
}

function Save-UGSMPortRegistry {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Registry
    )

    $path = Get-UGSMPortRegistryPath
    $dir = Split-Path -Path $path -Parent

    try {
        if (-not (Test-Path -LiteralPath $dir)) {
            $null = New-Item -Path $dir -ItemType Directory -Force
        }

        $assignments = foreach ($item in @($Registry.Assignments)) {
            $portTable = [ordered]@{}

            if ($null -ne $item.Ports) {
                $normalizedPorts = ConvertTo-UGSMPortHashtable $item.Ports
                foreach ($key in $normalizedPorts.Keys) {
                    $portTable[[string]$key] = [int]$normalizedPorts[$key]
                }
            }

            $firewallRules = @(ConvertTo-UGSMFirewallRuleList $item.FirewallRules | ForEach-Object {
                [pscustomobject]@{
                    Name       = [string]$_.Name
                    DisplayName = [string]$_.DisplayName
                    GameId     = [string]$_.GameId
                    InstanceId = [string]$_.InstanceId
                    PortName   = [string]$_.PortName
                    Port       = [int]$_.Port
                    Protocol   = [string]$_.Protocol
                    Direction  = [string]$_.Direction
                    Profile    = if ($_.PSObject.Properties['Profile'] -and -not [string]::IsNullOrWhiteSpace([string]$_.Profile)) { [string]$_.Profile } else { 'Private' }
                }
            })

            [pscustomobject]@{
                InstanceId    = [string]$item.InstanceId
                GameId        = [string]$item.GameId
                Ports         = [pscustomobject]$portTable
                FirewallRules = @($firewallRules)
            }
        }

        $toSave = [pscustomobject]@{
            Version     = 2
            LastUpdated = (Get-Date).ToString('o')
            Assignments = @($assignments)
        }

        $toSave |
            ConvertTo-Json -Depth 10 |
            Set-Content -LiteralPath $path -Encoding UTF8

        if (Test-UGSMVerbosePortLogging) {
            Write-UGSMPortsLog -Level 'DEBUG' -Message "Port registry saved. Assignments=$(@($toSave.Assignments).Count); Path=$path"
        }

        return $toSave
    }
    catch {
        Write-UGSMPortsLog -Level 'ERROR' -Message "Failed to save port registry. Path=$path" -Exception $_.Exception
        throw
    }
}

function Get-UGSMReservedPorts {
    [CmdletBinding()]
    param(
        [object]$Registry,
        [string]$ExcludeInstanceId
    )

    if ($null -eq $Registry) {
        $Registry = Get-UGSMPortRegistry
    }

    $reserved = @{}

    foreach ($assignment in @($Registry.Assignments)) {
        if ($ExcludeInstanceId -and [string]$assignment.InstanceId -eq $ExcludeInstanceId) {
            continue
        }

        if ($null -eq $assignment.Ports) {
            continue
        }

        $normalizedPorts = ConvertTo-UGSMPortHashtable $assignment.Ports
        foreach ($key in $normalizedPorts.Keys) {
            $portNumber = [int]$normalizedPorts[$key]
            if ($portNumber -gt 0) {
                $reserved[$portNumber] = [string]$assignment.InstanceId
            }
        }
    }

    return $reserved
}

function Test-UGSMRequestedPortsAvailable {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable]$Ports,

        [object]$Registry,
        [string]$ExcludeInstanceId,
        [string]$IPAddress = '127.0.0.1'
    )

    if ($null -eq $Registry) {
        $Registry = Get-UGSMPortRegistry
    }

    $started = Get-Date
    $reserved = Get-UGSMReservedPorts -Registry $Registry -ExcludeInstanceId $ExcludeInstanceId
    $results = New-Object System.Collections.Generic.List[object]
    $seenRequestedPorts = @{}

    foreach ($name in $Ports.Keys) {
        $portNumber = [int]$Ports[$name]
        $isDuplicateInRequest = $seenRequestedPorts.ContainsKey($portNumber)
        if (-not $isDuplicateInRequest) {
            $seenRequestedPorts[$portNumber] = [string]$name
        }

        $isReserved = $reserved.ContainsKey($portNumber)
        $osCheckTcp = Test-UGSMPortAvailable -Port $portNumber -Protocol TCP -IPAddress $IPAddress
        $osCheckUdp = Test-UGSMPortAvailable -Port $portNumber -Protocol UDP -IPAddress $IPAddress
        $isAvailable = (-not $isDuplicateInRequest) -and (-not $isReserved) -and $osCheckTcp.IsAvailable -and $osCheckUdp.IsAvailable

        [void]$results.Add([pscustomobject]@{
            Name                 = [string]$name
            Port                 = $portNumber
            IsDuplicateInRequest = $isDuplicateInRequest
            DuplicateOf          = if ($isDuplicateInRequest) { [string]$seenRequestedPorts[$portNumber] } else { $null }
            IsReservedByUGSM     = $isReserved
            ReservedInstanceId   = if ($isReserved) { [string]$reserved[$portNumber] } else { $null }
            TcpAvailable         = [bool]$osCheckTcp.IsAvailable
            UdpAvailable         = [bool]$osCheckUdp.IsAvailable
            IsAvailable          = $isAvailable
        })
    }

    $conflicts = @($results | Where-Object { -not $_.IsAvailable })
    $durationMs = [int]((Get-Date) - $started).TotalMilliseconds

    if ($conflicts.Count -gt 0) {
        $summary = ($conflicts | ForEach-Object { "$($_.Name)=$($_.Port) Duplicate=$($_.IsDuplicateInRequest) Reserved=$($_.IsReservedByUGSM) TCP=$($_.TcpAvailable) UDP=$($_.UdpAvailable)" }) -join '; '
        Write-UGSMPortsLog -Level 'WARN' -Message "Requested port availability check found conflicts. Count=$($conflicts.Count); ExcludeInstanceId=$ExcludeInstanceId; Details=$summary"
    }
    elseif ((Test-UGSMVerbosePortLogging) -or $durationMs -ge 1000) {
        $level = if ($durationMs -ge 1000) { 'WARN' } else { 'DEBUG' }
        Write-UGSMPortsLog -Level $level -Message "Requested port availability check completed. Ports=$($Ports.Count); DurationMs=$durationMs; Available=True"
    }

    return [pscustomobject]@{
        IsAvailable = ($conflicts.Count -eq 0)
        Results     = @($results)
    }
}

function New-UGSMInstancePortAssignments {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$InstanceId,

        [Parameter(Mandatory)]
        [string]$GameId,

        [Parameter(Mandatory)]
        [object[]]$PortSchema,

        [int]$SearchWindow = 200,
        [string]$IPAddress = '127.0.0.1'
    )

    if ($SearchWindow -lt 1) {
        throw 'SearchWindow must be 1 or greater.'
    }

    $started = Get-Date
    $createdFirewallRules = @()
    Write-UGSMPortsLog -Level 'INFO' -Message "Port assignment requested. GameId=$GameId; InstanceId=$InstanceId; SchemaCount=$(@($PortSchema).Count); SearchWindow=$SearchWindow"

    try {
        $registry = Get-UGSMPortRegistry -CreateIfMissing

        if (@($registry.Assignments | Where-Object { $_.InstanceId -eq $InstanceId }).Count -gt 0) {
            throw "Port assignments already exist for instance '$InstanceId'."
        }

        $reserved = Get-UGSMReservedPorts -Registry $registry
        $assigned = [ordered]@{}

        foreach ($definition in $PortSchema) {
            $name = [string]$definition.Name
            if ([string]::IsNullOrWhiteSpace($name)) {
                throw 'Port schema item is missing Name.'
            }

            $preferredStart = if ($null -ne $definition.PreferredStart) { [int]$definition.PreferredStart } else { 20000 }
            if ($preferredStart -lt 1 -or $preferredStart -gt 65535) {
                throw "PreferredStart for '$name' must be between 1 and 65535."
            }

            $selectedPort = $null

            for ($candidate = $preferredStart; $candidate -lt ($preferredStart + $SearchWindow) -and $candidate -le 65535; $candidate++) {
                if ($reserved.ContainsKey($candidate)) { continue }
                if (@($assigned.Values) -contains [int]$candidate) { continue }

                $tcpCheck = Test-UGSMPortAvailable -Port $candidate -Protocol TCP -IPAddress $IPAddress
                if (-not $tcpCheck.IsAvailable) { continue }

                $udpCheck = Test-UGSMPortAvailable -Port $candidate -Protocol UDP -IPAddress $IPAddress
                if (-not $udpCheck.IsAvailable) { continue }

                $selectedPort = $candidate
                break
            }

            if ($null -eq $selectedPort) {
                throw "Unable to find a free port for '$name' starting at $preferredStart."
            }

            $assigned[$name] = [int]$selectedPort
        }

        $createdFirewallRules = @(Set-UGSMInstanceFirewallRules -GameId $GameId -InstanceId $InstanceId -AssignedPorts (@{} + $assigned) -PortSchema $PortSchema)

        $assignment = [pscustomobject]@{
            InstanceId    = $InstanceId
            GameId        = $GameId
            Ports         = @{} + $assigned
            FirewallRules = @($createdFirewallRules)
        }

        $registry.Assignments = @($registry.Assignments) + $assignment
        Save-UGSMPortRegistry -Registry $registry | Out-Null

        $durationMs = [int]((Get-Date) - $started).TotalMilliseconds
        $summary = ($assigned.Keys | ForEach-Object { "$($_)=$($assigned[$_])" }) -join '; '
        Write-UGSMPortsLog -Level 'INFO' -Message "Port assignment completed. GameId=$GameId; InstanceId=$InstanceId; DurationMs=$durationMs; Ports=$summary"

        return (@{} + $assigned)
    }
    catch {
        if (@($createdFirewallRules).Count -gt 0) {
            Remove-UGSMInstanceFirewallRules -InstanceId $InstanceId -GameId $GameId -FirewallRules @($createdFirewallRules) | Out-Null
        }
        Write-UGSMPortsLog -Level 'ERROR' -Message "Port assignment failed. GameId=$GameId; InstanceId=$InstanceId" -Exception $_.Exception
        throw
    }
}

function Remove-UGSMInstancePortAssignments {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$InstanceId
    )

    $started = Get-Date
    Write-UGSMPortsLog -Level 'INFO' -Message "Port release requested. InstanceId=$InstanceId"

    try {
        $registry = Get-UGSMPortRegistry -CreateIfMissing
        $beforeCount = @($registry.Assignments).Count
        $removedAssignments = @($registry.Assignments | Where-Object { $_.InstanceId -eq $InstanceId })

        foreach ($removedAssignment in @($removedAssignments)) {
            Remove-UGSMInstanceFirewallRules -InstanceId $InstanceId -GameId ([string]$removedAssignment.GameId) -FirewallRules @($removedAssignment.FirewallRules) | Out-Null
        }
        if (@($removedAssignments).Count -eq 0) {
            Remove-UGSMInstanceFirewallRules -InstanceId $InstanceId | Out-Null
        }

        $registry.Assignments = @($registry.Assignments | Where-Object { $_.InstanceId -ne $InstanceId })
        $afterCount = @($registry.Assignments).Count
        $removed = ($beforeCount -ne $afterCount)

        Save-UGSMPortRegistry -Registry $registry | Out-Null

        $durationMs = [int]((Get-Date) - $started).TotalMilliseconds
        if ($removed) {
            $portSummary = ($removedAssignments | ForEach-Object {
                $ports = ConvertTo-UGSMPortHashtable $_.Ports
                ($ports.Keys | ForEach-Object { "$($_)=$($ports[$_])" }) -join '; '
            }) -join '; '
            Write-UGSMPortsLog -Level 'INFO' -Message "Port release completed. InstanceId=$InstanceId; DurationMs=$durationMs; Ports=$portSummary"
        }
        else {
            Write-UGSMPortsLog -Level 'DEBUG' -Message "Port release skipped; no assignments found. InstanceId=$InstanceId; DurationMs=$durationMs"
        }

        return [pscustomobject]@{
            InstanceId = $InstanceId
            Removed    = $removed
        }
    }
    catch {
        Write-UGSMPortsLog -Level 'ERROR' -Message "Port release failed. InstanceId=$InstanceId" -Exception $_.Exception
        throw
    }
}
