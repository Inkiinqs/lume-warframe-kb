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

function Add-UniqueText {
    param(
        [System.Collections.ArrayList]$List,
        [string]$Value
    )

    if (-not [string]::IsNullOrWhiteSpace($Value) -and -not $List.Contains($Value)) {
        [void]$List.Add($Value)
    }
}

function Infer-ModProfile {
    param($Mod)

    $effectType = [string]$Mod.mechanics.effectType
    $rules = @((As-Array $Mod.mechanics.relevantRules) + (As-Array $Mod.mechanics.relevantFormulas))
    $summary = (([string]$Mod.summary) + " " + ([string]$Mod.name)).ToLowerInvariant()
    $typeText = [string]$Mod.mechanics.type

    $signals = [ordered]@{
        statuses = @()
        roles = @()
        slots = @()
    }

    foreach ($compat in @(As-Array $Mod.stats.compatibility)) {
        $signals.slots += [string]$compat
    }

    $typeLower = $typeText.ToLowerInvariant()
    if ($signals.slots.Count -eq 0) {
        if ($typeLower.Contains("secondary") -or $typeLower.Contains("pistol")) {
            $signals.slots += "secondary"
        }
        if ($typeLower.Contains("melee")) {
            $signals.slots += "melee"
        }
        if ($typeLower.Contains("shotgun")) {
            $signals.slots += "shotgun"
        }
        elseif ($typeLower.Contains("rifle")) {
            $signals.slots += "rifle"
        }
        elseif ($typeLower.Contains("primary")) {
            $signals.slots += "primary"
        }
    }

    $statusMap = [ordered]@{
        "status.viral" = "viral"
        "status.corrosive" = "corrosive"
        "status.heat" = "heat"
        "status.slash" = "slash"
        "status.toxin" = "toxin"
        "status.magnetic" = "magnetic"
        "status.electric" = "electric"
        "status.gas" = "gas"
        "status.radiation" = "radiation"
        "status.cold" = "cold"
    }

    foreach ($pair in $statusMap.GetEnumerator()) {
        if ($rules -contains $pair.Key -or $effectType.ToLowerInvariant().Contains($pair.Value) -or $summary.Contains($pair.Value)) {
            $signals.statuses += $pair.Value
        }
    }

    if ($effectType -match "base-damage" -or $summary.Contains("damage")) { $signals.roles += "damage" }
    if ($effectType -match "multishot" -or $summary.Contains("multishot")) { $signals.roles += "multishot" }
    if ($effectType -match "crit" -or $summary.Contains("critical")) { $signals.roles += "crit" }
    if ($effectType -match "status" -or $summary.Contains("status chance")) { $signals.roles += "status" }
    if ($summary.Contains("attack speed") -or $summary.Contains("fire rate")) { $signals.roles += "speed" }
    if ($effectType -match "ability-strength" -or $rules -contains "ability.strength-scaling" -or $summary.Contains("ability strength")) { $signals.roles += "ability-strength" }
    if ($effectType -match "ability-duration" -or $rules -contains "ability.duration-scaling" -or $summary.Contains("ability duration")) { $signals.roles += "ability-duration" }
    if ($effectType -match "ability-range" -or $rules -contains "ability.range-scaling" -or $summary.Contains("ability range")) { $signals.roles += "ability-range" }
    if ($effectType -match "ability-efficiency" -or $rules -contains "ability.efficiency-scaling" -or $summary.Contains("ability efficiency")) { $signals.roles += "ability-efficiency" }
    if ($effectType -match "health" -or $rules -contains "damage.health-interactions" -or $summary.Contains("health")) { $signals.roles += "survival-health" }
    if ($effectType -match "shield" -or $rules -contains "damage.shield-interactions" -or $summary.Contains("shield")) { $signals.roles += "survival-shield" }
    if ($effectType -match "armor" -or $rules -contains "damage.armor-interactions" -or $summary.Contains("armor")) { $signals.roles += "survival-armor" }
    if ($typeLower.Contains("warframe") -and $signals.slots -notcontains "warframe") { $signals.slots += "warframe" }

    if ($signals.statuses.Count -gt 0 -and $signals.roles -notcontains "elemental") {
        $signals.roles += "elemental"
    }

    $signals.statuses = @($signals.statuses | Sort-Object -Unique)
    $signals.roles = @($signals.roles | Sort-Object -Unique)
    $signals.slots = @($signals.slots | Sort-Object -Unique)

    return $signals
}

