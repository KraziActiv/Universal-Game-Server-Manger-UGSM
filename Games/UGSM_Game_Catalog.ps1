# Game Catalog / Game Art

if (-not (Get-Variable -Name 'UGSM_GameModuleRegistryCache' -Scope Script -ErrorAction SilentlyContinue)) { $script:UGSM_GameModuleRegistryCache = $null }
if (-not (Get-Variable -Name 'UGSM_GameArtRootCache' -Scope Script -ErrorAction SilentlyContinue)) { $script:UGSM_GameArtRootCache = $null }
if (-not (Get-Variable -Name 'UGSM_GameArtFolderCache' -Scope Script -ErrorAction SilentlyContinue) -or -not $script:UGSM_GameArtFolderCache) { $script:UGSM_GameArtFolderCache = @{} }
if (-not (Get-Variable -Name 'UGSM_GameArtAssetCache' -Scope Script -ErrorAction SilentlyContinue) -or -not $script:UGSM_GameArtAssetCache) { $script:UGSM_GameArtAssetCache = @{} }

function Test-UGSMCatalogVerboseLogging {
    [CmdletBinding()]
    param()

    if ((Get-Variable -Name 'UGSM_EnableVerboseGameCatalogLogging' -Scope Script -ErrorAction SilentlyContinue) -and [bool]$script:UGSM_EnableVerboseGameCatalogLogging) { return $true }
    if (-not [string]::IsNullOrWhiteSpace($env:UGSM_VERBOSE_GAME_CATALOG)) { return $true }
    return $false
}

function Write-UGSMCatalogLog {
    [CmdletBinding()]
    param(
        [ValidateSet('TRACE','DEBUG','INFO','WARN','ERROR')]
        [string]$Level = 'DEBUG',

        [Parameter(Mandatory)]
        [string]$Message,

        [System.Exception]$Exception
    )

    if (($Level -in @('TRACE','DEBUG')) -and -not (Test-UGSMCatalogVerboseLogging)) { return }

    if (Get-Command -Name Write-UGSMLog -ErrorAction SilentlyContinue) {
        if ($Exception) {
            Write-UGSMLog -Level $Level -Category 'GameCatalog' -Message $Message -Exception $Exception
        }
        else {
            Write-UGSMLog -Level $Level -Category 'GameCatalog' -Message $Message
        }
        return
    }
}

function Clear-UGSMGameModuleRegistryCache {
    [CmdletBinding()]
    param()

    $script:UGSM_GameModuleRegistryCache = $null
    Write-UGSMCatalogLog -Level 'DEBUG' -Message 'Cleared game module registry cache.'
}

function Clear-UGSMGameArtPathCache {
    [CmdletBinding()]
    param(
        [string]$GameId
    )

    if ([string]::IsNullOrWhiteSpace($GameId)) {
        $script:UGSM_GameArtRootCache = $null
        $script:UGSM_GameArtFolderCache = @{}
        $script:UGSM_GameArtAssetCache = @{}
        return
    }

    if ($script:UGSM_GameArtFolderCache.ContainsKey($GameId)) {
        [void]$script:UGSM_GameArtFolderCache.Remove($GameId)
    }
    if ($script:UGSM_GameArtAssetCache.ContainsKey($GameId)) {
        [void]$script:UGSM_GameArtAssetCache.Remove($GameId)
    }
}

function Get-UGSMGameArtCacheRoot {
    [CmdletBinding()]
    param()

    if (-not [string]::IsNullOrWhiteSpace($script:UGSM_GameArtRootCache)) {
        return $script:UGSM_GameArtRootCache
    }

    $root = Join-Path $env:LOCALAPPDATA 'UGSM\Cache\GameArt'
    if (-not (Test-Path -LiteralPath $root -PathType Container)) {
        # Write-UGSMCatalogLog "Creating art cache root: $root"
        New-Item -Path $root -ItemType Directory -Force | Out-Null
    }

    $script:UGSM_GameArtRootCache = $root
    return $root
}

function Get-UGSMGameArtFolder {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$GameId
    )

    if ($script:UGSM_GameArtFolderCache.ContainsKey($GameId)) {
        return $script:UGSM_GameArtFolderCache[$GameId]
    }

    $folder = Join-Path (Get-UGSMGameArtCacheRoot) $GameId
    if (-not (Test-Path -LiteralPath $folder -PathType Container)) {
        # Write-UGSMCatalogLog "Creating art cache folder for ${GameId}: $folder"
        New-Item -Path $folder -ItemType Directory -Force | Out-Null
    }

    $script:UGSM_GameArtFolderCache[$GameId] = $folder
    return $folder
}

