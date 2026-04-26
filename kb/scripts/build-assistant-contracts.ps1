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

function Convert-ModList {
    param($Mods)

    $result = @()
    foreach ($mod in @(As-Array $Mods)) {
        $entry = [ordered]@{
            id = [string]$mod.modId
            name = [string]$mod.modName
            roles = @(As-Array $mod.roles)
        }

        if ($null -ne $mod.statuses) {
            $entry.statuses = @(As-Array $mod.statuses)
        }
        if ($null -ne $mod.score) {
            $entry.score = [int]$mod.score
        }
        if ($null -ne $mod.rankScore) {
            $entry.rankScore = [int]$mod.rankScore
        }
        if ($null -ne $mod.reasons) {
            $entry.reasons = @(As-Array $mod.reasons)
        }

        $result += $entry
    }

    return @($result)
}

function New-QueryAliases {
    param(
        [string]$EnemyName,
        [string]$FrameName,
        [string]$WeaponName
    )

    $aliases = @()
    if ($EnemyName) {
        $aliases += "build for $EnemyName"
        $aliases += "counter $EnemyName"
    }
    if ($FrameName -and $EnemyName) {
        $aliases += "$FrameName build for $EnemyName"
    }
    if ($FrameName -and $WeaponName -and $EnemyName) {
        $aliases += "$FrameName $WeaponName vs $EnemyName"
    }

    return @($aliases | Sort-Object -Unique)
}

$repoRoot = Resolve-Path $Root
$viewsRoot = Join-Path $repoRoot "ai\\materialized-views"
Ensure-Directory $viewsRoot

$owned = Read-Json -Path (Join-Path $viewsRoot "player-owned-summary.view.json")
$skeletonView = Read-Json -Path (Join-Path $viewsRoot "player-build-skeletons.view.json")
$combatRecommendations = Read-Json -Path (Join-Path $viewsRoot "player-combat-recommendations.view.json")
$missingTargets = Read-Json -Path (Join-Path $viewsRoot "player-missing-targets.view.json")

$contract = [ordered]@{
    generatedAt = (Get-Date).ToString("s") + "Z"
    schemaVersion = "assistant-build-contract.v1"
    playerId = [string]$owned.playerId
    description = "Stable assistant-facing build response contracts for overlay and backend calls."
    supportedIntents = @(
        "build.recommendation.for-enemy",
        "build.recommendation.for-faction",
        "inventory.gap-analysis",
        "farm.next-target"
    )
    responseGuidance = [ordered]@{
        contractRule = "Use buildRequests entries as the primary assistant response source for build questions."
        disclaimer = "Generated builds are starter skeletons. Capacity, polarities, arcanes, rivens, helminth, shards, and exact enemy level are intentionally outside this contract."
        fallbackRule = "If no buildRequest matches the player query, fall back to combatRecommendations and missingTargets."
    }
    playerContext = [ordered]@{
        ownedItemCount = @($owned.items.PSObject.Properties).Count
        ownedWarframes = @(@($owned.items.PSObject.Properties.Name) | Where-Object { $_ -like "warframe.*" })
        ownedWeapons = @(@($owned.items.PSObject.Properties.Name) | Where-Object { $_ -like "weapon.*" })
        ownedMods = @(@($owned.items.PSObject.Properties.Name) | Where-Object { $_ -like "mod.*" })
    }
    buildRequests = @{}
    fallbackViews = [ordered]@{
        combatRecommendations = "ai/materialized-views/player-combat-recommendations.view.json"
        buildSkeletons = "ai/materialized-views/player-build-skeletons.view.json"
        missingTargets = "ai/materialized-views/player-missing-targets.view.json"
    }
}

foreach ($enemyProp in @($skeletonView.enemies.PSObject.Properties)) {
    $enemyId = [string]$enemyProp.Name
    $enemy = $enemyProp.Value
    $builds = @()

    foreach ($skeleton in @(As-Array $enemy.skeletons)) {
        $frameName = [string]$skeleton.frame.name
        $weaponName = [string]$skeleton.weapon.name

        $builds += [ordered]@{
            buildId = [string]$skeleton.skeletonId
            confidence = "starter"
            score = [int]$skeleton.score
            queryAliases = @(New-QueryAliases -EnemyName ([string]$enemy.enemyName) -FrameName $frameName -WeaponName $weaponName)
            summary = "$frameName with $weaponName for $($enemy.enemyName)"
            frame = [ordered]@{
                id = [string]$skeleton.frame.id
                name = $frameName
                roles = @(As-Array $skeleton.frame.roles)
                desiredModRoles = @(As-Array $skeleton.frame.desiredModRoles)
                ownedModsToSlot = @(Convert-ModList -Mods $skeleton.ownedFrameModsToSlot)
                missingModsToChase = @(Convert-ModList -Mods $skeleton.missingFrameModsToChase)
                reasons = @(As-Array $skeleton.frame.reasons)
            }
            weapon = [ordered]@{
                id = [string]$skeleton.weapon.id
                name = $weaponName
                slot = [string]$skeleton.weapon.slot
                weaponClass = [string]$skeleton.weapon.weaponClass
                archetypes = @(As-Array $skeleton.weapon.archetypes)
                ownedModsToSlot = @(Convert-ModList -Mods $skeleton.ownedModsToSlot)
                missingModsToChase = @(Convert-ModList -Mods $skeleton.missingModsToChase)
                reasons = @(As-Array $skeleton.weapon.reasons)
            }
            buildFit = $skeleton.buildFit
            matchupPlan = @(As-Array $skeleton.matchupPlan)
            caveats = @(As-Array $skeleton.caveats)
        }
    }

    $contract.buildRequests[$enemyId] = [ordered]@{
        target = [ordered]@{
            id = $enemyId
            name = [string]$enemy.enemyName
            factionId = [string]$enemy.factionId
            recommendedDamage = @(As-Array $enemy.recommendedDamage)
        }
        recommendedBuilds = @($builds | Sort-Object -Property @(
            @{ Expression = { $_.score }; Descending = $true },
            @{ Expression = { $_.frame.name }; Descending = $false },
            @{ Expression = { $_.weapon.name }; Descending = $false }
        ))
    }
}

$contract.inventoryAdvice = [ordered]@{
    wishlistMissingTargets = @($missingTargets.missingTargets | Select-Object -First 10)
    farmableNow = @($missingTargets.farmableNow | Select-Object -First 10)
}

$contract.combatAdvice = [ordered]@{
    enemies = $combatRecommendations.enemies
}

$contract | ConvertTo-Json -Depth 18 | Set-Content -LiteralPath (Join-Path $viewsRoot "assistant-build-contracts.view.json")

Write-Host "Generated assistant-facing build contract view." -ForegroundColor Green
