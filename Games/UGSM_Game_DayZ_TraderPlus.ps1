# DayZ Trader Plus Mod Module.


function ConvertTo-UGSMGameDayZTraderPlusSafeLogText {
    [CmdletBinding()]
    param([AllowNull()][object]$Value)

    $text = [string]$Value
    if ([string]::IsNullOrWhiteSpace($text)) { return $text }

    try {
        $text = [regex]::Replace($text, '(?i)https?://(?:canary\.|ptb\.)?discord(?:app)?\.com/api/webhooks/[^\s''"<>]+', '[REDACTED_DISCORD_WEBHOOK]')
        $text = [regex]::Replace($text, '(?i)(password|pass|adminpassword|rconpassword|token|gslt|apikey|api_key|secret|privatekey|private_key)\s*[:=]\s*["'']?[^;"'',\s\}\]]+', '$1=[REDACTED]')
        $text = [regex]::Replace($text, '(?i)(C:\\Users\\)[^\\\s;,"'']+', '$1%USERPROFILE%')
        $text = [regex]::Replace($text, '(?i)(/Users/)[^/\s;,"'']+', '$1%USERPROFILE%')
    }
    catch {
    }

    return $text
}

function Write-UGSMGameDayZTraderPlusSafeLog {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Message,
        [ValidateSet('Debug', 'Info', 'Warn', 'Error')][string]$Level = 'Info'
    )

    try {
        $safeMessage = ConvertTo-UGSMGameDayZTraderPlusSafeLogText -Value $Message

        # Keep routine UI trace chatter out of INFO while preserving warnings/errors.
        if ($Level -eq 'Info') {
            if ($safeMessage -match '^(loadPrices:|cmbCategory\.SelectedIndexChanged|cmbCategory handler:|About to evaluate post-merge|loadFile completed after merge|loadPrices variable type|Merge start\.|Merge source selected\.|Backup created before merge\.)') {
                $Level = 'Debug'
            }
        }

        if (Get-Command -Name Write-UGSMGameDayZPathLog -ErrorAction SilentlyContinue) {
            Write-UGSMGameDayZPathLog -Message $safeMessage -Level $Level
            return
        }

        if (Get-Command -Name Write-UGSMLogEntry -ErrorAction SilentlyContinue) {
            Write-UGSMLogEntry -Category 'DayZTraderPlus' -Message $safeMessage -Level $Level
        }
    }
    catch {
    }
}


function Get-UGSMGameDayZTraderPlusManagedConfigFileNames {
    [CmdletBinding()]
    param()

    return @(
        'TraderPlusPriceConfig.json'
        'TraderPlusGeneralConfig.json'
        'TraderPlusIDsConfig.json'
        'TraderPlusSafeZoneConfig.json'
        'TraderPlusBankingConfig.json'
        'TraderPlusGarageConfig.json'
        'TraderPlusInsuranceConfig.json'
        'TraderPlusVehiclesConfig.json'
    )
}


function Get-UGSMGameDayZTraderPlusDefaultTraderClassNames {
    [CmdletBinding()]
    param()

    return @(
        'TraderPlusSign'
        'TraderPlus_BANK_ATM'

        'SurvivorM_Boris'
        'SurvivorM_Denis'
        'SurvivorM_Elias'
        'SurvivorM_Francis'
        'SurvivorM_Guo'
        'SurvivorM_Hassan'
        'SurvivorM_Indar'
        'SurvivorM_Jose'
        'SurvivorM_Kaito'
        'SurvivorM_Lewis'
        'SurvivorM_Manua'
        'SurvivorM_Niki'
        'SurvivorM_Oliver'
        'SurvivorM_Peter'
        'SurvivorM_Quinn'
        'SurvivorM_Rolf'
        'SurvivorM_Seth'
        'SurvivorM_Taiki'

        'SurvivorF_Eva'
        'SurvivorF_Frida'
        'SurvivorF_Gabi'
        'SurvivorF_Helga'
        'SurvivorF_Irena'
        'SurvivorF_Judy'
        'SurvivorF_Keiko'
        'SurvivorF_Linda'
        'SurvivorF_Maria'
        'SurvivorF_Naomi'
    )
}

function Get-UGSMGameDayZTraderPlusJsonFiles {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$Instance
    )

    $paths = Get-UGSMGameDayZProfilePaths -Instance $Instance
    $searchRoots = New-Object System.Collections.ArrayList

    $managedNames = Get-UGSMGameDayZTraderPlusManagedConfigFileNames

    $managedLookup = @{}
    foreach ($name in @($managedNames)) {
        if (-not [string]::IsNullOrWhiteSpace([string]$name)) {
            $managedLookup[[string]$name] = $true
        }
    }

    $preferredRoots = @()

    if ($paths.PSObject.Properties.Name -contains 'RuntimeProfilesRoot' -and
        -not [string]::IsNullOrWhiteSpace([string]$paths.RuntimeProfilesRoot)) {
        $preferredRoots += (Join-Path ([string]$paths.RuntimeProfilesRoot) 'TraderPlus\TraderPlusConfig')
    }

    if (-not [string]::IsNullOrWhiteSpace([string]$paths.ProfileRoot)) {
        $preferredRoots += (Join-Path ([string]$paths.ProfileRoot) 'profiles\TraderPlus\TraderPlusConfig')
    }

    foreach ($root in @($preferredRoots)) {
        if ([string]::IsNullOrWhiteSpace([string]$root)) { continue }
        if (-not (Test-Path -LiteralPath $root -PathType Container)) { continue }
        if ($searchRoots -contains $root) { continue }
        [void]$searchRoots.Add($root)
    }

    if ($searchRoots.Count -eq 0) {
        foreach ($candidate in @(
                [string]$paths.RuntimeProfilesRoot,
                [string]$paths.ProfileRoot,
                [string]$paths.RuntimeRoot,
                [string]$paths.RuntimeMissionPath,
                [string]$paths.RuntimeInstallRoot
            )) {
            if (-not [string]::IsNullOrWhiteSpace($candidate) -and (Test-Path -LiteralPath $candidate -PathType Container)) {
                if ($searchRoots -contains $candidate) { continue }
                [void]$searchRoots.Add($candidate)
            }
        }
    }

    $results = New-Object System.Collections.ArrayList
    $seen = @{}

    foreach ($root in @($searchRoots)) {
        foreach ($file in @(Get-ChildItem -LiteralPath $root -File -Recurse -ErrorAction SilentlyContinue)) {
            if (-not $managedLookup.ContainsKey([string]$file.Name)) { continue }
            if ($seen.ContainsKey($file.FullName)) { continue }
            $seen[$file.FullName] = $true

            $rank = 50
            $fullName = [string]$file.FullName

            $runtimeTraderPlusRoot = ''
            if ($paths.PSObject.Properties.Name -contains 'RuntimeProfilesRoot' -and
                -not [string]::IsNullOrWhiteSpace([string]$paths.RuntimeProfilesRoot)) {
                $runtimeTraderPlusRoot = Join-Path ([string]$paths.RuntimeProfilesRoot) 'TraderPlus\TraderPlusConfig'
            }

            $profileTraderPlusRoot = ''
            if (-not [string]::IsNullOrWhiteSpace([string]$paths.ProfileRoot)) {
                $profileTraderPlusRoot = Join-Path ([string]$paths.ProfileRoot) 'profiles\TraderPlus\TraderPlusConfig'
            }

            if (-not [string]::IsNullOrWhiteSpace($runtimeTraderPlusRoot) -and
                $fullName.StartsWith($runtimeTraderPlusRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
                $rank = 0
            }
            elseif (-not [string]::IsNullOrWhiteSpace($profileTraderPlusRoot) -and
                $fullName.StartsWith($profileTraderPlusRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
                $rank = 1
            }
            else {
                switch -Regex ($file.Name) {
                    '^TraderPlusPriceConfig\.json$' { $rank = 10; break }
                    '^TraderPlusGeneralConfig\.json$' { $rank = 11; break }
                    '^TraderPlusIDsConfig\.json$' { $rank = 12; break }
                    '^TraderPlus(SafeZone|Banking|Garage|Insurance|Vehicles)Config\.json$' { $rank = 13; break }
                }
            }

            $relativePath = $fullName
            if (-not [string]::IsNullOrWhiteSpace([string]$paths.ProfileRoot) -and
                $fullName.StartsWith([string]$paths.ProfileRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
                $relativePath = $fullName.Substring(([string]$paths.ProfileRoot).Length).TrimStart('\')
            }

            [void]$results.Add([pscustomobject]@{
                    Name         = $file.Name
                    FullName     = $fullName
                    Directory    = $file.DirectoryName
                    RelativePath = $relativePath
                    Rank         = $rank
                    LastWriteUtc = [datetime]$file.LastWriteTimeUtc
                })
        }
    }

    return @($results | Sort-Object Rank, Name, FullName)
}

function Convert-UGSMGameDayZTraderPlusProductStringToRow {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$CategoryName,
        [Parameter(Mandatory)][string]$ProductString
    )

    $parts = @([string]$ProductString -split ',', 6)
    while ($parts.Count -lt 6) { $parts += '' }

    return [pscustomobject]@{
        CategoryName  = [string]$CategoryName
        ClassName     = [string]$parts[0].Trim()
        Coefficient   = [string]$parts[1].Trim()
        MaxStock      = [string]$parts[2].Trim()
        TradeQuantity = [string]$parts[3].Trim()
        BuyPrice      = [string]$parts[4].Trim()
        SellPrice     = [string]$parts[5].Trim()
    }
}

function Convert-UGSMGameDayZTraderPlusRowToProductString {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$Row
    )

    return ([string[]]@(
            [string]$Row.ClassName
            [string]$Row.Coefficient
            [string]$Row.MaxStock
            [string]$Row.TradeQuantity
            [string]$Row.BuyPrice
            [string]$Row.SellPrice
        ) -join ',')
}

function Read-UGSMGameDayZTraderPlusPriceRows {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Path
    )

    $data = Read-UGSMGameDayZJsonDataSafe -Path $Path
    $rows = New-Object System.Collections.ArrayList

    foreach ($category in @($data.TraderCategories)) {
        if ($null -eq $category) { continue }
        $categoryName = [string](Get-UGSMGameDayZJsonObjectPropertyValue -Value $category -Name 'CategoryName')
        foreach ($product in @($category.Products)) {
            if ([string]::IsNullOrWhiteSpace([string]$product)) { continue }
            [void]$rows.Add((Convert-UGSMGameDayZTraderPlusProductStringToRow -CategoryName $categoryName -ProductString ([string]$product)))
        }
    }

    return @($rows)
}


function Read-UGSMGameDayZTraderPlusPriceCategoryNames {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Path
    )

    $data = Read-UGSMGameDayZJsonDataSafe -Path $Path
    $names = New-Object System.Collections.ArrayList
    $seen = @{}

    foreach ($category in @($data.TraderCategories)) {
        if ($null -eq $category) { continue }
        $categoryName = ([string](Get-UGSMGameDayZJsonObjectPropertyValue -Value $category -Name 'CategoryName')).Trim()
        if ([string]::IsNullOrWhiteSpace($categoryName)) { continue }
        if ($seen.ContainsKey($categoryName)) { continue }
        $seen[$categoryName] = $true
        [void]$names.Add($categoryName)
    }

    return @($names)
}

function Write-UGSMGameDayZTraderPlusPriceRows {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][object[]]$Rows,
        [object[]]$AdditionalCategories = @()
    )

    $data = Read-UGSMGameDayZJsonDataSafe -Path $Path
    $groupedRows = @{}

    foreach ($row in @($Rows)) {
        if ($null -eq $row) { continue }
        $categoryName = [string]$row.CategoryName
        $className = [string]$row.ClassName
        if ([string]::IsNullOrWhiteSpace($categoryName) -or [string]::IsNullOrWhiteSpace($className)) { continue }
        if (-not $groupedRows.ContainsKey($categoryName)) {
            $groupedRows[$categoryName] = New-Object System.Collections.ArrayList
        }
        [void]$groupedRows[$categoryName].Add((Convert-UGSMGameDayZTraderPlusRowToProductString -Row $row))
    }

    $categoryOrder = New-Object System.Collections.ArrayList
    foreach ($category in @($data.TraderCategories)) {
        $existingName = [string](Get-UGSMGameDayZJsonObjectPropertyValue -Value $category -Name 'CategoryName')
        if (-not [string]::IsNullOrWhiteSpace($existingName) -and -not ($categoryOrder -contains $existingName)) {
            [void]$categoryOrder.Add($existingName)
        }
    }
    foreach ($name in @($AdditionalCategories | Sort-Object)) {
        $categoryName = ([string]$name).Trim()
        if ([string]::IsNullOrWhiteSpace($categoryName)) { continue }
        if (-not ($categoryOrder -contains $categoryName)) { [void]$categoryOrder.Add($categoryName) }
        if (-not $groupedRows.ContainsKey($categoryName)) {
            $groupedRows[$categoryName] = New-Object System.Collections.ArrayList
        }
    }

    foreach ($name in @($groupedRows.Keys | Sort-Object)) {
        if (-not ($categoryOrder -contains $name)) { [void]$categoryOrder.Add([string]$name) }
    }

    $newCategories = New-Object System.Collections.ArrayList
    foreach ($name in @($categoryOrder)) {
        if (-not $groupedRows.ContainsKey([string]$name)) { continue }
        [void]$newCategories.Add([pscustomobject]@{
                CategoryName = [string]$name
                Products     = @($groupedRows[[string]$name])
            })
    }

    $data.TraderCategories = @($newCategories)
    [void](Write-UGSMGameDayZJsonDataSafe -Path $Path -Data $data)
    return $Path
}

function Get-UGSMGameDayZTypesItemIndex {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$TypesPath
    )

    $index = @{}
    if (-not (Test-Path -LiteralPath $TypesPath -PathType Leaf)) { return $index }

    try {
        [xml]$xml = Get-Content -LiteralPath $TypesPath -Raw -ErrorAction Stop
        foreach ($typeNode in @($xml.SelectNodes('//type'))) {
            if ($null -eq $typeNode) { continue }
            $name = [string]$typeNode.GetAttribute('name')
            if ([string]::IsNullOrWhiteSpace($name)) { continue }

            $nominal = 0
            $nominalNode = $typeNode.SelectSingleNode('./nominal')
            if ($nominalNode) { [void][int]::TryParse([string]$nominalNode.InnerText, [ref]$nominal) }

            $category = ''
            $categoryNode = $typeNode.SelectSingleNode('./category')
            if ($categoryNode -and $categoryNode.Attributes['name']) {
                $category = [string]$categoryNode.Attributes['name'].Value
            }

            $index[$name.ToLowerInvariant()] = [pscustomobject]@{
                ClassName = $name
                Nominal   = [int]$nominal
                Category  = $category
            }
        }
    }
    catch {
        throw "Failed to read types.xml item index from '$TypesPath': $($_.Exception.Message)"
    }

    return $index
}

function Get-UGSMGameDayZTraderPlusStockFromNominal {
    [CmdletBinding()]
    param([int]$Nominal)

    if (Get-Command -Name Get-UGSMGameDayZItemTraderBalance -ErrorAction SilentlyContinue) {
        $balance = Get-UGSMGameDayZItemTraderBalance -Nominal $Nominal
        return [int]$balance.MaxStock
    }

    $safeNom = [Math]::Max(1, [int]$Nominal)
    return [Math]::Max(1, [int](150 / ($safeNom / 5 + 1)))
}

function Get-UGSMGameDayZTraderPlusPriceFromNominal {
    [CmdletBinding()]
    param([int]$Nominal)

    if (Get-Command -Name Get-UGSMGameDayZItemTraderBalance -ErrorAction SilentlyContinue) {
        return (Get-UGSMGameDayZItemTraderBalance -Nominal $Nominal)
    }

    $safeNom = [Math]::Max(1, [int]$Nominal)
    return [pscustomobject]@{
        BuyPrice  = [int](150000 / ($safeNom + 10))
        SellPrice = [int](75000 / ($safeNom + 10))
        MaxStock  = (Get-UGSMGameDayZTraderPlusStockFromNominal -Nominal $safeNom)
    }
}

function Sync-UGSMGameDayZTraderPlusPriceConfigWithTypes {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory)][string]$PriceConfigPath,
        [Parameter(Mandatory)][string]$TypesPath,
        [string]$DefaultCategoryName = 'AUTO_IMPORTED_ITEMS',
        [string]$SkipNamePattern = '^(ZmbF_|ZmbM_|Zmb|StaticObj_|Land_|Wreck_|Fireplace|Bonfire|BanditAI_|TraderPlus_Money_)',
        [switch]$SkipZeroNominal,
        [switch]$AddMissingItems,
        [switch]$UpdateStockFromNominal,
        [switch]$PassThru
    )

    if (-not (Test-Path -LiteralPath $PriceConfigPath -PathType Leaf)) { throw "TraderPlus price config not found: $PriceConfigPath" }
    if (-not (Test-Path -LiteralPath $TypesPath -PathType Leaf)) { throw "types.xml not found: $TypesPath" }

    $typeIndex = Get-UGSMGameDayZTypesItemIndex -TypesPath $TypesPath
    $data = Read-UGSMGameDayZJsonDataSafe -Path $PriceConfigPath
    if ($null -eq $data.TraderCategories) {
        $data | Add-Member -NotePropertyName TraderCategories -NotePropertyValue @() -Force
    }

    $existing = @{}
    $categoryMap = @{}
    foreach ($cat in @($data.TraderCategories)) {
        if ($null -eq $cat) { continue }
        $catName = [string]$cat.CategoryName
        if ([string]::IsNullOrWhiteSpace($catName)) { continue }
        $categoryMap[$catName] = $cat
        foreach ($prod in @($cat.Products)) {
            $parts = @([string]$prod -split ',', 6)
            if ($parts.Count -lt 1) { continue }
            $className = [string]$parts[0].Trim()
            if ([string]::IsNullOrWhiteSpace($className)) { continue }
            $existing[$className.ToLowerInvariant()] = [pscustomobject]@{ Category = $cat; Product = [string]$prod }
        }
    }

    $stockUpdated = 0
    $itemsAdded = 0
    $itemsSkipped = 0
    $changed = $false

    if ($UpdateStockFromNominal) {
        foreach ($cat in @($data.TraderCategories)) {
            if ($null -eq $cat -or $null -eq $cat.Products) { continue }
            $newProducts = New-Object System.Collections.ArrayList
            foreach ($prod in @($cat.Products)) {
                $parts = @([string]$prod -split ',', 6)
                while ($parts.Count -lt 6) { $parts += '' }
                $className = [string]$parts[0].Trim()
                if ([string]::IsNullOrWhiteSpace($className)) { [void]$newProducts.Add([string]$prod); continue }

                $key = $className.ToLowerInvariant()
                if ($typeIndex.ContainsKey($key)) {
                    $newStock = [string](Get-UGSMGameDayZTraderPlusStockFromNominal -Nominal ([int]$typeIndex[$key].Nominal))
                    if ([string]$parts[2].Trim() -ne $newStock) {
                        $parts[2] = $newStock
                        $stockUpdated++
                        $changed = $true
                    }
                }

                [void]$newProducts.Add(([string[]]$parts -join ','))
            }
            $cat.Products = @($newProducts)
        }
    }

    if ($AddMissingItems) {
        if ([string]::IsNullOrWhiteSpace($DefaultCategoryName)) { $DefaultCategoryName = 'AUTO_IMPORTED_ITEMS' }
        if (-not $categoryMap.ContainsKey($DefaultCategoryName)) {
            $newCat = [pscustomobject]@{ CategoryName = $DefaultCategoryName; Products = @() }
            $data.TraderCategories += $newCat
            $categoryMap[$DefaultCategoryName] = $newCat
            $changed = $true
        }

        $targetCat = $categoryMap[$DefaultCategoryName]
        $products = New-Object System.Collections.ArrayList
        foreach ($prod in @($targetCat.Products)) { [void]$products.Add([string]$prod) }

        foreach ($key in @($typeIndex.Keys | Sort-Object)) {
            $item = $typeIndex[$key]
            $className = [string]$item.ClassName
            $nominal = [int]$item.Nominal

            if ([string]::IsNullOrWhiteSpace($className)) {
                $itemsSkipped++
                continue
            }

            if ($SkipZeroNominal -and $nominal -le 0) {
                $itemsSkipped++
                continue
            }

            if (-not [string]::IsNullOrWhiteSpace($SkipNamePattern) -and $className -imatch $SkipNamePattern) {
                $itemsSkipped++
                continue
            }

            if ($existing.ContainsKey($key)) {
                $itemsSkipped++
                continue
            }

            $balance = Get-UGSMGameDayZTraderPlusPriceFromNominal -Nominal $nominal

            $product = ([string[]]@(
                    $className,
                    '1.0',
                    [string](Get-UGSMGameDayZTraderPlusStockFromNominal -Nominal $nominal),
                    '-1',
                    [string][int]$balance.BuyPrice,
                    [string][int]$balance.SellPrice
                ) -join ',')

            [void]$products.Add($product)
            $existing[$key] = [pscustomobject]@{ Category = $targetCat; Product = $product }
            $itemsAdded++
            $changed = $true
        }

        $targetCat.Products = @($products)
    }

    if ($changed -and $PSCmdlet.ShouldProcess($PriceConfigPath, 'sync TraderPlus price config with types.xml')) {
        Write-UGSMGameDayZJsonDataSafe -Path $PriceConfigPath -Data $data
    }

    return [pscustomobject]@{
        PriceConfigPath        = $PriceConfigPath
        TypesPath              = $TypesPath
        AddMissingItems        = [bool]$AddMissingItems
        UpdateStockFromNominal = [bool]$UpdateStockFromNominal
        ItemsAdded             = [int]$itemsAdded
        ExistingItemsSkipped   = [int]$itemsSkipped
        StockValuesUpdated     = [int]$stockUpdated
        DefaultCategoryName    = [string]$DefaultCategoryName
        SkipNamePattern        = [string]$SkipNamePattern
        Changed                = [bool]$changed
    }
}

function Merge-UGSMGameDayZTraderPlusPriceData {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$TargetData,
        [Parameter(Mandatory)][object]$SourceData
    )

    $merged = Merge-UGSMGameDayZJsonValues -TargetValue $TargetData -SourceValue $SourceData

    $categories = New-Object System.Collections.ArrayList
    $categoryMap = @{}

    foreach ($cat in @($TargetData.TraderCategories)) {
        if ($null -eq $cat) { continue }
        $name = [string]$cat.CategoryName
        if ([string]::IsNullOrWhiteSpace($name)) { continue }

        $copy = [pscustomobject]@{
            CategoryName = $cat.CategoryName
            Products     = @($cat.Products)
        }

        $categoryMap[$name] = $copy
        [void]$categories.Add($copy)
    }

    foreach ($srcCat in @($SourceData.TraderCategories)) {
        if ($null -eq $srcCat) { continue }
        $name = [string]$srcCat.CategoryName
        if ([string]::IsNullOrWhiteSpace($name)) { continue }

        if (-not $categoryMap.ContainsKey($name)) {
            $copy = [pscustomobject]@{
                CategoryName = $srcCat.CategoryName
                Products     = @($srcCat.Products)
            }

            $categoryMap[$name] = $copy
            [void]$categories.Add($copy)
            continue
        }

        $targetCat = $categoryMap[$name]
        $productMap = @{}

        foreach ($prod in @($targetCat.Products)) {
            $key = (([string]$prod -split ',', 2)[0]).Trim()
            if (-not [string]::IsNullOrWhiteSpace($key) -and -not $productMap.ContainsKey($key)) {
                $productMap[$key] = [string]$prod
            }
        }

        foreach ($srcProd in @($srcCat.Products)) {
            $key = (([string]$srcProd -split ',', 2)[0]).Trim()
            if ([string]::IsNullOrWhiteSpace($key)) { continue }
            if (-not $productMap.ContainsKey($key)) {
                $productMap[$key] = [string]$srcProd
            }
        }

        $mergedProducts = New-Object System.Collections.ArrayList

        foreach ($existing in @($targetCat.Products)) {
            $key = (([string]$existing -split ',', 2)[0]).Trim()
            if (-not [string]::IsNullOrWhiteSpace($key) -and $productMap.ContainsKey($key)) {
                [void]$mergedProducts.Add($productMap[$key])
                [void]$productMap.Remove($key)
            }
        }

        foreach ($remainingKey in @($productMap.Keys | Sort-Object)) {
            [void]$mergedProducts.Add($productMap[$remainingKey])
        }

        $targetCat.Products = @($mergedProducts)
    }

    $merged.TraderCategories = @($categories)
    return $merged
}

function Test-UGSMGameDayZTraderPlusPriceConfigFile {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Path
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        return $false
    }

    try {
        $data = Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json -Depth 100
        if ($null -eq $data) { return $false }
        if ($null -eq $data.TraderCategories) { return $false }

        $propertyNames = @($data.PSObject.Properties.Name)

        if ($propertyNames -contains 'EnableAutoCalculation' -or
            $propertyNames -contains 'EnableAutoDestockAtRestart' -or
            $propertyNames -contains 'EnableDefaultTraderStock') {
            return $true
        }

        return $false
    }
    catch {
        return $false
    }
}