function Clear-UGSMGameArtCache {
    [CmdletBinding()]
    param()

    Clear-UGSMGameArtPathCache
    $root = Get-UGSMGameArtCacheRoot
    #Write-UGSMCatalogLog "Clearing game art cache under: $root"

    if (Test-Path -LiteralPath $root -PathType Container) {
        Get-ChildItem -LiteralPath $root -Recurse -File -ErrorAction SilentlyContinue |
        Remove-Item -Force -ErrorAction SilentlyContinue
    }

    if (-not (Test-Path -LiteralPath $root -PathType Container)) {
        New-Item -Path $root -ItemType Directory -Force | Out-Null
    }

    return $root
}

function Get-UGSMSteamHeaderArtUrl {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [int]$SteamAppId
    )

    return "https://cdn.cloudflare.steamstatic.com/steam/apps/$SteamAppId/header.jpg"
}

function Get-UGSMSteamLibraryArtUrl {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [int]$SteamAppId
    )

    return "https://cdn.cloudflare.steamstatic.com/steam/apps/$SteamAppId/library_600x900.jpg"
}

function Get-UGSMSteamCapsuleArtUrl {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [int]$SteamAppId
    )

    return "https://cdn.cloudflare.steamstatic.com/steam/apps/$SteamAppId/capsule_184x69.jpg"
}

function Get-UGSMSteamIconArtUrl {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [int]$SteamAppId
    )

    return "https://cdn.cloudflare.steamstatic.com/steam/apps/$SteamAppId/library_32x32.jpg"
}

function Save-UGSMGameArtFromUrl {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Url,

        [Parameter(Mandatory)]
        [string]$OutputPath
    )

    #Write-UGSMCatalogLog "Requesting art: $Url"
    #Write-UGSMCatalogLog "Target path: $OutputPath"

    try {
        $parent = Split-Path -Parent $OutputPath
        if (-not (Test-Path -LiteralPath $parent -PathType Container)) {
            #Write-UGSMCatalogLog "Creating parent folder: $parent"
            New-Item -Path $parent -ItemType Directory -Force | Out-Null
        }

        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

        Invoke-WebRequest -Uri $Url -OutFile $OutputPath -UseBasicParsing -ErrorAction Stop | Out-Null

        if (Test-Path -LiteralPath $OutputPath -PathType Leaf) {
            Write-UGSMCatalogLog -Level 'DEBUG' -Message "Saved game art: $OutputPath"
            return $OutputPath
        }

        Write-UGSMCatalogLog -Level 'WARN' -Message "Game art download completed but file was not created: $OutputPath"
    }
    catch {
        Write-UGSMCatalogLog -Level 'WARN' -Message "Game art download failed. Url=$Url; OutputPath=$OutputPath" -Exception $_.Exception
    }

    return $null
}

function Resolve-UGSMGameArtAssets {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$GameId,

        [Parameter()]
        [Nullable[int]]$SteamAppId,

        [Parameter()]
        [bool]$UseSteamArt = $true,

        [Parameter()]
        [switch]$Refresh
    )

    if (-not $Refresh -and $script:UGSM_GameArtAssetCache.ContainsKey($GameId)) {
        return $script:UGSM_GameArtAssetCache[$GameId]
    }

    $folder = Get-UGSMGameArtFolder -GameId $GameId

    $headerPath = Join-Path $folder 'header.jpg'
    $libraryPath = Join-Path $folder 'library_600x900.jpg'
    $capsulePath = Join-Path $folder 'capsule_184x69.jpg'
    # UGSM only needs the three reliable Steam art assets below.
    # Do not request the old fourth asset (library_32x32.jpg); many Steam apps return 404 for it.
    $iconPath = Join-Path $folder 'library_32x32.jpg'

    $headerExists = [System.IO.File]::Exists($headerPath)
    $libraryExists = [System.IO.File]::Exists($libraryPath)
    $capsuleExists = [System.IO.File]::Exists($capsulePath)
    $iconExists = [System.IO.File]::Exists($iconPath)

    if (($UseSteamArt -eq $true) -and ($null -ne $SteamAppId) -and ([int]$SteamAppId -gt 0)) {
        if (-not $headerExists) {
            [void](Save-UGSMGameArtFromUrl -Url (Get-UGSMSteamHeaderArtUrl -SteamAppId $SteamAppId) -OutputPath $headerPath)
            $headerExists = [System.IO.File]::Exists($headerPath)
        }

        if (-not $libraryExists) {
            [void](Save-UGSMGameArtFromUrl -Url (Get-UGSMSteamLibraryArtUrl -SteamAppId $SteamAppId) -OutputPath $libraryPath)
            $libraryExists = [System.IO.File]::Exists($libraryPath)
        }

        if (-not $capsuleExists) {
            [void](Save-UGSMGameArtFromUrl -Url (Get-UGSMSteamCapsuleArtUrl -SteamAppId $SteamAppId) -OutputPath $capsulePath)
            $capsuleExists = [System.IO.File]::Exists($capsulePath)
        }

        # Intentionally skipped:
        # library_32x32.jpg is not available for many games and creates noisy 404 warnings.
        # Header, library, and capsule art are enough for UGSM UI fallbacks.
    }

    $result = [pscustomobject]@{
        HeaderArtPath  = if ($headerExists) { $headerPath } else { $null }
        LibraryArtPath = if ($libraryExists) { $libraryPath } else { $null }
        CapsuleArtPath = if ($capsuleExists) { $capsulePath } else { $null }
        IconArtPath    = if ($iconExists) { $iconPath } else { $null }
    }

    $script:UGSM_GameArtAssetCache[$GameId] = $result
    return $result
}

