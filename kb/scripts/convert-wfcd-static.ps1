param(
    [string]$Root = "."
)

$ErrorActionPreference = "Stop"

function Convert-ToSlug {
    param([string]$Value)
    $slug = $Value.ToLowerInvariant()
    $slug = $slug -replace "[^a-z0-9]+", "-"
    $slug = $slug.Trim("-")
    return $slug
}

function Read-WfcdJson {
    param(
        [string]$RawRoot,
        [string]$FileName,
        [switch]$Optional
    )

    $path = Join-Path $RawRoot $FileName
    if (-not (Test-Path -LiteralPath $path)) {
        if ($Optional) { return @() }
        throw "WFCD raw snapshot missing: $path"
    }

    return @(Get-Content -Raw -LiteralPath $path | ConvertFrom-Json)
}

function Get-FirstText {
    param([array]$Values)

    foreach ($value in $Values) {
        if ($null -eq $value) { continue }
        $text = [string]$value
        if (-not [string]::IsNullOrWhiteSpace($text)) {
            return $text
        }
    }

    return ""
}

function Get-LevelStatLines {
    param([pscustomobject]$Item)

    if (-not $Item.levelStats) { return @() }

    $lines = @()
    foreach ($level in @($Item.levelStats)) {
        foreach ($stat in @($level.stats)) {
            if (-not [string]::IsNullOrWhiteSpace([string]$stat)) {
                $lines += [string]$stat
            }
        }
    }

    return @($lines)
}

function Get-TopLevelStatLines {
    param([pscustomobject]$Item)

    $lines = Get-LevelStatLines -Item $Item
    if ($lines.Count -eq 0) { return @() }

    $perRank = @()
    foreach ($level in @($Item.levelStats)) {
        $rankLines = @($level.stats | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) })
        if ($rankLines.Count -gt 0) {
            $perRank += ,@($rankLines)
        }
    }

    if ($perRank.Count -gt 0) {
        return @($perRank[-1])
    }

    return @($lines | Select-Object -Last 8)
}

function Get-WikiData {
    param([pscustomobject]$Item)

    [ordered]@{
        available = $Item.wikiAvailable
        url = $Item.wikiaUrl
        thumbnail = $Item.wikiaThumbnail
        imageName = $Item.imageName
    }
}

function Get-CraftingData {
    param([pscustomobject]$Item)

    [ordered]@{
        buildPrice = $Item.buildPrice
        buildTime = $Item.buildTime
        skipBuildTimePrice = $Item.skipBuildTimePrice
        buildQuantity = $Item.buildQuantity
        consumeOnBuild = $Item.consumeOnBuild
        components = @($Item.components | ForEach-Object {
            [ordered]@{
                name = $_.name
                uniqueName = $_.uniqueName
                itemCount = $_.itemCount
                type = $_.type
                tradable = $_.tradable
                drops = @($_.drops)
            }
        })
    }
}

function Map-WfcdWarframe {
    param([pscustomobject]$Item)

    $slug = Convert-ToSlug $Item.name
    [ordered]@{
        id = "warframe.$slug"
        slug = $slug
        name = $Item.name
        summary = if ($Item.description) { [string]$Item.description } else { "$($Item.name) imported from WFCD static data." }
        description = $Item.description
        subCategory = if ($Item.isPrime) { "prime" } else { "standard" }
        aliases = @($Item.uniqueName)
        stats = [ordered]@{
            health = $Item.health
            shield = $Item.shield
            armor = $Item.armor
            power = $Item.power
            stamina = $Item.stamina
            masteryReq = $Item.masteryReq
            sprintSpeed = $Item.sprintSpeed
            polarities = @($Item.polarities)
            aura = $Item.aura
            tradable = $Item.tradable
            masterable = $Item.masterable
            vaulted = $Item.vaulted
            vaultDate = $Item.vaultDate
            estimatedVaultDate = $Item.estimatedVaultDate
        }
        mechanics = [ordered]@{
            passiveDescription = $Item.passiveDescription
            abilities = @($Item.abilities | ForEach-Object {
                [ordered]@{
                    name = $_.name
                    description = $_.description
                    uniqueName = $_.uniqueName
                    imageName = $_.imageName
                }
            })
            exalted = @($Item.exalted)
            crafting = Get-CraftingData -Item $Item
            wiki = Get-WikiData -Item $Item
        }
        relationships = @()
        release = [ordered]@{
            releaseDate = $Item.releaseDate
            introduced = $Item.introduced
        }
        tags = @("warframe") + $(if ($Item.isPrime) { @("prime") } else { @("base") })
        notes = @("Converted from WFCD Warframes.json.")
    }
}

