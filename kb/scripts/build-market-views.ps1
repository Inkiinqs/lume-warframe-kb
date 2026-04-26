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

$repoRoot = Resolve-Path $Root
$normalizedPath = Join-Path $repoRoot "imports\\market\\normalized\\market-summary.json"
$viewsRoot = Join-Path $repoRoot "ai\\materialized-views"
Ensure-Directory $viewsRoot

if (-not (Test-Path -LiteralPath $normalizedPath)) {
    Write-Host "No normalized market snapshots found; skipping market view build." -ForegroundColor Yellow
    exit 0
}

$summary = Read-Json -Path $normalizedPath
$items = @{}

foreach ($item in @($summary.items)) {
    $latestOrders = @($item.snapshots.orders | Sort-Object { [datetime]$_.capturedAt } -Descending | Select-Object -First 1)
    $latestStats = @($item.snapshots.statistics | Sort-Object { [datetime]$_.capturedAt } -Descending | Select-Object -First 1)

    $items[[string]$item.canonicalItemId] = [ordered]@{
        marketItemIds = @($item.marketItemIds)
        latestOrders = if ($latestOrders.Count -gt 0) { $latestOrders[0].summary } else { $null }
        latestStatistics = if ($latestStats.Count -gt 0) {
            [ordered]@{
                rolling7d = $latestStats[0].rolling7d
                rolling48h = $latestStats[0].rolling48h
            }
        } else { $null }
    }
}

$view = [ordered]@{
    generatedAt = (Get-Date).ToString("s") + "Z"
    description = "Maps canonical items to latest normalized market snapshots."
    items = $items
}

$outPath = Join-Path $viewsRoot "market-summary.view.json"
$view | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $outPath

Write-Host "Generated market materialized view." -ForegroundColor Green
