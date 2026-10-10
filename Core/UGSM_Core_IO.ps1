# Core IO Helpers
# Consolidates path, directory, download, and archive helpers.

function Ensure-UGSMDirectory {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    if ([string]::IsNullOrWhiteSpace($Path)) {
        throw 'Path cannot be empty.'
    }

    if (-not (Test-Path -LiteralPath $Path -PathType Container)) {
        New-Item -Path $Path -ItemType Directory -Force | Out-Null
    }

    return $Path
}

function Test-UGSMFileExists {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    return (Test-Path -LiteralPath $Path -PathType Leaf)
}

function Test-UGSMDirectoryExists {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    return (Test-Path -LiteralPath $Path -PathType Container)
}

function Invoke-UGSMDownloadFile {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Uri,

        [Parameter(Mandatory)]
        [string]$OutFile
    )

    $parent = Split-Path -Path $OutFile -Parent
    if (-not [string]::IsNullOrWhiteSpace($parent)) {
        Ensure-UGSMDirectory -Path $parent | Out-Null
    }

    Invoke-WebRequest -Uri $Uri -OutFile $OutFile -UseBasicParsing -ErrorAction Stop | Out-Null

    return [pscustomobject]@{
        Success = (Test-Path -LiteralPath $OutFile -PathType Leaf)
        Path    = $OutFile
        Uri     = $Uri
    }
}

function Expand-UGSMZipArchive {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ZipPath,

        [Parameter(Mandatory)]
        [string]$DestinationPath
    )

    if (-not (Test-Path -LiteralPath $ZipPath -PathType Leaf)) {
        throw "Zip file not found: $ZipPath"
    }

    Ensure-UGSMDirectory -Path $DestinationPath | Out-Null
    Expand-Archive -LiteralPath $ZipPath -DestinationPath $DestinationPath -Force

    return [pscustomobject]@{
        Success         = $true
        ZipPath         = $ZipPath
        DestinationPath = $DestinationPath
    }
}