function Map-WfcdWeapon {
    param(
        [pscustomobject]$Item,
        [string]$Slot
    )

    $slug = Convert-ToSlug $Item.name
    $weaponClass = if ($Item.type) { [string]$Item.type } else { $Slot }
    [ordered]@{
        id = "weapon.$slug"
        slug = $slug
        name = $Item.name
        summary = if ($Item.description) { [string]$Item.description } else { "$($Item.name) imported from WFCD static data." }
        description = $Item.description
        subCategory = Convert-ToSlug "$Slot-$weaponClass"
        aliases = @($Item.uniqueName)
        stats = [ordered]@{
            slot = $Slot
            weaponClass = $weaponClass
            masteryReq = $Item.masteryReq
            trigger = $Item.trigger
            fireRate = $Item.fireRate
            accuracy = $Item.accuracy
            noise = $Item.noise
            critChance = $Item.criticalChance
            critMultiplier = $Item.criticalMultiplier
            statusChance = $Item.procChance
            multishot = $Item.multishot
            magazineSize = $Item.magazineSize
            reloadTime = $Item.reloadTime
            totalDamage = $Item.totalDamage
            disposition = $Item.disposition
            polarities = @($Item.polarities)
            tradable = $Item.tradable
            masterable = $Item.masterable
            vaulted = $Item.vaulted
            vaultDate = $Item.vaultDate
            estimatedVaultDate = $Item.estimatedVaultDate
        }
        mechanics = [ordered]@{
            damageTypes = $Item.damageTypes
            damage = $Item.damage
            damagePerShot = @($Item.damagePerShot)
            attacks = @($Item.attacks)
            stancePolarity = $Item.stancePolarity
            blockingAngle = $Item.blockingAngle
            comboDuration = $Item.comboDuration
            followThrough = $Item.followThrough
            range = $Item.range
            slamAttack = $Item.slamAttack
            slamRadialDamage = $Item.slamRadialDamage
            slamRadius = $Item.slamRadius
            slideAttack = $Item.slideAttack
            heavyAttackDamage = $Item.heavyAttackDamage
            heavySlamAttack = $Item.heavySlamAttack
            heavySlamRadialDamage = $Item.heavySlamRadialDamage
            heavySlamRadius = $Item.heavySlamRadius
            windUp = $Item.windUp
            sentinel = $Item.sentinel
            crafting = Get-CraftingData -Item $Item
            drops = @($Item.drops)
            wiki = Get-WikiData -Item $Item
        }
        relationships = @()
        release = [ordered]@{
            releaseDate = $Item.releaseDate
            introduced = $Item.introduced
        }
        tags = @("weapon", $Slot)
        notes = @("Converted from WFCD $Slot static data.")
    }
}

