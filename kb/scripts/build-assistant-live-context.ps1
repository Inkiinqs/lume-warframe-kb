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

function Has-Property {
    param($Object, [string]$Name)
    return $Object -and ($Object.PSObject.Properties.Name -contains $Name)
}

function Get-ObjectValue {
    param($Object, [string]$Name, $Default = $null)
    if (Has-Property -Object $Object -Name $Name) {
        return $Object.$Name
    }
    return $Default
}

function Convert-MapToArray {
    param($Map)

    if (-not $Map) { return @() }
    return @($Map.PSObject.Properties | ForEach-Object {
        [ordered]@{
            id = [string]$_.Name
            value = $_.Value
        }
    })
}

$repoRoot = Resolve-Path $Root
$viewsRoot = Join-Path $repoRoot "ai\\materialized-views"
Ensure-Directory $viewsRoot

$sessionPath = Join-Path $repoRoot "player\\sessions\\demo-account-session-latest.json"
$ownedSummaryPath = Join-Path $viewsRoot "player-owned-summary.view.json"
$combatRecommendationsPath = Join-Path $viewsRoot "player-combat-recommendations.view.json"
$buildSkeletonsPath = Join-Path $viewsRoot "player-build-skeletons.view.json"

$session = Read-Json -Path $sessionPath
$ownedSummary = Read-Json -Path $ownedSummaryPath
$combatRecommendations = Read-Json -Path $combatRecommendationsPath
$buildSkeletons = Read-Json -Path $buildSkeletonsPath

$sessionData = $session.data
$currentMission = Get-ObjectValue -Object $sessionData -Name "currentMission"
$currentLoadout = Get-ObjectValue -Object $sessionData -Name "currentLoadout"
$overlayEvents = @(Get-ObjectValue -Object $sessionData -Name "overlayEvents" -Default @())
$recentDropsSeen = @(Get-ObjectValue -Object $sessionData -Name "recentDropsSeen" -Default @())
$recentActivityIds = @(Get-ObjectValue -Object $sessionData -Name "recentActivityIds" -Default @())

$equippedIds = @()
if ($currentLoadout -and $currentLoadout.equipped) {
    foreach ($name in @("warframeId", "primaryWeaponId", "secondaryWeaponId", "meleeWeaponId", "companionId", "companionWeaponId")) {
        $value = Get-ObjectValue -Object $currentLoadout.equipped -Name $name
        if ($value) { $equippedIds += [string]$value }
    }
}

$equippedOwned = @()
foreach ($itemId in $equippedIds) {
    $owned = $null
    if ($ownedSummary.items.PSObject.Properties.Name -contains $itemId) {
        $owned = $ownedSummary.items.$itemId
    }
    $equippedOwned += [ordered]@{
        itemId = $itemId
        owned = $null -ne $owned
        quantity = if ($owned) { $owned.quantity } else { $null }
        mastered = if ($owned) { $owned.mastered } else { $null }
    }
}

$recentDropSummaries = @()
foreach ($itemId in $recentDropsSeen | Select-Object -First 10) {
    $owned = $null
    if ($ownedSummary.items.PSObject.Properties.Name -contains [string]$itemId) {
        $owned = $ownedSummary.items.([string]$itemId)
    }
    $recentDropSummaries += [ordered]@{
        itemId = [string]$itemId
        ownedQuantity = if ($owned) { $owned.quantity } else { $null }
        lastSeenAt = if ($owned) { $owned.lastSeenAt } else { $null }
    }
}

$factionId = if ($currentMission) { Get-ObjectValue -Object $currentMission -Name "factionId" } else { $null }
$enemyRecommendations = @()
foreach ($enemy in @(Convert-MapToArray -Map $combatRecommendations.enemies)) {
    if ($factionId -and $enemy.value.factionId -ne $factionId) {
        continue
    }
    $enemyRecommendations += [ordered]@{
        enemyId = $enemy.id
        enemyName = $enemy.value.enemyName
        factionId = $enemy.value.factionId
        recommendedDamage = @($enemy.value.recommendedDamage)
        recommendedStatusPlan = @($enemy.value.recommendedStatusPlan)
        ownedSupportMods = @($enemy.value.ownedSupportMods | Select-Object -First 5)
        missingTargetMods = @($enemy.value.missingTargetMods | Select-Object -First 5)
    }
}
if ($enemyRecommendations.Count -eq 0) {
    $enemyRecommendations = @(Convert-MapToArray -Map $combatRecommendations.enemies | Select-Object -First 3 | ForEach-Object {
        [ordered]@{
            enemyId = $_.id
            enemyName = $_.value.enemyName
            factionId = $_.value.factionId
            recommendedDamage = @($_.value.recommendedDamage)
            recommendedStatusPlan = @($_.value.recommendedStatusPlan)
            ownedSupportMods = @($_.value.ownedSupportMods | Select-Object -First 5)
            missingTargetMods = @($_.value.missingTargetMods | Select-Object -First 5)
        }
    })
}

