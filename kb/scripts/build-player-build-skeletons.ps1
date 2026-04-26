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

function Get-NumberOrDefault {
    param(
        $Value,
        [double]$Default = 0
    )

    if ($null -eq $Value) { return $Default }
    try {
        return [double]$Value
    }
    catch {
        return $Default
    }
}

function Get-RecordById {
    param(
        [string]$Root,
        [string]$Id
    )

    $parts = $Id -split "\.", 2
    if ($parts.Count -ne 2) { return $null }

    $kind = $parts[0]
    $slug = $parts[1]
    $folder = switch ($kind) {
        "warframe" { "content\\items\\warframes" }
        "weapon" { "content\\items\\weapons" }
        "mod" { "content\\items\\mods" }
        default { $null }
    }

    if (-not $folder) { return $null }
    $path = Join-Path $Root (Join-Path $folder ($slug + ".json"))
    if (-not (Test-Path -LiteralPath $path)) { return $null }
    return Read-Json -Path $path
}

function Get-OwnedEntry {
    param(
        $Owned,
        [string]$Id
    )

    if ($Owned.items.PSObject.Properties.Name -contains $Id) {
        return $Owned.items.$Id
    }
    return $null
}

function Get-ModDrain {
    param(
        $Mod,
        $OwnedEntry
    )

    $baseDrain = Get-NumberOrDefault -Value $Mod.stats.baseDrain -Default 0
    $fusionLimit = Get-NumberOrDefault -Value $Mod.stats.fusionLimit -Default 0
    $ownedRank = if ($OwnedEntry -and $null -ne $OwnedEntry.maxRankOwned) {
        Get-NumberOrDefault -Value $OwnedEntry.maxRankOwned -Default $fusionLimit
    } else {
        $fusionLimit
    }

    $rankForDrain = [Math]::Min($fusionLimit, [Math]::Max(0, $ownedRank))
    return [int]($baseDrain + $rankForDrain)
}

function Get-ModCapacityContribution {
    param(
        $Mod,
        $OwnedEntry
    )

    $baseDrain = Get-NumberOrDefault -Value $Mod.stats.baseDrain -Default 0
    $fusionLimit = Get-NumberOrDefault -Value $Mod.stats.fusionLimit -Default 0
    $ownedRank = if ($OwnedEntry -and $null -ne $OwnedEntry.maxRankOwned) {
        Get-NumberOrDefault -Value $OwnedEntry.maxRankOwned -Default $fusionLimit
    } else {
        $fusionLimit
    }
    $rankForDrain = [Math]::Min($fusionLimit, [Math]::Max(0, $ownedRank))

    if ($baseDrain -lt 0) {
        return [ordered]@{
            drain = 0
            capacityBonus = [int]([Math]::Abs($baseDrain) + $rankForDrain)
        }
    }

    return [ordered]@{
        drain = [int]($baseDrain + $rankForDrain)
        capacityBonus = 0
    }
}

function Get-ModBuildFit {
    param(
        [string]$Root,
        [string]$ModId,
        $OwnedEntry,
        [string[]]$AvailablePolarities = @()
    )

    $mod = Get-RecordById -Root $Root -Id $ModId
    if (-not $mod) {
        return [ordered]@{
            drain = 0
            polarity = ""
            polarityMatched = $false
            ownedRank = $null
            maxRank = $null
        }
    }

    $polarity = [string]$mod.stats.polarity
    $available = @($AvailablePolarities | ForEach-Object { ([string]$_).ToLowerInvariant() })
    $polarityMatched = -not [string]::IsNullOrWhiteSpace($polarity) -and ($available -contains $polarity.ToLowerInvariant())
    $ownedRank = if ($OwnedEntry -and $null -ne $OwnedEntry.maxRankOwned) { [int](Get-NumberOrDefault -Value $OwnedEntry.maxRankOwned) } else { $null }
    $maxRank = if ($null -ne $mod.stats.fusionLimit) { [int](Get-NumberOrDefault -Value $mod.stats.fusionLimit) } else { $null }

    $capacity = Get-ModCapacityContribution -Mod $mod -OwnedEntry $OwnedEntry
    return [ordered]@{
        drain = $capacity.drain
        capacityBonus = $capacity.capacityBonus
        polarity = $polarity
        polarityMatched = $polarityMatched
        ownedRank = $ownedRank
        maxRank = $maxRank
    }
}

