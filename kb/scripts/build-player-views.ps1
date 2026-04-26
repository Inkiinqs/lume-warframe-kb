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
$viewsRoot = Join-Path $repoRoot "ai\\materialized-views"
Ensure-Directory $viewsRoot

$inventoryPath = Join-Path $repoRoot "player\\inventory-tracking\\demo-account-inventory.json"
$wishlistPath = Join-Path $repoRoot "player\\wishlist\\demo-account-wishlist.json"
$progressPath = Join-Path $repoRoot "player\\progression\\demo-account-progression.json"
$partsViewPath = Join-Path $viewsRoot "item-to-parts.view.json"
$sourcesViewPath = Join-Path $viewsRoot "part-to-sources.view.json"
$relicsViewPath = Join-Path $viewsRoot "part-to-relics.view.json"

$inventory = Read-Json -Path $inventoryPath
$wishlist = Read-Json -Path $wishlistPath
$progress = Read-Json -Path $progressPath
$itemToParts = Read-Json -Path $partsViewPath
$partToSources = Read-Json -Path $sourcesViewPath
$partToRelics = Read-Json -Path $relicsViewPath

$ownedMap = @{}
foreach ($entry in @($inventory.data.owned)) {
    $ownedMap[[string]$entry.itemId] = $entry
}

$missingTargets = @()
foreach ($target in @($wishlist.data.targets)) {
    $targetId = [string]$target.itemId
    $neededParts = @()
    if ($itemToParts.items.PSObject.Properties.Name -contains $targetId) {
        $neededParts = @($itemToParts.items.$targetId)
    }

    $missingParts = @()
    foreach ($part in $neededParts) {
        if (-not $ownedMap.ContainsKey([string]$part.partId)) {
            $sources = @()
            if ($partToSources.parts.PSObject.Properties.Name -contains [string]$part.partId) {
                $sources = @($partToSources.parts.([string]$part.partId))
            }
            $relics = @()
            if ($partToRelics.parts.PSObject.Properties.Name -contains [string]$part.partId) {
                $relics = @($partToRelics.parts.([string]$part.partId))
            }
            $missingParts += [ordered]@{
                partId = [string]$part.partId
                sources = $sources
                relics = $relics
            }
        }
    }

    $missingTargets += [ordered]@{
        targetId = $targetId
        priority = $target.priority
        reason = $target.reason
        missingParts = $missingParts
    }
}

$farmableNow = @()
foreach ($target in $missingTargets) {
    $farmableParts = @()
    foreach ($part in @($target.missingParts)) {
        $availableSources = @($part.sources | Where-Object {
            $sourceId = [string]$_.sourceId
            if ($sourceId -like "activity.*") {
                return $progress.data.unlockedActivities -contains $sourceId
            }
            return $true
        })
        $farmableParts += [ordered]@{
            partId = $part.partId
            currentlyAccessibleSources = $availableSources
            relics = $part.relics
        }
    }
    $farmableNow += [ordered]@{
        targetId = $target.targetId
        farmableParts = $farmableParts
    }
}

$view = [ordered]@{
    generatedAt = (Get-Date).ToString("s") + "Z"
    playerId = [string]$inventory.playerId
    description = "Player-aware crafting and farming hints derived from owned inventory and wishlist targets."
    missingTargets = $missingTargets
    farmableNow = $farmableNow
}

$outPath = Join-Path $viewsRoot "player-missing-targets.view.json"
$view | ConvertTo-Json -Depth 14 | Set-Content -LiteralPath $outPath

$ownedSummary = [ordered]@{
    generatedAt = (Get-Date).ToString("s") + "Z"
    playerId = [string]$inventory.playerId
    description = "Flattened owned inventory keyed by canonical item ID for overlay and assistant queries."
    items = @{}
}

foreach ($entry in @($inventory.data.owned)) {
    $ownedSummary.items[[string]$entry.itemId] = [ordered]@{
        quantity = $entry.quantity
        mastered = $entry.mastered
        maxRankOwned = $entry.maxRankOwned
        lastSeenConfidence = $entry.lastSeenConfidence
        lastSeenRawLabel = $entry.lastSeenRawLabel
        lastSeenAt = $entry.lastSeenAt
    }
}

$ownedSummary | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath (Join-Path $viewsRoot "player-owned-summary.view.json")

Write-Host "Generated player-aware materialized views." -ForegroundColor Green
