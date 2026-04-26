param(
    [string]$Root = ".",
    [string]$ManifestPath = "imports/overlay-sync/manifests/sample-overlay-import.json"
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

function Merge-OwnedItem {
    param(
        [hashtable]$OwnedMap,
        $Recognized
    )

    $canonicalItemId = [string]$Recognized.canonicalItemId
    if (-not $canonicalItemId) { return }

    $entry = if ($OwnedMap.ContainsKey($canonicalItemId)) {
        $OwnedMap[$canonicalItemId]
    } else {
        [ordered]@{
            itemId = $canonicalItemId
            quantity = 0
        }
    }

    $newQuantity = 0
    if ($Recognized.PSObject.Properties.Name -contains "quantity") {
        $newQuantity = [int]$Recognized.quantity
    }

    if ($newQuantity -gt [int]$entry.quantity) {
        $entry.quantity = $newQuantity
    }

    $entry.lastSeenConfidence = $Recognized.confidence
    $entry.lastSeenRawLabel = $Recognized.rawLabel
    $entry.lastSeenAt = (Get-Date).ToString("s") + "Z"

    $OwnedMap[$canonicalItemId] = $entry
}

$repoRoot = Resolve-Path $Root
$manifest = Read-Json -Path (Join-Path $repoRoot $ManifestPath)
$normalizedDir = Join-Path $repoRoot "imports\\overlay-sync\\normalized"
Ensure-Directory $normalizedDir

$inventoryPath = Join-Path $repoRoot ("player\\inventory-tracking\\" + (($manifest.playerId -replace '^player\.', '') + "-inventory.json"))
if (-not (Test-Path -LiteralPath $inventoryPath)) {
    throw "Player inventory file not found: $inventoryPath"
}

$inventory = Read-Json -Path $inventoryPath
$ownedMap = @{}
foreach ($owned in @($inventory.data.owned)) {
    $ownedMap[[string]$owned.itemId] = [ordered]@{}
    foreach ($property in $owned.PSObject.Properties) {
        $ownedMap[[string]$owned.itemId][$property.Name] = $property.Value
    }
}

$normalizedSnapshots = @()
$unknownItems = @()

foreach ($entry in @($manifest.entries)) {
    $snapshotPath = Join-Path $repoRoot ("imports\\overlay-sync\\" + $entry.snapshotFile)
    $snapshot = Read-Json -Path $snapshotPath

    $normalizedRecognized = @()
    foreach ($recognized in @($snapshot.payload.recognizedItems)) {
        $normalizedRecognized += [ordered]@{
            rawLabel = $recognized.rawLabel
            canonicalItemId = $recognized.canonicalItemId
            quantity = $recognized.quantity
            confidence = $recognized.confidence
        }

        if ($recognized.canonicalItemId) {
            Merge-OwnedItem -OwnedMap $ownedMap -Recognized $recognized
        }
        else {
            $unknownItems += [ordered]@{
                rawLabel = $recognized.rawLabel
                quantity = $recognized.quantity
                confidence = $recognized.confidence
                capturedAt = $snapshot.capturedAt
            }
        }
    }

    $normalizedSnapshots += [ordered]@{
        id = [string]$snapshot.id
        playerId = [string]$snapshot.playerId
        capturedAt = [string]$snapshot.capturedAt
        source = [string]$snapshot.source
        snapshotType = [string]$snapshot.snapshotType
        recognizedItems = $normalizedRecognized
        unknownItems = @($normalizedRecognized | Where-Object { -not $_.canonicalItemId })
        metadata = $snapshot.metadata
    }
}

$inventory.data.owned = @($ownedMap.GetEnumerator() | Sort-Object Name | ForEach-Object { $_.Value })
$inventory.updatedAt = (Get-Date).ToString("s") + "Z"
$inventory.sources = @(
    [ordered]@{
        type = "overlay-sync"
        value = [string]$manifest.id
    }
) + @($inventory.sources | Where-Object { $_.type -ne "overlay-sync" })

$inventory | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $inventoryPath

$normalizedOutput = [ordered]@{
    generatedAt = (Get-Date).ToString("s") + "Z"
    manifestId = [string]$manifest.id
    playerId = [string]$manifest.playerId
    snapshots = $normalizedSnapshots
    unknownItems = $unknownItems
}

$normalizedPath = Join-Path $normalizedDir "latest-overlay-import.json"
$normalizedOutput | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $normalizedPath

Write-Host "Merged overlay inventory into $inventoryPath and wrote normalized snapshot output." -ForegroundColor Green