function Get-CapacityPlan {
    param(
        [string]$Root,
        $Item,
        [string]$ItemKind,
        $Owned,
        $Mods,
        [int]$BaseCapacity = 30,
        $UpgradeState = $null
    )

    $availablePolarities = @()
    $nativePolarities = @()
    if ($ItemKind -eq "warframe") {
        $nativePolarities = @(As-Array $Item.stats.polarities)
    }
    elseif ($Item.stats.PSObject.Properties.Name -contains "polarities") {
        $nativePolarities = @(As-Array $Item.stats.polarities)
    }
    $formaPolarities = if ($UpgradeState) { @(As-Array $UpgradeState.formaPolarities) } else { @() }
    $availablePolarities = @($nativePolarities + $formaPolarities)

    $reactorOrCatalystInstalled = $false
    if ($ItemKind -eq "warframe" -and $UpgradeState -and $UpgradeState.reactorInstalled) {
        $reactorOrCatalystInstalled = [bool]$UpgradeState.reactorInstalled
    }
    elseif ($ItemKind -eq "weapon" -and $UpgradeState -and $UpgradeState.catalystInstalled) {
        $reactorOrCatalystInstalled = [bool]$UpgradeState.catalystInstalled
    }

    $effectiveBaseCapacity = if ($reactorOrCatalystInstalled) { $BaseCapacity * 2 } else { $BaseCapacity }
    $capacityBonus = 0
    $auraOrStance = $null
    $auraOrStanceId = ""
    if ($ItemKind -eq "warframe" -and $UpgradeState -and $UpgradeState.auraModId) {
        $auraOrStanceId = [string]$UpgradeState.auraModId
    }
    elseif ($ItemKind -eq "weapon" -and $UpgradeState -and $UpgradeState.stanceModId) {
        $auraOrStanceId = [string]$UpgradeState.stanceModId
    }

    if (-not [string]::IsNullOrWhiteSpace($auraOrStanceId)) {
        $ownedEntry = Get-OwnedEntry -Owned $Owned -Id $auraOrStanceId
        $fit = Get-ModBuildFit -Root $Root -ModId $auraOrStanceId -OwnedEntry $ownedEntry -AvailablePolarities @(([string]$Item.stats.aura), ([string]$Item.mechanics.stancePolarity))
        $capacityBonus = [int]$fit.capacityBonus
        if ($fit.polarityMatched -and $capacityBonus -gt 0) {
            $capacityBonus = $capacityBonus * 2
        }
        $auraOrStance = [ordered]@{
            modId = $auraOrStanceId
            drain = $fit.drain
            capacityBonus = $capacityBonus
            polarity = $fit.polarity
            polarityMatched = $fit.polarityMatched
            ownedRank = $fit.ownedRank
            maxRank = $fit.maxRank
        }
    }

    $modFits = @()
    foreach ($mod in @(As-Array $Mods)) {
        $modId = [string]$mod.modId
        $ownedEntry = Get-OwnedEntry -Owned $Owned -Id $modId
        $fit = Get-ModBuildFit -Root $Root -ModId $modId -OwnedEntry $ownedEntry -AvailablePolarities $availablePolarities
        $modFits += [ordered]@{
            modId = $modId
            modName = [string]$mod.modName
            drain = $fit.drain
            capacityBonus = $fit.capacityBonus
            polarity = $fit.polarity
            polarityMatched = $fit.polarityMatched
            ownedRank = $fit.ownedRank
            maxRank = $fit.maxRank
        }
    }

    $estimatedDrain = 0
    foreach ($fit in $modFits) {
        $estimatedDrain += [int]$fit.drain
    }

    $matchedCount = @($modFits | Where-Object { $_.polarityMatched }).Count
    return [ordered]@{
        capacityModel = "starter-estimate.v2"
        estimatedBaseCapacity = $BaseCapacity
        effectiveBaseCapacity = $effectiveBaseCapacity
        capacityBonus = $capacityBonus
        estimatedTotalCapacity = $effectiveBaseCapacity + $capacityBonus
        estimatedDrain = $estimatedDrain
        estimatedRemaining = ($effectiveBaseCapacity + $capacityBonus) - $estimatedDrain
        reactorOrCatalystInstalled = $reactorOrCatalystInstalled
        polaritySlotsKnown = $availablePolarities.Count -gt 0
        nativePolarities = @($nativePolarities)
        formaPolarities = @($formaPolarities)
        availablePolarities = @($availablePolarities)
        matchedPolarityCount = $matchedCount
        auraOrStance = $auraOrStance
        slottedMods = @($modFits)
        caveats = @(
            "Capacity is estimated from base drain plus owned/max rank where available.",
            "Reactors, catalysts, aura/stance capacity, and forma polarities are applied when player build upgradeState provides them.",
            "Exilus, exact slot layout, aura/stance drain edge cases, and forma history are not fully modeled yet.",
            "Polarity matching is counted where item polarity data exists; weapon polarities are often unavailable in current records."
        )
    }
}