function Merge-UGSMGameDayZJsonFiles {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$TargetPath,
        [Parameter(Mandatory)][string]$SourcePath
    )

    $targetData = Read-UGSMGameDayZJsonDataSafe -Path $TargetPath
    $sourceData = Read-UGSMGameDayZJsonDataSafe -Path $SourcePath

    $isTraderPlusMerge = ([System.IO.Path]::GetFileName($TargetPath) -eq 'TraderPlusPriceConfig.json')

    if ($isTraderPlusMerge) {
        $merged = Merge-UGSMGameDayZTraderPlusPriceData -TargetData $targetData -SourceData $sourceData
    }
    else {
        $merged = Merge-UGSMGameDayZJsonValues -TargetValue $targetData -SourceValue $sourceData
    }

    [void](Write-UGSMGameDayZJsonDataSafe -Path $TargetPath -Data $merged)
    return $TargetPath
}

function Merge-UGSMGameDayZTraderPlusPriceConfig {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$TargetPath,
        [Parameter(Mandatory)][string]$SourcePath
    )

    if (-not (Test-Path -LiteralPath $TargetPath -PathType Leaf)) { throw "Target file not found: $TargetPath" }
    if (-not (Test-Path -LiteralPath $SourcePath -PathType Leaf)) { throw "Source file not found: $SourcePath" }

    $target = Get-Content -LiteralPath $TargetPath -Raw | ConvertFrom-Json -Depth 100
    $source = Get-Content -LiteralPath $SourcePath -Raw | ConvertFrom-Json -Depth 100

    if ($null -eq $target.TraderCategories) {
        $target | Add-Member -NotePropertyName TraderCategories -NotePropertyValue @() -Force
    }

    if ($null -eq $source.TraderCategories) {
        return $TargetPath
    }

    $categoryMap = @{}
    foreach ($cat in @($target.TraderCategories)) {
        if ($null -eq $cat) { continue }
        $name = [string]$cat.CategoryName
        if ([string]::IsNullOrWhiteSpace($name)) { continue }
        $categoryMap[$name] = $cat
    }

    foreach ($srcCat in @($source.TraderCategories)) {
        if ($null -eq $srcCat) { continue }

        $catName = [string]$srcCat.CategoryName
        if ([string]::IsNullOrWhiteSpace($catName)) { continue }

        if (-not $categoryMap.ContainsKey($catName)) {
            $target.TraderCategories += $srcCat
            $categoryMap[$catName] = $srcCat
            continue
        }

        $tgtCat = $categoryMap[$catName]

        if ($null -eq $tgtCat.Products) { $tgtCat.Products = @() }
        if ($null -eq $srcCat.Products) { continue }

        $productMap = @{}
        foreach ($prod in @($tgtCat.Products)) {
            $prodText = [string]$prod
            $key = ($prodText -split ',', 2)[0].Trim()
            if (-not [string]::IsNullOrWhiteSpace($key) -and -not $productMap.ContainsKey($key)) {
                $productMap[$key] = $prodText
            }
        }

        foreach ($srcProd in @($srcCat.Products)) {
            $prodText = [string]$srcProd
            $key = ($prodText -split ',', 2)[0].Trim()
            if ([string]::IsNullOrWhiteSpace($key)) { continue }
            if (-not $productMap.ContainsKey($key)) {
                $productMap[$key] = $prodText
            }
        }

        $mergedProducts = New-Object System.Collections.ArrayList

        foreach ($existing in @($tgtCat.Products)) {
            $key = (([string]$existing -split ',', 2)[0]).Trim()
            if (-not [string]::IsNullOrWhiteSpace($key) -and $productMap.ContainsKey($key)) {
                [void]$mergedProducts.Add($productMap[$key])
                [void]$productMap.Remove($key)
            }
        }

        foreach ($remainingKey in @($productMap.Keys | Sort-Object)) {
            [void]$mergedProducts.Add($productMap[$remainingKey])
        }

        $tgtCat.Products = @($mergedProducts)
    }

    $json = $target | ConvertTo-Json -Depth 100
    [System.IO.File]::WriteAllText($TargetPath, $json, (New-Object System.Text.UTF8Encoding($false)))

    return $TargetPath
}

function Read-UGSMGameDayZTypesXmlRows {

    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Path
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        return @()
    }

    [xml]$xml = Get-Content -LiteralPath $Path -Raw -ErrorAction Stop
    $rows = @()

    $typeNodes = @()
    if ($xml -and $xml.DocumentElement -and $xml.DocumentElement.Name -eq 'types') {
        $typeNodes = $xml.DocumentElement.SelectNodes('./type')
    }

    foreach ($typeNode in $typeNodes) {
        if ($null -eq $typeNode) { continue }

        $usageValues = @()
        foreach ($usageNode in @($typeNode.SelectNodes('./usage'))) {
            if ($usageNode -and $usageNode.Attributes['name']) {
                $usageValues += [string]$usageNode.Attributes['name'].Value
            }
        }

        $valueValues = @()
        foreach ($valueNode in @($typeNode.SelectNodes('./value'))) {
            if ($valueNode -and $valueNode.Attributes['name']) {
                $valueValues += [string]$valueNode.Attributes['name'].Value
            }
        }

        $categoryValue = ''
        $categoryNode = $typeNode.SelectSingleNode('./category')
        if ($categoryNode -and $categoryNode.Attributes['name']) {
            $categoryValue = [string]$categoryNode.Attributes['name'].Value
        }

        $flagsNode = $typeNode.SelectSingleNode('./flags')
        $getFlagValue = {
            param(
                [object]$Node,
                [string]$Name,
                [string]$Default
            )

            if ($Node -and $Node.Attributes[$Name]) {
                return [string]$Node.Attributes[$Name].Value
            }

            return [string]$Default
        }

        $flagCargo = & $getFlagValue $flagsNode 'count_in_cargo' '0'
        $flagHoarder = & $getFlagValue $flagsNode 'count_in_hoarder' '0'
        $flagMap = & $getFlagValue $flagsNode 'count_in_map' '1'
        $flagPlayer = & $getFlagValue $flagsNode 'count_in_player' '0'
        $flagCrafted = & $getFlagValue $flagsNode 'crafted' '0'
        $flagDeloot = & $getFlagValue $flagsNode 'deloot' '0'
        $delootDisplay = if ($flagDeloot -eq '1' -or $flagDeloot.ToLowerInvariant() -eq 'true' -or $flagDeloot.ToLowerInvariant() -eq 'yes') { 'Yes' } else { 'No' }

        $rows += [pscustomobject]@{
            Name           = [string]$(if ($typeNode.Attributes['name']) { $typeNode.Attributes['name'].Value } else { '' })
            Nominal        = [string]($typeNode.SelectSingleNode('./nominal').'#text')
            Lifetime       = [string]($typeNode.SelectSingleNode('./lifetime').'#text')
            Restock        = [string]($typeNode.SelectSingleNode('./restock').'#text')
            Min            = [string]($typeNode.SelectSingleNode('./min').'#text')
            Max            = if ($typeNode.SelectSingleNode('./max') -and -not [string]::IsNullOrWhiteSpace([string]($typeNode.SelectSingleNode('./max').'#text'))) { [string]($typeNode.SelectSingleNode('./max').'#text') } else { '0' }
            QuantMin       = [string]($typeNode.SelectSingleNode('./quantmin').'#text')
            QuantMax       = [string]($typeNode.SelectSingleNode('./quantmax').'#text')
            Cost           = [string]($typeNode.SelectSingleNode('./cost').'#text')
            Category       = $categoryValue
            Usage          = [string]($usageValues -join ',')
            Value          = [string]($valueValues -join ',')
            Deloot         = $delootDisplay
            CountInCargo   = $flagCargo
            CountInHoarder = $flagHoarder
            CountInMap     = $flagMap
            CountInPlayer  = $flagPlayer
            Crafted        = $flagCrafted
        }
    }

    return @($rows)
}

function Write-UGSMGameDayZTypesXmlRows {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][object[]]$Rows
    )

    $settings = New-Object System.Xml.XmlWriterSettings
    $settings.Indent = $true
    $settings.IndentChars = '    '
    $settings.NewLineChars = [Environment]::NewLine
    $settings.NewLineHandling = [System.Xml.NewLineHandling]::Replace
    $settings.Encoding = New-Object System.Text.UTF8Encoding($false)

    $parent = Split-Path -Parent $Path
    if (-not [string]::IsNullOrWhiteSpace([string]$parent) -and -not (Test-Path -LiteralPath $parent -PathType Container)) {
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
    }

    $writer = [System.Xml.XmlWriter]::Create($Path, $settings)
    try {
        $writer.WriteStartDocument()
        $writer.WriteStartElement('types')

        foreach ($row in @($Rows)) {
            if ($null -eq $row) { continue }

            $name = [string]$row.Name
            if ([string]::IsNullOrWhiteSpace($name)) { continue }

            $writer.WriteStartElement('type')
            $writer.WriteAttributeString('name', $name)

            $normalizeTypeValue = {
                param(
                    [object]$Value,
                    [string]$Default = ''
                )

                $text = [string]$Value
                if ([string]::IsNullOrWhiteSpace($text)) { return $Default }
                return $text.Trim()
            }

            foreach ($field in @(
                    @{ Name = 'nominal'; Value = (& $normalizeTypeValue $row.Nominal '0') }
                    @{ Name = 'lifetime'; Value = (& $normalizeTypeValue $row.Lifetime '0') }
                    @{ Name = 'restock'; Value = (& $normalizeTypeValue $row.Restock '0') }
                    @{ Name = 'min'; Value = (& $normalizeTypeValue $row.Min '0') }
                    @{ Name = 'max'; Value = if ($row.PSObject.Properties.Name -contains 'Max') { (& $normalizeTypeValue $row.Max '0') } else { '0' } }
                    @{ Name = 'quantmin'; Value = (& $normalizeTypeValue $row.QuantMin '-1') }
                    @{ Name = 'quantmax'; Value = (& $normalizeTypeValue $row.QuantMax '-1') }
                    @{ Name = 'cost'; Value = (& $normalizeTypeValue $row.Cost '100') }
                )) {
                $writer.WriteElementString($field.Name, [string]$field.Value)
            }

            $normalizeFlag = {
                param(
                    [string]$Value,
                    [string]$Default = '0'
                )

                if ([string]::IsNullOrWhiteSpace($Value)) { return $Default }

                $clean = $Value.Trim()
                if ($clean -eq '1' -or $clean.ToLowerInvariant() -eq 'true' -or $clean.ToLowerInvariant() -eq 'yes') { return '1' }
                if ($clean -eq '0' -or $clean.ToLowerInvariant() -eq 'false' -or $clean.ToLowerInvariant() -eq 'no') { return '0' }

                return $clean
            }

            $writer.WriteStartElement('flags')
            $writer.WriteAttributeString('count_in_cargo', (& $normalizeFlag ([string]$row.CountInCargo) '0'))
            $writer.WriteAttributeString('count_in_hoarder', (& $normalizeFlag ([string]$row.CountInHoarder) '0'))
            $writer.WriteAttributeString('count_in_map', (& $normalizeFlag ([string]$row.CountInMap) '1'))
            $writer.WriteAttributeString('count_in_player', (& $normalizeFlag ([string]$row.CountInPlayer) '0'))
            $writer.WriteAttributeString('crafted', (& $normalizeFlag ([string]$row.Crafted) '0'))
            $writer.WriteAttributeString('deloot', (& $normalizeFlag ([string]$row.Deloot) '0'))
            $writer.WriteEndElement()

            $category = [string]$row.Category
            if (-not [string]::IsNullOrWhiteSpace($category)) {
                $writer.WriteStartElement('category')
                $writer.WriteAttributeString('name', $category.Trim())
                $writer.WriteEndElement()
            }

            foreach ($usage in @(([string]$row.Usage -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ }))) {
                $writer.WriteStartElement('usage')
                $writer.WriteAttributeString('name', $usage)
                $writer.WriteEndElement()
            }

            foreach ($value in @(([string]$row.Value -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ }))) {
                $writer.WriteStartElement('value')
                $writer.WriteAttributeString('name', $value)
                $writer.WriteEndElement()
            }

            $writer.WriteEndElement()
        }

        $writer.WriteEndElement()
        $writer.WriteEndDocument()
    }
    finally {
        if ($writer) { $writer.Dispose() }
    }

    return $Path
}

function Get-UGSMGameDayZTypesGridRows {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][System.Windows.Forms.DataGridView]$Grid
    )

    $rows = @()

    foreach ($gridRow in @($Grid.Rows)) {
        if ($null -eq $gridRow -or $gridRow.IsNewRow) { continue }

        $name = [string]$gridRow.Cells['Name'].Value
        if ([string]::IsNullOrWhiteSpace($name)) { continue }

        $rows += [pscustomobject]@{
            Name     = $name.Trim()
            Nominal  = [string]$gridRow.Cells['Nominal'].Value
            Lifetime = [string]$gridRow.Cells['Lifetime'].Value
            Restock  = [string]$gridRow.Cells['Restock'].Value
            Min      = [string]$gridRow.Cells['Min'].Value
            Max      = if ($Grid.Columns.Contains('Max') -and -not [string]::IsNullOrWhiteSpace([string]$gridRow.Cells['Max'].Value)) { [string]$gridRow.Cells['Max'].Value } else { '0' }
            QuantMin = [string]$gridRow.Cells['QuantMin'].Value
            QuantMax = [string]$gridRow.Cells['QuantMax'].Value
            Cost     = [string]$gridRow.Cells['Cost'].Value
            Category       = [string]$gridRow.Cells['Category'].Value
            Usage          = [string]$gridRow.Cells['Usage'].Value
            Value          = [string]$gridRow.Cells['Value'].Value
            Deloot         = [string]$gridRow.Cells['Deloot'].Value
            CountInCargo   = [string]$gridRow.Cells['CountInCargo'].Value
            CountInHoarder = [string]$gridRow.Cells['CountInHoarder'].Value
            CountInMap     = [string]$gridRow.Cells['CountInMap'].Value
            CountInPlayer  = [string]$gridRow.Cells['CountInPlayer'].Value
            Crafted        = [string]$gridRow.Cells['Crafted'].Value
        }
    }

    return @($rows)
}


function Convert-UGSMGameDayZXmlNodeToPrettyString {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][System.Xml.XmlNode]$Node
    )

    $settings = New-Object System.Xml.XmlWriterSettings
    $settings.Indent = $true
    $settings.IndentChars = '    '
    $settings.OmitXmlDeclaration = $true
    $settings.NewLineChars = [Environment]::NewLine
    $settings.NewLineHandling = [System.Xml.NewLineHandling]::Replace

    $builder = New-Object System.Text.StringBuilder
    $writer = [System.Xml.XmlWriter]::Create($builder, $settings)
    try {
        $Node.WriteTo($writer)
    }
    finally {
        if ($writer) {
            $writer.Flush()
            $writer.Dispose()
        }
    }

    return [string]$builder.ToString()
}

function Read-UGSMGameDayZSpawnableTypesXmlRows {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Path
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        return @()
    }

    $xml = Read-UGSMGameDayZXmlDocumentSafe -Path $Path
    if ($null -eq $xml -or $null -eq $xml.DocumentElement) {
        return @()
    }

    $rows = @()
    $typeNodes = $xml.DocumentElement.SelectNodes('./type')

    foreach ($typeNode in @($typeNodes)) {
        if ($null -eq $typeNode) { continue }

        $attachmentsNode = $typeNode.SelectSingleNode('./attachments')
        $cargoNode = $typeNode.SelectSingleNode('./cargo')
        $damageNode = $typeNode.SelectSingleNode('./damage')

        $rows += [pscustomobject]@{
            Name             = [string]$typeNode.GetAttribute('name')
            AttachmentsCount = @($typeNode.SelectNodes('./attachments/attachment')).Count
            CargoCount       = @($typeNode.SelectNodes('./cargo/item')).Count
            HasAttachments   = if ($attachmentsNode) { 'Yes' } else { 'No' }
            HasCargo         = if ($cargoNode) { 'Yes' } else { 'No' }
            DamageMin        = if ($damageNode) { [string]$damageNode.GetAttribute('min') } else { '' }
            DamageMax        = if ($damageNode) { [string]$damageNode.GetAttribute('max') } else { '' }
            OuterXml         = [string](Convert-UGSMGameDayZXmlNodeToPrettyString -Node $typeNode)
        }
    }

    return @($rows)
}

function Get-UGSMGameDayZSpawnableTypesGridRows {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][System.Windows.Forms.DataGridView]$Grid
    )

    $rows = @()

    foreach ($gridRow in @($Grid.Rows)) {
        if ($null -eq $gridRow -or $gridRow.IsNewRow) { continue }

        $name = [string]$gridRow.Cells['Name'].Value
        if ([string]::IsNullOrWhiteSpace($name)) { continue }

        $tag = $gridRow.Tag
        $rows += [pscustomobject]@{
            Name             = $name.Trim()
            AttachmentsCount = [string]$gridRow.Cells['AttachmentsCount'].Value
            CargoCount       = [string]$gridRow.Cells['CargoCount'].Value
            HasAttachments   = [string]$gridRow.Cells['HasAttachments'].Value
            HasCargo         = [string]$gridRow.Cells['HasCargo'].Value
            DamageMin        = [string]$gridRow.Cells['DamageMin'].Value
            DamageMax        = [string]$gridRow.Cells['DamageMax'].Value
            OuterXml         = if ($tag) { [string]$tag.OuterXml } else { '' }
        }
    }

    return @($rows)
}

function Write-UGSMGameDayZSpawnableTypesXmlRows {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][object[]]$Rows
    )

    $settings = New-Object System.Xml.XmlWriterSettings
    $settings.Indent = $true
    $settings.IndentChars = '    '
    $settings.NewLineChars = [Environment]::NewLine
    $settings.NewLineHandling = [System.Xml.NewLineHandling]::Replace
    $settings.Encoding = New-Object System.Text.UTF8Encoding($false)

    $parent = Split-Path -Parent $Path
    if (-not [string]::IsNullOrWhiteSpace([string]$parent) -and -not (Test-Path -LiteralPath $parent -PathType Container)) {
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
    }

    $writer = [System.Xml.XmlWriter]::Create($Path, $settings)
    try {
        $writer.WriteStartDocument()
        $writer.WriteStartElement('spawnabletypes')

        foreach ($row in @($Rows)) {
            if ($null -eq $row) { continue }

            $outerXml = [string]$row.OuterXml
            $name = [string]$row.Name
            if ([string]::IsNullOrWhiteSpace($outerXml) -and [string]::IsNullOrWhiteSpace($name)) { continue }

            if (-not [string]::IsNullOrWhiteSpace($outerXml)) {
                $fragmentDoc = New-Object System.Xml.XmlDocument
                try {
                    $fragmentDoc.LoadXml("<spawnabletypes>$outerXml</spawnabletypes>")
                }
                catch {
                    throw "Spawnable type '$name' contains invalid XML: $($_.Exception.Message)"
                }

                foreach ($typeNode in @($fragmentDoc.DocumentElement.SelectNodes('./type'))) {
                    if ($typeNode) {
                        $writer.WriteRaw([string](Convert-UGSMGameDayZXmlNodeToPrettyString -Node $typeNode))
                    }
                }
            }
        }

        $writer.WriteEndElement()
        $writer.WriteEndDocument()
    }
    finally {
        if ($writer) { $writer.Dispose() }
    }

    return $Path
}



function Get-UGSMGameDayZTraderPlusSiblingConfigPath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$PriceConfigPath,
        [Parameter(Mandatory)][string]$FileName
    )

    if ([string]::IsNullOrWhiteSpace($PriceConfigPath)) { return '' }
    $configRoot = Split-Path -Parent $PriceConfigPath
    if ([string]::IsNullOrWhiteSpace($configRoot)) { return '' }
    return (Join-Path $configRoot $FileName)
}

function Get-UGSMGameDayZTraderPlusTraderRows {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$PriceConfigPath
    )

    $rows = New-Object System.Collections.ArrayList
    $seen = @{}

    $generalPath = Get-UGSMGameDayZTraderPlusSiblingConfigPath -PriceConfigPath $PriceConfigPath -FileName 'TraderPlusGeneralConfig.json'
    if (-not [string]::IsNullOrWhiteSpace($generalPath) -and (Test-Path -LiteralPath $generalPath -PathType Leaf)) {
        try {
            $generalData = Read-UGSMGameDayZJsonDataSafe -Path $generalPath
            foreach ($trader in @($generalData.Traders)) {
                if ($null -eq $trader) { continue }
                $id = [string]$trader.Id
                if ([string]::IsNullOrWhiteSpace($id)) { continue }
                $seen[$id] = $true
                $givenName = [string]$trader.GivenName
                $role = [string]$trader.Role
                $name = [string]$trader.Name
                $labelBits = @($id)
                if (-not [string]::IsNullOrWhiteSpace($givenName)) { $labelBits += $givenName }
                if (-not [string]::IsNullOrWhiteSpace($role)) { $labelBits += ('- ' + $role) }
                elseif (-not [string]::IsNullOrWhiteSpace($name)) { $labelBits += ('- ' + $name) }

                [void]$rows.Add([pscustomobject]@{
                    Id        = $id
                    GivenName = $givenName
                    Role      = $role
                    Name      = $name
                    Label     = [string]($labelBits -join ' ')
                })
            }
        }
        catch { }
    }

    $idsPath = Get-UGSMGameDayZTraderPlusSiblingConfigPath -PriceConfigPath $PriceConfigPath -FileName 'TraderPlusIDsConfig.json'
    if (-not [string]::IsNullOrWhiteSpace($idsPath) -and (Test-Path -LiteralPath $idsPath -PathType Leaf)) {
        try {
            $idsData = Read-UGSMGameDayZJsonDataSafe -Path $idsPath
            foreach ($entry in @($idsData.IDs)) {
                if ($null -eq $entry) { continue }
                $id = [string]$entry.Id
                if ([string]::IsNullOrWhiteSpace($id) -or $seen.ContainsKey($id)) { continue }
                $seen[$id] = $true
                [void]$rows.Add([pscustomobject]@{
                    Id        = $id
                    GivenName = ''
                    Role      = ''
                    Name      = ''
                    Label     = ('{0} - Trader ID {0}' -f $id)
                })
            }
        }
        catch { }
    }

    return @($rows | Sort-Object { [int]($_.Id -replace '[^0-9-]', '') }, Id)
}

function Set-UGSMGameDayZTraderPlusCategoryAssignments {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory)][string]$PriceConfigPath,
        [Parameter(Mandatory)][string]$CategoryName,
        [Parameter()][string[]]$TraderIds = @()
    )

    $category = ([string]$CategoryName).Trim()
    if ([string]::IsNullOrWhiteSpace($category)) { throw 'Category name is empty.' }

    $idsPath = Get-UGSMGameDayZTraderPlusSiblingConfigPath -PriceConfigPath $PriceConfigPath -FileName 'TraderPlusIDsConfig.json'
    if ([string]::IsNullOrWhiteSpace($idsPath)) { throw 'TraderPlusIDsConfig.json path could not be resolved.' }

    if (Test-Path -LiteralPath $idsPath -PathType Leaf) {
        $idsData = Read-UGSMGameDayZJsonDataSafe -Path $idsPath
    }
    else {
        $idsData = [pscustomobject]@{ Version = '2.5'; IDs = @() }
    }

    if ($null -eq $idsData.IDs) {
        $idsData | Add-Member -NotePropertyName IDs -NotePropertyValue @() -Force
    }

    $entryList = New-Object System.Collections.ArrayList
    foreach ($entry in @($idsData.IDs)) {
        if ($null -ne $entry) { [void]$entryList.Add($entry) }
    }

    $wanted = @{}
    foreach ($id in @($TraderIds)) {
        $idText = ([string]$id).Trim()
        if (-not [string]::IsNullOrWhiteSpace($idText)) { $wanted[$idText] = $true }
    }

    $entryById = @{}
    foreach ($entry in @($entryList)) {
        $idText = ([string]$entry.Id).Trim()
        if ([string]::IsNullOrWhiteSpace($idText)) { continue }
        $entryById[$idText] = $entry

        $cats = New-Object System.Collections.ArrayList
        foreach ($cat in @($entry.Categories)) {
            $catText = ([string]$cat).Trim()
            if ([string]::IsNullOrWhiteSpace($catText)) { continue }
            if ($catText -ieq $category) { continue }
            if (-not ($cats -contains $catText)) { [void]$cats.Add($catText) }
        }
        $entry.Categories = @($cats)
        if ($null -eq $entry.LicencesRequired) { $entry | Add-Member -NotePropertyName LicencesRequired -NotePropertyValue @() -Force }
        if ($null -eq $entry.CurrenciesAccepted) { $entry | Add-Member -NotePropertyName CurrenciesAccepted -NotePropertyValue @() -Force }
    }

    foreach ($idText in @($wanted.Keys | Sort-Object)) {
        if (-not $entryById.ContainsKey($idText)) {
            $newEntry = [pscustomobject]@{
                Id                 = [int]$idText
                Categories         = @()
                LicencesRequired   = @()
                CurrenciesAccepted = @()
            }
            [void]$entryList.Add($newEntry)
            $entryById[$idText] = $newEntry
        }

        $entry = $entryById[$idText]
        $cats = New-Object System.Collections.ArrayList
        foreach ($cat in @($entry.Categories)) {
            $catText = ([string]$cat).Trim()
            if ([string]::IsNullOrWhiteSpace($catText)) { continue }
            if (-not ($cats -contains $catText)) { [void]$cats.Add($catText) }
        }
        if (-not ($cats -contains $category)) { [void]$cats.Add($category) }
        $entry.Categories = @($cats)
    }

    $idsData.IDs = @($entryList | Sort-Object { [int]([string]$_.Id -replace '[^0-9-]', '') }, Id)

    if ($PSCmdlet.ShouldProcess($idsPath, "save TraderPlus category assignment for '$category'")) {
        if (Test-Path -LiteralPath $idsPath -PathType Leaf) {
            try { [void](Backup-UGSMGameDayZFile -TargetPath $idsPath) } catch { }
        }
        Write-UGSMGameDayZJsonDataSafe -Path $idsPath -Data $idsData
    }

    return [pscustomobject]@{
        Path       = $idsPath
        Category   = $category
        TraderIds  = @($wanted.Keys | Sort-Object)
        TraderCount = [int]$wanted.Count
    }
}