function Map-WfcdMod {
    param([pscustomobject]$Item)

    $slug = Convert-ToSlug $Item.name
    $topRankStats = @(Get-TopLevelStatLines -Item $Item)
    $summary = if ($topRankStats.Count -gt 0) {
        [string]($topRankStats -join " ")
    } elseif ($Item.levelStats -and $Item.levelStats.Count -gt 0 -and $Item.levelStats[0].stats) {
        [string]($Item.levelStats[0].stats -join " ")
    } else {
        "$($Item.name) imported from WFCD static data."
    }

    [ordered]@{
        id = "mod.$slug"
        slug = $slug
        name = $Item.name
        summary = $summary
        description = $summary
        subCategory = if ($Item.compatName) { Convert-ToSlug $Item.compatName } else { "mod" }
        aliases = @($Item.uniqueName)
        stats = [ordered]@{
            polarity = $Item.polarity
            rarity = $Item.rarity
            baseDrain = $Item.baseDrain
            fusionLimit = $Item.fusionLimit
            compatName = $Item.compatName
            tradable = $Item.tradable
            transmutable = $Item.transmutable
            masterable = $Item.masterable
            isPrime = $Item.isPrime
        }
        mechanics = [ordered]@{
            type = $Item.type
            levelStats = @($Item.levelStats | ForEach-Object { $_.stats })
            topRankStats = $topRankStats
            isAugment = $Item.isAugment
            drops = @($Item.drops)
            wiki = Get-WikiData -Item $Item
        }
        relationships = @()
        release = [ordered]@{
            releaseDate = $Item.releaseDate
            introduced = $Item.introduced
        }
        tags = @("mod")
        notes = @("Converted from WFCD Mods.json.")
    }
}

function Map-WfcdResource {
    param([pscustomobject]$Item)

    $slug = Convert-ToSlug $Item.name
    [ordered]@{
        id = "resource.$slug"
        slug = $slug
        name = $Item.name
        summary = if ($Item.description) { [string]$Item.description } else { "$($Item.name) imported from WFCD static data." }
        description = $Item.description
        subCategory = "resource"
        aliases = @($Item.uniqueName)
        stats = [ordered]@{
            type = $Item.type
            tradable = $Item.tradable
            masterable = $Item.masterable
        }
        mechanics = [ordered]@{
            crafting = Get-CraftingData -Item $Item
            drops = @($Item.drops)
            wiki = Get-WikiData -Item $Item
        }
        relationships = @()
        release = [ordered]@{}
        tags = @("resource")
        notes = @("Converted from WFCD Resources.json.")
    }
}

function Map-WfcdRelic {
    param([pscustomobject]$Item)

    $slug = Convert-ToSlug $Item.name
    $era = if ($Item.name -match "^(Lith|Meso|Neo|Axi)") { $Matches[1] } else { "Relic" }
    [ordered]@{
        id = "relic.$slug"
        slug = $slug
        name = $Item.name
        summary = if ($Item.description) { [string]$Item.description } else { "$($Item.name) imported from WFCD static data." }
        description = $Item.description
        subCategory = $era.ToLowerInvariant()
        aliases = @($Item.uniqueName)
        stats = [ordered]@{
            vaulted = $Item.vaulted
            tradable = $Item.tradable
            masterable = $Item.masterable
        }
        mechanics = [ordered]@{
            era = $era
            rewards = @($Item.rewards | ForEach-Object {
                [ordered]@{
                    itemName = $_.itemName
                    rarity = $_.rarity
                    chance = $_.chance
                }
            })
            drops = @($Item.drops)
            wiki = Get-WikiData -Item $Item
        }
        relationships = @()
        release = [ordered]@{
            releaseDate = $Item.releaseDate
            introduced = $Item.introduced
        }
        tags = @("relic", $era.ToLowerInvariant())
        notes = @("Converted from WFCD Relics.json.")
    }
}