function Get-MasteryEligibility {
    param(
        $Item,
        $Progress
    )

    $required = [int](Get-NumberOrDefault -Value $Item.stats.masteryReq -Default 0)
    $current = if ($Progress -and $Progress.data.masteryRank) {
        [int](Get-NumberOrDefault -Value $Progress.data.masteryRank -Default 0)
    } else {
        0
    }

    return [ordered]@{
        requiredMasteryRank = $required
        playerMasteryRank = $current
        eligible = $current -ge $required
    }
}

function Get-BuildUpgradeIndex {
    param([string]$Root)

    $index = @{
        warframes = @{}
        weapons = @{}
    }

    $templateRoot = Join-Path $Root "player\\build-templates"
    if (-not (Test-Path -LiteralPath $templateRoot)) { return $index }

    foreach ($file in Get-ChildItem -Path $templateRoot -File -Filter *.json | Where-Object { $_.Name -ne "manifest.json" }) {
        $template = Read-Json -Path $file.FullName
        if ($template.data.upgradeState) {
            foreach ($prop in @($template.data.upgradeState.warframes.PSObject.Properties)) {
                $index.warframes[[string]$prop.Name] = $prop.Value
            }
            foreach ($prop in @($template.data.upgradeState.weapons.PSObject.Properties)) {
                $index.weapons[[string]$prop.Name] = $prop.Value
            }
        }
    }

    return $index
}

function Get-WeaponArchetype {
    param($Weapon)

    $critChance = Get-NumberOrDefault -Value $Weapon.stats.critChance
    $statusChance = Get-NumberOrDefault -Value $Weapon.stats.statusChance
    $fireRate = Get-NumberOrDefault -Value $Weapon.stats.fireRate

    $roles = @()
    if ($critChance -ge 0.25) { $roles += "crit" }
    if ($statusChance -ge 0.2) { $roles += "status" }
    if ($fireRate -ge 8) { $roles += "rapid-fire" }
    if ($roles.Count -eq 0) { $roles += "generalist" }

    return @($roles)
}

