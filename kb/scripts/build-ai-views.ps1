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

function Add-ToMapList {
    param(
        [hashtable]$Map,
        [string]$Key,
        $Value
    )
    if (-not $Map.ContainsKey($Key)) {
        $Map[$Key] = @()
    }
    $Map[$Key] += $Value
}

$repoRoot = Resolve-Path $Root
$viewsRoot = Join-Path $repoRoot "ai\\materialized-views"
Ensure-Directory $viewsRoot

$craftingFiles = Get-ChildItem -Path (Join-Path $repoRoot "content\\relationships\\crafting") -File -Filter *.json | Where-Object { $_.Name -ne "manifest.json" }
$dropFiles = Get-ChildItem -Path (Join-Path $repoRoot "content\\relationships\\drops") -File -Filter *.json | Where-Object { $_.Name -ne "manifest.json" }
$referenceFiles = Get-ChildItem -Path (Join-Path $repoRoot "content\\relationships\\references") -File -Filter *.json | Where-Object { $_.Name -ne "manifest.json" }

$itemToParts = @{}
$partToSources = @{}
$relicToRewards = @{}
$partToRelics = @{}

foreach ($file in $craftingFiles) {
    $json = Read-Json -Path $file.FullName
    if (-not $json.from -or -not $json.to) { continue }
    Add-ToMapList -Map $itemToParts -Key ([string]$json.from) -Value ([ordered]@{
        partId = [string]$json.to
        relationId = [string]$json.id
        values = $json.values
    })
}

foreach ($file in $dropFiles) {
    $json = Read-Json -Path $file.FullName
    if (-not $json.from -or -not $json.to) { continue }
    Add-ToMapList -Map $partToSources -Key ([string]$json.to) -Value ([ordered]@{
        sourceId = [string]$json.from
        relationId = [string]$json.id
        values = $json.values
        conditions = $json.conditions
    })
}

foreach ($file in $referenceFiles) {
    $json = Read-Json -Path $file.FullName
    if ($json.type -ne "relic_reward") { continue }
    Add-ToMapList -Map $relicToRewards -Key ([string]$json.from) -Value ([ordered]@{
        partId = [string]$json.to
        relationId = [string]$json.id
        values = $json.values
        conditions = $json.conditions
    })
    Add-ToMapList -Map $partToRelics -Key ([string]$json.to) -Value ([ordered]@{
        relicId = [string]$json.from
        relationId = [string]$json.id
        values = $json.values
        conditions = $json.conditions
    })
}

$view1 = [ordered]@{
    generatedAt = (Get-Date).ToString("s") + "Z"
    description = "Maps craftable targets to their required parts or resources."
    items = $itemToParts
}
$view2 = [ordered]@{
    generatedAt = (Get-Date).ToString("s") + "Z"
    description = "Maps parts or resources to known source activities, relics, or raw source IDs."
    parts = $partToSources
}
$view3 = [ordered]@{
    generatedAt = (Get-Date).ToString("s") + "Z"
    description = "Maps relic IDs to their reward part records."
    relics = $relicToRewards
}
$view4 = [ordered]@{
    generatedAt = (Get-Date).ToString("s") + "Z"
    description = "Maps reward parts to relics that contain them."
    parts = $partToRelics
}

$view1 | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath (Join-Path $viewsRoot "item-to-parts.view.json")
$view2 | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath (Join-Path $viewsRoot "part-to-sources.view.json")
$view3 | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath (Join-Path $viewsRoot "relic-to-rewards.view.json")
$view4 | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath (Join-Path $viewsRoot "part-to-relics.view.json")

Write-Host "Generated AI materialized views." -ForegroundColor Green