function Map-WfcdArcane {
    param([pscustomobject]$Item)

    $slug = Convert-ToSlug $Item.name
    $topRankStats = @(Get-TopLevelStatLines -Item $Item)
    $summary = if ($topRankStats.Count -gt 0) { [string]($topRankStats -join " ") } else { "$($Item.name) imported from WFCD static data." }
    [ordered]@{
        id = "arcane.$slug"
        slug = $slug
        name = $Item.name
        summary = $summary
        description = $summary
        subCategory = if ($Item.type) { Convert-ToSlug $Item.type } else { "arcane" }
        aliases = @($Item.uniqueName)
        stats = [ordered]@{
            rarity = $Item.rarity
            tradable = $Item.tradable
            masterable = $Item.masterable
        }
        mechanics = [ordered]@{
            type = $Item.type
            levelStats = @($Item.levelStats | ForEach-Object { $_.stats })
            topRankStats = $topRankStats
            drops = @($Item.drops)
            wiki = Get-WikiData -Item $Item
        }
        relationships = @()
        release = [ordered]@{}
        tags = @("arcane") + $(if ($Item.type) { @(Convert-ToSlug $Item.type) } else { @() })
        notes = @("Converted from WFCD Arcanes.json.")
    }
}

function Map-WfcdCompanion {
    param(
        [pscustomobject]$Item,
        [string]$CompanionKind
    )

    $slug = Convert-ToSlug $Item.name
    [ordered]@{
        id = "companion.$slug"
        slug = $slug
        name = $Item.name
        summary = Get-FirstText -Values @($Item.description, "$($Item.name) imported from WFCD static data.")
        description = $Item.description
        subCategory = Convert-ToSlug $CompanionKind
        aliases = @($Item.uniqueName)
        stats = [ordered]@{
            health = $Item.health
            shield = $Item.shield
            armor = $Item.armor
            stamina = $Item.stamina
            power = $Item.power
            masteryReq = $Item.masteryReq
            polarities = @($Item.polarities)
            tradable = $Item.tradable
            masterable = $Item.masterable
            vaulted = $Item.vaulted
            vaultDate = $Item.vaultDate
            estimatedVaultDate = $Item.estimatedVaultDate
        }
        mechanics = [ordered]@{
            type = $Item.type
            crafting = Get-CraftingData -Item $Item
            drops = @($Item.drops)
            wiki = Get-WikiData -Item $Item
        }
        relationships = @()
        release = [ordered]@{
            releaseDate = $Item.releaseDate
            introduced = $Item.introduced
        }
        tags = @("companion", (Convert-ToSlug $CompanionKind))
        notes = @("Converted from WFCD $CompanionKind static data.")
    }
}

function Map-WfcdVehicle {
    param([pscustomobject]$Item)

    $slug = Convert-ToSlug $Item.name
    [ordered]@{
        id = "vehicle.$slug"
        slug = $slug
        name = $Item.name
        summary = Get-FirstText -Values @($Item.description, "$($Item.name) imported from WFCD static data.")
        description = $Item.description
        subCategory = "archwing"
        aliases = @($Item.uniqueName)
        stats = [ordered]@{
            health = $Item.health
            shield = $Item.shield
            armor = $Item.armor
            stamina = $Item.stamina
            power = $Item.power
            masteryReq = $Item.masteryReq
            sprintSpeed = $Item.sprintSpeed
            polarities = @($Item.polarities)
            tradable = $Item.tradable
            masterable = $Item.masterable
            vaulted = $Item.vaulted
            vaultDate = $Item.vaultDate
            estimatedVaultDate = $Item.estimatedVaultDate
        }
        mechanics = [ordered]@{
            type = $Item.type
            abilities = @($Item.abilities | ForEach-Object {
                [ordered]@{
                    name = $_.name
                    description = $_.description
                    uniqueName = $_.uniqueName
                    imageName = $_.imageName
                }
            })
            crafting = Get-CraftingData -Item $Item
            drops = @($Item.drops)
            wiki = Get-WikiData -Item $Item
        }
        relationships = @()
        release = [ordered]@{
            releaseDate = $Item.releaseDate
            introduced = $Item.introduced
        }
        tags = @("vehicle", "archwing")
        notes = @("Converted from WFCD Archwing.json.")
    }
}