function Get-UGSMGameModuleRegistry {
    [CmdletBinding()]
    param(
        [switch]$Refresh
    )

    if (-not $Refresh -and $script:UGSM_GameModuleRegistryCache) {
        #Write-UGSMCatalogLog 'Using cached game module registry.'
        return $script:UGSM_GameModuleRegistryCache
    }

    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    Write-UGSMCatalogLog -Level 'DEBUG' -Message 'Building game module registry from Register-UGSMGame*Module functions.'

    $registry = [ordered]@{}
    $registerCommands = @(
        Get-Command -Name 'Register-UGSMGame*Module' -CommandType Function -ErrorAction SilentlyContinue |
        Sort-Object Name
    )

    # Write-UGSMCatalogLog "Discovered register functions: $($registerCommands.Count)"

    foreach ($command in $registerCommands) {
        #   Write-UGSMCatalogLog "Invoking register function: $($command.Name)"

        try {
            $module = & $command.Name
        }
        catch {
            Write-UGSMCatalogLog -Level 'WARN' -Message "Register function failed. Function=$($command.Name)" -Exception $_.Exception
            continue
        }

        if (-not $module) {
            Write-UGSMCatalogLog -Level 'WARN' -Message "Register function returned null. Function=$($command.Name)"
            continue
        }

        $metadata = if ($module.PSObject.Properties['Metadata']) { $module.Metadata } else { $module }
        $handlers = if ($module.PSObject.Properties['Handlers']) { $module.Handlers } else { $null }
        $id = if ($metadata -and $metadata.PSObject.Properties['Id']) { [string]$metadata.Id } else { $null }

        if ([string]::IsNullOrWhiteSpace($id)) {
            Write-UGSMCatalogLog -Level 'WARN' -Message "Skipping game module because metadata Id was blank. Function=$($command.Name)"
            continue
        }

        $registry[$id] = [pscustomobject]@{
            Id       = $id
            Metadata = $metadata
            Handlers = $handlers
            Module   = $module
        }

        #    Write-UGSMCatalogLog "Registered game module: $id"
    }

    $script:UGSM_GameModuleRegistryCache = $registry
    $sw.Stop()
    Write-UGSMCatalogLog -Level 'INFO' -Message "Game module registry built. Count=$($registry.Count); DurationMs=$($sw.ElapsedMilliseconds)"
    return $registry
}

function Get-UGSMGameModuleById {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$GameId,

        [switch]$Refresh
    )

    $registry = Get-UGSMGameModuleRegistry -Refresh:$Refresh
    if ($registry.Contains($GameId)) {
        return $registry[$GameId]
    }

    #  Write-UGSMCatalogLog "Game module not found in registry: $GameId"
    return $null
}