$matchingBuilds = @()
if ($currentLoadout -and $currentLoadout.buildTemplateId) {
    foreach ($target in @($buildSkeletons.targets)) {
        foreach ($build in @($target.recommendedBuilds)) {
            if ($build.buildId -eq $currentLoadout.buildTemplateId) {
                $matchingBuilds += $build
            }
        }
    }
}
if ($matchingBuilds.Count -eq 0) {
    $matchingBuilds = @($buildSkeletons.targets | Select-Object -First 3 | ForEach-Object { @($_.recommendedBuilds | Select-Object -First 1) })
}

$assistantHints = @()
if ($currentMission) {
    $assistantHints += "Use current mission faction/objective context before recommending damage types or next actions."
} else {
    $assistantHints += "No current mission snapshot is stored yet; ask the overlay/app to send /overlay/mission-sync for stronger live guidance."
}
if ($currentLoadout) {
    $assistantHints += "Use current loadout and build-fit state before suggesting mod or weapon swaps."
} else {
    $assistantHints += "No current loadout snapshot is stored yet; ask the overlay/app to send /overlay/loadout-sync for build-aware guidance."
}
if ($overlayEvents.Count -gt 0) {
    $assistantHints += "Use recent overlay events to react to objective progress, pickups, and player-state warnings."
} else {
    $assistantHints += "No rolling overlay events are stored yet; event-feed ingestion is ready for live OCR/gameplay events."
}

$view = [ordered]@{
    schemaVersion = "assistant-live-context.view.v1"
    generatedAt = (Get-Date).ToString("s") + "Z"
    playerId = [string]$session.playerId
    description = "Low-latency assistant context that fuses session, overlay, inventory, loadout, and combat recommendation state."
    sourceViews = @(
        "player/sessions/demo-account-session-latest.json",
        "ai/materialized-views/player-owned-summary.view.json",
        "ai/materialized-views/player-combat-recommendations.view.json",
        "ai/materialized-views/player-build-skeletons.view.json"
    )
    session = [ordered]@{
        updatedAt = $session.updatedAt
        currentGoalItemId = Get-ObjectValue -Object $sessionData -Name "currentGoalItemId"
        recentActivityIds = @($recentActivityIds | Select-Object -First 10)
        recentDropsSeen = @($recentDropsSeen | Select-Object -First 10)
    }
    currentMission = $currentMission
    currentLoadout = $currentLoadout
    recentOverlayEvents = @($overlayEvents | Sort-Object occurredAt -Descending | Select-Object -First 20)
    inventoryContext = [ordered]@{
        sourceViewGeneratedAt = $ownedSummary.generatedAt
        ownedItemCount = @($ownedSummary.items.PSObject.Properties).Count
        equippedOwned = $equippedOwned
        recentDrops = $recentDropSummaries
    }
    combatContext = [ordered]@{
        sourceViewGeneratedAt = $combatRecommendations.generatedAt
        activeFactionId = $factionId
        recommendations = @($enemyRecommendations | Select-Object -First 5)
    }
    buildContext = [ordered]@{
        sourceViewGeneratedAt = $buildSkeletons.generatedAt
        currentBuildTemplateId = if ($currentLoadout) { $currentLoadout.buildTemplateId } else { $null }
        recommendations = @($matchingBuilds | Select-Object -First 3)
    }
    assistantHints = $assistantHints
}

$view | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath (Join-Path $viewsRoot "assistant-live-context.view.json")

Write-Host "Generated assistant live context view." -ForegroundColor Green