function Map-WfcdEnemy {
    param([pscustomobject]$Item)

    $slug = Convert-ToSlug $Item.name
    $faction = if ($Item.faction) { [string]$Item.faction } elseif ($Item.type) { [string]$Item.type } else { "enemy" }
    [ordered]@{
        id = "enemy.$slug"
        slug = $slug
        name = $Item.name
        summary = Get-FirstText -Values @($Item.description, "$($Item.name) enemy record imported from WFCD static data.")
        description = $Item.description
        subCategory = Convert-ToSlug $faction
        aliases = @($Item.uniqueName)
        stats = [ordered]@{
            health = $Item.health
            shield = $Item.shield
            armor = $Item.armor
            faction = $faction
            type = $Item.type
            regionBits = $Item.regionBits
            tradable = $Item.tradable
        }
        mechanics = [ordered]@{
            resistances = @($Item.resistances)
            drops = @($Item.drops)
            wiki = Get-WikiData -Item $Item
        }
        relationships = @()
        release = [ordered]@{}
        tags = @("enemy", (Convert-ToSlug $faction))
        notes = @("Converted from WFCD Enemy.json.")
    }
}

function Map-WfcdNode {
    param([pscustomobject]$Item)

    $slug = Convert-ToSlug ("{0}-{1}" -f $Item.systemName, $Item.name)
    [ordered]@{
        id = "activity.$slug"
        slug = $slug
        name = if ($Item.systemName) { "{0} ({1})" -f $Item.name, $Item.systemName } else { $Item.name }
        summary = if ($Item.systemName) { "Mission node on $($Item.systemName)." } else { "$($Item.name) mission node imported from WFCD static data." }
        description = if ($Item.systemName) { "Mission node on $($Item.systemName)." } else { "" }
        subCategory = "node"
        aliases = @($Item.uniqueName, $Item.name)
        stats = [ordered]@{
            masteryReq = $Item.masteryReq
            minEnemyLevel = $Item.minEnemyLevel
            maxEnemyLevel = $Item.maxEnemyLevel
            systemIndex = $Item.systemIndex
            missionIndex = $Item.missionIndex
            factionIndex = $Item.factionIndex
            nodeType = $Item.nodeType
        }
        mechanics = [ordered]@{
            type = $Item.type
            systemName = $Item.systemName
            drops = @($Item.drops)
        }
        relationships = @()
        release = [ordered]@{}
        tags = @("activity", "node") + $(if ($Item.systemName) { @(Convert-ToSlug $Item.systemName) } else { @() })
        notes = @("Converted from WFCD Node.json.")
    }
}

function Map-WfcdQuest {
    param([pscustomobject]$Item)

    $slug = Convert-ToSlug $Item.name
    [ordered]@{
        id = "activity.quest-$slug"
        slug = "quest-$slug"
        name = $Item.name
        summary = Get-FirstText -Values @($Item.description, "$($Item.name) quest imported from WFCD static data.")
        description = $Item.description
        subCategory = "quest"
        aliases = @($Item.uniqueName)
        stats = [ordered]@{
            tradable = $Item.tradable
            masterable = $Item.masterable
        }
        mechanics = [ordered]@{
            type = $Item.type
            crafting = Get-CraftingData -Item $Item
            drops = @($Item.drops)
            wiki = Get-WikiData -Item $Item
        }
        relationships = @()
        release = [ordered]@{}
        tags = @("activity", "quest")
        notes = @("Converted from WFCD Quests.json.")
    }
}

function Map-WfcdGear {
    param([pscustomobject]$Item)

    $slug = Convert-ToSlug $Item.name
    [ordered]@{
        id = "gear.$slug"
        slug = $slug
        name = $Item.name
        summary = Get-FirstText -Values @($Item.description, "$($Item.name) gear imported from WFCD static data.")
        description = $Item.description
        subCategory = if ($Item.type) { Convert-ToSlug $Item.type } else { "gear" }
        aliases = @($Item.uniqueName)
        stats = [ordered]@{
            type = $Item.type
            tradable = $Item.tradable
            masterable = $Item.masterable
        }
        mechanics = [ordered]@{
            crafting = Get-CraftingData -Item $Item
            drops = @($Item.drops)
            wiki = Get-WikiData -Item $Item
        }
        relationships = @()
        release = [ordered]@{}
        tags = @("gear") + $(if ($Item.type) { @(Convert-ToSlug $Item.type) } else { @() })
        notes = @("Converted from WFCD Gear.json.")
    }
}