function Get-UGSMGameCatalog {
    [CmdletBinding()]
    param(
        [switch]$Refresh
    )

    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    Write-UGSMCatalogLog -Level 'DEBUG' -Message 'Building game catalog.'

    $registry = Get-UGSMGameModuleRegistry -Refresh:$Refresh
    $games = foreach ($entry in $registry.Values) {
        try {
            $metadataFunction = $null

            if ($entry.PSObject.Properties['Handlers'] -and $entry.Handlers) {
                if ($entry.Handlers.PSObject.Properties['GetMetadata']) {
                    $metadataFunction = [string]$entry.Handlers.GetMetadata
                }
                elseif ($entry.Handlers.ContainsKey('GetMetadata')) {
                    $metadataFunction = [string]$entry.Handlers['GetMetadata']
                }
            }

            if ([string]::IsNullOrWhiteSpace($metadataFunction)) {
                Write-UGSMCatalogLog -Level 'WARN' -Message "Registry entry has no metadata function. GameId=$($entry.Id)"
                continue
            }

            if (-not (Get-Command -Name $metadataFunction -CommandType Function -ErrorAction SilentlyContinue)) {
                Write-UGSMCatalogLog -Level 'WARN' -Message "Metadata function was not found. GameId=$($entry.Id); Function=$metadataFunction"
                continue
            }

            $game = & $metadataFunction
            if (-not $game) {
                Write-UGSMCatalogLog -Level 'WARN' -Message "Metadata function returned null. GameId=$($entry.Id); Function=$metadataFunction"
                continue
            }

            if ($game.PSObject.Properties['IsVisible'] -and -not [bool]$game.IsVisible) {
                continue
            }

            # Write-UGSMCatalogLog "Processing game: $($game.Id) / $($game.Name)"

            $effectiveSteamAppId = $null
            if ($null -ne $game.SteamStoreAppId -and [int]$game.SteamStoreAppId -gt 0) {
                $effectiveSteamAppId = [int]$game.SteamStoreAppId
            }
            elseif ($null -ne $game.SteamAppId -and [int]$game.SteamAppId -gt 0) {
                $effectiveSteamAppId = [int]$game.SteamAppId
            }

            # Write-UGSMCatalogLog "Effective Steam art app id for $($game.Id): $effectiveSteamAppId"



            $useSteamArt = $game.UseSteamArt
            $useSteamArtType = if ($null -eq $useSteamArt) { '<null>' } else { $useSteamArt.GetType().FullName }
            # Write-UGSMCatalogLog "Pre-resolve for $($game.Id): game.UseSteamArt=[$useSteamArt] type=[$useSteamArtType]"

            $art = Resolve-UGSMGameArtAssets -GameId ([string]$game.Id) -SteamAppId $effectiveSteamAppId -UseSteamArt ([bool]$game.UseSteamArt) -Refresh:$Refresh

            [pscustomobject]@{
                Id               = [string]$game.Id
                Name             = [string]$game.Name
                SteamAppId       = if ($null -ne $effectiveSteamAppId) { $effectiveSteamAppId } else { $null }
                Category         = if ([string]::IsNullOrWhiteSpace([string]$game.Category)) { 'Other' } else { [string]$game.Category }
                UseSteamArt      = [bool]$game.UseSteamArt
                SupportsMods     = [bool]$game.SupportsMods
                SupportsWorkshop = [bool]$game.SupportsWorkshop
                IsCustom         = [bool]$game.IsCustom
                SortOrder        = if ($null -ne $game.SortOrder) { [int]$game.SortOrder } else { 9999 }
                HeaderArtPath    = $art.HeaderArtPath
                LibraryArtPath   = $art.LibraryArtPath
                CapsuleArtPath   = $art.CapsuleArtPath
                IconArtPath      = $art.IconArtPath
            }
        }
        catch {
            Write-UGSMCatalogLog -Level 'ERROR' -Message "Catalog build error. GameId=$($entry.Id)" -Exception $_.Exception
        }
    }

    $games = @($games | Sort-Object Name)
    $sw.Stop()
    if ($sw.ElapsedMilliseconds -ge 1000 -or (Test-UGSMCatalogVerboseLogging)) {
        Write-UGSMCatalogLog -Level 'INFO' -Message "Game catalog built. Count=$($games.Count); DurationMs=$($sw.ElapsedMilliseconds)"
    }
    return $games
}

function Get-UGSMGameById {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Id,

        [switch]$Refresh
    )

    return (Get-UGSMGameCatalog -Refresh:$Refresh | Where-Object { $_.Id -eq $Id } | Select-Object -First 1)
}

function Get-UGSMGameHeaderArt {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [psobject]$Game,

        [Parameter()]
        [switch]$Refresh
    )

    $resolvedGame = $Game
    if ($Game -and $Game.PSObject.Properties['Id'] -and -not [string]::IsNullOrWhiteSpace([string]$Game.Id) -and (Get-Command Get-UGSMGameById -ErrorAction SilentlyContinue)) {
        try {
            $freshGame = Get-UGSMGameById -Id ([string]$Game.Id) -Refresh:$Refresh
            if ($freshGame) {
                $resolvedGame = $freshGame
            }
        }
        catch {}
    }

    foreach ($propName in @('HeaderArtPath','LibraryArtPath','CapsuleArtPath','IconArtPath')) {
        if ($resolvedGame -and $resolvedGame.PSObject.Properties[$propName]) {
            $candidate = [string]$resolvedGame.$propName
            if (-not [string]::IsNullOrWhiteSpace($candidate) -and (Test-Path -LiteralPath $candidate -PathType Leaf)) {
                return $candidate
            }
        }
    }

    return $null
}