function Mod-FitsWeapon {
    param(
        $ModProfile,
        $Weapon
    )

    $slots = @((As-Array $ModProfile.slots) | ForEach-Object { ([string]$_).ToLowerInvariant() })
    if ($slots.Count -eq 0) { return $false }

    $weaponSlot = ([string]$Weapon.stats.slot).ToLowerInvariant()
    $weaponClass = ([string]$Weapon.stats.weaponClass).ToLowerInvariant()

    if ($slots -contains $weaponSlot) { return $true }
    if ($weaponSlot -eq "primary" -and $slots -contains "primary") { return $true }
    if ($weaponSlot -eq "primary" -and $weaponClass -eq "rifle" -and $slots -contains "rifle") { return $true }
    if ($weaponSlot -eq "primary" -and $weaponClass -eq "shotgun" -and $slots -contains "shotgun") { return $true }
    if ($weaponSlot -eq "secondary" -and ($slots -contains "pistol" -or $slots -contains "secondary")) { return $true }
    if ($weaponSlot -eq "melee" -and $slots -contains "melee") { return $true }
    if ($weaponClass -and $slots -contains $weaponClass) { return $true }

    return $false
}

function Mod-FitsFrame {
    param($ModProfile)

    $slots = @((As-Array $ModProfile.slots) | ForEach-Object { ([string]$_).ToLowerInvariant() })
    return $slots -contains "warframe"
}

function Get-DesiredFrameRoles {
    param(
        $Frame,
        $Enemy
    )

    $desired = @()
    $frameRoles = @(As-Array $Frame.stats.role)
    $enemyDefense = @(As-Array $Enemy.defenseProfile)
    $enemyThreats = @(As-Array $Enemy.priorityThreats)

    if ($frameRoles -contains "tank" -or $enemyDefense -contains "armor-heavy" -or $enemyThreats -contains "endgame-pressure") {
        $desired += "survival-health"
        $desired += "survival-armor"
    }
    if ($frameRoles -contains "buffer" -or $Frame.mechanics.scalesWith -contains "ability.strength-scaling") {
        $desired += "ability-strength"
    }
    if ($Frame.mechanics.scalesWith -contains "ability.duration-scaling") {
        $desired += "ability-duration"
    }
    if ($enemyThreats -contains "ability-denial") {
        $desired += "ability-efficiency"
    }
    if ($desired.Count -eq 0) {
        $desired += "survival-health"
    }

    return @($desired | Sort-Object -Unique)
}

function Get-FrameModScore {
    param(
        $ModProfile,
        [string[]]$DesiredRoles
    )

    $score = 0
    $reasons = New-Object System.Collections.ArrayList
    foreach ($role in $DesiredRoles) {
        if ($ModProfile.roles -contains $role) {
            $score += 4
            [void]$reasons.Add("Covers desired frame role: $role")
        }
    }

    return [ordered]@{
        score = $score
        reasons = @($reasons)
    }
}

function Get-FoundationFrameModPriority {
    param(
        [string]$ModId,
        $ModProfile
    )

    $id = ([string]$ModId).ToLowerInvariant()
    $name = ([string]$ModProfile.name).ToLowerInvariant()

    switch ($id) {
        "mod.vitality" { return 100 }
        "mod.intensify" { return 100 }
        "mod.steel-fiber" { return 95 }
        "mod.continuity" { return 95 }
        "mod.streamline" { return 90 }
        "mod.stretch" { return 90 }
        "mod.flow" { return 85 }
        "mod.redirection" { return 80 }
        "mod.umbral-intensify" { return 75 }
        "mod.umbral-vitality" { return 75 }
        "mod.umbral-fiber" { return 75 }
    }

    switch ($name) {
        "vitality" { return 100 }
        "intensify" { return 100 }
        "steel fiber" { return 95 }
        "continuity" { return 95 }
        "streamline" { return 90 }
        "stretch" { return 90 }
        "flow" { return 85 }
        "redirection" { return 80 }
        "umbral intensify" { return 75 }
        "umbral vitality" { return 75 }
        "umbral fiber" { return 75 }
        default { return 0 }
    }
}

