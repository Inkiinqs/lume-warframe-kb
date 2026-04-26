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

function As-Array {
    param($Value)
    if ($null -eq $Value) { return @() }
    return @($Value)
}

$repoRoot = Resolve-Path $Root
$viewsRoot = Join-Path $repoRoot "ai\\materialized-views"
Ensure-Directory $viewsRoot

$factionFiles = Get-ChildItem -Path (Join-Path $repoRoot "content\\world\\factions") -File -Filter *.json |
    Where-Object { $_.Name -ne "manifest.json" }
$enemyFiles = Get-ChildItem -Path (Join-Path $repoRoot "content\\world\\enemies") -File -Filter *.json |
    Where-Object { $_.Name -ne "manifest.json" }

$factions = @{}
foreach ($file in $factionFiles) {
    $json = Read-Json -Path $file.FullName
    $factions[[string]$json.id] = $json
}

$factionView = [ordered]@{
    generatedAt = (Get-Date).ToString("s") + "Z"
    description = "High-level combat guidance by faction for build and matchup reasoning."
    factions = @{}
}

foreach ($pair in $factions.GetEnumerator()) {
    $faction = $pair.Value
    $factionView.factions[[string]$faction.id] = [ordered]@{
        name = [string]$faction.name
        commonTraits = @(As-Array $faction.mechanics.commonTraits)
        defenseLayers = @(As-Array $faction.mechanics.defenseLayers)
        recommendedDamage = @(As-Array $faction.mechanics.recommendedDamage)
        recommendedStatusPlan = @(As-Array $faction.mechanics.recommendedStatusPlan)
        cautions = @(As-Array $faction.mechanics.cautions)
        benchmarkEnemies = @($faction.relationships | Where-Object { $_ -like "enemy.*" })
    }
}

$enemyView = [ordered]@{
    generatedAt = (Get-Date).ToString("s") + "Z"
    description = "Enemy-level combat matchups composed from enemy and faction benchmark data."
    enemies = @{}
}

foreach ($file in $enemyFiles) {
    $enemy = Read-Json -Path $file.FullName
    $factionId = [string]$enemy.mechanics.faction
    $faction = if ($factions.ContainsKey($factionId)) { $factions[$factionId] } else { $null }

    $enemyView.enemies[[string]$enemy.id] = [ordered]@{
        name = [string]$enemy.name
        factionId = $factionId
        factionName = if ($faction) { [string]$faction.name } else { $null }
        combatRole = [string]$enemy.mechanics.combatRole
        defenseProfile = @(As-Array $enemy.mechanics.defenseProfile)
        priorityThreats = @(As-Array $enemy.mechanics.priorityThreats)
        recommendedDamage = @(As-Array $enemy.mechanics.recommendedDamage)
        recommendedStatusPlan = @(As-Array $enemy.mechanics.recommendedStatusPlan)
        inheritedFactionPlan = if ($faction) { @(As-Array $faction.mechanics.recommendedStatusPlan) } else { @() }
        inheritedFactionCautions = if ($faction) { @(As-Array $faction.mechanics.cautions) } else { @() }
        relatedSystems = @($enemy.relationships | Where-Object { $_ -like "damage.*" -or $_ -like "status.*" })
    }
}

$factionView | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath (Join-Path $viewsRoot "faction-combat-profiles.view.json")
$enemyView | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath (Join-Path $viewsRoot "enemy-matchups.view.json")

Write-Host "Generated combat materialized views." -ForegroundColor Green