function Score-ModForEnemy {
    param(
        $Profile,
        $Enemy
    )

    $score = 0
    $reasons = New-Object System.Collections.ArrayList

    foreach ($status in @(As-Array $Enemy.recommendedDamage)) {
        $statusName = [string]($status -replace '^status\.', '')
        if ($Profile.statuses -contains $statusName) {
            $score += 5
            Add-UniqueText -List $reasons -Value ("Supports " + $statusName + " matchup plan")
        }
    }

    if ($Enemy.defenseProfile -contains "armor-heavy" -and $Profile.roles -contains "damage") {
        $score += 2
        Add-UniqueText -List $reasons -Value "Provides foundational damage for armored targets"
    }

    if ($Enemy.defenseProfile -contains "shield-oriented" -and ($Profile.roles -contains "status" -or $Profile.statuses -contains "toxin" -or $Profile.statuses -contains "magnetic")) {
        $score += 2
        Add-UniqueText -List $reasons -Value "Helps handle shield-focused enemies"
    }

    if ($Enemy.defenseProfile -contains "support-aura" -and ($Profile.roles -contains "elemental" -or $Profile.roles -contains "speed")) {
        $score += 1
        Add-UniqueText -List $reasons -Value "Useful in swarm or priority-kill situations"
    }

    if ($Profile.roles -contains "crit" -and ($Enemy.recommendedDamage -contains "status.slash")) {
        $score += 2
        Add-UniqueText -List $reasons -Value "Crit synergy can feed slash-style recommendations"
    }

    return [ordered]@{
        score = $score
        reasons = @($reasons)
    }
}

function Is-CombatRelevantMod {
    param(
        $Profile,
        $ModId,
        $CompatByMod
    )

    $combatSlots = @("primary", "secondary", "melee", "rifle", "shotgun", "pistol")
    $hasCombatSlot = @($Profile.slots | Where-Object { $combatSlots -contains $_ }).Count -gt 0
    $hasSignal = $Profile.roles.Count -gt 0 -or $Profile.statuses.Count -gt 0
    $hasCompatibility = $CompatByMod.ContainsKey($ModId)

    return ($hasCombatSlot -or $hasCompatibility) -and $hasSignal
}

$repoRoot = Resolve-Path $Root
$viewsRoot = Join-Path $repoRoot "ai\\materialized-views"
Ensure-Directory $viewsRoot

$modFiles = Get-ChildItem -Path (Join-Path $repoRoot "content\\items\\mods") -File -Filter *.json |
    Where-Object { $_.Name -ne "manifest.json" }
$compatibilityFiles = Get-ChildItem -Path (Join-Path $repoRoot "content\\relationships\\compatibility") -File -Filter *.json |
    Where-Object { $_.Name -ne "manifest.json" }
$enemyView = Read-Json -Path (Join-Path $viewsRoot "enemy-matchups.view.json")
$playerOwned = Read-Json -Path (Join-Path $viewsRoot "player-owned-summary.view.json")

$compatByMod = @{}
foreach ($file in $compatibilityFiles) {
    $json = Read-Json -Path $file.FullName
    if (-not $compatByMod.ContainsKey([string]$json.from)) {
        $compatByMod[[string]$json.from] = @()
    }
    $compatByMod[[string]$json.from] += [ordered]@{
        weaponId = [string]$json.to
        relationId = [string]$json.id
        reason = [string]$json.values.reason
        tags = @(As-Array $json.tags)
    }
}