function Score-WeaponForEnemy {
    param(
        $Weapon,
        $Enemy
    )

    $score = 0
    $reasons = New-Object System.Collections.ArrayList
    $archetypes = @(Get-WeaponArchetype -Weapon $Weapon)
    $recommendedDamage = @(As-Array $Enemy.recommendedDamage)
    $priorityThreats = @(As-Array $Enemy.priorityThreats)
    $defenseProfile = @(As-Array $Enemy.defenseProfile)

    if ($archetypes -contains "crit" -and $recommendedDamage -contains "status.slash") {
        $score += 4
        [void]$reasons.Add("Crit profile can support slash-focused matchup plans.")
    }
    if ($archetypes -contains "status" -and $recommendedDamage.Count -gt 0) {
        $score += 3
        [void]$reasons.Add("Status profile can apply recommended elemental plans.")
    }
    if ($archetypes -contains "rapid-fire" -and $priorityThreats -contains "nullifier-bubble") {
        $score += 4
        [void]$reasons.Add("Rapid fire helps answer Nullifier-style bubble pressure.")
    }
    if ($defenseProfile -contains "armor-heavy" -and ($archetypes -contains "crit" -or $archetypes -contains "status")) {
        $score += 2
        [void]$reasons.Add("Has a scalable damage identity for armored benchmark targets.")
    }
    if ($archetypes -contains "generalist") {
        $score += 1
        [void]$reasons.Add("Generalist owned weapon fallback.")
    }

    return [ordered]@{
        score = $score
        archetypes = $archetypes
        reasons = @($reasons)
    }
}

function Score-FrameForEnemy {
    param(
        $Frame,
        $Enemy
    )

    $score = 0
    $reasons = New-Object System.Collections.ArrayList
    $roles = @(As-Array $Frame.stats.role)
    $enemyDefense = @(As-Array $Enemy.defenseProfile)

    if ($roles -contains "tank" -and ($enemyDefense -contains "armor-heavy" -or $enemyDefense -contains "encounter-mechanics")) {
        $score += 3
        [void]$reasons.Add("Tank profile is safe for high-pressure or benchmark targets.")
    }
    if ($roles -contains "buffer") {
        $score += 2
        [void]$reasons.Add("Buffing role can amplify weapon-focused matchup plans.")
    }
    if ($Frame.mechanics.scalesWith -contains "ability.strength-scaling") {
        $score += 1
        [void]$reasons.Add("Ability strength scaling is relevant for durable frame/buff setups.")
    }

    return [ordered]@{
        score = $score
        roles = $roles
        reasons = @($reasons)
    }
}

$repoRoot = Resolve-Path $Root
$viewsRoot = Join-Path $repoRoot "ai\\materialized-views"
Ensure-Directory $viewsRoot

$owned = Read-Json -Path (Join-Path $viewsRoot "player-owned-summary.view.json")
$enemyMatchups = Read-Json -Path (Join-Path $viewsRoot "enemy-matchups.view.json")
$modProfiles = Read-Json -Path (Join-Path $viewsRoot "combat-mod-profiles.view.json")
$combatRecommendations = Read-Json -Path (Join-Path $viewsRoot "player-combat-recommendations.view.json")
$progressPath = Join-Path $repoRoot "player\\mastery\\demo-account-mastery.json"
$progress = if (Test-Path -LiteralPath $progressPath) { Read-Json -Path $progressPath } else { $null }
$upgradeIndex = Get-BuildUpgradeIndex -Root $repoRoot

$ownedIds = @($owned.items.PSObject.Properties.Name)
$ownedWarframes = @()
$ownedWeapons = @()
$ownedMods = @()

foreach ($id in $ownedIds) {
    if ($id -like "warframe.*") {
        $record = Get-RecordById -Root $repoRoot -Id $id
        if ($record) { $ownedWarframes += $record }
    }
    elseif ($id -like "weapon.*") {
        $record = Get-RecordById -Root $repoRoot -Id $id
        if ($record) { $ownedWeapons += $record }
    }
    elseif ($id -like "mod.*") {
        $record = Get-RecordById -Root $repoRoot -Id $id
        if ($record) { $ownedMods += $record }
    }
}

