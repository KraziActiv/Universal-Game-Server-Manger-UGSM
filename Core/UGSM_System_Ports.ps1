# Ports logic as no ports should be hard coded in a game.
# Some games use the same ports and will cause conflicts.
# To avoid conflicts during server creation the server will be assigned a free port if the asking port is used.

# Core Ports
# Raw port availability checks only. This file must not know about games, instances, or registry ownership.

function Test-UGSMTcpPortAvailable {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateRange(1, 65535)]
        [int]$Port,

        [string]$IPAddress = '127.0.0.1'
    )

    $listener = $null
    $isAvailable = $false
    $errorMessage = $null

    try {
        $address = [System.Net.IPAddress]::Parse($IPAddress)
        $listener = [System.Net.Sockets.TcpListener]::new($address, $Port)
        $listener.Start()
        $isAvailable = $true
    }
    catch {
        $errorMessage = $_.Exception.Message
        $isAvailable = $false
    }
    finally {
        if ($null -ne $listener) {
            try { $listener.Stop() } catch { }
        }
    }

    return [pscustomobject]@{
        Port         = $Port
        Protocol     = 'TCP'
        IPAddress    = $IPAddress
        IsAvailable  = $isAvailable
        ErrorMessage = $errorMessage
    }
}

function Test-UGSMUdpPortAvailable {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateRange(1, 65535)]
        [int]$Port,

        [string]$IPAddress = '127.0.0.1'
    )

    $client = $null
    $isAvailable = $false
    $errorMessage = $null

    try {
        $address = [System.Net.IPAddress]::Parse($IPAddress)
        $client = [System.Net.Sockets.UdpClient]::new([System.Net.IPEndPoint]::new($address, $Port))
        $isAvailable = $true
    }
    catch {
        $errorMessage = $_.Exception.Message
        $isAvailable = $false
    }
    finally {
        if ($null -ne $client) {
            try { $client.Dispose() } catch { }
        }
    }

    return [pscustomobject]@{
        Port         = $Port
        Protocol     = 'UDP'
        IPAddress    = $IPAddress
        IsAvailable  = $isAvailable
        ErrorMessage = $errorMessage
    }
}

function Test-UGSMPortAvailable {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateRange(1, 65535)]
        [int]$Port,

        [Parameter(Mandatory)]
        [ValidateSet('TCP', 'UDP')]
        [string]$Protocol,

        [string]$IPAddress = '127.0.0.1'
    )

    switch ($Protocol.ToUpperInvariant()) {
        'TCP' { return (Test-UGSMTcpPortAvailable -Port $Port -IPAddress $IPAddress) }
        'UDP' { return (Test-UGSMUdpPortAvailable -Port $Port -IPAddress $IPAddress) }
    }
}

function Test-UGSMPortSetAvailable {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object[]]$PortSet,

        [string]$IPAddress = '127.0.0.1'
    )

    # A single server instance must not request the same numeric port more than once,
    # even if labels/protocols differ. Some games fail when game/query/rcon ports collide.
    $normalizedPortSet = @(
        foreach ($item in $PortSet) {
            if ($null -eq $item) { continue }

            $port = 0
            if (-not [int]::TryParse(([string]$item.Port), [ref]$port)) { continue }

            [pscustomobject]@{
                Port     = $port
                Protocol = [string]$item.Protocol
                Raw      = $item
            }
        }
    )

    $duplicatePorts = @(
        $normalizedPortSet |
            Group-Object -Property Port |
            Where-Object { $_.Count -gt 1 } |
            ForEach-Object { [int]$_.Name }
    )

    $duplicateResults = foreach ($entry in $normalizedPortSet) {
        if ($duplicatePorts -contains $entry.Port) {
            [pscustomobject]@{
                Port         = $entry.Port
                Protocol     = $entry.Protocol
                IPAddress    = $IPAddress
                IsAvailable  = $false
                ErrorMessage = 'Port is duplicated in the requested port set.'
            }
        }
    }

    $availabilityResults = foreach ($entry in $normalizedPortSet) {
        if ($duplicatePorts -contains $entry.Port) { continue }

        Test-UGSMPortAvailable -Port $entry.Port -Protocol $entry.Protocol -IPAddress $IPAddress
    }

    $results = @($duplicateResults) + @($availabilityResults)

    return [pscustomobject]@{
        IsAvailable = (@($results | Where-Object { -not $_.IsAvailable }).Count -eq 0)
        Results     = @($results)
    }
}