function Add-UGSMGameDayZTraderPlusTraderId {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory)][string]$PriceConfigPath,
        [Parameter(Mandatory)][int]$TraderId,
        [string]$GivenName = '',
        [string]$Role = ''
    )

    $generalPath = Get-UGSMGameDayZTraderPlusSiblingConfigPath -PriceConfigPath $PriceConfigPath -FileName 'TraderPlusGeneralConfig.json'
    $idsPath = Get-UGSMGameDayZTraderPlusSiblingConfigPath -PriceConfigPath $PriceConfigPath -FileName 'TraderPlusIDsConfig.json'
    if ([string]::IsNullOrWhiteSpace($generalPath) -or [string]::IsNullOrWhiteSpace($idsPath)) { throw 'TraderPlus config folder could not be resolved.' }

    if (Test-Path -LiteralPath $generalPath -PathType Leaf) { $generalData = Read-UGSMGameDayZJsonDataSafe -Path $generalPath }
    else { $generalData = [pscustomobject]@{ Version = '2.5'; Traders = @(); TraderObjects = @() } }
    if ($null -eq $generalData.Traders) { $generalData | Add-Member -NotePropertyName Traders -NotePropertyValue @() -Force }

    $traders = New-Object System.Collections.ArrayList
    $foundTrader = $false
    foreach ($trader in @($generalData.Traders)) {
        if ($null -eq $trader) { continue }
        if ([string]$trader.Id -eq [string]$TraderId) {
            $foundTrader = $true
            if (-not [string]::IsNullOrWhiteSpace($GivenName)) { $trader.GivenName = [string]$GivenName }
            if (-not [string]::IsNullOrWhiteSpace($Role)) { $trader.Role = [string]$Role }
        }
        [void]$traders.Add($trader)
    }

    if (-not $foundTrader) {
        [void]$traders.Add([pscustomobject]@{
            Id          = [int]$TraderId
            Name        = 'TraderPlusSign'
            GivenName   = $(if ([string]::IsNullOrWhiteSpace($GivenName)) { ('Trader ' + $TraderId) } else { [string]$GivenName })
            Role        = $(if ([string]::IsNullOrWhiteSpace($Role)) { 'Custom Trader' } else { [string]$Role })
            Position    = @(0.0, 0.0, 0.0)
            Orientation = @(0.0, 0.0, 0.0)
            Clothes     = @()
        })
    }
    $generalData.Traders = @($traders | Sort-Object { [int]([string]$_.Id -replace '[^0-9-]', '') }, Id)

    if (Test-Path -LiteralPath $idsPath -PathType Leaf) { $idsData = Read-UGSMGameDayZJsonDataSafe -Path $idsPath }
    else { $idsData = [pscustomobject]@{ Version = '2.5'; IDs = @() } }
    if ($null -eq $idsData.IDs) { $idsData | Add-Member -NotePropertyName IDs -NotePropertyValue @() -Force }

    $entries = New-Object System.Collections.ArrayList
    $foundId = $false
    foreach ($entry in @($idsData.IDs)) {
        if ($null -eq $entry) { continue }
        if ([string]$entry.Id -eq [string]$TraderId) {
            $foundId = $true
            if ($null -eq $entry.Categories) { $entry | Add-Member -NotePropertyName Categories -NotePropertyValue @() -Force }
            if ($null -eq $entry.LicencesRequired) { $entry | Add-Member -NotePropertyName LicencesRequired -NotePropertyValue @() -Force }
            if ($null -eq $entry.CurrenciesAccepted) { $entry | Add-Member -NotePropertyName CurrenciesAccepted -NotePropertyValue @() -Force }
        }
        [void]$entries.Add($entry)
    }
    if (-not $foundId) {
        [void]$entries.Add([pscustomobject]@{
            Id                 = [int]$TraderId
            Categories         = @()
            LicencesRequired   = @()
            CurrenciesAccepted = @()
        })
    }
    $idsData.IDs = @($entries | Sort-Object { [int]([string]$_.Id -replace '[^0-9-]', '') }, Id)

    if ($PSCmdlet.ShouldProcess($PriceConfigPath, "add/update TraderPlus trader ID $TraderId")) {
        if (Test-Path -LiteralPath $generalPath -PathType Leaf) { try { [void](Backup-UGSMGameDayZFile -TargetPath $generalPath) } catch { } }
        if (Test-Path -LiteralPath $idsPath -PathType Leaf) { try { [void](Backup-UGSMGameDayZFile -TargetPath $idsPath) } catch { } }
        Write-UGSMGameDayZJsonDataSafe -Path $generalPath -Data $generalData
        Write-UGSMGameDayZJsonDataSafe -Path $idsPath -Data $idsData
    }

    return [pscustomobject]@{ TraderId = [int]$TraderId; GeneralPath = $generalPath; IdsPath = $idsPath }
}

function Show-UGSMGameDayZTraderPlusTraderAssignmentDialog {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$CategoryName,
        [Parameter(Mandatory)][object[]]$TraderRows,
        [Parameter()][string[]]$SelectedTraderIds = @()
    )

    $form = New-Object System.Windows.Forms.Form
    $form.Text = 'Assign TraderPlus Category'
    $form.StartPosition = 'CenterParent'
    $form.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::FixedDialog
    $form.MinimizeBox = $false
    $form.MaximizeBox = $false
    $form.ShowInTaskbar = $false
    $form.ClientSize = New-Object System.Drawing.Size(520, 430)

    $lbl = New-Object System.Windows.Forms.Label
    $lbl.Location = New-Object System.Drawing.Point(12, 12)
    $lbl.Size = New-Object System.Drawing.Size(490, 36)
    $lbl.Text = "Assign category '$CategoryName' to trader IDs:"
    [void]$form.Controls.Add($lbl)

    $list = New-Object System.Windows.Forms.CheckedListBox
    $list.Location = New-Object System.Drawing.Point(12, 54)
    $list.Size = New-Object System.Drawing.Size(490, 310)
    $list.CheckOnClick = $true
    $list.BorderStyle = 'FixedSingle'
    $selectedLookup = @{}
    foreach ($id in @($SelectedTraderIds)) {
        if (-not [string]::IsNullOrWhiteSpace([string]$id)) { $selectedLookup[[string]$id] = $true }
    }

    foreach ($trader in @($TraderRows)) {
        if ($null -eq $trader) { continue }
        $display = [string]$trader.Label
        if ([string]::IsNullOrWhiteSpace($display)) { $display = ('{0} - Trader ID {0}' -f $trader.Id) }
        $item = [pscustomobject]@{ Id = [string]$trader.Id; Label = $display }
        $index = $list.Items.Add($item)
        $list.DisplayMember = 'Label'
        if ($selectedLookup.ContainsKey([string]$trader.Id)) { $list.SetItemChecked($index, $true) }
    }
    [void]$form.Controls.Add($list)

    $ok = New-Object System.Windows.Forms.Button
    $ok.Text = 'Save'
    $ok.DialogResult = [System.Windows.Forms.DialogResult]::OK
    $ok.Location = New-Object System.Drawing.Point(330, 382)
    $ok.Size = New-Object System.Drawing.Size(80, 28)
    [void]$form.Controls.Add($ok)

    $cancel = New-Object System.Windows.Forms.Button
    $cancel.Text = 'Cancel'
    $cancel.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
    $cancel.Location = New-Object System.Drawing.Point(422, 382)
    $cancel.Size = New-Object System.Drawing.Size(80, 28)
    [void]$form.Controls.Add($cancel)

    $form.AcceptButton = $ok
    $form.CancelButton = $cancel

    try {
        if ($form.ShowDialog() -ne [System.Windows.Forms.DialogResult]::OK) { return $null }
        $ids = New-Object System.Collections.ArrayList
        foreach ($item in @($list.CheckedItems)) {
            if ($null -ne $item -and -not [string]::IsNullOrWhiteSpace([string]$item.Id)) { [void]$ids.Add([string]$item.Id) }
        }
        return @($ids)
    }
    finally {
        $form.Dispose()
    }
}

function Get-UGSMGameDayZTraderPlusCategoryAssignmentMap {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$PriceConfigPath
    )

    $map = New-Object 'System.Collections.Generic.Dictionary[string,object]' ([System.StringComparer]::OrdinalIgnoreCase)
    if ([string]::IsNullOrWhiteSpace($PriceConfigPath)) { return $map }

    $configRoot = Split-Path -Parent $PriceConfigPath
    if ([string]::IsNullOrWhiteSpace($configRoot)) { return $map }

    $idsPath = Join-Path $configRoot 'TraderPlusIDsConfig.json'
    if (-not (Test-Path -LiteralPath $idsPath -PathType Leaf)) { return $map }

    try {
        $idsData = Read-UGSMGameDayZJsonDataSafe -Path $idsPath
        foreach ($entry in @($idsData.IDs)) {
            if ($null -eq $entry) { continue }
            $traderId = [string]$entry.Id
            if ([string]::IsNullOrWhiteSpace($traderId)) { continue }

            foreach ($categoryName in @($entry.Categories)) {
                $name = ([string]$categoryName).Trim()
                if ([string]::IsNullOrWhiteSpace($name)) { continue }
                if (-not $map.ContainsKey($name)) {
                    $map[$name] = New-Object System.Collections.ArrayList
                }
                if (-not ($map[$name] -contains $traderId)) {
                    [void]$map[$name].Add($traderId)
                }
            }
        }
    }
    catch {
    }

    return $map
}

function Show-UGSMGameDayZTraderPlusTextPrompt {
    [CmdletBinding()]
    param(
        [string]$Title = 'UGSM',
        [string]$Prompt = 'Enter value:',
        [string]$DefaultValue = ''
    )

    $form = New-Object System.Windows.Forms.Form
    $form.Text = $Title
    $form.StartPosition = 'CenterParent'
    $form.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::FixedDialog
    $form.MinimizeBox = $false
    $form.MaximizeBox = $false
    $form.ShowInTaskbar = $false
    $form.ClientSize = New-Object System.Drawing.Size(430, 130)

    $label = New-Object System.Windows.Forms.Label
    $label.Location = New-Object System.Drawing.Point(12, 12)
    $label.Size = New-Object System.Drawing.Size(406, 20)
    $label.Text = $Prompt
    [void]$form.Controls.Add($label)

    $textBox = New-Object System.Windows.Forms.TextBox
    $textBox.Location = New-Object System.Drawing.Point(12, 40)
    $textBox.Size = New-Object System.Drawing.Size(406, 24)
    $textBox.Text = $DefaultValue
    [void]$form.Controls.Add($textBox)

    $ok = New-Object System.Windows.Forms.Button
    $ok.Text = 'OK'
    $ok.DialogResult = [System.Windows.Forms.DialogResult]::OK
    $ok.Location = New-Object System.Drawing.Point(250, 88)
    $ok.Size = New-Object System.Drawing.Size(80, 28)
    [void]$form.Controls.Add($ok)

    $cancel = New-Object System.Windows.Forms.Button
    $cancel.Text = 'Cancel'
    $cancel.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
    $cancel.Location = New-Object System.Drawing.Point(338, 88)
    $cancel.Size = New-Object System.Drawing.Size(80, 28)
    [void]$form.Controls.Add($cancel)

    $form.AcceptButton = $ok
    $form.CancelButton = $cancel

    try {
        $result = $form.ShowDialog()
        if ($result -eq [System.Windows.Forms.DialogResult]::OK) {
            return [string]$textBox.Text
        }
        return $null
    }
    finally {
        $form.Dispose()
    }
}


function Show-UGSMGameDayZTraderPlusCategoryPicker {
    [CmdletBinding()]
    param(
        [string]$Title = 'Move TraderPlus Items',
        [string]$Prompt = 'Move selected item(s) to category:',
        [string[]]$Categories = @(),
        [string]$DefaultValue = ''
    )

    $form = New-Object System.Windows.Forms.Form
    $form.Text = $Title
    $form.StartPosition = 'CenterParent'
    $form.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::FixedDialog
    $form.MinimizeBox = $false
    $form.MaximizeBox = $false
    $form.ShowInTaskbar = $false
    $form.ClientSize = New-Object System.Drawing.Size(430, 130)

    $label = New-Object System.Windows.Forms.Label
    $label.Location = New-Object System.Drawing.Point(12, 12)
    $label.Size = New-Object System.Drawing.Size(406, 20)
    $label.Text = $Prompt
    [void]$form.Controls.Add($label)

    $combo = New-Object System.Windows.Forms.ComboBox
    $combo.Location = New-Object System.Drawing.Point(12, 40)
    $combo.Size = New-Object System.Drawing.Size(406, 24)
    $combo.DropDownStyle = [System.Windows.Forms.ComboBoxStyle]::DropDown

    $seen = @{}
    foreach ($cat in @($Categories | Sort-Object)) {
        $name = ([string]$cat).Trim()
        if ([string]::IsNullOrWhiteSpace($name)) { continue }
        if ($name -eq 'All Categories') { continue }
        $key = $name.ToLowerInvariant()
        if ($seen.ContainsKey($key)) { continue }
        $seen[$key] = $true
        [void]$combo.Items.Add($name)
    }

    if (-not [string]::IsNullOrWhiteSpace($DefaultValue) -and $DefaultValue -ne 'All Categories') {
        $combo.Text = $DefaultValue
    }
    elseif ($combo.Items.Count -gt 0) {
        $combo.SelectedIndex = 0
    }
    [void]$form.Controls.Add($combo)

    $ok = New-Object System.Windows.Forms.Button
    $ok.Text = 'OK'
    $ok.DialogResult = [System.Windows.Forms.DialogResult]::OK
    $ok.Location = New-Object System.Drawing.Point(250, 88)
    $ok.Size = New-Object System.Drawing.Size(80, 28)
    [void]$form.Controls.Add($ok)

    $cancel = New-Object System.Windows.Forms.Button
    $cancel.Text = 'Cancel'
    $cancel.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
    $cancel.Location = New-Object System.Drawing.Point(338, 88)
    $cancel.Size = New-Object System.Drawing.Size(80, 28)
    [void]$form.Controls.Add($cancel)

    $form.AcceptButton = $ok
    $form.CancelButton = $cancel

    try {
        $result = $form.ShowDialog()
        if ($result -eq [System.Windows.Forms.DialogResult]::OK) {
            return ([string]$combo.Text).Trim()
        }
        return $null
    }
    finally {
        $form.Dispose()
    }
}

