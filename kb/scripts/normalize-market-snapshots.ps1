param(
    [string]$Root = "."
)

$ErrorActionPreference = "Stop"

function Read-Json {
    param([string]$Path)
    Get-Content -Raw -LiteralPath $Path | ConvertFrom-Json
}

function Ensure-Directory {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) {
        New-Item -ItemType Directory -Force -Path $Path | Out-Null
    }
}

function Get-OrderSummary {
    param($Snapshot)

    $buy = @($Snapshot.payload.buyOrders)
    $sell = @($Snapshot.payload.sellOrders)

    $buyPrices = @($buy | ForEach-Object { [double]$_.price })
    $sellPrices = @($sell | ForEach-Object { [double]$_.price })

    return [ordered]@{
        bestBuy = if ($buyPrices.Count -gt 0) { ($buyPrices | Measure-Object -Maximum).Maximum } else { $null }
        bestSell = if ($sellPrices.Count -gt 0) { ($sellPrices | Measure-Object -Minimum).Minimum } else { $null }
        buyOrderCount = $buy.Count
        sellOrderCount = $sell.Count
        spread = if ($buyPrices.Count -gt 0 -and $sellPrices.Count -gt 0) { (($sellPrices | Measure-Object -Minimum).Minimum - ($buyPrices | Measure-Object -Maximum).Maximum) } else { $null }
    }
}

function Get-StatisticsSummary {
    param($Snapshot)

    if ($Snapshot.payload.PSObject.Properties.Name -contains "rolling7d" -or $Snapshot.payload.PSObject.Properties.Name -contains "rolling48h") {
        return [ordered]@{
            rolling7d = $Snapshot.payload.rolling7d
            rolling48h = $Snapshot.payload.rolling48h
        }
    }

    if (
        $Snapshot.payload.PSObject.Properties.Name -contains "payload" -and
        $Snapshot.payload.payload.PSObject.Properties.Name -contains "statistics_closed"
    ) {
        $closed = $Snapshot.payload.payload.statistics_closed
        $series48h = @()
        $series7d = @()

        if ($closed.PSObject.Properties.Name -contains "48hours") {
            $series48h = @($closed.'48hours')
        }
        if ($closed.PSObject.Properties.Name -contains "90days") {
            $series7d = @($closed.'90days' | Select-Object -Last 7)
        }

        $latest48h = @($series48h | Select-Object -Last 1)
        $latest7d = @($series7d | Select-Object -Last 1)

        return [ordered]@{
            rolling7d = if ($latest7d.Count -gt 0) {
                [ordered]@{
                    median = $latest7d[0].median
                    volume = ($series7d | Measure-Object volume -Sum).Sum
                    avgPrice = $latest7d[0].avg_price
                }
            } else { $null }
            rolling48h = if ($latest48h.Count -gt 0) {
                [ordered]@{
                    median = $latest48h[0].median
                    volume = ($series48h | Measure-Object volume -Sum).Sum
                    avgPrice = $latest48h[0].avg_price
                }
            } else { $null }
        }
    }

    return $null
}

$repoRoot = Resolve-Path $Root
$sourceRoot = Join-Path $repoRoot "imports\\market\\source-snapshots"
$normalizedRoot = Join-Path $repoRoot "imports\\market\\normalized"
Ensure-Directory $normalizedRoot

$inputFiles = Get-ChildItem -Path $sourceRoot -Recurse -File -Filter *.json
$snapshots = @()
foreach ($file in $inputFiles) {
    $json = Read-Json -Path $file.FullName
    if ($json -is [System.Array]) {
        $snapshots += $json
    }
    else {
        $snapshots += ,$json
    }
}

$grouped = $snapshots | Group-Object canonicalItemId
$normalized = @()

foreach ($group in $grouped) {
    if (-not $group.Name) { continue }
    $orders = @($group.Group | Where-Object {
        $_.snapshotType -eq "orders" -and
        $_.payload -and
        ($_.payload.PSObject.Properties.Name -contains "buyOrders" -or $_.payload.PSObject.Properties.Name -contains "sellOrders")
    })
    $stats = @($group.Group | Where-Object {
        $_.snapshotType -eq "statistics" -and
        $_.payload -and
        (
            $_.payload.PSObject.Properties.Name -contains "rolling7d" -or
            $_.payload.PSObject.Properties.Name -contains "rolling48h" -or
            $_.payload.PSObject.Properties.Name -contains "payload"
        )
    })

    $record = [ordered]@{
        canonicalItemId = [string]$group.Name
        marketItemIds = @($group.Group | ForEach-Object { $_.marketItemId } | Sort-Object -Unique)
        snapshots = [ordered]@{
            orders = @($orders | ForEach-Object {
                [ordered]@{
                    id = $_.id
                    capturedAt = $_.capturedAt
                    summary = Get-OrderSummary -Snapshot $_
                }
            })
            statistics = @($stats | ForEach-Object {
                $summary = Get-StatisticsSummary -Snapshot $_
                [ordered]@{
                    id = $_.id
                    capturedAt = $_.capturedAt
                    rolling7d = if ($summary) { $summary.rolling7d } else { $null }
                    rolling48h = if ($summary) { $summary.rolling48h } else { $null }
                }
            })
        }
    }
    $normalized += $record
}

$outPath = Join-Path $normalizedRoot "market-summary.json"
$payload = [ordered]@{
    generatedAt = (Get-Date).ToString("s") + "Z"
    sourceCount = $inputFiles.Count
    items = $normalized
}
$payload | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $outPath

Write-Host "Normalized market snapshots for $($normalized.Count) canonical items." -ForegroundColor Green