$modCatalog = @{}
$modProfiles = [ordered]@{
    generatedAt = (Get-Date).ToString("s") + "Z"
    description = "Inferred mod role and status profiles used for backend recommendation views."
    mods = @{}
}

foreach ($file in $modFiles) {
    $mod = Read-Json -Path $file.FullName
    $profile = Infer-ModProfile -Mod $mod
    $modCatalog[[string]$mod.id] = [ordered]@{
        mod = $mod
        profile = $profile
    }

    $modProfiles.mods[[string]$mod.id] = [ordered]@{
        name = [string]$mod.name
        slots = @($profile.slots)
        roles = @($profile.roles)
        statuses = @($profile.statuses)
        compatibilityAnchors = if ($compatByMod.ContainsKey([string]$mod.id)) { @($compatByMod[[string]$mod.id]) } else { @() }
    }
}

$recommendations = [ordered]@{
    generatedAt = (Get-Date).ToString("s") + "Z"
    playerId = [string]$playerOwned.playerId
    description = "Player-aware combat recommendations built from enemy matchups, inferred mod roles, and current ownership."
    enemies = @{}
}

$ownedItemIds = @($playerOwned.items.PSObject.Properties.Name)

foreach ($enemyProp in $enemyView.enemies.PSObject.Properties) {
    $enemyId = [string]$enemyProp.Name
    $enemy = $enemyProp.Value

    $ownedMatches = @()
    $missingTargets = @()

    foreach ($pair in $modCatalog.GetEnumerator()) {
        $modId = [string]$pair.Key
        $entry = $pair.Value
        if (-not (Is-CombatRelevantMod -Profile $entry.profile -ModId $modId -CompatByMod $compatByMod)) { continue }
        $scored = Score-ModForEnemy -Profile $entry.profile -Enemy $enemy
        if ($scored.score -le 0) { continue }

        $compatibilityMatches = @()
        if ($compatByMod.ContainsKey($modId)) {
            $compatibilityMatches = @($compatByMod[$modId] | Where-Object { $ownedItemIds -contains $_.weaponId })
        }

        $record = [ordered]@{
            modId = $modId
            modName = [string]$entry.mod.name
            score = $scored.score
            slots = @($entry.profile.slots)
            roles = @($entry.profile.roles)
            statuses = @($entry.profile.statuses)
            reasons = @($scored.reasons)
            compatibleOwnedWeapons = @($compatibilityMatches)
        }

        if ($ownedItemIds -contains $modId) {
            $ownedMatches += $record
        }
        else {
            $missingTargets += $record
        }
    }

    $ownedMatches = @($ownedMatches | Sort-Object -Property @(
        @{ Expression = { $_.score }; Descending = $true },
        @{ Expression = { $_.modName }; Descending = $false }
    ) | Select-Object -First 8)
    $missingTargets = @($missingTargets | Sort-Object -Property @(
        @{ Expression = { $_.score }; Descending = $true },
        @{ Expression = { $_.modName }; Descending = $false }
    ) | Select-Object -First 8)

    $recommendations.enemies[$enemyId] = [ordered]@{
        enemyName = [string]$enemy.name
        factionId = [string]$enemy.factionId
        recommendedDamage = @($enemy.recommendedDamage)
        recommendedStatusPlan = @($enemy.recommendedStatusPlan)
        ownedSupportMods = $ownedMatches
        missingTargetMods = $missingTargets
    }
}

$modProfiles | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath (Join-Path $viewsRoot "combat-mod-profiles.view.json")
$recommendations | ConvertTo-Json -Depth 14 | Set-Content -LiteralPath (Join-Path $viewsRoot "player-combat-recommendations.view.json")

Write-Host "Generated recommendation materialized views." -ForegroundColor Green