function New-DayZTraderPlusContent {
    param(
        [Parameter(Mandatory)][System.Windows.Forms.Control]$Parent,
        [Parameter()][object]$Instance,
        [Parameter()][object]$Theme,
        [Parameter()][object]$StatusLabel
    )

    try {
        $tpInstance = if ($PSBoundParameters.ContainsKey('Instance') -and $null -ne $Instance) { $Instance } else { $editorInstance }
        if ($null -eq $tpInstance) { throw 'Editor instance is not available for TraderPlus.' }

        $tpStatusLabel = if ($PSBoundParameters.ContainsKey('StatusLabel')) { $StatusLabel } else { $editorStatusLabel }
        $tpTheme = if ($PSBoundParameters.ContainsKey('Theme') -and $null -ne $Theme) { $Theme } else { $script:Theme }
        if ($null -eq $tpTheme) { $tpTheme = $Theme }
        $tpState = [ordered]@{
            Files         = @()
            CurrentPath   = ''
            PriceRows     = @()
            PriceFilePath = ''
            PriceSearch   = ''
            PriceCategory = 'All Categories'
            PriceCustomCategories = @()
            CategoryAssignments = @{}
            TraderRows = @()
            IdRows = @()
            InsuranceRows = @()
            InsuranceAuthorizedIds = @()
            GeneralSettings = @{}
            GeneralLicences = @()
            GeneralCurrencies = @()
            GeneralTraders = @()
            GeneralObjects = @()
        }

        $rootPanel = New-Object System.Windows.Forms.Panel
        $rootPanel.Dock = 'Fill'
        $rootPanel.Padding = New-Object System.Windows.Forms.Padding(10, 8, 10, 10)
        $rootPanel.BackColor = New-UGSMColor '#0B121D'
        [void]$Parent.Controls.Add($rootPanel)

        $desc = New-UGSMLabel -Text 'Manage TraderPlus config without hand-editing fragile JSON. Use Files for raw config and Prices for the parsed price table.' -X 0 -Y 0 -Width 1500 -Height 18 -FontSize 8.5 -Color $tpTheme.Muted
        [void]$rootPanel.Controls.Add($desc)

        $topBar = New-Object System.Windows.Forms.Panel
        $topBar.Location = New-Object System.Drawing.Point(0, 26)
        $topBar.Height = 58
        $topBar.Anchor = 'Top,Left,Right'
        $topBar.Width = [Math]::Max(900, $rootPanel.ClientSize.Width)
        $topBar.BackColor = New-UGSMColor '#0B121D'
        [void]$rootPanel.Controls.Add($topBar)

        $lblFile = New-UGSMLabel -Text 'TraderPlus config:' -X 0 -Y 0 -Width 120 -Height 18 -FontSize 8.5 -Color $tpTheme.Text
        [void]$topBar.Controls.Add($lblFile)

        $cmbFile = New-Object System.Windows.Forms.ComboBox
        $cmbFile.Location = New-Object System.Drawing.Point(0, 22)
        $cmbFile.Size = New-Object System.Drawing.Size(470, 24)
        $cmbFile.DropDownStyle = [System.Windows.Forms.ComboBoxStyle]::DropDownList
        $cmbFile.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
        $cmbFile.BackColor = [System.Drawing.Color]::White
        $cmbFile.ForeColor = [System.Drawing.Color]::Black
        $cmbFile.DisplayMember = 'RelativePath'
        $cmbFile.ValueMember = 'FullName'
        [void]$topBar.Controls.Add($cmbFile)

        $btnRefresh = New-UGSMButton -Text 'Refresh Files' -X 485 -Y 20 -Width 105 -Height 28 -BackColor '#253341'
        [void]$topBar.Controls.Add($btnRefresh)

        $lblPath = New-UGSMLabel -Text '' -X 0 -Y 88 -Width 1600 -Height 18 -FontSize 8 -Color $tpTheme.Muted
        [void]$rootPanel.Controls.Add($lblPath)

        $tabTrader = New-Object System.Windows.Forms.TabControl
        $tabTrader.Location = New-Object System.Drawing.Point(0, 112)
        $tabTrader.Anchor = 'Top,Bottom,Left,Right'
        $tabTrader.Size = New-Object System.Drawing.Size(
            [Math]::Max(900, $rootPanel.ClientSize.Width),
            [Math]::Max(420, $rootPanel.ClientSize.Height - 120)
        )
        [void]$rootPanel.Controls.Add($tabTrader)
           
        $pricesTab = New-Object System.Windows.Forms.TabPage
        $pricesTab.Text = 'Prices'
        $pricesTab.BackColor = New-UGSMColor '#0B121D'
        [void]$tabTrader.TabPages.Add($pricesTab)

        $filesTab = New-Object System.Windows.Forms.TabPage
        $filesTab.Text = 'Files'
        $filesTab.BackColor = New-UGSMColor '#0B121D'
        [void]$tabTrader.TabPages.Add($filesTab)

        $idsTab = New-Object System.Windows.Forms.TabPage
        $idsTab.Text = 'IDs'
        $idsTab.BackColor = New-UGSMColor '#0B121D'
        [void]$tabTrader.TabPages.Add($idsTab)

        $insuranceTab = New-Object System.Windows.Forms.TabPage
        $insuranceTab.Text = 'Insurance'
        $insuranceTab.BackColor = New-UGSMColor '#0B121D'
        [void]$tabTrader.TabPages.Add($insuranceTab)

        $generalTab = New-Object System.Windows.Forms.TabPage
        $generalTab.Text = 'General'
        $generalTab.BackColor = New-UGSMColor '#0B121D'
        [void]$tabTrader.TabPages.Add($generalTab)

        $helpTab = New-Object System.Windows.Forms.TabPage
        $helpTab.Text = 'Help'
        $helpTab.BackColor = New-UGSMColor '#0B121D'
        [void]$tabTrader.TabPages.Add($helpTab)


        $generalPanel = New-Object System.Windows.Forms.Panel
        $generalPanel.Dock = 'Fill'
        $generalPanel.Padding = New-Object System.Windows.Forms.Padding(8)
        $generalPanel.BackColor = New-UGSMColor '#0B121D'
        [void]$generalTab.Controls.Add($generalPanel)

        $generalBar = New-Object System.Windows.Forms.Panel
        $generalBar.Dock = 'Top'
        $generalBar.Height = 34
        $generalBar.BackColor = New-UGSMColor '#0B121D'
        [void]$generalPanel.Controls.Add($generalBar)

        $btnLoadGeneral = New-UGSMButton -Text 'Load General' -X 0 -Y 2 -Width 110 -Height 28 -BackColor '#253341'
        $btnSaveGeneral = New-UGSMButton -Text 'Save General' -X 120 -Y 2 -Width 110 -Height 28 -BackColor $tpTheme.AccentBlue
        if ($btnLoadGeneral) { [void]$generalBar.Controls.Add($btnLoadGeneral) }
        if ($btnSaveGeneral) { [void]$generalBar.Controls.Add($btnSaveGeneral) }

        $generalSettingsPanel = New-Object System.Windows.Forms.Panel
        $generalSettingsPanel.Dock = 'Top'
        $generalSettingsPanel.Height = 170
        $generalSettingsPanel.BackColor = New-UGSMColor '#0B121D'
        [void]$generalPanel.Controls.Add($generalSettingsPanel)

        $generalSections = New-Object System.Windows.Forms.TabControl
        $generalSections.Location = New-Object System.Drawing.Point(8, 240)
        $generalSections.Anchor = 'Top,Bottom,Left,Right'
        $generalSections.Size = New-Object System.Drawing.Size([Math]::Max(900, $generalPanel.ClientSize.Width - 16), [Math]::Max(220, $generalPanel.ClientSize.Height - 250))
        $generalSections.Appearance = 'Normal'
        [void]$generalPanel.Controls.Add($generalSections)

        $generalCurrenciesTab = New-Object System.Windows.Forms.TabPage
        $generalCurrenciesTab.Text = 'Currencies'
        $generalCurrenciesTab.BackColor = New-UGSMColor '#0B121D'
        [void]$generalSections.TabPages.Add($generalCurrenciesTab)

        $generalTradersTab = New-Object System.Windows.Forms.TabPage
        $generalTradersTab.Text = 'Traders'
        $generalTradersTab.BackColor = New-UGSMColor '#0B121D'
        [void]$generalSections.TabPages.Add($generalTradersTab)

        $generalObjectsTab = New-Object System.Windows.Forms.TabPage
        $generalObjectsTab.Text = 'Trader Objects'
        $generalObjectsTab.BackColor = New-UGSMColor '#0B121D'
        [void]$generalSections.TabPages.Add($generalObjectsTab)

        $generalTopY = 0
        $generalCheckboxSpecs = @(
            @{ Name = 'ConvertTraderConfigToTraderPlus'; Text = 'Convert Trader Config'; X = 0; Y = 0; W = 200 },
            @{ Name = 'ConvertTraderConfigToTraderPlusWithStockBasedOnCE'; Text = 'Convert Trader Config With CE Stock'; X = 210; Y = 0; W = 260 },
            @{ Name = 'UseGarageToTradeCar'; Text = 'Use Garage To Trade Car'; X = 480; Y = 0; W = 210 },
            @{ Name = 'DisableHeightFailSafeForReceiptDeployment'; Text = 'Disable Height Failsafe'; X = 700; Y = 0; W = 220 },
            @{ Name = 'HideInsuranceBtn'; Text = 'Hide Insurance Button'; X = 0; Y = 26; W = 180 },
            @{ Name = 'HideGarageBtn'; Text = 'Hide Garage Button'; X = 190; Y = 26; W = 170 },
            @{ Name = 'HideLicenceBtn'; Text = 'Hide Licence Button'; X = 370; Y = 26; W = 170 },
            @{ Name = 'EnableShowAllPrices'; Text = 'Enable Show All Prices'; X = 550; Y = 26; W = 190 },
            @{ Name = 'EnableShowAllCheckBox'; Text = 'Enable Show All Checkbox'; X = 750; Y = 26; W = 210 },
            @{ Name = 'IsReceiptTraderOnly'; Text = 'Receipt Trader Only'; X = 0; Y = 52; W = 160 },
            @{ Name = 'IsReceiptSaveLock'; Text = 'Receipt Save Lock'; X = 170; Y = 52; W = 150 },
            @{ Name = 'IsReceiptSaveAttachment'; Text = 'Receipt Save Attachment'; X = 330; Y = 52; W = 180 },
            @{ Name = 'IsReceiptSaveCargo'; Text = 'Receipt Save Cargo'; X = 520; Y = 52; W = 160 },
            @{ Name = 'StoreOnlyToPristineState'; Text = 'Store Only To Pristine State'; X = 690; Y = 52; W = 220 }
        )
        $generalCheckboxes = @{}
        foreach ($spec in $generalCheckboxSpecs) {
            $cb = New-Object System.Windows.Forms.CheckBox
            $cb.Text = [string]$spec.Text
            $cb.Location = New-Object System.Drawing.Point([int]$spec.X, [int]$spec.Y)
            $cb.Size = New-Object System.Drawing.Size([int]$spec.W, 22)
            $cb.ForeColor = [System.Drawing.Color]::White
            $cb.BackColor = [System.Drawing.Color]::Transparent
            [void]$generalSettingsPanel.Controls.Add($cb)
            $generalCheckboxes[[string]$spec.Name] = $cb
        }

        $lblGeneralLicenceKeyword = New-UGSMLabel -Text 'Licence Keyword:' -X 0 -Y 84 -Width 100 -Height 18 -FontSize 8.5 -Color $tpTheme.Muted
        [void]$generalSettingsPanel.Controls.Add($lblGeneralLicenceKeyword)
        $txtGeneralLicenceKeyword = New-Object System.Windows.Forms.TextBox
        $txtGeneralLicenceKeyword.Location = New-Object System.Drawing.Point(104, 82)
        $txtGeneralLicenceKeyword.Size = New-Object System.Drawing.Size(160, 24)
        [void]$generalSettingsPanel.Controls.Add($txtGeneralLicenceKeyword)

        $lblGeneralLockPickChance = New-UGSMLabel -Text 'LockPickChance:' -X 280 -Y 84 -Width 100 -Height 18 -FontSize 8.5 -Color $tpTheme.Muted
        [void]$generalSettingsPanel.Controls.Add($lblGeneralLockPickChance)
        $txtGeneralLockPickChance = New-Object System.Windows.Forms.TextBox
        $txtGeneralLockPickChance.Location = New-Object System.Drawing.Point(384, 82)
        $txtGeneralLockPickChance.Size = New-Object System.Drawing.Size(80, 24)
        [void]$generalSettingsPanel.Controls.Add($txtGeneralLockPickChance)

        $lblGeneralLicences = New-UGSMLabel -Text 'Licences (; separated):' -X 480 -Y 84 -Width 140 -Height 18 -FontSize 8.5 -Color $tpTheme.Muted
        [void]$generalSettingsPanel.Controls.Add($lblGeneralLicences)
        $txtGeneralLicences = New-Object System.Windows.Forms.TextBox
        $txtGeneralLicences.Location = New-Object System.Drawing.Point(624, 82)
        $txtGeneralLicences.Size = New-Object System.Drawing.Size(320, 24)
        [void]$generalSettingsPanel.Controls.Add($txtGeneralLicences)

        $lblAcceptedStatesTitle = New-UGSMLabel -Text 'Accepted States' -X 0 -Y 114 -Width 120 -Height 18 -FontSize 9 -Color $tpTheme.Text
        [void]$generalSettingsPanel.Controls.Add($lblAcceptedStatesTitle)

        $chkAcceptWorn = New-Object System.Windows.Forms.CheckBox
        $chkAcceptWorn.Text = 'Accept Worn'
        $chkAcceptWorn.Location = New-Object System.Drawing.Point(0, 136)
        $chkAcceptWorn.Size = New-Object System.Drawing.Size(110,22)
        $chkAcceptWorn.ForeColor = [System.Drawing.Color]::White
        [void]$generalSettingsPanel.Controls.Add($chkAcceptWorn)

        $chkAcceptDamaged = New-Object System.Windows.Forms.CheckBox
        $chkAcceptDamaged.Text = 'Accept Damaged'
        $chkAcceptDamaged.Location = New-Object System.Drawing.Point(120, 136)
        $chkAcceptDamaged.Size = New-Object System.Drawing.Size(130,22)
        $chkAcceptDamaged.ForeColor = [System.Drawing.Color]::White
        [void]$generalSettingsPanel.Controls.Add($chkAcceptDamaged)

        $chkAcceptBadlyDamaged = New-Object System.Windows.Forms.CheckBox
        $chkAcceptBadlyDamaged.Text = 'Accept Badly Damaged'
        $chkAcceptBadlyDamaged.Location = New-Object System.Drawing.Point(260, 136)
        $chkAcceptBadlyDamaged.Size = New-Object System.Drawing.Size(170,22)
        $chkAcceptBadlyDamaged.ForeColor = [System.Drawing.Color]::White
        [void]$generalSettingsPanel.Controls.Add($chkAcceptBadlyDamaged)

        $lblCoefWorn = New-UGSMLabel -Text 'Coef Worn:' -X 450 -Y 138 -Width 70 -Height 18 -FontSize 8.5 -Color $tpTheme.Muted
        [void]$generalSettingsPanel.Controls.Add($lblCoefWorn)
        $txtCoefWorn = New-Object System.Windows.Forms.TextBox
        $txtCoefWorn.Location = New-Object System.Drawing.Point(520, 136)
        $txtCoefWorn.Size = New-Object System.Drawing.Size(60,24)
        [void]$generalSettingsPanel.Controls.Add($txtCoefWorn)
        $lblCoefDamaged = New-UGSMLabel -Text 'Coef Damaged:' -X 590 -Y 138 -Width 88 -Height 18 -FontSize 8.5 -Color $tpTheme.Muted
        [void]$generalSettingsPanel.Controls.Add($lblCoefDamaged)
        $txtCoefDamaged = New-Object System.Windows.Forms.TextBox
        $txtCoefDamaged.Location = New-Object System.Drawing.Point(680, 136)
        $txtCoefDamaged.Size = New-Object System.Drawing.Size(60,24)
        [void]$generalSettingsPanel.Controls.Add($txtCoefDamaged)
        $lblCoefBadlyDamaged = New-UGSMLabel -Text 'Coef Badly Damaged:' -X 750 -Y 138 -Width 120 -Height 18 -FontSize 8.5 -Color $tpTheme.Muted
        [void]$generalSettingsPanel.Controls.Add($lblCoefBadlyDamaged)
        $txtCoefBadlyDamaged = New-Object System.Windows.Forms.TextBox
        $txtCoefBadlyDamaged.Location = New-Object System.Drawing.Point(874, 136)
        $txtCoefBadlyDamaged.Size = New-Object System.Drawing.Size(60,24)
        [void]$generalSettingsPanel.Controls.Add($txtCoefBadlyDamaged)

        $currenciesPanel = New-Object System.Windows.Forms.Panel
        $currenciesPanel.Dock = 'Fill'
        $currenciesPanel.Padding = New-Object System.Windows.Forms.Padding(6)
        [void]$generalCurrenciesTab.Controls.Add($currenciesPanel)
        $currenciesBar = New-Object System.Windows.Forms.Panel
        $currenciesBar.Dock = 'Top'
        $currenciesBar.Height = 36
        $btnAddCurrencyRow = New-UGSMButton -Text 'Add Row' -X 0 -Y 2 -Width 90 -Height 26 -BackColor '#253341'
        $btnRemoveCurrencyRow = New-UGSMButton -Text 'Remove Selected' -X 100 -Y 2 -Width 130 -Height 26 -BackColor '#B91C1C'
        [void]$currenciesBar.Controls.Add($btnAddCurrencyRow)
        [void]$currenciesBar.Controls.Add($btnRemoveCurrencyRow)
        $gridGeneralCurrencies = New-Object System.Windows.Forms.DataGridView
        $gridGeneralCurrencies.Dock = 'Fill'
        $gridGeneralCurrencies.AllowUserToAddRows = $false
        $gridGeneralCurrencies.RowHeadersVisible = $false
        $gridGeneralCurrencies.SelectionMode = 'FullRowSelect'
        $gridGeneralCurrencies.MultiSelect = $true
        $gridGeneralCurrencies.BackgroundColor = [System.Drawing.Color]::FromArgb(16,20,27)
        $gridGeneralCurrencies.GridColor = [System.Drawing.Color]::FromArgb(45,58,77)
        $gridGeneralCurrencies.BorderStyle = 'FixedSingle'
        $gridGeneralCurrencies.AllowUserToDeleteRows = $false
        $gridGeneralCurrencies.AllowUserToResizeRows = $false
        $gridGeneralCurrencies.EnableHeadersVisualStyles = $false
        $gridGeneralCurrencies.ColumnHeadersDefaultCellStyle.BackColor = [System.Drawing.Color]::FromArgb(35,50,75)
        $gridGeneralCurrencies.ColumnHeadersDefaultCellStyle.ForeColor = [System.Drawing.Color]::White
        $gridGeneralCurrencies.DefaultCellStyle.BackColor = [System.Drawing.Color]::FromArgb(20,28,40)
        $gridGeneralCurrencies.DefaultCellStyle.ForeColor = [System.Drawing.Color]::White
        $gridGeneralCurrencies.DefaultCellStyle.SelectionBackColor = [System.Drawing.Color]::FromArgb(59,130,246)
        $gridGeneralCurrencies.DefaultCellStyle.SelectionForeColor = [System.Drawing.Color]::White
        $gridGeneralCurrencies.AutoSizeColumnsMode = 'Fill'
        [void]$gridGeneralCurrencies.Columns.Add('ClassName','ClassName')
        [void]$gridGeneralCurrencies.Columns.Add('Value','Value')
        $gridGeneralCurrencies.Columns['ClassName'].FillWeight = 70
        $gridGeneralCurrencies.Columns['Value'].FillWeight = 30
        [void]$currenciesPanel.Controls.Add($gridGeneralCurrencies)
        [void]$currenciesPanel.Controls.Add($currenciesBar)

        $tradersPanel = New-Object System.Windows.Forms.Panel
        $tradersPanel.Dock = 'Fill'
        $tradersPanel.Padding = New-Object System.Windows.Forms.Padding(6)
        [void]$generalTradersTab.Controls.Add($tradersPanel)
        $tradersBar = New-Object System.Windows.Forms.Panel
        $tradersBar.Dock = 'Top'
        $tradersBar.Height = 62

        $btnAddTraderRow = New-UGSMButton -Text 'Add Row' -X 0 -Y 2 -Width 90 -Height 26 -BackColor '#253341'
        $btnRemoveTraderRow = New-UGSMButton -Text 'Remove Selected' -X 100 -Y 2 -Width 130 -Height 26 -BackColor '#B91C1C'
        [void]$tradersBar.Controls.Add($btnAddTraderRow)
        [void]$tradersBar.Controls.Add($btnRemoveTraderRow)
        $lblTraderItemSearch = New-UGSMLabel -Text 'Item:' -X 250 -Y 7 -Width 36 -Height 18 -FontSize 8.5 -Color $tpTheme.Muted
        [void]$tradersBar.Controls.Add($lblTraderItemSearch)
        $txtTraderItemSearch = New-Object System.Windows.Forms.TextBox
        $txtTraderItemSearch.Location = New-Object System.Drawing.Point(286, 4)
        $txtTraderItemSearch.Size = New-Object System.Drawing.Size(170, 24)
        [void]$tradersBar.Controls.Add($txtTraderItemSearch)
        $cmbTraderItemPicker = New-Object System.Windows.Forms.ComboBox
        $cmbTraderItemPicker.Location = New-Object System.Drawing.Point(466, 4)
        $cmbTraderItemPicker.Size = New-Object System.Drawing.Size(260, 24)
        $cmbTraderItemPicker.DropDownStyle = 'DropDownList'
        $cmbTraderItemPicker.BackColor = [System.Drawing.Color]::FromArgb(20,28,40)
        $cmbTraderItemPicker.ForeColor = [System.Drawing.Color]::White
        [void]$tradersBar.Controls.Add($cmbTraderItemPicker)
        $btnAddTraderItem = New-UGSMButton -Text 'Add To Selected Trader' -X 736 -Y 2 -Width 170 -Height 28 -BackColor '#253341'
        [void]$tradersBar.Controls.Add($btnAddTraderItem)
        $lblTraderItemHint = New-UGSMLabel -Text 'Adds selected types.xml item to the selected trader Clothes field.' -X 250 -Y 35 -Width 520 -Height 18 -FontSize 8.5 -Color $tpTheme.Muted
        [void]$tradersBar.Controls.Add($lblTraderItemHint)
        $gridGeneralTraders = New-Object System.Windows.Forms.DataGridView
        $gridGeneralTraders.Dock = 'Fill'
        $gridGeneralTraders.AllowUserToAddRows = $false
        $gridGeneralTraders.RowHeadersVisible = $false
        $gridGeneralTraders.SelectionMode = 'FullRowSelect'
        $gridGeneralTraders.MultiSelect = $true
        $gridGeneralTraders.BackgroundColor = [System.Drawing.Color]::FromArgb(16,20,27)
        $gridGeneralTraders.GridColor = [System.Drawing.Color]::FromArgb(45,58,77)
        $gridGeneralTraders.BorderStyle = 'FixedSingle'
        $gridGeneralTraders.AllowUserToDeleteRows = $false
        $gridGeneralTraders.AllowUserToResizeRows = $false
        $gridGeneralTraders.EnableHeadersVisualStyles = $false
        $gridGeneralTraders.ColumnHeadersDefaultCellStyle.BackColor = [System.Drawing.Color]::FromArgb(35,50,75)
        $gridGeneralTraders.ColumnHeadersDefaultCellStyle.ForeColor = [System.Drawing.Color]::White
        $gridGeneralTraders.DefaultCellStyle.BackColor = [System.Drawing.Color]::FromArgb(20,28,40)
        $gridGeneralTraders.DefaultCellStyle.ForeColor = [System.Drawing.Color]::White
        $gridGeneralTraders.DefaultCellStyle.SelectionBackColor = [System.Drawing.Color]::FromArgb(59,130,246)
        $gridGeneralTraders.DefaultCellStyle.SelectionForeColor = [System.Drawing.Color]::White
        $gridGeneralTraders.AutoSizeColumnsMode = 'None'
        $traderNameColumn = New-Object System.Windows.Forms.DataGridViewComboBoxColumn
        $traderNameColumn.Name = 'Name'
        $traderNameColumn.HeaderText = 'Name'
        $traderNameColumn.Width = 170
        $traderNameColumn.FlatStyle = 'Flat'
        $traderNameColumn.DisplayStyle = 'ComboBox'
        $traderClassNames = New-Object System.Collections.ArrayList
        foreach ($n in @(Get-UGSMGameDayZTraderPlusDefaultTraderClassNames)) { if (-not ($traderClassNames -contains [string]$n)) { [void]$traderClassNames.Add([string]$n) } }
        foreach ($n in @($traderClassNames)) { [void]$traderNameColumn.Items.Add([string]$n) }
        [void]$gridGeneralTraders.Columns.Add('Id','Id')
        [void]$gridGeneralTraders.Columns.Add($traderNameColumn)
        [void]$gridGeneralTraders.Columns.Add('GivenName','GivenName')
        [void]$gridGeneralTraders.Columns.Add('Role','Role')
        [void]$gridGeneralTraders.Columns.Add('Position','Position x;y;z')
        [void]$gridGeneralTraders.Columns.Add('Orientation','Orientation x;y;z')
        [void]$gridGeneralTraders.Columns.Add('Clothes','Clothes (; separated)')
        $gridGeneralTraders.Columns['Id'].Width = 60
        $gridGeneralTraders.Columns['GivenName'].Width = 120
        $gridGeneralTraders.Columns['Role'].Width = 150
        $gridGeneralTraders.Columns['Position'].Width = 350
        $gridGeneralTraders.Columns['Orientation'].Width = 170
        $gridGeneralTraders.Columns['Clothes'].Width = 650
        [void]$tradersPanel.Controls.Add($gridGeneralTraders)
                [void]$tradersPanel.Controls.Add($tradersBar)

        $objectsPanel = New-Object System.Windows.Forms.Panel
        $objectsPanel.Dock = 'Fill'
        $objectsPanel.Padding = New-Object System.Windows.Forms.Padding(6)
        [void]$generalObjectsTab.Controls.Add($objectsPanel)
        $objectsBar = New-Object System.Windows.Forms.Panel
        $objectsBar.Dock = 'Top'
        $objectsBar.Height = 32
        
        $btnAddObjectRow = New-UGSMButton -Text 'Add Row' -X 0 -Y 2 -Width 90 -Height 26 -BackColor '#253341'
        $btnRemoveObjectRow = New-UGSMButton -Text 'Remove Selected' -X 100 -Y 2 -Width 130 -Height 26 -BackColor '#B91C1C'
        [void]$objectsBar.Controls.Add($btnAddObjectRow)
        [void]$objectsBar.Controls.Add($btnRemoveObjectRow)
        $gridGeneralObjects = New-Object System.Windows.Forms.DataGridView
        $gridGeneralObjects.Dock = 'Fill'
        $gridGeneralObjects.AllowUserToAddRows = $false
        $gridGeneralObjects.RowHeadersVisible = $false
        $gridGeneralObjects.SelectionMode = 'FullRowSelect'
        $gridGeneralObjects.MultiSelect = $true
        $gridGeneralObjects.BackgroundColor = [System.Drawing.Color]::FromArgb(16,20,27)
        $gridGeneralObjects.GridColor = [System.Drawing.Color]::FromArgb(45,58,77)
        $gridGeneralObjects.BorderStyle = 'FixedSingle'
        $gridGeneralObjects.AllowUserToDeleteRows = $false
        $gridGeneralObjects.AllowUserToResizeRows = $false
        $gridGeneralObjects.EnableHeadersVisualStyles = $false
        $gridGeneralObjects.ColumnHeadersDefaultCellStyle.BackColor = [System.Drawing.Color]::FromArgb(35,50,75)
        $gridGeneralObjects.ColumnHeadersDefaultCellStyle.ForeColor = [System.Drawing.Color]::White
        $gridGeneralObjects.DefaultCellStyle.BackColor = [System.Drawing.Color]::FromArgb(20,28,40)
        $gridGeneralObjects.DefaultCellStyle.ForeColor = [System.Drawing.Color]::White
        $gridGeneralObjects.DefaultCellStyle.SelectionBackColor = [System.Drawing.Color]::FromArgb(59,130,246)
        $gridGeneralObjects.DefaultCellStyle.SelectionForeColor = [System.Drawing.Color]::White
        $gridGeneralObjects.AutoSizeColumnsMode = 'Fill'
        [void]$gridGeneralObjects.Columns.Add('ObjectName','ObjectName')
        [void]$gridGeneralObjects.Columns.Add('Position','Position x;y;z')
        [void]$gridGeneralObjects.Columns.Add('Orientation','Orientation x;y;z')
        $gridGeneralObjects.Columns['ObjectName'].FillWeight = 30
        $gridGeneralObjects.Columns['Position'].FillWeight = 35
        $gridGeneralObjects.Columns['Orientation'].FillWeight = 35
        [void]$objectsPanel.Controls.Add($gridGeneralObjects)
        [void]$objectsPanel.Controls.Add($objectsBar)

        $resizeGeneralLayout = {
            if ($null -eq $generalPanel -or $null -eq $generalSections) { return }
            $topY = 212
            $width = [Math]::Max(900, $generalPanel.ClientSize.Width - 16)
            $height = [Math]::Max(220, $generalPanel.ClientSize.Height - $topY - 8)
            $generalSections.Location = New-Object System.Drawing.Point(8, $topY)
            $generalSections.Size = New-Object System.Drawing.Size($width, $height)
        }.GetNewClosure()
        $generalPanel.Add_Resize($resizeGeneralLayout)
        & $resizeGeneralLayout


        $helpPanel = New-Object System.Windows.Forms.Panel
        $helpPanel.Dock = 'Fill'
        $helpPanel.Padding = New-Object System.Windows.Forms.Padding(8)
        $helpPanel.BackColor = New-UGSMColor '#0B121D'
        [void]$helpTab.Controls.Add($helpPanel)

        $lblHelpTitle = New-UGSMLabel -Text 'TraderPlus Help' -X 8 -Y 8 -Width 260 -Height 24 -FontSize 10 -Color $tpTheme.Text
        $lblHelpTitle.Font = New-Object System.Drawing.Font('Segoe UI', 10, [System.Drawing.FontStyle]::Bold)
        [void]$helpPanel.Controls.Add($lblHelpTitle)

        $txtHelp = New-Object System.Windows.Forms.TextBox
        $txtHelp.Location = New-Object System.Drawing.Point(8, 40)
        $txtHelp.Anchor = 'Top,Bottom,Left,Right'
        $txtHelp.Size = New-Object System.Drawing.Size(
            [Math]::Max(600, $helpPanel.ClientSize.Width - 16),
            [Math]::Max(300, $helpPanel.ClientSize.Height - 48)
        )
        $txtHelp.Multiline = $true
        $txtHelp.ReadOnly = $true
        $txtHelp.ScrollBars = 'Vertical'
        $txtHelp.BorderStyle = 'FixedSingle'
        $txtHelp.BackColor = [System.Drawing.Color]::FromArgb(16, 20, 27)
        $txtHelp.ForeColor = [System.Drawing.Color]::White
        $txtHelp.Font = New-Object System.Drawing.Font('Segoe UI', 9)
        $txtHelp.Text = @"
TraderPlus Help

Use the Prices tab to edit TraderPlusPriceConfig.json in grid form.
Use the Files tab when you need to edit raw JSON directly.

Recommended workflow:
1. Select the correct TraderPlus config file from the dropdown
2. Use Prices for normal price editing
3. Use Merge JSON for merge-ready TraderPlus price config files
4. Use Files for manual copy/paste when a mod does not provide a merge-ready JSON
5. Use Pretty Print after manual edits to normalize valid JSON formatting

Manual file tips:
- Some mods include TraderPlus data in files such as TraderPlus.txt
- Some mods include trader config snippets or readme/setup notes with classnames or category data
- If a mod does not include a merge-ready TraderPlus JSON, copy only the entries you need into the raw file

Important notes:
- Always back up before large manual edits
- Merge JSON works best with TraderPlus price config files
- Pretty Print does not repair invalid JSON syntax in every case
- If JSON is badly broken, fix the syntax in the Files tab first, then use Pretty Print

Suggested manual process:
1. Open the Files tab
2. Paste or edit the raw JSON
3. Click Pretty Print
4. Switch back to Prices to review the parsed result
"@
        [void]$helpPanel.Controls.Add($txtHelp)

            

        $filesPanel = New-Object System.Windows.Forms.Panel
        $filesPanel.Dock = 'Fill'
        $filesPanel.Padding = New-Object System.Windows.Forms.Padding(8)
        $filesPanel.BackColor = New-UGSMColor '#0B121D'
        [void]$filesTab.Controls.Add($filesPanel)

        $txtJson = New-Object System.Windows.Forms.TextBox
        $txtJson.Dock = 'Fill'
        $txtJson.Multiline = $true
        $txtJson.ScrollBars = 'Both'
        $txtJson.AcceptsReturn = $true
        $txtJson.AcceptsTab = $true
        $txtJson.WordWrap = $false
        $txtJson.MaxLength = 0
        $txtJson.Font = New-Object System.Drawing.Font('Consolas', 9)
        $txtJson.BackColor = [System.Drawing.Color]::FromArgb(16, 20, 27)
        $txtJson.ForeColor = [System.Drawing.Color]::White
        $txtJson.BorderStyle = 'FixedSingle'
        [void]$filesPanel.Controls.Add($txtJson)

        $filesBar = New-Object System.Windows.Forms.Panel
        $filesBar.Dock = 'Top'
        $filesBar.Height = 34
        $filesBar.BackColor = New-UGSMColor '#0B121D'
        [void]$filesPanel.Controls.Add($filesBar)

        $btnLoad = New-UGSMButton -Text 'Load JSON' -X 0 -Y 2 -Width 95 -Height 28 -BackColor '#253341'
        $btnSaveJson = New-UGSMButton -Text 'Save JSON' -X 105 -Y 2 -Width 95 -Height 28 -BackColor $tpTheme.AccentBlue
        $btnBackup = New-UGSMButton -Text 'Backup JSON' -X 210 -Y 2 -Width 105 -Height 28 -BackColor '#253341'
        $btnPretty = New-UGSMButton -Text 'Pretty Print' -X 325 -Y 2 -Width 100 -Height 28 -BackColor '#253341'
        $btnMerge = New-UGSMButton -Text 'Merge JSON' -X 435 -Y 2 -Width 95 -Height 28 -BackColor $tpTheme.AccentBlue

        if ($btnLoad) { [void]$filesBar.Controls.Add($btnLoad) }
        if ($btnSaveJson) { [void]$filesBar.Controls.Add($btnSaveJson) }
        if ($btnBackup) { [void]$filesBar.Controls.Add($btnBackup) }
        if ($btnPretty) { [void]$filesBar.Controls.Add($btnPretty) }
        if ($btnMerge) { [void]$filesBar.Controls.Add($btnMerge) }

        $idsPanel = New-Object System.Windows.Forms.Panel
        $idsPanel.Dock = 'Fill'
        $idsPanel.Padding = New-Object System.Windows.Forms.Padding(8)
        $idsPanel.BackColor = New-UGSMColor '#0B121D'
        [void]$idsTab.Controls.Add($idsPanel)

        $idsBar = New-Object System.Windows.Forms.Panel
        $idsBar.Dock = 'Top'
        $idsBar.Height = 98
        $idsBar.BackColor = New-UGSMColor '#0B121D'
        [void]$idsPanel.Controls.Add($idsBar)

        $lblIdsHint = New-UGSMLabel -Text 'Trader IDs config: edit categories, licences, and accepted currencies per trader ID. Use Load IDs to open the fixed IDs file.' -X 0 -Y 0 -Width 760 -Height 18 -FontSize 8.5 -Color $tpTheme.Muted
        [void]$idsBar.Controls.Add($lblIdsHint)

        $btnLoadIds = New-UGSMButton -Text 'Load IDs' -X 0 -Y 24 -Width 95 -Height 28 -BackColor '#253341'
        $btnSaveIds = New-UGSMButton -Text 'Save IDs' -X 105 -Y 24 -Width 95 -Height 28 -BackColor $tpTheme.AccentBlue
        $btnAddIdRow = New-UGSMButton -Text 'Add Row' -X 210 -Y 24 -Width 95 -Height 28 -BackColor '#253341'
        $btnRemoveIdRow = New-UGSMButton -Text 'Remove Selected' -X 315 -Y 24 -Width 130 -Height 28 -BackColor '#B91C1C'
        if ($btnLoadIds) { [void]$idsBar.Controls.Add($btnLoadIds) }
        if ($btnSaveIds) { [void]$idsBar.Controls.Add($btnSaveIds) }
        if ($btnAddIdRow) { [void]$idsBar.Controls.Add($btnAddIdRow) }
        if ($btnRemoveIdRow) { [void]$idsBar.Controls.Add($btnRemoveIdRow) }

        $lblIdCategoryPicker = New-UGSMLabel -Text 'Price Categories:' -X 0 -Y 62 -Width 90 -Height 20 -FontSize 8.5 -Color $tpTheme.Muted
        [void]$idsBar.Controls.Add($lblIdCategoryPicker)
        $cmbIdCategory = New-Object System.Windows.Forms.ComboBox
        $cmbIdCategory.Location = New-Object System.Drawing.Point(96, 59)
        $cmbIdCategory.Size = New-Object System.Drawing.Size(250, 24)
        $cmbIdCategory.DropDownStyle = 'DropDownList'
        $cmbIdCategory.BackColor = [System.Drawing.Color]::FromArgb(20,28,40)
        $cmbIdCategory.ForeColor = [System.Drawing.Color]::White
        [void]$idsBar.Controls.Add($cmbIdCategory)
        $btnIdCategoryAdd = New-UGSMButton -Text 'Add Category to Selected' -X 356 -Y 58 -Width 160 -Height 26 -BackColor '#253341'
        $btnIdCategoryRemove = New-UGSMButton -Text 'Remove Category from Selected' -X 526 -Y 58 -Width 190 -Height 26 -BackColor '#253341'
        if ($btnIdCategoryAdd) { [void]$idsBar.Controls.Add($btnIdCategoryAdd) }
        if ($btnIdCategoryRemove) { [void]$idsBar.Controls.Add($btnIdCategoryRemove) }

        $gridIds = New-Object System.Windows.Forms.DataGridView
        $gridIds.Location = New-Object System.Drawing.Point(8, 108)
        $gridIds.Anchor = 'Top,Bottom,Left,Right'
        $gridIds.Size = New-Object System.Drawing.Size([Math]::Max(900, $idsPanel.ClientSize.Width - 16), [Math]::Max(220, $idsPanel.ClientSize.Height - 116))
        $gridIds.BackgroundColor = [System.Drawing.Color]::FromArgb(16,20,27)
        $gridIds.GridColor = [System.Drawing.Color]::FromArgb(45,58,77)
        $gridIds.BorderStyle = 'FixedSingle'
        $gridIds.AllowUserToAddRows = $false
        $gridIds.AllowUserToDeleteRows = $false
        $gridIds.AllowUserToResizeRows = $false
        $gridIds.SelectionMode = 'FullRowSelect'
        $gridIds.MultiSelect = $true
        $gridIds.RowHeadersVisible = $false
        $gridIds.EnableHeadersVisualStyles = $false
        $gridIds.ColumnHeadersDefaultCellStyle.BackColor = [System.Drawing.Color]::FromArgb(35,50,75)
        $gridIds.ColumnHeadersDefaultCellStyle.ForeColor = [System.Drawing.Color]::White
        $gridIds.DefaultCellStyle.BackColor = [System.Drawing.Color]::FromArgb(20,28,40)
        $gridIds.DefaultCellStyle.ForeColor = [System.Drawing.Color]::White
        $gridIds.DefaultCellStyle.SelectionBackColor = [System.Drawing.Color]::FromArgb(59,130,246)
        $gridIds.DefaultCellStyle.SelectionForeColor = [System.Drawing.Color]::White
        $gridIds.AutoSizeColumnsMode = 'Fill'
        [void]$gridIds.Columns.Add('Id','Id')
        [void]$gridIds.Columns.Add('Categories','Categories (; separated)')
        [void]$gridIds.Columns.Add('LicencesRequired','Licences Required (; separated)')
        [void]$gridIds.Columns.Add('CurrenciesAccepted','Currencies Accepted (; separated)')
        $gridIds.Columns['Id'].FillWeight = 15
        $gridIds.Columns['Categories'].FillWeight = 40
        $gridIds.Columns['LicencesRequired'].FillWeight = 22
        $gridIds.Columns['CurrenciesAccepted'].FillWeight = 23
        [void]$idsPanel.Controls.Add($gridIds)

        $insurancePanel = New-Object System.Windows.Forms.Panel
        $insurancePanel.Dock = 'Fill'
        $insurancePanel.Padding = New-Object System.Windows.Forms.Padding(8)
        $insurancePanel.BackColor = New-UGSMColor '#0B121D'
        [void]$insuranceTab.Controls.Add($insurancePanel)

        $insuranceBar = New-Object System.Windows.Forms.Panel
        $insuranceBar.Dock = 'Top'
        $insuranceBar.Height = 98
        $insuranceBar.BackColor = New-UGSMColor '#0B121D'
        [void]$insurancePanel.Controls.Add($insuranceBar)

        $lblInsuranceHint = New-UGSMLabel -Text 'TraderPlus insurance config: edit authorized trader ID(s) and vehicle insurance coefficients.' -X 0 -Y 0 -Width 900 -Height 18 -FontSize 8.5 -Color $tpTheme.Muted
        [void]$insuranceBar.Controls.Add($lblInsuranceHint)

        $btnLoadInsurance = New-UGSMButton -Text 'Load Insurance' -X 0 -Y 24 -Width 110 -Height 28 -BackColor '#253341'
        $btnSaveInsurance = New-UGSMButton -Text 'Save Insurance' -X 120 -Y 24 -Width 110 -Height 28 -BackColor $tpTheme.AccentBlue
        $btnAddInsuranceRow = New-UGSMButton -Text 'Add Row' -X 240 -Y 24 -Width 95 -Height 28 -BackColor '#253341'
        $btnRemoveInsuranceRow = New-UGSMButton -Text 'Remove Selected' -X 345 -Y 24 -Width 130 -Height 28 -BackColor '#B91C1C'
        if ($btnLoadInsurance) { [void]$insuranceBar.Controls.Add($btnLoadInsurance) }
        if ($btnSaveInsurance) { [void]$insuranceBar.Controls.Add($btnSaveInsurance) }
        if ($btnAddInsuranceRow) { [void]$insuranceBar.Controls.Add($btnAddInsuranceRow) }
        if ($btnRemoveInsuranceRow) { [void]$insuranceBar.Controls.Add($btnRemoveInsuranceRow) }

        $lblAuthorizedInsuranceIds = New-UGSMLabel -Text 'Authorized ID(s):' -X 0 -Y 62 -Width 100 -Height 20 -FontSize 8.5 -Color $tpTheme.Muted
        [void]$insuranceBar.Controls.Add($lblAuthorizedInsuranceIds)
        $txtAuthorizedInsuranceIds = New-Object System.Windows.Forms.TextBox
        $txtAuthorizedInsuranceIds.Location = New-Object System.Drawing.Point(106, 59)
        $txtAuthorizedInsuranceIds.Size = New-Object System.Drawing.Size(260, 24)
        $txtAuthorizedInsuranceIds.BackColor = [System.Drawing.Color]::FromArgb(20,28,40)
        $txtAuthorizedInsuranceIds.ForeColor = [System.Drawing.Color]::White
        $txtAuthorizedInsuranceIds.BorderStyle = 'FixedSingle'
        [void]$insuranceBar.Controls.Add($txtAuthorizedInsuranceIds)

        $gridInsurance = New-Object System.Windows.Forms.DataGridView
        $gridInsurance.Location = New-Object System.Drawing.Point(8, 108)
        $gridInsurance.Anchor = 'Top,Bottom,Left,Right'
        $gridInsurance.Size = New-Object System.Drawing.Size([Math]::Max(900, $insurancePanel.ClientSize.Width - 16), [Math]::Max(220, $insurancePanel.ClientSize.Height - 116))
        $gridInsurance.BackgroundColor = [System.Drawing.Color]::FromArgb(16,20,27)
        $gridInsurance.GridColor = [System.Drawing.Color]::FromArgb(45,58,77)
        $gridInsurance.BorderStyle = 'FixedSingle'
        $gridInsurance.AllowUserToAddRows = $false
        $gridInsurance.AllowUserToDeleteRows = $false
        $gridInsurance.AllowUserToResizeRows = $false
        $gridInsurance.SelectionMode = 'FullRowSelect'
        $gridInsurance.MultiSelect = $true
        $gridInsurance.RowHeadersVisible = $false
        $gridInsurance.EnableHeadersVisualStyles = $false
        $gridInsurance.ColumnHeadersDefaultCellStyle.BackColor = [System.Drawing.Color]::FromArgb(35,50,75)
        $gridInsurance.ColumnHeadersDefaultCellStyle.ForeColor = [System.Drawing.Color]::White
        $gridInsurance.DefaultCellStyle.BackColor = [System.Drawing.Color]::FromArgb(20,28,40)
        $gridInsurance.DefaultCellStyle.ForeColor = [System.Drawing.Color]::White
        $gridInsurance.DefaultCellStyle.SelectionBackColor = [System.Drawing.Color]::FromArgb(59,130,246)
        $gridInsurance.DefaultCellStyle.SelectionForeColor = [System.Drawing.Color]::White
        $gridInsurance.AutoSizeColumnsMode = 'Fill'
        [void]$gridInsurance.Columns.Add('VehicleName','Vehicle Name')
        [void]$gridInsurance.Columns.Add('InsurancePriceCoefficient','Insurance Price Coefficient')
        [void]$gridInsurance.Columns.Add('CollateralMoneyCoefficient','Collateral Money Coefficient')
        $gridInsurance.Columns['VehicleName'].FillWeight = 42
        $gridInsurance.Columns['InsurancePriceCoefficient'].FillWeight = 29
        $gridInsurance.Columns['CollateralMoneyCoefficient'].FillWeight = 29
        [void]$insurancePanel.Controls.Add($gridInsurance)

        $pricesPanel = New-Object System.Windows.Forms.Panel
        $pricesPanel.Dock = 'Fill'
        $pricesPanel.Padding = New-Object System.Windows.Forms.Padding(8)
        $pricesPanel.BackColor = New-UGSMColor '#0B121D'
        [void]$pricesTab.Controls.Add($pricesPanel)

        $pricesBar = New-Object System.Windows.Forms.Panel
        $pricesBar.Dock = 'Top'
        $pricesBar.Height = 92
        $pricesBar.BackColor = New-UGSMColor '#0B121D'
        [void]$pricesPanel.Controls.Add($pricesBar)

        $lblPricesHint = New-UGSMLabel -Text 'TraderPlus rows: ClassName, Coefficient, MaxStock, TradeQuantity, BuyPrice, SellPrice.' -X 0 -Y 0 -Width 700 -Height 18 -FontSize 8.5 -Color $Theme.Muted
        [void]$pricesBar.Controls.Add($lblPricesHint)

        $btnLoadPrices = New-UGSMButton -Text 'Load Prices' -X 0 -Y 24 -Width 95 -Height 28 -BackColor '#253341'
        $btnSavePrices = New-UGSMButton -Text 'Save Prices' -X 105 -Y 24 -Width 95 -Height 28 -BackColor $tpTheme.AccentBlue
        $btnBackupPrices = New-UGSMButton -Text 'Backup JSON' -X 210 -Y 24 -Width 105 -Height 28 -BackColor '#253341'
        $btnMergePrices = New-UGSMButton -Text 'Merge JSON' -X 325 -Y 24 -Width 95 -Height 28 -BackColor $tpTheme.AccentBlue
        $btnSyncPrices = New-UGSMButton -Text 'Sync From types.xml' -X 430 -Y 24 -Width 155 -Height 28 -BackColor $tpTheme.AccentBlue
        $btnAddPriceCategory = New-UGSMButton -Text 'Add Category' -X 0 -Y 58 -Width 110 -Height 26 -BackColor '#253341'
        $btnMovePriceSelected = New-UGSMButton -Text 'Move Selected' -X 120 -Y 58 -Width 120 -Height 26 -BackColor '#253341'
        $btnAddPriceItem = New-UGSMButton -Text 'Add Item' -X 250 -Y 58 -Width 90 -Height 26 -BackColor '#253341'
        $btnDeletePriceSelected = New-UGSMButton -Text 'Delete Selected' -X 350 -Y 58 -Width 125 -Height 26 -BackColor '#8B1E1E'
        $btnAssignPriceCategory = New-UGSMButton -Text 'Assign Category' -X 485 -Y 58 -Width 125 -Height 26 -BackColor '#253341'
        $btnAddTraderId = New-UGSMButton -Text 'Add Trader ID' -X 620 -Y 58 -Width 115 -Height 26 -BackColor '#253341'

        if ($btnLoadPrices) { [void]$pricesBar.Controls.Add($btnLoadPrices) }
        if ($btnSavePrices) { [void]$pricesBar.Controls.Add($btnSavePrices) }
        if ($btnBackupPrices) { [void]$pricesBar.Controls.Add($btnBackupPrices) }
        if ($btnMergePrices) { [void]$pricesBar.Controls.Add($btnMergePrices) }
        if ($btnSyncPrices) { [void]$pricesBar.Controls.Add($btnSyncPrices) }
        if ($btnAddPriceCategory) { [void]$pricesBar.Controls.Add($btnAddPriceCategory) }
        if ($btnMovePriceSelected) { [void]$pricesBar.Controls.Add($btnMovePriceSelected) }
        if ($btnAddPriceItem) { [void]$pricesBar.Controls.Add($btnAddPriceItem) }
        if ($btnDeletePriceSelected) { [void]$pricesBar.Controls.Add($btnDeletePriceSelected) }
        if ($btnAssignPriceCategory) { [void]$pricesBar.Controls.Add($btnAssignPriceCategory) }
        if ($btnAddTraderId) { [void]$pricesBar.Controls.Add($btnAddTraderId) }

        $lblCategory = New-UGSMLabel -Text 'Category:' -X 760 -Y 0 -Width 70 -Height 18 -FontSize 8.5 -Color $tpTheme.Text
        [void]$pricesBar.Controls.Add($lblCategory)

        $cmbCategory = New-Object System.Windows.Forms.ComboBox
        $cmbCategory.Location = New-Object System.Drawing.Point(760, 22)
        $cmbCategory.Size = New-Object System.Drawing.Size(230, 24)
        $cmbCategory.DropDownStyle = [System.Windows.Forms.ComboBoxStyle]::DropDownList
        $cmbCategory.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
        $cmbCategory.BackColor = [System.Drawing.Color]::White
        $cmbCategory.ForeColor = [System.Drawing.Color]::Black
        [void]$pricesBar.Controls.Add($cmbCategory)

        $lblSearch = New-UGSMLabel -Text 'Search:' -X 1040 -Y 0 -Width 80 -Height 18 -FontSize 8.5 -Color $tpTheme.Text
        [void]$pricesBar.Controls.Add($lblSearch)

        $txtSearch = New-Object System.Windows.Forms.TextBox
        $txtSearch.Location = New-Object System.Drawing.Point(1040, 22)
        $txtSearch.Size = New-Object System.Drawing.Size(240, 24)
        $txtSearch.BorderStyle = 'FixedSingle'
        [void]$pricesBar.Controls.Add($txtSearch)

        $gridPrices = New-Object System.Windows.Forms.DataGridView
        $gridPrices.Location = New-Object System.Drawing.Point(8, 100)
        $gridPrices.Anchor = 'Top,Bottom,Left,Right'
        $gridPrices.Size = New-Object System.Drawing.Size(
            [Math]::Max(620, $pricesPanel.ClientSize.Width - 16),
            [Math]::Max(280, $pricesPanel.ClientSize.Height - 140)
        )
        $gridPrices.BackgroundColor = New-UGSMColor '#1e2e49'
        $gridPrices.GridColor = New-UGSMColor '#324158'
        $gridPrices.BorderStyle = 'None'
        $gridPrices.CellBorderStyle = 'SingleHorizontal'
        $gridPrices.EnableHeadersVisualStyles = $false
        $gridPrices.ColumnHeadersBorderStyle = 'Single'
        $gridPrices.RowHeadersBorderStyle = 'Single'
        $gridPrices.RowHeadersVisible = $false
        $gridPrices.ColumnHeadersHeightSizeMode = [System.Windows.Forms.DataGridViewColumnHeadersHeightSizeMode]::DisableResizing
        $gridPrices.ColumnHeadersHeight = 24
        $gridPrices.AllowUserToAddRows = $false
        $gridPrices.AllowUserToDeleteRows = $false
        $gridPrices.AllowUserToResizeRows = $false
        $gridPrices.SelectionMode = [System.Windows.Forms.DataGridViewSelectionMode]::FullRowSelect
        $gridPrices.MultiSelect = $true
        $gridPrices.AutoSizeColumnsMode = [System.Windows.Forms.DataGridViewAutoSizeColumnsMode]::None
        $gridPrices.EditMode = [System.Windows.Forms.DataGridViewEditMode]::EditOnEnter

        $gridPrices.ColumnHeadersDefaultCellStyle.BackColor = New-UGSMColor '#223047'
        $gridPrices.ColumnHeadersDefaultCellStyle.ForeColor = [System.Drawing.Color]::White
        $gridPrices.ColumnHeadersDefaultCellStyle.SelectionBackColor = New-UGSMColor '#223047'
        $gridPrices.ColumnHeadersDefaultCellStyle.SelectionForeColor = [System.Drawing.Color]::White
        $gridPrices.ColumnHeadersDefaultCellStyle.Font = New-Object System.Drawing.Font('Segoe UI', 9, [System.Drawing.FontStyle]::Bold)

        $gridPrices.DefaultCellStyle.BackColor = New-UGSMColor '#1A2332'
        $gridPrices.DefaultCellStyle.ForeColor = [System.Drawing.Color]::White
        $gridPrices.DefaultCellStyle.SelectionBackColor = New-UGSMColor '#2F7DFF'
        $gridPrices.DefaultCellStyle.SelectionForeColor = [System.Drawing.Color]::White
        $gridPrices.DefaultCellStyle.Font = New-Object System.Drawing.Font('Segoe UI', 9)

        $gridPrices.RowsDefaultCellStyle.BackColor = New-UGSMColor '#1A2332'
        $gridPrices.AlternatingRowsDefaultCellStyle.BackColor = New-UGSMColor '#16202E'

        [void]$gridPrices.Columns.Add('CategoryName', 'Category')
        [void]$gridPrices.Columns.Add('ClassName', 'Class Name')
        [void]$gridPrices.Columns.Add('Coefficient', 'Coefficient')
        [void]$gridPrices.Columns.Add('MaxStock', 'Max Stock')
        [void]$gridPrices.Columns.Add('TradeQuantity', 'Trade Qty')
        [void]$gridPrices.Columns.Add('BuyPrice', 'Buy Price')
        [void]$gridPrices.Columns.Add('SellPrice', 'Sell Price')
        [void]$gridPrices.Columns.Add('AssignedToTrader', 'Assigned')
        [void]$gridPrices.Columns.Add('TraderIds', 'Trader IDs')

        $gridPrices.Columns['CategoryName'].Width = 240
        $gridPrices.Columns['ClassName'].Width = 220
        $gridPrices.Columns['Coefficient'].Width = 70
        $gridPrices.Columns['MaxStock'].Width = 80
        $gridPrices.Columns['TradeQuantity'].Width = 90
        $gridPrices.Columns['BuyPrice'].Width = 90
        $gridPrices.Columns['SellPrice'].Width = 90
        $gridPrices.Columns['AssignedToTrader'].Width = 80
        $gridPrices.Columns['TraderIds'].Width = 140
        $gridPrices.Columns['AssignedToTrader'].ReadOnly = $true
        $gridPrices.Columns['TraderIds'].ReadOnly = $true

        [void]$pricesPanel.Controls.Add($gridPrices)

            

        $updateFileButtonState = {
            $hasSelection = ($cmbFile.Items.Count -gt 0 -and $cmbFile.SelectedIndex -ge 0)
            if ($btnLoad) { $btnLoad.Enabled = $hasSelection }
            if ($btnSaveJson) { $btnSaveJson.Enabled = $hasSelection }
            if ($btnBackup) { $btnBackup.Enabled = $hasSelection }
            if ($btnPretty) { $btnPretty.Enabled = $hasSelection }
            if ($btnMerge) { $btnMerge.Enabled = $hasSelection }
            if ($btnLoadPrices) { $btnLoadPrices.Enabled = $hasSelection }
            if ($btnSavePrices) { $btnSavePrices.Enabled = $hasSelection }
            if ($btnBackupPrices) { $btnBackupPrices.Enabled = $hasSelection }
            if ($btnMergePrices) { $btnMergePrices.Enabled = $hasSelection }
            if ($btnSyncPrices) { $btnSyncPrices.Enabled = $hasSelection }
            if ($btnAddPriceCategory) { $btnAddPriceCategory.Enabled = $hasSelection }
            if ($btnMovePriceSelected) { $btnMovePriceSelected.Enabled = $hasSelection }
            if ($btnAddPriceItem) { $btnAddPriceItem.Enabled = $hasSelection }
            if ($btnDeletePriceSelected) { $btnDeletePriceSelected.Enabled = $hasSelection }
            if ($btnAssignPriceCategory) { $btnAssignPriceCategory.Enabled = $hasSelection }
            if ($btnAddTraderId) { $btnAddTraderId.Enabled = $hasSelection }
            if ($btnLoadIds) { $btnLoadIds.Enabled = $hasSelection }
            if ($btnSaveIds) { $btnSaveIds.Enabled = $hasSelection }
            if ($btnAddIdRow) { $btnAddIdRow.Enabled = $hasSelection }
            if ($btnRemoveIdRow) { $btnRemoveIdRow.Enabled = $hasSelection }
        }.GetNewClosure()

        $resizeLayout = {
            $topBar.Width = [Math]::Max(900, $rootPanel.ClientSize.Width)
            $lblPath.Width = [Math]::Max(900, $rootPanel.ClientSize.Width)
            $tabTrader.Size = New-Object System.Drawing.Size(
                [Math]::Max(900, $rootPanel.ClientSize.Width),
                [Math]::Max(420, $rootPanel.ClientSize.Height - 120)
            )
            $pricesBar.Width = [Math]::Max(900, $pricesPanel.ClientSize.Width - 16)
            $gridPrices.Size = New-Object System.Drawing.Size([Math]::Max(900, $pricesPanel.ClientSize.Width - 16), [Math]::Max(320, $pricesPanel.ClientSize.Height - 108))
        }.GetNewClosure()

        $resolveCurrentPath = {
            if ($cmbFile.SelectedItem -and $cmbFile.SelectedItem.PSObject -and $cmbFile.SelectedItem.PSObject.Properties['FullName']) {
                return [string]$cmbFile.SelectedItem.FullName
            }
            if (-not [string]::IsNullOrWhiteSpace([string]$cmbFile.SelectedValue)) {
                return [string]$cmbFile.SelectedValue
            }
            return ''
        }.GetNewClosure()

        $isPriceConfigSelected = {
            $path = & $resolveCurrentPath
            return ([System.IO.Path]::GetFileName([string]$path) -eq 'TraderPlusPriceConfig.json')
        }.GetNewClosure()

        $syncGridToPriceState = {
            if ($null -eq $tpState.PriceRows -or @($tpState.PriceRows).Count -le 0) { return }

            $rowIndex = @{}
            for ($i = 0; $i -lt $tpState.PriceRows.Count; $i++) {
                $stateRow = $tpState.PriceRows[$i]
                if ($null -eq $stateRow) { continue }
                $key = ([string]$stateRow.CategoryName + '|' + [string]$stateRow.ClassName)
                if (-not $rowIndex.ContainsKey($key)) { $rowIndex[$key] = $i }
            }

            foreach ($gridRow in @($gridPrices.Rows)) {
                if ($null -eq $gridRow -or $gridRow.IsNewRow) { continue }
                $key = ([string]$gridRow.Cells['CategoryName'].Value + '|' + [string]$gridRow.Cells['ClassName'].Value)
                if (-not $rowIndex.ContainsKey($key)) { continue }

                $stateRow = $tpState.PriceRows[[int]$rowIndex[$key]]
                $stateRow.CategoryName = [string]$gridRow.Cells['CategoryName'].Value
                $stateRow.ClassName = [string]$gridRow.Cells['ClassName'].Value
                $stateRow.Coefficient = [string]$gridRow.Cells['Coefficient'].Value
                $stateRow.MaxStock = [string]$gridRow.Cells['MaxStock'].Value
                $stateRow.TradeQuantity = [string]$gridRow.Cells['TradeQuantity'].Value
                $stateRow.BuyPrice = [string]$gridRow.Cells['BuyPrice'].Value
                $stateRow.SellPrice = [string]$gridRow.Cells['SellPrice'].Value
            }
        }.GetNewClosure()

        $refreshPriceCategories = {
            if ($null -eq $cmbCategory) { return }

            $currentSelection = [string]$tpState.PriceCategory
            $nameMap = @{}
            $categoryNames = New-Object System.Collections.ArrayList
            [void]$categoryNames.Add('All Categories')

            foreach ($row in @($tpState.PriceRows)) {
                if ($null -eq $row) { continue }
                $name = [string]$row.CategoryName
                if ([string]::IsNullOrWhiteSpace($name)) { continue }
                if (-not $nameMap.ContainsKey($name)) { $nameMap[$name] = $true }
            }

            foreach ($customCategory in @($tpState.PriceCustomCategories)) {
                $name = [string]$customCategory
                if ([string]::IsNullOrWhiteSpace($name)) { continue }
                if (-not $nameMap.ContainsKey($name)) { $nameMap[$name] = $true }
            }

            foreach ($name in @($nameMap.Keys | Sort-Object)) {
                [void]$categoryNames.Add([string]$name)
            }

            $cmbCategory.BeginUpdate()
            try {
                $cmbCategory.Items.Clear()
                foreach ($name in @($categoryNames)) {
                    [void]$cmbCategory.Items.Add([string]$name)
                }

                $selectedIndex = 0
                for ($i = 0; $i -lt $cmbCategory.Items.Count; $i++) {
                    if ([string]$cmbCategory.Items[$i] -eq $currentSelection) {
                        $selectedIndex = $i
                        break
                    }
                }

                if ($cmbCategory.Items.Count -gt 0 -and $cmbCategory.SelectedIndex -ne $selectedIndex) {
                    $cmbCategory.SelectedIndex = $selectedIndex
                }
            }
            finally {
                $cmbCategory.EndUpdate()
            }
        }.GetNewClosure()

        $populatePriceGrid = {
            if ($null -eq $gridPrices) { return }

            $gridPrices.Rows.Clear()

            $categoryFilter = [string]$tpState.PriceCategory
            $searchFilter = [string]$tpState.PriceSearch

            foreach ($row in @($tpState.PriceRows)) {
                if ($null -eq $row) { continue }
                if (-not [string]::IsNullOrWhiteSpace($categoryFilter) -and $categoryFilter -ne 'All Categories' -and [string]$row.CategoryName -ne $categoryFilter) { continue }

                if (-not [string]::IsNullOrWhiteSpace($searchFilter)) {
                    $haystack = ([string]$row.ClassName + ' ' + [string]$row.CategoryName)
                    if ($haystack.IndexOf($searchFilter, [System.StringComparison]::OrdinalIgnoreCase) -lt 0) { continue }
                }

                $assignedToTrader = 'No'
                $traderIds = ''
                $categoryKey = ([string]$row.CategoryName).Trim()
                if ($null -ne $tpState.CategoryAssignments -and $tpState.CategoryAssignments.ContainsKey($categoryKey)) {
                    $ids = @($tpState.CategoryAssignments[$categoryKey])
                    if ($ids.Count -gt 0) {
                        $assignedToTrader = 'Yes'
                        $traderIds = [string]($ids -join ',')
                    }
                }

                [void]$gridPrices.Rows.Add(
                    [string]$row.CategoryName,
                    [string]$row.ClassName,
                    [string]$row.Coefficient,
                    [string]$row.MaxStock,
                    [string]$row.TradeQuantity,
                    [string]$row.BuyPrice,
                    [string]$row.SellPrice,
                    $assignedToTrader,
                    $traderIds
                )
            }
        }.GetNewClosure()

        $refreshFiles = {
            try {
                $cmbFile.Items.Clear()
                $files = @(Get-UGSMGameDayZTraderPlusJsonFiles -Instance $tpInstance)
                $tpState.Files = $files

                if ($tpStatusLabel) {
                    $tpStatusLabel.Text = "TraderPlus refresh found $($files.Count) file(s)."
                }
                Write-UGSMGameDayZTraderPlusSafeLog -Message ("TraderPlus refresh files completed. Instance={0}; FileCount={1}" -f ([string]$tpInstance.Id), $files.Count) -Level 'Debug'

                foreach ($file in $files) {
                    [void]$cmbFile.Items.Add($file)
                }

                if ($cmbFile.Items.Count -gt 0) {
                    $cmbFile.SelectedIndex = 0
                    $lblPath.Text = [string]$cmbFile.SelectedValue
                }
                else {
                    $tpState.CurrentPath = ''
                    $lblPath.Text = ''
                    if ($tpStatusLabel) { $tpStatusLabel.Text = 'No TraderPlus config JSON files found.' }
                }

                & $updateFileButtonState
            }
            catch {
                $safeRefreshError = $_.Exception.Message
                if ($tpStatusLabel) { $tpStatusLabel.Text = 'Refreshing TraderPlus files failed: ' + $safeRefreshError }
                Write-UGSMGameDayZTraderPlusSafeLog -Message ("TraderPlus refresh files failed: {0}" -f $safeRefreshError) -Level 'Error'
            }
        }.GetNewClosure()

        $selectManagedFileByName = {
            param(
                [string]$FileName
            )

            for ($i = 0; $i -lt $cmbFile.Items.Count; $i++) {
                $item = $cmbFile.Items[$i]
                if ($null -ne $item -and $item.PSObject -and $item.PSObject.Properties['Name'] -and [string]$item.Name -eq $FileName) {
                    $cmbFile.SelectedIndex = $i
                    return $true
                }
            }

            return $false
        }.GetNewClosure()

        $loadFile = {
            try {
                $path = & $resolveCurrentPath
                if ([string]::IsNullOrWhiteSpace($path)) { throw 'No TraderPlus JSON file is selected.' }
                if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw 'Selected TraderPlus JSON file was not found.' }

                $rawJson = [System.IO.File]::ReadAllText($path)
                $txtJson.Text = $rawJson
                $txtJson.SelectionStart = 0
                $txtJson.SelectionLength = 0
                $txtJson.ScrollToCaret()

                $tpState.CurrentPath = $path
                $lblPath.Text = $path
                if ($tpStatusLabel) { $tpStatusLabel.Text = ('Loaded TraderPlus JSON: ' + [System.IO.Path]::GetFileName($path)) }
            }
            catch {
                if ($tpStatusLabel) { $tpStatusLabel.Text = 'Loading TraderPlus JSON failed: ' + $_.Exception.Message }
            }
        }.GetNewClosure()

        $loadPrices = {
            try {
                $path = & $resolveCurrentPath
                if ([string]::IsNullOrWhiteSpace($path)) { throw 'No TraderPlus JSON file is selected.' }
                if ([System.IO.Path]::GetFileName($path) -ne 'TraderPlusPriceConfig.json') { throw 'Select TraderPlusPriceConfig.json in the file picker to use the Prices view.' }

                $tpState.PriceRows = @(Read-UGSMGameDayZTraderPlusPriceRows -Path $path)
                $tpState.PriceFilePath = $path
                $tpState.CategoryAssignments = Get-UGSMGameDayZTraderPlusCategoryAssignmentMap -PriceConfigPath $path
                $tpState.TraderRows = @(Get-UGSMGameDayZTraderPlusTraderRows -PriceConfigPath $path)

                & $refreshPriceCategories
                & $populatePriceGrid

                $lblPath.Text = $path
                if ($tpStatusLabel) { $tpStatusLabel.Text = ('Loaded TraderPlus price rows: ' + $tpState.PriceRows.Count) }
            }
            catch {
                Write-UGSMGameDayZTraderPlusSafeLog -Message ("loadPrices failed: {0}" -f $_.Exception.Message) -Level 'Error'
                if ($tpStatusLabel) { $tpStatusLabel.Text = 'Loading TraderPlus prices failed: ' + $_.Exception.Message }
            }
        }.GetNewClosure()

        $savePrices = {
            try {
                $path = [string]$tpState.CurrentPath
                if ([string]::IsNullOrWhiteSpace($path)) { throw 'No TraderPlus JSON file is loaded.' }
                if ([System.IO.Path]::GetFileName($path) -ne 'TraderPlusPriceConfig.json') {
                    throw 'Select TraderPlusPriceConfig.json to use the Prices view.'
                }

                & $syncGridToPriceState
                [void](Backup-UGSMGameDayZFile -TargetPath $path)
                [void](Write-UGSMGameDayZTraderPlusPriceRows -Path $path -Rows @($tpState.PriceRows) -AdditionalCategories @($tpState.PriceCustomCategories))

                & $loadFile
                & $loadPrices

                if ($tpStatusLabel) { $tpStatusLabel.Text = ('Saved TraderPlus price rows: ' + $tpState.PriceRows.Count) }
            }
            catch {
                if ($tpStatusLabel) { $tpStatusLabel.Text = 'Saving TraderPlus prices failed: ' + $_.Exception.Message }
            }
        }.GetNewClosure()

        $saveFile = {
            try {
                $path = [string]$tpState.CurrentPath
                if ([string]::IsNullOrWhiteSpace($path)) { throw 'No TraderPlus JSON file is loaded.' }

                $parsed = $txtJson.Text | ConvertFrom-Json -ErrorAction Stop
                [void](Backup-UGSMGameDayZFile -TargetPath $path)
                [void](Write-UGSMGameDayZJsonDataSafe -Path $path -Data $parsed)

                $txtJson.Text = ($parsed | ConvertTo-Json -Depth 100)
                $lblPath.Text = $path
                if ($tpStatusLabel) { $tpStatusLabel.Text = ('Saved TraderPlus JSON: ' + [System.IO.Path]::GetFileName($path)) }
            }
            catch {
                if ($tpStatusLabel) { $tpStatusLabel.Text = 'Saving TraderPlus JSON failed: ' + $_.Exception.Message }
            }
        }.GetNewClosure()

        $backupFile = {
            try {
                $path = & $resolveCurrentPath
                if ([string]::IsNullOrWhiteSpace($path)) { throw 'No TraderPlus JSON file is selected.' }

                $backup = Backup-UGSMGameDayZFile -TargetPath $path
                if ($tpStatusLabel) {
                    if ([string]::IsNullOrWhiteSpace([string]$backup)) {
                        $tpStatusLabel.Text = 'No TraderPlus JSON file exists yet to back up.'
                    }
                    else {
                        $tpStatusLabel.Text = ('Backed up TraderPlus JSON: ' + $backup)
                    }
                }
            }
            catch {
                if ($tpStatusLabel) { $tpStatusLabel.Text = 'Backing up TraderPlus JSON failed: ' + $_.Exception.Message }
            }
        }.GetNewClosure()

        $prettyPrint = {
            try {
                $parsed = $txtJson.Text | ConvertFrom-Json -ErrorAction Stop
                $txtJson.Text = ($parsed | ConvertTo-Json -Depth 100)
                if ($tpStatusLabel) { $tpStatusLabel.Text = 'Formatted TraderPlus JSON.' }
            }
            catch {
                if ($tpStatusLabel) { $tpStatusLabel.Text = 'Formatting TraderPlus JSON failed: ' + $_.Exception.Message }
            }
        }.GetNewClosure()

        $loadPrices = {
            try {
                Write-UGSMGameDayZTraderPlusSafeLog -Message 'loadPrices: enter'

                Write-UGSMGameDayZTraderPlusSafeLog -Message 'loadPrices: calling resolveCurrentPath'
                $path = & $resolveCurrentPath
                Write-UGSMGameDayZTraderPlusSafeLog -Message ("loadPrices: resolveCurrentPath returned '{0}'" -f $path)

                if ([string]::IsNullOrWhiteSpace($path)) { throw 'No TraderPlus JSON file is selected.' }
                if ([System.IO.Path]::GetFileName($path) -ne 'TraderPlusPriceConfig.json') { throw 'Select TraderPlusPriceConfig.json in the file picker to use the Prices view.' }

                Write-UGSMGameDayZTraderPlusSafeLog -Message 'loadPrices: reading rows'
                $tpState.PriceRows = @(Read-UGSMGameDayZTraderPlusPriceRows -Path $path)
                Write-UGSMGameDayZTraderPlusSafeLog -Message ("loadPrices: rows read = {0}" -f @($tpState.PriceRows).Count)

                $tpState.PriceFilePath = $path
                $tpState.PriceCustomCategories = @(Read-UGSMGameDayZTraderPlusPriceCategoryNames -Path $path)
                $tpState.CategoryAssignments = Get-UGSMGameDayZTraderPlusCategoryAssignmentMap -PriceConfigPath $path
                $tpState.TraderRows = @(Get-UGSMGameDayZTraderPlusTraderRows -PriceConfigPath $path)
                Write-UGSMGameDayZTraderPlusSafeLog -Message ("loadPrices: category names loaded = {0}; assignments loaded = {1}" -f @($tpState.PriceCustomCategories).Count, $tpState.CategoryAssignments.Count)

                Write-UGSMGameDayZTraderPlusSafeLog -Message ("loadPrices: refreshPriceCategories type = {0}" -f $(if ($null -eq $refreshPriceCategories) { '<null>' } else { $refreshPriceCategories.GetType().FullName }))
                & $refreshPriceCategories
                Write-UGSMGameDayZTraderPlusSafeLog -Message 'loadPrices: refreshPriceCategories completed'

                Write-UGSMGameDayZTraderPlusSafeLog -Message ("loadPrices: populatePriceGrid type = {0}" -f $(if ($null -eq $populatePriceGrid) { '<null>' } else { $populatePriceGrid.GetType().FullName }))
                & $populatePriceGrid
                Write-UGSMGameDayZTraderPlusSafeLog -Message ("loadPrices: populatePriceGrid completed, grid rows = {0}" -f $gridPrices.Rows.Count)

                $lblPath.Text = $path
                if ($tpStatusLabel) { $tpStatusLabel.Text = ('Loaded TraderPlus price rows: ' + $tpState.PriceRows.Count) }
            }
            catch {
                Write-UGSMGameDayZTraderPlusSafeLog -Message ("loadPrices failed: {0}" -f $_.Exception.Message) -Level 'Error'
                if ($tpStatusLabel) { $tpStatusLabel.Text = 'Loading TraderPlus prices failed: ' + $_.Exception.Message }
            }
        }.GetNewClosure()

        $mergeFile = {
            try {
                $targetPath = & $resolveCurrentPath
                if ([string]::IsNullOrWhiteSpace($targetPath)) { throw 'No TraderPlus JSON target file is selected.' }

                Write-UGSMGameDayZTraderPlusSafeLog -Message ("Merge start. Target='{0}'" -f $targetPath)

                $dialog = New-Object System.Windows.Forms.OpenFileDialog
                $dialog.Title = 'Select TraderPlus JSON to merge'
                $dialog.InitialDirectory = Split-Path -Parent $targetPath
                $dialog.Multiselect = $false
                $dialog.CheckFileExists = $true
                $dialog.CheckPathExists = $true
                $dialog.Filter = 'JSON files (*.json)|*.json|All files (*.*)|*.*'
                $dialog.FileName = ''

                if ($dialog.ShowDialog() -ne [System.Windows.Forms.DialogResult]::OK) {
                    Write-UGSMGameDayZTraderPlusSafeLog -Message 'Merge cancelled by user.'
                    return
                }

                $sourcePath = [string]$dialog.FileName
                if ([string]::IsNullOrWhiteSpace($sourcePath) -or -not (Test-Path -LiteralPath $sourcePath -PathType Leaf)) {
                    throw 'Selected TraderPlus JSON file was not found.'
                }

                Write-UGSMGameDayZTraderPlusSafeLog -Message ("Merge source selected. Source='{0}'" -f $sourcePath)

                [void](Backup-UGSMGameDayZFile -TargetPath $targetPath)
                Write-UGSMGameDayZTraderPlusSafeLog -Message 'Backup created before merge.'

                [void](Merge-UGSMGameDayZJsonFiles -TargetPath $targetPath -SourcePath $sourcePath)
                Write-UGSMGameDayZTraderPlusSafeLog -Message 'Merge completed.'

                & $loadFile
                Write-UGSMGameDayZTraderPlusSafeLog -Message 'loadFile completed after merge.'
                Write-UGSMGameDayZTraderPlusSafeLog -Message 'About to evaluate post-merge price reload condition.'

                Write-UGSMGameDayZTraderPlusSafeLog -Message ("loadPrices variable type before post-merge invoke = {0}" -f $(if ($null -eq $loadPrices) { '<null>' } else { $loadPrices.GetType().FullName }))

                if ([System.IO.Path]::GetFileName($targetPath) -eq 'TraderPlusPriceConfig.json') {
                    if ($loadPrices -is [scriptblock]) {
                        & $loadPrices
                        Write-UGSMGameDayZTraderPlusSafeLog -Message 'loadPrices completed after merge.'
                    }
                    else {
                        Write-UGSMGameDayZTraderPlusSafeLog -Message ("loadPrices is not callable after merge. Type='{0}'" -f $(if ($null -eq $loadPrices) { '<null>' } else { $loadPrices.GetType().FullName })) -Level 'Error'
                        if ($tpStatusLabel) { $tpStatusLabel.Text = 'Merged TraderPlus JSON, but prices reload handler was not callable.' }
                    }
                }
            }
            catch {
                Write-UGSMGameDayZTraderPlusSafeLog -Message ("Merge failed: {0}" -f $_.Exception.Message) -Level 'Error'
                if ($tpStatusLabel) { $tpStatusLabel.Text = 'Merging TraderPlus JSON failed: ' + $_.Exception.Message }
            }
        }.GetNewClosure()

            

        $savePrices = {
            try {
                $path = & $resolveCurrentPath
                if ([string]::IsNullOrWhiteSpace($path)) { throw 'No TraderPlus JSON file is selected.' }
                if ([System.IO.Path]::GetFileName($path) -ne 'TraderPlusPriceConfig.json') { throw 'Select TraderPlusPriceConfig.json in the file picker to use the Prices view.' }

                & $syncGridToPriceState
                [void](Backup-UGSMGameDayZFile -TargetPath $path)
                [void](Write-UGSMGameDayZTraderPlusPriceRows -Path $path -Rows @($tpState.PriceRows) -AdditionalCategories @($tpState.PriceCustomCategories))

                & $loadFile
                & $loadPrices

                if ($tpStatusLabel) { $tpStatusLabel.Text = ('Saved TraderPlus price rows: ' + $tpState.PriceRows.Count) }
            }
            catch {
                if ($tpStatusLabel) { $tpStatusLabel.Text = 'Saving TraderPlus prices failed: ' + $_.Exception.Message }
            }
        }.GetNewClosure()


        $addPriceCategory = {
            try {
                $name = Show-UGSMGameDayZTraderPlusTextPrompt -Title 'Add TraderPlus Category' -Prompt 'New category name:' -DefaultValue ''
                if ([string]::IsNullOrWhiteSpace([string]$name)) { return }
                $name = ([string]$name).Trim()

                if (-not ($tpState.PriceCustomCategories -contains $name)) {
                    $tpState.PriceCustomCategories = @($tpState.PriceCustomCategories) + $name
                }

                $tpState.PriceCategory = $name
                & $refreshPriceCategories
                & $populatePriceGrid
                if ($tpStatusLabel) { $tpStatusLabel.Text = "Added category '$name'. Click Save Prices to keep it, or move/add items into it." }
            }
            catch {
                if ($tpStatusLabel) { $tpStatusLabel.Text = 'Adding TraderPlus category failed: ' + $_.Exception.Message }
            }
        }.GetNewClosure()

        $moveSelectedPriceRows = {
            try {
                if ($gridPrices.SelectedRows.Count -le 0) { throw 'Select one or more price rows first.' }

                $defaultCategory = [string]$tpState.PriceCategory
                if ([string]::IsNullOrWhiteSpace($defaultCategory) -or $defaultCategory -eq 'All Categories') { $defaultCategory = 'AUTO_IMPORTED_ITEMS' }

                $targetCategory = Show-UGSMGameDayZTraderPlusCategoryPicker -Title 'Move TraderPlus Items' -Prompt 'Move selected item(s) to category:' -Categories @($tpState.PriceCategories + $tpState.PriceCustomCategories) -DefaultValue $defaultCategory
                if ([string]::IsNullOrWhiteSpace([string]$targetCategory)) { return }
                $targetCategory = ([string]$targetCategory).Trim()

                & $syncGridToPriceState

                $moved = 0
                foreach ($gridRow in @($gridPrices.SelectedRows)) {
                    if ($null -eq $gridRow -or $gridRow.IsNewRow) { continue }
                    $oldCategory = [string]$gridRow.Cells['CategoryName'].Value
                    $className = [string]$gridRow.Cells['ClassName'].Value
                    if ([string]::IsNullOrWhiteSpace($className)) { continue }

                    foreach ($stateRow in @($tpState.PriceRows)) {
                        if ($null -eq $stateRow) { continue }
                        if ([string]$stateRow.CategoryName -eq $oldCategory -and [string]$stateRow.ClassName -eq $className) {
                            $stateRow.CategoryName = $targetCategory
                            $moved++
                            break
                        }
                    }
                }

                if (-not ($tpState.PriceCustomCategories -contains $targetCategory)) {
                    $tpState.PriceCustomCategories = @($tpState.PriceCustomCategories) + $targetCategory
                }

                $tpState.PriceCategory = $targetCategory
                & $refreshPriceCategories
                & $populatePriceGrid
                if ($tpStatusLabel) { $tpStatusLabel.Text = "Moved $moved TraderPlus item(s) to '$targetCategory'. Click Save Prices to write changes." }
            }
            catch {
                if ($tpStatusLabel) { $tpStatusLabel.Text = 'Moving TraderPlus items failed: ' + $_.Exception.Message }
            }
        }.GetNewClosure()

        $addPriceItem = {
            try {
                $categoryName = [string]$tpState.PriceCategory
                if ([string]::IsNullOrWhiteSpace($categoryName) -or $categoryName -eq 'All Categories') { $categoryName = 'AUTO_IMPORTED_ITEMS' }

                $className = Show-UGSMGameDayZTraderPlusTextPrompt -Title 'Add TraderPlus Item' -Prompt 'Class name to add:' -DefaultValue ''
                if ([string]::IsNullOrWhiteSpace([string]$className)) { return }
                $className = ([string]$className).Trim()

                & $syncGridToPriceState

                foreach ($row in @($tpState.PriceRows)) {
                    if ($null -eq $row) { continue }
                    if ([string]$row.CategoryName -eq $categoryName -and [string]$row.ClassName -eq $className) {
                        throw "'$className' already exists in '$categoryName'."
                    }
                }

                $newRows = New-Object System.Collections.ArrayList
                foreach ($row in @($tpState.PriceRows)) { [void]$newRows.Add($row) }
                [void]$newRows.Add([pscustomobject]@{
                    CategoryName  = $categoryName
                    ClassName     = $className
                    Coefficient   = '1.0'
                    MaxStock      = '125'
                    TradeQuantity = '-1'
                    BuyPrice      = '100'
                    SellPrice     = '50'
                })
                $tpState.PriceRows = @($newRows)

                if (-not ($tpState.PriceCustomCategories -contains $categoryName)) {
                    $tpState.PriceCustomCategories = @($tpState.PriceCustomCategories) + $categoryName
                }

                & $refreshPriceCategories
                & $populatePriceGrid
                if ($tpStatusLabel) { $tpStatusLabel.Text = "Added '$className' to '$categoryName'. Click Save Prices to write changes." }
            }
            catch {
                if ($tpStatusLabel) { $tpStatusLabel.Text = 'Adding TraderPlus item failed: ' + $_.Exception.Message }
            }
        }.GetNewClosure()

        $deleteSelectedPriceRows = {
            try {
                if ($gridPrices.SelectedRows.Count -le 0) { throw 'Select one or more price rows first.' }

                & $syncGridToPriceState

                $deleteKeys = @{}
                foreach ($gridRow in @($gridPrices.SelectedRows)) {
                    if ($null -eq $gridRow -or $gridRow.IsNewRow) { continue }
                    $key = ([string]$gridRow.Cells['CategoryName'].Value + '|' + [string]$gridRow.Cells['ClassName'].Value)
                    $deleteKeys[$key] = $true
                }

                $newRows = New-Object System.Collections.ArrayList
                $deleted = 0
                foreach ($row in @($tpState.PriceRows)) {
                    if ($null -eq $row) { continue }
                    $key = ([string]$row.CategoryName + '|' + [string]$row.ClassName)
                    if ($deleteKeys.ContainsKey($key)) {
                        $deleted++
                        continue
                    }
                    [void]$newRows.Add($row)
                }

                $tpState.PriceRows = @($newRows)
                & $refreshPriceCategories
                & $populatePriceGrid
                if ($tpStatusLabel) { $tpStatusLabel.Text = "Deleted $deleted TraderPlus item(s). Click Save Prices to write changes." }
            }
            catch {
                if ($tpStatusLabel) { $tpStatusLabel.Text = 'Deleting TraderPlus items failed: ' + $_.Exception.Message }
            }
        }.GetNewClosure()

        $syncPricesFromTypes = {
            try {
                $path = & $resolveCurrentPath
                if ([string]::IsNullOrWhiteSpace($path)) { throw 'No TraderPlus JSON file is selected.' }
                if ([System.IO.Path]::GetFileName($path) -ne 'TraderPlusPriceConfig.json') { throw 'Select TraderPlusPriceConfig.json in the file picker to use the Prices view.' }
                if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw 'Selected TraderPlusPriceConfig.json was not found.' }

                $typesPath = ''
                if (Get-Command -Name Resolve-UGSMGameDayZTypesXmlPath -ErrorAction SilentlyContinue) {
                    $typesPath = Resolve-UGSMGameDayZTypesXmlPath -Instance $tpInstance
                }

                if ([string]::IsNullOrWhiteSpace($typesPath) -or -not (Test-Path -LiteralPath $typesPath -PathType Leaf)) {
                    try {
                        $paths = Get-UGSMGameDayZProfilePaths -Instance $tpInstance
                        foreach ($candidate in @(
                                $paths.RuntimeTypesPath,
                                $(if (-not [string]::IsNullOrWhiteSpace([string]$paths.RuntimeDbPath)) { Join-Path ([string]$paths.RuntimeDbPath) 'types.xml' }),
                                $(if (-not [string]::IsNullOrWhiteSpace([string]$paths.RuntimeMissionPath)) { Join-Path ([string]$paths.RuntimeMissionPath) 'db\types.xml' }),
                                $(if (-not [string]::IsNullOrWhiteSpace([string]$paths.MissionFolderPath)) { Join-Path ([string]$paths.MissionFolderPath) 'db\types.xml' })
                            )) {
                            if (-not [string]::IsNullOrWhiteSpace([string]$candidate) -and (Test-Path -LiteralPath $candidate -PathType Leaf)) {
                                $typesPath = [string]$candidate
                                break
                            }
                        }
                    }
                    catch { }
                }

                if ([string]::IsNullOrWhiteSpace($typesPath) -or -not (Test-Path -LiteralPath $typesPath -PathType Leaf)) {
                    throw 'types.xml could not be resolved for this instance.'
                }

                if (-not (Get-Command -Name Sync-UGSMGameDayZTraderPlusPriceConfigWithTypes -ErrorAction SilentlyContinue)) {
                    throw 'TraderPlus types sync function is not loaded.'
                }

                # Commit any current grid edits before syncing from types.xml. Without this,
                # a user can edit the grid, click Sync, and the sync will read the older JSON on disk.
                & $syncGridToPriceState
                [void](Backup-UGSMGameDayZFile -TargetPath $path)
                [void](Write-UGSMGameDayZTraderPlusPriceRows -Path $path -Rows @($tpState.PriceRows) -AdditionalCategories @($tpState.PriceCustomCategories))

                $skipNamePattern = '^(ZmbF_|ZmbM_|Zmb|StaticObj_|Land_|Wreck_|Fireplace|Bonfire|BanditAI_|TraderPlus_Money_)'

                $report = Sync-UGSMGameDayZTraderPlusPriceConfigWithTypes `
                    -PriceConfigPath $path `
                    -TypesPath $typesPath `
                    -DefaultCategoryName 'AUTO_IMPORTED_ITEMS' `
                    -SkipNamePattern $skipNamePattern `
                    -AddMissingItems `
                    -UpdateStockFromNominal

                & $loadFile
                & $loadPrices

                if ($tpStatusLabel) {
                    $tpStatusLabel.Text = ('TraderPlus sync complete: {0} added, {1} existing/skipped, {2} MaxStock updated from nominal.' -f [int]$report.ItemsAdded, [int]$report.ExistingItemsSkipped, [int]$report.StockValuesUpdated)
                }
            }
            catch {
                if ($tpStatusLabel) { $tpStatusLabel.Text = 'TraderPlus sync from types.xml failed: ' + $_.Exception.Message }
            }
        }.GetNewClosure()

        $resolveIdsPath = {
            $candidate = & $resolveCurrentPath
            if (-not [string]::IsNullOrWhiteSpace([string]$candidate) -and [System.IO.Path]::GetFileName([string]$candidate) -eq 'TraderPlusIDsConfig.json') {
                return [string]$candidate
            }
            foreach ($fileRow in @($tpState.Files)) {
                if ($null -eq $fileRow) { continue }
                if ([string]$fileRow.Name -eq 'TraderPlusIDsConfig.json') { return [string]$fileRow.FullName }
            }
            return ''
        }.GetNewClosure()


        $resolvePriceConfigPathForIds = {
            $candidate = & $resolveCurrentPath
            if (-not [string]::IsNullOrWhiteSpace([string]$candidate) -and [System.IO.Path]::GetFileName([string]$candidate) -eq 'TraderPlusPriceConfig.json') {
                return [string]$candidate
            }
            $idsCandidate = & $resolveIdsPath
            if (-not [string]::IsNullOrWhiteSpace([string]$idsCandidate)) {
                $sibling = Get-UGSMGameDayZTraderPlusSiblingConfigPath -PriceConfigPath $idsCandidate -FileName 'TraderPlusPriceConfig.json'
                if (-not [string]::IsNullOrWhiteSpace([string]$sibling)) { return [string]$sibling }
            }
            foreach ($fileRow in @($tpState.Files)) {
                if ($null -eq $fileRow) { continue }
                if ([string]$fileRow.Name -eq 'TraderPlusPriceConfig.json') { return [string]$fileRow.FullName }
            }
            return ''
        }.GetNewClosure()

        $loadIdCategoryChoices = {
            if ($null -eq $cmbIdCategory) { return }
            try {
                $path = & $resolvePriceConfigPathForIds
                $cmbIdCategory.Items.Clear()
                $names = New-Object System.Collections.ArrayList
                if (-not [string]::IsNullOrWhiteSpace($path) -and (Test-Path -LiteralPath $path)) {
                    $raw = [System.IO.File]::ReadAllText($path)
                    $json = $raw | ConvertFrom-Json -ErrorAction Stop
                    foreach ($cat in @($json.TraderCategories)) {
                        if ($null -eq $cat) { continue }
                        $name = [string]$cat.CategoryName
                        if (-not [string]::IsNullOrWhiteSpace($name) -and -not ($names -contains $name)) { [void]$names.Add($name) }
                    }
                }
                foreach ($name in @($names | Sort-Object)) { [void]$cmbIdCategory.Items.Add([string]$name) }
                if ($cmbIdCategory.Items.Count -gt 0 -and $cmbIdCategory.SelectedIndex -lt 0) { $cmbIdCategory.SelectedIndex = 0 }
            }
            catch {
                if ($tpStatusLabel) { $tpStatusLabel.Text = 'Loading ID category choices failed: ' + $_.Exception.Message }
            }
        }.GetNewClosure()

        $populateIdsGrid = {
            if ($null -eq $gridIds) { return }
            $gridIds.Rows.Clear()
            foreach ($row in @($tpState.IdRows)) {
                if ($null -eq $row) { continue }
                $idx = $gridIds.Rows.Add()
                $gridIds.Rows[$idx].Cells['Id'].Value = [string]$row.Id
                $gridIds.Rows[$idx].Cells['Categories'].Value = [string]::Join('; ', @($row.Categories))
                $gridIds.Rows[$idx].Cells['LicencesRequired'].Value = [string]::Join('; ', @($row.LicencesRequired))
                $gridIds.Rows[$idx].Cells['CurrenciesAccepted'].Value = [string]::Join('; ', @($row.CurrenciesAccepted))
            }
        }.GetNewClosure()

        $loadIds = {
            try {
                $path = & $resolveIdsPath
                if ([string]::IsNullOrWhiteSpace($path)) { throw 'TraderPlusIDsConfig.json was not found for this instance.' }
                $raw = [System.IO.File]::ReadAllText($path)
                $json = $raw | ConvertFrom-Json -ErrorAction Stop
                $rows = New-Object System.Collections.ArrayList
                foreach ($entry in @($json.IDs)) {
                    [void]$rows.Add([pscustomobject]@{
                        Id = [string]$entry.Id
                        Categories = @($entry.Categories)
                        LicencesRequired = @($entry.LicencesRequired)
                        CurrenciesAccepted = @($entry.CurrenciesAccepted)
                    })
                }
                $tpState.IdRows = @($rows)
                & $populateIdsGrid
                & $loadIdCategoryChoices
                $lblPath.Text = $path
                if ($tpStatusLabel) { $tpStatusLabel.Text = ('Loaded TraderPlus IDs rows: ' + $tpState.IdRows.Count) }
            }
            catch {
                if ($tpStatusLabel) { $tpStatusLabel.Text = 'Loading TraderPlus IDs failed: ' + $_.Exception.Message }
            }
        }.GetNewClosure()
        $script:UGSM_TraderPlus_LoadIds = $loadIds

        if (-not ($script:UGSM_TraderPlus_LoadIds -is [scriptblock])) { $script:UGSM_TraderPlus_LoadIds = { } }

        $cmbCategory.Add_SelectedIndexChanged({
                if ($gridPrices -and ($gridPrices.ContainsFocus -or $cmbCategory.ContainsFocus)) { & $syncGridToPriceState }
                if ($null -ne $cmbCategory.SelectedItem) {
                    $tpState.PriceCategory = [string]$cmbCategory.SelectedItem
                }
                else {
                    $tpState.PriceCategory = 'All Categories'
                }
                & $populatePriceGrid
            }.GetNewClosure())

        $txtSearch.Add_TextChanged({
                if ($gridPrices -and ($gridPrices.ContainsFocus -or $txtSearch.ContainsFocus)) { & $syncGridToPriceState }
                $tpState.PriceSearch = [string]$txtSearch.Text
                & $populatePriceGrid
            }.GetNewClosure())

        if ($btnRefresh) { $btnRefresh.Add_Click($refreshFiles) }

        

        

        $updateSelectedIdCategories = {
            param([string]$Mode)
            try {
                if ($null -eq $gridIds -or $gridIds.SelectedRows.Count -le 0) { throw 'Select one or more ID rows first.' }
                $categoryName = ''
                if ($null -ne $cmbIdCategory) { $categoryName = ([string]$cmbIdCategory.Text).Trim() }
                if ([string]::IsNullOrWhiteSpace($categoryName)) { throw 'Select a category first.' }
                $changed = 0
                foreach ($row in @($gridIds.SelectedRows)) {
                    if ($null -eq $row -or $row.IsNewRow) { continue }
                    $existing = New-Object System.Collections.ArrayList
                    foreach ($part in @(([string]$row.Cells['Categories'].Value -split ';'))) {
                        $trimmed = [string]$part
                        if ($null -ne $trimmed) { $trimmed = $trimmed.Trim() }
                        if (-not [string]::IsNullOrWhiteSpace($trimmed) -and -not ($existing -contains $trimmed)) { [void]$existing.Add($trimmed) }
                    }
                    if ($Mode -eq 'Add') {
                        if (-not ($existing -contains $categoryName)) {
                            [void]$existing.Add($categoryName)
                            $row.Cells['Categories'].Value = [string]::Join('; ', @($existing))
                            $changed++
                        }
                    }
                    elseif ($Mode -eq 'Remove') {
                        if ($existing -contains $categoryName) {
                            [void]$existing.Remove($categoryName)
                            $row.Cells['Categories'].Value = [string]::Join('; ', @($existing))
                            $changed++
                        }
                    }
                }
                if ($tpStatusLabel) { $tpStatusLabel.Text = ('ID categories ' + $Mode.ToLowerInvariant() + 'ed on rows: ' + $changed) }
            }
            catch {
                if ($tpStatusLabel) { $tpStatusLabel.Text = 'Updating ID categories failed: ' + $_.Exception.Message }
            }
        }.GetNewClosure()

        


        $saveIds = {
            try {
                $path = & $resolveIdsPath
                if ([string]::IsNullOrWhiteSpace($path)) { throw 'TraderPlusIDsConfig.json was not found for this instance.' }
                $rows = New-Object System.Collections.ArrayList
                foreach ($gridRow in @($gridIds.Rows)) {
                    if ($null -eq $gridRow -or $gridRow.IsNewRow) { continue }
                    $idText = [string]$gridRow.Cells['Id'].Value
                    if ([string]::IsNullOrWhiteSpace($idText)) { continue }
                    [int]$idVal = 0
                    if (-not [int]::TryParse($idText, [ref]$idVal)) { throw ('Invalid trader Id: ' + $idText) }
                    $splitter = {
                        param([string]$s)
                        $items = New-Object System.Collections.ArrayList
                        foreach ($part in @(([string]$s -split ';'))) {
                            $trimmed = [string]$part
                            if ($null -ne $trimmed) { $trimmed = $trimmed.Trim() }
                            if (-not [string]::IsNullOrWhiteSpace($trimmed)) { [void]$items.Add($trimmed) }
                        }
                        return @($items)
                    }
                    [void]$rows.Add([ordered]@{
                        Id = $idVal
                        Categories = @(& $splitter ([string]$gridRow.Cells['Categories'].Value))
                        LicencesRequired = @(& $splitter ([string]$gridRow.Cells['LicencesRequired'].Value))
                        CurrenciesAccepted = @(& $splitter ([string]$gridRow.Cells['CurrenciesAccepted'].Value))
                    })
                }
                $payload = [ordered]@{
                    Version = '2.5'
                    IDs = @($rows)
                }
                [void](Backup-UGSMGameDayZFile -TargetPath $path)
                [void](Write-UGSMGameDayZJsonDataSafe -Path $path -Data $payload)
                $tpState.IdRows = @($rows | ForEach-Object {
                    [pscustomobject]@{
                        Id = [string]$_.Id
                        Categories = @($_.Categories)
                        LicencesRequired = @($_.LicencesRequired)
                        CurrenciesAccepted = @($_.CurrenciesAccepted)
                    }
                })
                & $populateIdsGrid
                $lblPath.Text = $path
                if ($tpStatusLabel) { $tpStatusLabel.Text = ('Saved TraderPlus IDs rows: ' + $tpState.IdRows.Count) }
            }
            catch {
                if ($tpStatusLabel) { $tpStatusLabel.Text = 'Saving TraderPlus IDs failed: ' + $_.Exception.Message }
            }
        }.GetNewClosure()

        $resolveInsurancePath = {
            $candidate = & $resolveCurrentPath
            if (-not [string]::IsNullOrWhiteSpace([string]$candidate) -and [System.IO.Path]::GetFileName([string]$candidate) -eq 'TraderPlusInsuranceConfig.json') {
                return [string]$candidate
            }
            $idsCandidate = & $resolveIdsPath
            if (-not [string]::IsNullOrWhiteSpace([string]$idsCandidate)) {
                $sibling = Get-UGSMGameDayZTraderPlusSiblingConfigPath -PriceConfigPath $idsCandidate -FileName 'TraderPlusInsuranceConfig.json'
                if (-not [string]::IsNullOrWhiteSpace([string]$sibling)) { return [string]$sibling }
            }
            return ''
        }.GetNewClosure()


        $resolveGeneralPath = {
            $candidate = & $resolveCurrentPath
            if (-not [string]::IsNullOrWhiteSpace([string]$candidate) -and [System.IO.Path]::GetFileName([string]$candidate) -eq 'TraderPlusGeneralConfig.json') {
                return [string]$candidate
            }
            foreach ($fileRow in @($tpState.Files)) {
                if ($null -eq $fileRow) { continue }
                if ([string]$fileRow.Name -eq 'TraderPlusGeneralConfig.json') { return [string]$fileRow.FullName }
            }
            return ''
        }.GetNewClosure()

        
        $resolveGeneralTypesPath = {
            $typesPath = ''
            if (Get-Command -Name Resolve-UGSMGameDayZTypesXmlPath -ErrorAction SilentlyContinue) {
                $typesPath = Resolve-UGSMGameDayZTypesXmlPath -Instance $tpInstance
            }
            if ([string]::IsNullOrWhiteSpace($typesPath) -or -not (Test-Path -LiteralPath $typesPath -PathType Leaf)) {
                try {
                    $paths = Get-UGSMGameDayZProfilePaths -Instance $tpInstance
                    foreach ($candidate in @(
                            $paths.RuntimeTypesPath,
                            $(if (-not [string]::IsNullOrWhiteSpace([string]$paths.RuntimeDbPath)) { Join-Path ([string]$paths.RuntimeDbPath) 'types.xml' }),
                            $(if (-not [string]::IsNullOrWhiteSpace([string]$paths.RuntimeMissionPath)) { Join-Path ([string]$paths.RuntimeMissionPath) 'db\types.xml' }),
                            $(if (-not [string]::IsNullOrWhiteSpace([string]$paths.MissionFolderPath)) { Join-Path ([string]$paths.MissionFolderPath) 'db\types.xml' })
                        )) {
                        if (-not [string]::IsNullOrWhiteSpace([string]$candidate) -and (Test-Path -LiteralPath $candidate -PathType Leaf)) {
                            $typesPath = [string]$candidate
                            break
                        }
                    }
                }
                catch { }
            }
            return [string]$typesPath
        }.GetNewClosure()

        $applyGeneralTraderItemFilter = {
            if ($null -eq $cmbTraderItemPicker) { return }
            $cmbTraderItemPicker.BeginUpdate()
            try {
                $cmbTraderItemPicker.Items.Clear()
                $filterText = ''
                if ($txtTraderItemSearch) { $filterText = [string]$txtTraderItemSearch.Text }
                $items = @($tpState.GeneralTraderPickerAllItems)
                if (-not [string]::IsNullOrWhiteSpace($filterText)) {
                    $needle = $filterText.ToLowerInvariant()
                    $items = @($items | Where-Object { ([string]$_).ToLowerInvariant().Contains($needle) })
                }
                foreach ($item in @($items | Select-Object -First 500)) {
                    [void]$cmbTraderItemPicker.Items.Add([string]$item)
                }
                if ($cmbTraderItemPicker.Items.Count -gt 0) { $cmbTraderItemPicker.SelectedIndex = 0 }
            }
            finally {
                $cmbTraderItemPicker.EndUpdate()
            }
        }.GetNewClosure()

        $loadGeneralTraderPickerItems = {
            try {
                $tpState.GeneralTraderPickerAllItems = @()
                $typesPath = & $resolveGeneralTypesPath
                if ([string]::IsNullOrWhiteSpace($typesPath) -or -not (Test-Path -LiteralPath $typesPath -PathType Leaf)) {
                    & $applyGeneralTraderItemFilter
                    return
                }
                $index = Get-UGSMGameDayZTypesItemIndex -TypesPath $typesPath
                $items = @($index.Keys | Sort-Object)
                $tpState.GeneralTraderPickerAllItems = @($items)
                & $applyGeneralTraderItemFilter
            }
            catch {
                $tpState.GeneralTraderPickerAllItems = @()
                & $applyGeneralTraderItemFilter
            }
        }.GetNewClosure()

        $addGeneralTraderItemToSelected = {
            try {
                if ($null -eq $gridGeneralTraders -or $gridGeneralTraders.SelectedRows.Count -le 0) { throw 'Select one or more trader rows first.' }
                $selectedItem = ''
                if ($null -ne $cmbTraderItemPicker.SelectedItem) { $selectedItem = [string]$cmbTraderItemPicker.SelectedItem }
                elseif ($cmbTraderItemPicker.Text) { $selectedItem = [string]$cmbTraderItemPicker.Text }
                $selectedItem = $selectedItem.Trim()
                if ([string]::IsNullOrWhiteSpace($selectedItem)) { throw 'Select an item to add to the trader.' }

                $updated = 0
                foreach ($row in @($gridGeneralTraders.SelectedRows)) {
                    if ($null -eq $row -or $row.IsNewRow) { continue }
                    $existing = [string]$row.Cells['Clothes'].Value
                    $parts = @()
                    foreach ($part in @($existing -split ';')) {
                        $value = ([string]$part).Trim()
                        if (-not [string]::IsNullOrWhiteSpace($value) -and -not ($parts -contains $value)) { $parts += $value }
                    }
                    if (-not ($parts -contains $selectedItem)) {
                        $parts += $selectedItem
                        $row.Cells['Clothes'].Value = [string]::Join('; ', @($parts))
                        $updated++
                    }
                }
                if ($tpStatusLabel) { $tpStatusLabel.Text = ("Added '{0}' to {1} trader row(s)." -f $selectedItem, $updated) }
            }
            catch {
                if ($tpStatusLabel) { $tpStatusLabel.Text = 'Add trader item failed: ' + $_.Exception.Message }
            }
        }.GetNewClosure()