$repoRoot = Resolve-Path $Root
$rawRoot = Join-Path $repoRoot "imports\\static\\source-snapshots\\wfcd\\raw"
$outRoot = Join-Path $repoRoot "imports\\static\\source-snapshots\\wfcd"

$warframes = Read-WfcdJson -RawRoot $rawRoot -FileName "Warframes.json"
$primary = Read-WfcdJson -RawRoot $rawRoot -FileName "Primary.json"
$secondary = Read-WfcdJson -RawRoot $rawRoot -FileName "Secondary.json"
$melee = Read-WfcdJson -RawRoot $rawRoot -FileName "Melee.json"
$mods = Read-WfcdJson -RawRoot $rawRoot -FileName "Mods.json"
$resources = Read-WfcdJson -RawRoot $rawRoot -FileName "Resources.json"
$relics = Read-WfcdJson -RawRoot $rawRoot -FileName "Relics.json"
$arcanes = Read-WfcdJson -RawRoot $rawRoot -FileName "Arcanes.json" -Optional
$archwing = Read-WfcdJson -RawRoot $rawRoot -FileName "Archwing.json" -Optional
$archGun = Read-WfcdJson -RawRoot $rawRoot -FileName "Arch-Gun.json" -Optional
$archMelee = Read-WfcdJson -RawRoot $rawRoot -FileName "Arch-Melee.json" -Optional
$enemies = Read-WfcdJson -RawRoot $rawRoot -FileName "Enemy.json" -Optional
$nodes = Read-WfcdJson -RawRoot $rawRoot -FileName "Node.json" -Optional
$pets = Read-WfcdJson -RawRoot $rawRoot -FileName "Pets.json" -Optional
$sentinels = Read-WfcdJson -RawRoot $rawRoot -FileName "Sentinels.json" -Optional
$sentinelWeapons = Read-WfcdJson -RawRoot $rawRoot -FileName "SentinelWeapons.json" -Optional
$gear = Read-WfcdJson -RawRoot $rawRoot -FileName "Gear.json" -Optional
$quests = Read-WfcdJson -RawRoot $rawRoot -FileName "Quests.json" -Optional

$convertedWarframes = @($warframes | ForEach-Object { Map-WfcdWarframe -Item $_ })
$convertedWeapons = @()
$convertedWeapons += @($primary | ForEach-Object { Map-WfcdWeapon -Item $_ -Slot "primary" })
$convertedWeapons += @($secondary | ForEach-Object { Map-WfcdWeapon -Item $_ -Slot "secondary" })
$convertedWeapons += @($melee | ForEach-Object { Map-WfcdWeapon -Item $_ -Slot "melee" })
$convertedWeapons += @($archGun | ForEach-Object { Map-WfcdWeapon -Item $_ -Slot "archgun" })
$convertedWeapons += @($archMelee | ForEach-Object { Map-WfcdWeapon -Item $_ -Slot "archmelee" })
$convertedWeapons += @($sentinelWeapons | ForEach-Object { Map-WfcdWeapon -Item $_ -Slot "companion" })
$convertedMods = @($mods | ForEach-Object { Map-WfcdMod -Item $_ })
$convertedResources = @($resources | ForEach-Object { Map-WfcdResource -Item $_ })
$convertedRelics = @($relics | ForEach-Object { Map-WfcdRelic -Item $_ })
$convertedArcanes = @($arcanes | ForEach-Object { Map-WfcdArcane -Item $_ })
$convertedCompanions = @()
$convertedCompanions += @($pets | ForEach-Object { Map-WfcdCompanion -Item $_ -CompanionKind "pet" })
$convertedCompanions += @($sentinels | ForEach-Object { Map-WfcdCompanion -Item $_ -CompanionKind "sentinel" })
$convertedVehicles = @($archwing | ForEach-Object { Map-WfcdVehicle -Item $_ })
$convertedGear = @($gear | ForEach-Object { Map-WfcdGear -Item $_ })
$convertedEnemies = @($enemies | ForEach-Object { Map-WfcdEnemy -Item $_ })
$convertedActivities = @()
$convertedActivities += @($nodes | ForEach-Object { Map-WfcdNode -Item $_ })
$convertedActivities += @($quests | ForEach-Object { Map-WfcdQuest -Item $_ })