$view = [ordered]@{
    generatedAt = (Get-Date).ToString("s") + "Z"
    playerId = [string]$owned.playerId
    description = "Target-aware starter build skeletons composed from owned frames, owned weapons, owned mods, and combat recommendation views."
    enemies = @{}
}

foreach ($enemyProp in $enemyMatchups.enemies.PSObject.Properties) {
    $enemyId = [string]$enemyProp.Name
    $enemy = $enemyProp.Value
    $enemyRecommendations = $combatRecommendations.enemies.$enemyId

    $candidateSkeletons = @()
    foreach ($frame in $ownedWarframes) {
        $frameScore = Score-FrameForEnemy -Frame $frame -Enemy $enemy
        $desiredFrameRoles = @(Get-DesiredFrameRoles -Frame $frame -Enemy $enemy)

        $ownedFrameMods = @()
        $missingFrameMods = @()
        foreach ($modProp in $modProfiles.mods.PSObject.Properties) {
            $modId = [string]$modProp.Name
            $profile = $modProp.Value
            if (-not (Mod-FitsFrame -ModProfile $profile)) { continue }
            $scoredFrameMod = Get-FrameModScore -ModProfile $profile -DesiredRoles $desiredFrameRoles
            if ($scoredFrameMod.score -le 0) { continue }

            $frameModRecord = [ordered]@{
                modId = $modId
                modName = [string]$profile.name
                score = $scoredFrameMod.score
                foundationPriority = Get-FoundationFrameModPriority -ModId $modId -ModProfile $profile
                rankScore = $scoredFrameMod.score + [Math]::Floor((Get-FoundationFrameModPriority -ModId $modId -ModProfile $profile) / 10)
                roles = @(As-Array $profile.roles)
                reasons = @($scoredFrameMod.reasons)
            }

            if ($ownedIds -contains $modId) {
                $ownedFrameMods += $frameModRecord
            }
            else {
                $missingFrameMods += $frameModRecord
            }
        }

        $ownedFrameMods = @($ownedFrameMods | Sort-Object -Property @(
            @{ Expression = { $_.rankScore }; Descending = $true },
            @{ Expression = { $_.score }; Descending = $true },
            @{ Expression = { $_.foundationPriority }; Descending = $true },
            @{ Expression = { $_.modName }; Descending = $false }
        ) | Select-Object -First 8)
        $missingFrameMods = @($missingFrameMods | Sort-Object -Property @(
            @{ Expression = { $_.rankScore }; Descending = $true },
            @{ Expression = { $_.score }; Descending = $true },
            @{ Expression = { $_.foundationPriority }; Descending = $true },
            @{ Expression = { $_.modName }; Descending = $false }
        ) | Select-Object -First 8)

            foreach ($weapon in $ownedWeapons) {
            $weaponScore = Score-WeaponForEnemy -Weapon $weapon -Enemy $enemy

            $ownedWeaponMods = @()
            foreach ($mod in $ownedMods) {
                $profile = $modProfiles.mods.([string]$mod.id)
                if ($profile -and (Mod-FitsWeapon -ModProfile $profile -Weapon $weapon)) {
                    $ownedWeaponMods += [ordered]@{
                        modId = [string]$mod.id
                        modName = [string]$mod.name
                        roles = @(As-Array $profile.roles)
                        statuses = @(As-Array $profile.statuses)
                    }
                }
            }

            $missingWeaponMods = @()
            foreach ($target in @(As-Array $enemyRecommendations.missingTargetMods)) {
                if (Mod-FitsWeapon -ModProfile $target -Weapon $weapon) {
                    $missingWeaponMods += $target
                }
            }

            $frameUpgradeState = if ($upgradeIndex.warframes.ContainsKey([string]$frame.id)) { $upgradeIndex.warframes[[string]$frame.id] } else { $null }
            $weaponUpgradeState = if ($upgradeIndex.weapons.ContainsKey([string]$weapon.id)) { $upgradeIndex.weapons[[string]$weapon.id] } else { $null }
            $frameCapacityPlan = Get-CapacityPlan -Root $repoRoot -Item $frame -ItemKind "warframe" -Owned $owned -Mods $ownedFrameMods -BaseCapacity 30 -UpgradeState $frameUpgradeState
            $weaponCapacityPlan = Get-CapacityPlan -Root $repoRoot -Item $weapon -ItemKind "weapon" -Owned $owned -Mods $ownedWeaponMods -BaseCapacity 30 -UpgradeState $weaponUpgradeState

            $candidateSkeletons += [ordered]@{
                skeletonId = (($enemyId + "." + $frame.id + "." + $weapon.id) -replace '[^a-zA-Z0-9\.\-]', '-')
                frame = [ordered]@{
                    id = [string]$frame.id
                    name = [string]$frame.name
                    roles = @(As-Array $frame.stats.role)
                    mastery = Get-MasteryEligibility -Item $frame -Progress $progress
                    desiredModRoles = $desiredFrameRoles
                    reasons = @($frameScore.reasons)
                }
                weapon = [ordered]@{
                    id = [string]$weapon.id
                    name = [string]$weapon.name
                    slot = [string]$weapon.stats.slot
                    weaponClass = [string]$weapon.stats.weaponClass
                    mastery = Get-MasteryEligibility -Item $weapon -Progress $progress
                    archetypes = @($weaponScore.archetypes)
                    reasons = @($weaponScore.reasons)
                }
                score = [int]($frameScore.score + $weaponScore.score + ($ownedWeaponMods.Count * 2) + ($ownedFrameMods.Count * 2) + ($frameCapacityPlan.matchedPolarityCount) + ($weaponCapacityPlan.matchedPolarityCount) - [Math]::Max(0, -1 * $frameCapacityPlan.estimatedRemaining) - [Math]::Max(0, -1 * $weaponCapacityPlan.estimatedRemaining))
                matchupPlan = @(As-Array $enemy.recommendedStatusPlan)
                ownedFrameModsToSlot = @($ownedFrameMods)
                missingFrameModsToChase = @($missingFrameMods)
                ownedModsToSlot = @($ownedWeaponMods | Select-Object -First 8)
                missingModsToChase = @($missingWeaponMods | Sort-Object -Property @(
                    @{ Expression = { $_.score }; Descending = $true },
                    @{ Expression = { $_.modName }; Descending = $false }
                ) | Select-Object -First 6)
                buildFit = [ordered]@{
                    frame = $frameCapacityPlan
                    weapon = $weaponCapacityPlan
                    masteryEligible = [bool]((Get-MasteryEligibility -Item $frame -Progress $progress).eligible -and (Get-MasteryEligibility -Item $weapon -Progress $progress).eligible)
                    upgradeStateSource = "player/build-templates"
                }
                caveats = @(
                    "Skeleton output is a backend starter plan, not a final optimized mod configuration.",
                    "Capacity and polarity use a first-pass model with player build upgradeState where available; exilus, exact slot layout, arcanes, rivens, shards, and exact enemy level are not fully applied yet."
                )
            }
        }
    }

    $view.enemies[$enemyId] = [ordered]@{
        enemyName = [string]$enemy.name
        factionId = [string]$enemy.factionId
        recommendedDamage = @(As-Array $enemy.recommendedDamage)
        skeletons = @($candidateSkeletons | Sort-Object -Property @(
            @{ Expression = { $_.score }; Descending = $true },
            @{ Expression = { $_.weapon.name }; Descending = $false }
        ) | Select-Object -First 5)
    }
}

$view | ConvertTo-Json -Depth 16 | Set-Content -LiteralPath (Join-Path $viewsRoot "player-build-skeletons.view.json")

Write-Host "Generated player build skeleton view." -ForegroundColor Green