$populateGeneralGrids = {
            if ($null -ne $gridGeneralCurrencies) {
                $gridGeneralCurrencies.Rows.Clear()
                foreach ($row in @($tpState.GeneralCurrencies)) {
                    [void]$gridGeneralCurrencies.Rows.Add([string]$row.ClassName, [string]$row.Value)
                }
            }
            if ($null -ne $gridGeneralTraders) {
                $gridGeneralTraders.Rows.Clear()
                foreach ($row in @($tpState.GeneralTraders)) {
                    $idx = $gridGeneralTraders.Rows.Add([string]$row.Id, [string]$row.Name, [string]$row.GivenName, [string]$row.Role, [string]$row.Position, [string]$row.Orientation, [string]$row.Clothes)
                    $val = [string]$row.Name
                    if (-not [string]::IsNullOrWhiteSpace($val) -and -not $gridGeneralTraders.Columns['Name'].Items.Contains($val)) {
                        [void]$gridGeneralTraders.Columns['Name'].Items.Add($val)
                        $gridGeneralTraders.Rows[$idx].Cells['Name'].Value = $val
                    }
                }
            }
            if ($null -ne $gridGeneralObjects) {
                $gridGeneralObjects.Rows.Clear()
                foreach ($row in @($tpState.GeneralObjects)) {
                    [void]$gridGeneralObjects.Rows.Add([string]$row.ObjectName, [string]$row.Position, [string]$row.Orientation)
                }
            }
        }.GetNewClosure()

        $loadGeneral = {
            try {
                $path = & $resolveGeneralPath
                if ([string]::IsNullOrWhiteSpace($path)) { throw 'TraderPlusGeneralConfig.json was not found for this instance.' }
                $json = ([System.IO.File]::ReadAllText($path) | ConvertFrom-Json)
                $tpState.GeneralSettings = [ordered]@{
                    ConvertTraderConfigToTraderPlus = [int]$json.ConvertTraderConfigToTraderPlus
                    ConvertTraderConfigToTraderPlusWithStockBasedOnCE = [int]$json.ConvertTraderConfigToTraderPlusWithStockBasedOnCE
                    UseGarageToTradeCar = [int]$json.UseGarageToTradeCar
                    DisableHeightFailSafeForReceiptDeployment = [int]$json.DisableHeightFailSafeForReceiptDeployment
                    HideInsuranceBtn = [int]$json.HideInsuranceBtn
                    HideGarageBtn = [int]$json.HideGarageBtn
                    HideLicenceBtn = [int]$json.HideLicenceBtn
                    EnableShowAllPrices = [int]$json.EnableShowAllPrices
                    EnableShowAllCheckBox = [int]$json.EnableShowAllCheckBox
                    IsReceiptTraderOnly = [int]$json.IsReceiptTraderOnly
                    IsReceiptSaveLock = [int]$json.IsReceiptSaveLock
                    IsReceiptSaveAttachment = [int]$json.IsReceiptSaveAttachment
                    IsReceiptSaveCargo = [int]$json.IsReceiptSaveCargo
                    StoreOnlyToPristineState = [int]$json.StoreOnlyToPristineState
                }
                foreach ($k in @($generalCheckboxes.Keys)) {
                    if ($generalCheckboxes[$k]) { $generalCheckboxes[$k].Checked = ([int]$tpState.GeneralSettings[$k] -eq 1) }
                }
                $txtGeneralLicenceKeyword.Text = [string]$json.LicenceKeyWord
                $txtGeneralLockPickChance.Text = [string]$json.LockPickChance
                $txtGeneralLicences.Text = [string]::Join('; ', @($json.Licences))
                $acc = $json.AcceptedStates
                $chkAcceptWorn.Checked = ([int]$acc.AcceptWorn -eq 1)
                $chkAcceptDamaged.Checked = ([int]$acc.AcceptDamaged -eq 1)
                $chkAcceptBadlyDamaged.Checked = ([int]$acc.AcceptBadlyDamaged -eq 1)
                $txtCoefWorn.Text = [string]$acc.CoefficientWorn
                $txtCoefDamaged.Text = [string]$acc.CoefficientDamaged
                $txtCoefBadlyDamaged.Text = [string]$acc.CoefficientBadlyDamaged

                $tpState.GeneralCurrencies = @(@($json.Currencies) | ForEach-Object { [pscustomobject]@{ ClassName=[string]$_.ClassName; Value=[string]$_.Value } })
                $tpState.GeneralTraders = @(@($json.Traders) | ForEach-Object {
                    [pscustomobject]@{
                        Id=[string]$_.Id; Name=[string]$_.Name; GivenName=[string]$_.GivenName; Role=[string]$_.Role;
                        Position=([string]::Join('; ', @($_.Position | ForEach-Object { [string]$_ })));
                        Orientation=([string]::Join('; ', @($_.Orientation | ForEach-Object { [string]$_ })));
                        Clothes=([string]::Join('; ', @($_.Clothes | ForEach-Object { [string]$_ })))
                    }
                })
                $tpState.GeneralObjects = @(@($json.TraderObjects) | ForEach-Object {
                    [pscustomobject]@{
                        ObjectName=[string]$_.ObjectName;
                        Position=([string]::Join('; ', @($_.Position | ForEach-Object { [string]$_ })));
                        Orientation=([string]::Join('; ', @($_.Orientation | ForEach-Object { [string]$_ })))
                    }
                })
                & $populateGeneralGrids
                & $loadGeneralTraderPickerItems
                $lblPath.Text = $path
                if ($tpStatusLabel) { $tpStatusLabel.Text = ('Loaded TraderPlus General config.') }
            } catch {
                if ($tpStatusLabel) { $tpStatusLabel.Text = 'Loading TraderPlus General failed: ' + $_.Exception.Message }
            }
        }.GetNewClosure()

        $saveGeneral = {
            try {
                $path = & $resolveGeneralPath
                if ([string]::IsNullOrWhiteSpace($path)) { throw 'TraderPlusGeneralConfig.json was not found for this instance.' }
                [double]$lockPick = 0
                [double]$coefWorn = 0
                [double]$coefDamaged = 0
                [double]$coefBadly = 0
                if (-not [double]::TryParse([string]$txtGeneralLockPickChance.Text, [System.Globalization.NumberStyles]::Float, [System.Globalization.CultureInfo]::InvariantCulture, [ref]$lockPick)) { throw 'Invalid LockPickChance.' }
                if (-not [double]::TryParse([string]$txtCoefWorn.Text, [System.Globalization.NumberStyles]::Float, [System.Globalization.CultureInfo]::InvariantCulture, [ref]$coefWorn)) { throw 'Invalid CoefficientWorn.' }
                if (-not [double]::TryParse([string]$txtCoefDamaged.Text, [System.Globalization.NumberStyles]::Float, [System.Globalization.CultureInfo]::InvariantCulture, [ref]$coefDamaged)) { throw 'Invalid CoefficientDamaged.' }
                if (-not [double]::TryParse([string]$txtCoefBadlyDamaged.Text, [System.Globalization.NumberStyles]::Float, [System.Globalization.CultureInfo]::InvariantCulture, [ref]$coefBadly)) { throw 'Invalid CoefficientBadlyDamaged.' }

                $splitList = {
                    param([string]$value)
                    $out = New-Object System.Collections.ArrayList
                    foreach ($part in @($value -split ';|,')) {
                        $trim = [string]$part
                        if ($null -ne $trim) { $trim = $trim.Trim() }
                        if ([string]::IsNullOrWhiteSpace($trim)) { continue }
                        [void]$out.Add($trim)
                    }
                    return @($out)
                }

                $currencies = New-Object System.Collections.ArrayList
                foreach ($row in @($gridGeneralCurrencies.Rows)) {
                    if ($null -eq $row -or $row.IsNewRow) { continue }
                    $className = ([string]$row.Cells['ClassName'].Value).Trim()
                    if ([string]::IsNullOrWhiteSpace($className)) { continue }
                    [int]$v = 0
                    if (-not [int]::TryParse(([string]$row.Cells['Value'].Value).Trim(), [ref]$v)) { throw ('Invalid currency value for ' + $className) }
                    [void]$currencies.Add([ordered]@{ ClassName=$className; Value=$v })
                }

                $traders = New-Object System.Collections.ArrayList
                foreach ($row in @($gridGeneralTraders.Rows)) {
                    if ($null -eq $row -or $row.IsNewRow) { continue }
                    $name = ([string]$row.Cells['Name'].Value).Trim()
                    if ([string]::IsNullOrWhiteSpace($name)) { continue }
                    [int]$idv = 0
                    if (-not [int]::TryParse(([string]$row.Cells['Id'].Value).Trim(), [ref]$idv)) { throw ('Invalid trader Id for ' + $name) }
                    $pos = @(& $splitList ([string]$row.Cells['Position'].Value) | ForEach-Object { [double]$_ })
                    $ori = @(& $splitList ([string]$row.Cells['Orientation'].Value) | ForEach-Object { [double]$_ })
                    $clothes = @(& $splitList ([string]$row.Cells['Clothes'].Value))
                    [void]$traders.Add([ordered]@{
                        Id=$idv; Name=$name; GivenName=([string]$row.Cells['GivenName'].Value).Trim(); Role=([string]$row.Cells['Role'].Value).Trim();
                        Position=@($pos); Orientation=@($ori); Clothes=@($clothes)
                    })
                }

                $objects = New-Object System.Collections.ArrayList
                foreach ($row in @($gridGeneralObjects.Rows)) {
                    if ($null -eq $row -or $row.IsNewRow) { continue }
                    $objName = ([string]$row.Cells['ObjectName'].Value).Trim()
                    if ([string]::IsNullOrWhiteSpace($objName)) { continue }
                    $pos = @(& $splitList ([string]$row.Cells['Position'].Value) | ForEach-Object { [double]$_ })
                    $ori = @(& $splitList ([string]$row.Cells['Orientation'].Value) | ForEach-Object { [double]$_ })
                    [void]$objects.Add([ordered]@{ ObjectName=$objName; Position=@($pos); Orientation=@($ori) })
                }

                $payload = [ordered]@{
                    Version = '2.5'
                    ConvertTraderConfigToTraderPlus = $(if ($generalCheckboxes['ConvertTraderConfigToTraderPlus'].Checked) {1} else {0})
                    ConvertTraderConfigToTraderPlusWithStockBasedOnCE = $(if ($generalCheckboxes['ConvertTraderConfigToTraderPlusWithStockBasedOnCE'].Checked) {1} else {0})
                    UseGarageToTradeCar = $(if ($generalCheckboxes['UseGarageToTradeCar'].Checked) {1} else {0})
                    DisableHeightFailSafeForReceiptDeployment = $(if ($generalCheckboxes['DisableHeightFailSafeForReceiptDeployment'].Checked) {1} else {0})
                    HideInsuranceBtn = $(if ($generalCheckboxes['HideInsuranceBtn'].Checked) {1} else {0})
                    HideGarageBtn = $(if ($generalCheckboxes['HideGarageBtn'].Checked) {1} else {0})
                    HideLicenceBtn = $(if ($generalCheckboxes['HideLicenceBtn'].Checked) {1} else {0})
                    EnableShowAllPrices = $(if ($generalCheckboxes['EnableShowAllPrices'].Checked) {1} else {0})
                    EnableShowAllCheckBox = $(if ($generalCheckboxes['EnableShowAllCheckBox'].Checked) {1} else {0})
                    IsReceiptTraderOnly = $(if ($generalCheckboxes['IsReceiptTraderOnly'].Checked) {1} else {0})
                    IsReceiptSaveLock = $(if ($generalCheckboxes['IsReceiptSaveLock'].Checked) {1} else {0})
                    IsReceiptSaveAttachment = $(if ($generalCheckboxes['IsReceiptSaveAttachment'].Checked) {1} else {0})
                    IsReceiptSaveCargo = $(if ($generalCheckboxes['IsReceiptSaveCargo'].Checked) {1} else {0})
                    LockPickChance = $lockPick
                    LicenceKeyWord = [string]$txtGeneralLicenceKeyword.Text
                    Licences = @(& $splitList ([string]$txtGeneralLicences.Text))
                    AcceptedStates = [ordered]@{
                        AcceptWorn = $(if ($chkAcceptWorn.Checked) {1} else {0})
                        AcceptDamaged = $(if ($chkAcceptDamaged.Checked) {1} else {0})
                        AcceptBadlyDamaged = $(if ($chkAcceptBadlyDamaged.Checked) {1} else {0})
                        CoefficientWorn = $coefWorn
                        CoefficientDamaged = $coefDamaged
                        CoefficientBadlyDamaged = $coefBadly
                    }
                    StoreOnlyToPristineState = $(if ($generalCheckboxes['StoreOnlyToPristineState'].Checked) {1} else {0})
                    Currencies = @($currencies)
                    Traders = @($traders)
                    TraderObjects = @($objects)
                }
                [void](Backup-UGSMGameDayZFile -TargetPath $path)
                [void](Write-UGSMGameDayZJsonDataSafe -Path $path -Data $payload)
                & $loadGeneral
                if ($tpStatusLabel) { $tpStatusLabel.Text = 'Saved TraderPlus General config.' }
            } catch {
                if ($tpStatusLabel) { $tpStatusLabel.Text = 'Saving TraderPlus General failed: ' + $_.Exception.Message }
            }
        }.GetNewClosure()


        $populateInsuranceGrid = {
            if ($null -eq $gridInsurance) { return }
            $gridInsurance.Rows.Clear()
            foreach ($row in @($tpState.InsuranceRows)) {
                $vehicleName = ''
                $insuranceCoef = ''
                $collateralCoef = ''
                if ($null -ne $row) {
                    $vehicleName = [string]$row.VehicleName
                    $insuranceCoef = [string]$row.InsurancePriceCoefficient
                    $collateralCoef = [string]$row.CollateralMoneyCoefficient
                }
                [void]$gridInsurance.Rows.Add($vehicleName, $insuranceCoef, $collateralCoef)
            }
            if ($null -ne $txtAuthorizedInsuranceIds) {
                $txtAuthorizedInsuranceIds.Text = [string]::Join('; ', @($tpState.InsuranceAuthorizedIds | ForEach-Object { [string]$_ }))
            }
        }.GetNewClosure()

        $loadInsurance = {
            try {
                $path = & $resolveInsurancePath
                if ([string]::IsNullOrWhiteSpace($path)) { throw 'TraderPlusInsuranceConfig.json was not found for this instance.' }
                $raw = [System.IO.File]::ReadAllText($path)
                $json = $raw | ConvertFrom-Json
                $rows = New-Object System.Collections.ArrayList
                foreach ($entry in @($json.Insurances)) {
                    if ($null -eq $entry) { continue }
                    [void]$rows.Add([pscustomobject]@{
                        VehicleName = [string]$entry.VehicleName
                        InsurancePriceCoefficient = [string]$entry.InsurancePriceCoefficient
                        CollateralMoneyCoefficient = [string]$entry.CollateralMoneyCoefficient
                    })
                }
                $tpState.InsuranceRows = @($rows)
                $tpState.InsuranceAuthorizedIds = @($json.AuthorizedIDInsurance)
                & $populateInsuranceGrid
                $lblPath.Text = $path
                if ($tpStatusLabel) { $tpStatusLabel.Text = ('Loaded TraderPlus Insurance rows: ' + $tpState.InsuranceRows.Count) }
            }
            catch {
                if ($tpStatusLabel) { $tpStatusLabel.Text = 'Loading TraderPlus Insurance failed: ' + $_.Exception.Message }
            }
        }.GetNewClosure()

        $saveInsurance = {
            try {
                $path = & $resolveInsurancePath
                if ([string]::IsNullOrWhiteSpace($path)) { throw 'TraderPlusInsuranceConfig.json was not found for this instance.' }
                $authorizedIds = New-Object System.Collections.ArrayList
                foreach ($part in @(([string]$txtAuthorizedInsuranceIds.Text -split ';|,'))) {
                    $trimmed = [string]$part
                    if ($null -ne $trimmed) { $trimmed = $trimmed.Trim() }
                    if ([string]::IsNullOrWhiteSpace($trimmed)) { continue }
                    [int]$idVal = 0
                    if (-not [int]::TryParse($trimmed, [ref]$idVal)) { throw ('Invalid authorized insurance Id: ' + $trimmed) }
                    if (-not ($authorizedIds -contains $idVal)) { [void]$authorizedIds.Add($idVal) }
                }

                $rows = New-Object System.Collections.ArrayList
                foreach ($gridRow in @($gridInsurance.Rows)) {
                    if ($null -eq $gridRow -or $gridRow.IsNewRow) { continue }
                    $vehicleName = ([string]$gridRow.Cells['VehicleName'].Value).Trim()
                    if ([string]::IsNullOrWhiteSpace($vehicleName)) { continue }
                    [double]$insuranceCoef = 0
                    [double]$collateralCoef = 0
                    $insuranceText = ([string]$gridRow.Cells['InsurancePriceCoefficient'].Value).Trim()
                    $collateralText = ([string]$gridRow.Cells['CollateralMoneyCoefficient'].Value).Trim()
                    if (-not [double]::TryParse($insuranceText, [System.Globalization.NumberStyles]::Float, [System.Globalization.CultureInfo]::InvariantCulture, [ref]$insuranceCoef)) { throw ('Invalid InsurancePriceCoefficient for ' + $vehicleName) }
                    if (-not [double]::TryParse($collateralText, [System.Globalization.NumberStyles]::Float, [System.Globalization.CultureInfo]::InvariantCulture, [ref]$collateralCoef)) { throw ('Invalid CollateralMoneyCoefficient for ' + $vehicleName) }
                    [void]$rows.Add([ordered]@{
                        VehicleName = $vehicleName
                        InsurancePriceCoefficient = $insuranceCoef
                        CollateralMoneyCoefficient = $collateralCoef
                    })
                }

                $payload = [ordered]@{
                    Version = '2.5'
                    AuthorizedIDInsurance = @($authorizedIds)
                    Insurances = @($rows)
                }
                [void](Backup-UGSMGameDayZFile -TargetPath $path)
                [void](Write-UGSMGameDayZJsonDataSafe -Path $path -Data $payload)

                $tpState.InsuranceRows = @($rows | ForEach-Object {
                    [pscustomobject]@{
                        VehicleName = [string]$_.VehicleName
                        InsurancePriceCoefficient = [string]$_.InsurancePriceCoefficient
                        CollateralMoneyCoefficient = [string]$_.CollateralMoneyCoefficient
                    }
                })
                $tpState.InsuranceAuthorizedIds = @($authorizedIds)
                & $populateInsuranceGrid
                $lblPath.Text = $path
                if ($tpStatusLabel) { $tpStatusLabel.Text = ('Saved TraderPlus Insurance rows: ' + $tpState.InsuranceRows.Count) }
            }
            catch {
                if ($tpStatusLabel) { $tpStatusLabel.Text = 'Saving TraderPlus Insurance failed: ' + $_.Exception.Message }
            }
        }.GetNewClosure()

        if ($btnLoad) { $btnLoad.Add_Click($loadFile) }
        if ($btnSaveJson) { $btnSaveJson.Add_Click($saveFile) }
        if ($btnBackup) { $btnBackup.Add_Click($backupFile) }
        if ($btnPretty) { $btnPretty.Add_Click($prettyPrint) }
        if ($btnMerge) { $btnMerge.Add_Click($mergeFile) }
        if ($btnLoadPrices) { $btnLoadPrices.Add_Click($loadPrices) }
        if ($btnSavePrices) { $btnSavePrices.Add_Click($savePrices) }
        if ($btnBackupPrices) { $btnBackupPrices.Add_Click($backupFile) }
        if ($btnMergePrices) { $btnMergePrices.Add_Click($mergeFile) }
        if ($btnSyncPrices) { $btnSyncPrices.Add_Click($syncPricesFromTypes) }
        if ($btnLoadIds) { $btnLoadIds.Add_Click($loadIds) }
        if ($btnSaveIds) { $btnSaveIds.Add_Click($saveIds) }
        if ($btnLoadInsurance) { $btnLoadInsurance.Add_Click($loadInsurance) }
        if ($btnSaveInsurance) { $btnSaveInsurance.Add_Click($saveInsurance) }
        if ($btnLoadGeneral) { $btnLoadGeneral.Add_Click($loadGeneral) }
        if ($btnSaveGeneral) { $btnSaveGeneral.Add_Click($saveGeneral) }
        if ($btnAddIdRow) { $btnAddIdRow.Add_Click({ [void]$gridIds.Rows.Add('', '', '', '') }.GetNewClosure()) }
        if ($btnRemoveIdRow) { $btnRemoveIdRow.Add_Click({ foreach ($row in @($gridIds.SelectedRows)) { if ($null -ne $row -and -not $row.IsNewRow) { $gridIds.Rows.Remove($row) } } }.GetNewClosure()) }
        if ($btnAddInsuranceRow) { $btnAddInsuranceRow.Add_Click({ [void]$gridInsurance.Rows.Add('', '', '') }.GetNewClosure()) }
        if ($btnRemoveInsuranceRow) { $btnRemoveInsuranceRow.Add_Click({ foreach ($row in @($gridInsurance.SelectedRows)) { if ($null -ne $row -and -not $row.IsNewRow) { $gridInsurance.Rows.Remove($row) } } }.GetNewClosure()) }
        if ($btnAddCurrencyRow) { $btnAddCurrencyRow.Add_Click({ [void]$gridGeneralCurrencies.Rows.Add('', '') }.GetNewClosure()) }
        if ($btnRemoveCurrencyRow) { $btnRemoveCurrencyRow.Add_Click({ foreach ($row in @($gridGeneralCurrencies.SelectedRows)) { if ($null -ne $row -and -not $row.IsNewRow) { $gridGeneralCurrencies.Rows.Remove($row) } } }.GetNewClosure()) }
        if ($btnAddTraderRow) { $btnAddTraderRow.Add_Click({ [void]$gridGeneralTraders.Rows.Add('', 'TraderPlusSign', '', '', '', '', '') }.GetNewClosure()) }
        if ($btnRemoveTraderRow) { $btnRemoveTraderRow.Add_Click({ foreach ($row in @($gridGeneralTraders.SelectedRows)) { if ($null -ne $row -and -not $row.IsNewRow) { $gridGeneralTraders.Rows.Remove($row) } } }.GetNewClosure()) }
        if ($txtTraderItemSearch) { $txtTraderItemSearch.Add_TextChanged({ & $applyGeneralTraderItemFilter }.GetNewClosure()) }
        if ($btnAddTraderItem) { $btnAddTraderItem.Add_Click({ & $addGeneralTraderItemToSelected }.GetNewClosure()) }
        if ($btnAddObjectRow) { $btnAddObjectRow.Add_Click({ [void]$gridGeneralObjects.Rows.Add('', '', '') }.GetNewClosure()) }
        if ($btnRemoveObjectRow) { $btnRemoveObjectRow.Add_Click({ foreach ($row in @($gridGeneralObjects.SelectedRows)) { if ($null -ne $row -and -not $row.IsNewRow) { $gridGeneralObjects.Rows.Remove($row) } } }.GetNewClosure()) }
        if ($btnIdCategoryAdd) { $btnIdCategoryAdd.Add_Click({ & $updateSelectedIdCategories 'Add' }.GetNewClosure()) }
        if ($btnIdCategoryRemove) { $btnIdCategoryRemove.Add_Click({ & $updateSelectedIdCategories 'Remove' }.GetNewClosure()) }

        $assignPriceCategory = {
            try {
                $path = & $resolveCurrentPath
                if ([string]::IsNullOrWhiteSpace($path)) { throw 'No TraderPlus JSON file is selected.' }
                if ([System.IO.Path]::GetFileName($path) -ne 'TraderPlusPriceConfig.json') { throw 'Select TraderPlusPriceConfig.json in the file picker to assign categories.' }

                $category = ([string]$cmbCategory.Text).Trim()
                if ([string]::IsNullOrWhiteSpace($category) -or $category -eq 'All Categories') {
                    if ($gridPrices.SelectedRows.Count -gt 0) {
                        $category = ([string]$gridPrices.SelectedRows[0].Cells['CategoryName'].Value).Trim()
                    }
                }
                if ([string]::IsNullOrWhiteSpace($category) -or $category -eq 'All Categories') { throw 'Select a real category first.' }

                $tpState.CategoryAssignments = Get-UGSMGameDayZTraderPlusCategoryAssignmentMap -PriceConfigPath $path
                $tpState.TraderRows = @(Get-UGSMGameDayZTraderPlusTraderRows -PriceConfigPath $path)
                if (@($tpState.TraderRows).Count -le 0) { throw 'No TraderPlus trader IDs were found. Add a Trader ID first.' }

                $selectedIds = @()
                if ($tpState.CategoryAssignments.ContainsKey($category)) { $selectedIds = @($tpState.CategoryAssignments[$category]) }

                $newIds = Show-UGSMGameDayZTraderPlusTraderAssignmentDialog -CategoryName $category -TraderRows @($tpState.TraderRows) -SelectedTraderIds $selectedIds
                if ($null -eq $newIds) { return }

                $result = Set-UGSMGameDayZTraderPlusCategoryAssignments -PriceConfigPath $path -CategoryName $category -TraderIds @($newIds)
                $tpState.CategoryAssignments = Get-UGSMGameDayZTraderPlusCategoryAssignmentMap -PriceConfigPath $path
                $tpState.TraderRows = @(Get-UGSMGameDayZTraderPlusTraderRows -PriceConfigPath $path)
                & $populatePriceGrid
                & $loadFile

                if ($tpStatusLabel) { $tpStatusLabel.Text = "Assigned category '$category' to $($result.TraderCount) trader ID(s)." }
            }
            catch {
                if ($tpStatusLabel) { $tpStatusLabel.Text = 'Assigning TraderPlus category failed: ' + $_.Exception.Message }
            }
        }.GetNewClosure()

        $addTraderId = {
            try {
                $path = & $resolveCurrentPath
                if ([string]::IsNullOrWhiteSpace($path)) { throw 'No TraderPlus JSON file is selected.' }
                if ([System.IO.Path]::GetFileName($path) -ne 'TraderPlusPriceConfig.json') { throw 'Select TraderPlusPriceConfig.json first.' }

                $idText = Show-UGSMGameDayZTraderPlusTextPrompt -Title 'Add TraderPlus Trader ID' -Prompt 'Trader ID number:' -DefaultValue ''
                if ([string]::IsNullOrWhiteSpace($idText)) { return }
                $traderId = 0
                if (-not [int]::TryParse(([string]$idText).Trim(), [ref]$traderId)) { throw 'Trader ID must be a number.' }

                $givenName = Show-UGSMGameDayZTraderPlusTextPrompt -Title 'Add TraderPlus Trader ID' -Prompt 'Given name / display name:' -DefaultValue ('Trader ' + $traderId)
                if ($null -eq $givenName) { return }

                $role = Show-UGSMGameDayZTraderPlusTextPrompt -Title 'Add TraderPlus Trader ID' -Prompt 'Trader role:' -DefaultValue 'Custom Trader'
                if ($null -eq $role) { return }

                [void](Add-UGSMGameDayZTraderPlusTraderId -PriceConfigPath $path -TraderId $traderId -GivenName $givenName -Role $role)
                $tpState.CategoryAssignments = Get-UGSMGameDayZTraderPlusCategoryAssignmentMap -PriceConfigPath $path
                $tpState.TraderRows = @(Get-UGSMGameDayZTraderPlusTraderRows -PriceConfigPath $path)
                & $populatePriceGrid
                & $loadFile

                if ($tpStatusLabel) { $tpStatusLabel.Text = "Added/updated TraderPlus trader ID $traderId. Use Assign Category to give it categories." }
            }
            catch {
                if ($tpStatusLabel) { $tpStatusLabel.Text = 'Adding TraderPlus trader ID failed: ' + $_.Exception.Message }
            }
        }.GetNewClosure()

        if ($btnAddPriceCategory) { $btnAddPriceCategory.Add_Click($addPriceCategory) }
        if ($btnMovePriceSelected) { $btnMovePriceSelected.Add_Click($moveSelectedPriceRows) }
        if ($btnAddPriceItem) { $btnAddPriceItem.Add_Click($addPriceItem) }
        if ($btnDeletePriceSelected) { $btnDeletePriceSelected.Add_Click($deleteSelectedPriceRows) }
        if ($btnAssignPriceCategory) { $btnAssignPriceCategory.Add_Click($assignPriceCategory) }
        if ($btnAddTraderId) { $btnAddTraderId.Add_Click($addTraderId) }

        $pricesTab.Add_Enter({
                if ($cmbFile.Items.Count -gt 0) {
                    [void](& $selectManagedFileByName 'TraderPlusPriceConfig.json')
                    & $loadFile
                    & $loadPrices
                }
            }.GetNewClosure())

        $idsTab.Add_Enter({
                if ($cmbFile.Items.Count -gt 0) { [void](& $selectManagedFileByName 'TraderPlusIDsConfig.json') }
                & $loadIds
            }.GetNewClosure())

        $insuranceTab.Add_Enter({
                if ($cmbFile.Items.Count -gt 0) { [void](& $selectManagedFileByName 'TraderPlusInsuranceConfig.json') }
                & $loadInsurance
            }.GetNewClosure())

        $generalTab.Add_Enter({
                if ($cmbFile.Items.Count -gt 0) { [void](& $selectManagedFileByName 'TraderPlusGeneralConfig.json') }
                & $loadGeneral
            }.GetNewClosure())

        $rootPanel.Add_Resize($resizeLayout)

        & $resizeLayout
        & $refreshFiles
        if ($cmbFile.Items.Count -gt 0) {
            [void](& $selectManagedFileByName 'TraderPlusPriceConfig.json')
            & $loadFile

            $shouldLoadPrices = $false
            if ($isPriceConfigSelected -is [scriptblock]) {
                $shouldLoadPrices = [bool](& $isPriceConfigSelected)
            }
            else {
                $shouldLoadPrices = ([System.IO.Path]::GetFileName($targetPath) -eq 'TraderPlusPriceConfig.json')
            }

            if ($shouldLoadPrices) {
                & $loadPrices
            }
        }
    }
    catch {
        $fallback = New-UGSMLabel -Text ('TraderPlus tab failed to initialize: ' + $_.Exception.Message) -X 12 -Y 12 -Width 1400 -Height 24 -FontSize 9 -Color '#FF8A80'
        [void]$Parent.Controls.Add($fallback)
        if ($editorStatusLabel) { $editorStatusLabel.Text = 'TraderPlus tab failed to initialize: ' + $_.Exception.Message }
    }
}