$convertedWarframes | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath (Join-Path $outRoot "wfcd-warframes.json")
$convertedWeapons | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath (Join-Path $outRoot "wfcd-weapons.json")
$convertedMods | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath (Join-Path $outRoot "wfcd-mods.json")
$convertedResources | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath (Join-Path $outRoot "wfcd-resources.json")
$convertedRelics | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath (Join-Path $outRoot "wfcd-relics.json")
$convertedArcanes | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath (Join-Path $outRoot "wfcd-arcanes.json")
$convertedCompanions | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath (Join-Path $outRoot "wfcd-companions.json")
$convertedVehicles | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath (Join-Path $outRoot "wfcd-vehicles.json")
$convertedGear | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath (Join-Path $outRoot "wfcd-gear.json")
$convertedEnemies | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath (Join-Path $outRoot "wfcd-enemies.json")
$convertedActivities | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath (Join-Path $outRoot "wfcd-activities.json")

$manifest = [ordered]@{
    sourceId = "static.wfcd-seed"
    sourceType = "static-export"
    fetchedAt = (Get-Date).ToString("s") + "Z"
    upstreamVersion = "wfcd-master"
    entries = @(
        [ordered]@{ file = "imports/static/source-snapshots/wfcd/wfcd-warframes.json"; domain = "warframes" },
        [ordered]@{ file = "imports/static/source-snapshots/wfcd/wfcd-weapons.json"; domain = "weapons" },
        [ordered]@{ file = "imports/static/source-snapshots/wfcd/wfcd-mods.json"; domain = "mods" },
        [ordered]@{ file = "imports/static/source-snapshots/wfcd/wfcd-resources.json"; domain = "resources" },
        [ordered]@{ file = "imports/static/source-snapshots/wfcd/wfcd-relics.json"; domain = "relics" },
        [ordered]@{ file = "imports/static/source-snapshots/wfcd/wfcd-arcanes.json"; domain = "arcanes" },
        [ordered]@{ file = "imports/static/source-snapshots/wfcd/wfcd-companions.json"; domain = "companions" },
        [ordered]@{ file = "imports/static/source-snapshots/wfcd/wfcd-vehicles.json"; domain = "vehicles" },
        [ordered]@{ file = "imports/static/source-snapshots/wfcd/wfcd-gear.json"; domain = "gear" },
        [ordered]@{ file = "imports/static/source-snapshots/wfcd/wfcd-enemies.json"; domain = "enemies" },
        [ordered]@{ file = "imports/static/source-snapshots/wfcd/wfcd-activities.json"; domain = "activities" }
    )
    normalizesInto = @(
        "content/items/warframes",
        "content/items/weapons",
        "content/items/mods",
        "content/items/resources",
        "content/items/relics",
        "content/items/arcanes",
        "content/items/companions",
        "content/items/vehicles",
        "content/items/gear",
        "content/world/enemies",
        "content/activities"
    )
    notes = @(
        "Converted from WFCD raw category snapshots."
    )
}

$manifestPath = Join-Path $repoRoot "imports\\static\\manifests\\wfcd-static-import.json"
$manifest | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $manifestPath

Write-Host ("Converted WFCD snapshots to staged canonical-source files. Manifest: {0}" -f $manifestPath) -ForegroundColor Green
