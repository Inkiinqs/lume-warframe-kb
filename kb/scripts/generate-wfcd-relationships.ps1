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

function Ensure-Directory {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) {
        New-Item -ItemType Directory -Force -Path $Path | Out-Null
    }
}

function Write-JsonFile {
    param(
        [string]$Path,
        $Object
    )
    $Object | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $Path
}

function Get-CanonicalItemId {
    param(
        [pscustomobject]$Item,
        [string]$Slot
    )

    $slug = Convert-ToSlug $Item.name
    switch ($Slot) {
        "warframe" { return "warframe.$slug" }
        "primary" { return "weapon.$slug" }
        "secondary" { return "weapon.$slug" }
        "melee" { return "weapon.$slug" }
        default { return "item.$slug" }
    }
}

function Get-ExistingIds {
    param([string]$Folder)
    $ids = @{}
    if (-not (Test-Path -LiteralPath $Folder)) { return $ids }
    Get-ChildItem -LiteralPath $Folder -File -Filter *.json | Where-Object { $_.Name -ne "manifest.json" } | ForEach-Object {
        try {
            $json = Get-Content -Raw -LiteralPath $_.FullName | ConvertFrom-Json
            if ($json.id) { $ids[[string]$json.id] = $_.FullName }
        }
        catch {}
    }
    return $ids
}

function New-PartRecord {
    param(
        [string]$PartId,
        [string]$Name,
        [string]$Description,
        [string]$ParentId,
        [string]$SourceLabel
    )

    [ordered]@{
        id = $PartId
        name = $Name
        category = "item_part"
        subCategory = "component"
        aliases = @()
        summary = if ($Description) { $Description } else { "$Name imported from WFCD relationship generation." }
        description = $Description
        stats = [ordered]@{}
        mechanics = [ordered]@{}
        relationships = @($ParentId)
        release = [ordered]@{}
        tags = @("part", "wfcd-generated")
        notes = @("Generated from WFCD component or relic reward data.")
        sources = @(
            [ordered]@{
                type = "wfcd-generated"
                value = $SourceLabel
            }
        )
    }
}

function Resolve-ComponentId {
    param(
        [pscustomobject]$Component,
        [string]$ParentId,
        [hashtable]$ExistingIds
    )

    $resourceSlug = Convert-ToSlug $Component.name
    $resourceId = "resource.$resourceSlug"
    if ($ExistingIds.ContainsKey($resourceId)) {
        return $resourceId
    }

    $parentSlug = ($ParentId -split "\.", 2)[1]
    $componentSlug = Convert-ToSlug $Component.name
    return "part.$parentSlug-$componentSlug"
}

function Create-CraftingRelationship {
    param(
        [string]$ParentId,
        [string]$ComponentId,
        [pscustomobject]$Component
    )

    $rid = "relationship.craft-" + (Convert-ToSlug (($ParentId -split "\.", 2)[1] + "-" + ($ComponentId -split "\.", 2)[1]))
    [ordered]@{
        id = $rid
        type = "crafting_dependency"
        from = $ParentId
        to = $ComponentId
        summary = "$ParentId requires $($Component.name) as a crafting component."
        conditions = [ordered]@{}
        values = [ordered]@{
            itemCount = $Component.itemCount
            componentName = $Component.name
        }
        tags = @("crafting", "wfcd-generated")
        sources = @(
            [ordered]@{
                type = "wfcd-generated"
                value = "component:$($ParentId)"
            }
        )
    }
}

function Create-DropRelationship {
    param(
        [string]$ComponentId,
        [pscustomobject]$Drop,
        [string]$ParentId
    )

    $locationSlug = Convert-ToSlug $Drop.location
    $rid = "relationship.drop-" + (Convert-ToSlug ((($ComponentId -split "\.", 2)[1]) + "-" + $locationSlug))
    [ordered]@{
        id = $rid
        type = "wfcd_drop"
        from = "source.$locationSlug"
        to = $ComponentId
        summary = "$($Drop.location) can drop $($Drop.type)."
        conditions = [ordered]@{}
        values = [ordered]@{
            location = $Drop.location
            chance = $Drop.chance
            rarity = $Drop.rarity
            rewardType = $Drop.type
            parentId = $ParentId
        }
        tags = @("drop", "wfcd-generated")
        sources = @(
            [ordered]@{
                type = "wfcd-generated"
                value = "drop:$($ParentId)"
            }
        )
    }
}

function Create-RelicRewardRelationship {
    param(
        [string]$RelicId,
        [string]$PartId,
        [pscustomobject]$Reward
    )

    $rid = "relationship.relic-reward-" + (Convert-ToSlug ((($RelicId -split "\.", 2)[1]) + "-" + (($PartId -split "\.", 2)[1])))
    [ordered]@{
        id = $rid
        type = "relic_reward"
        from = $RelicId
        to = $PartId
        summary = "$RelicId contains $($Reward.item.name) as a reward."
        conditions = [ordered]@{
            rarity = $Reward.rarity
        }
        values = [ordered]@{
            chance = $Reward.chance
            rewardName = $Reward.item.name
        }
        tags = @("relic", "reward", "wfcd-generated")
        sources = @(
            [ordered]@{
                type = "wfcd-generated"
                value = "relic:$RelicId"
            }
        )
    }
}

$repoRoot = Resolve-Path $Root
$rawRoot = Join-Path $repoRoot "imports\\static\\source-snapshots\\wfcd\\raw"

$resourceFolder = Join-Path $repoRoot "content\\items\\resources"
$craftingFolder = Join-Path $repoRoot "content\\relationships\\crafting"
$dropsFolder = Join-Path $repoRoot "content\\relationships\\drops"
$referencesFolder = Join-Path $repoRoot "content\\relationships\\references"

Ensure-Directory $resourceFolder
Ensure-Directory $craftingFolder
Ensure-Directory $dropsFolder
Ensure-Directory $referencesFolder

$existingIds = Get-ExistingIds -Folder $resourceFolder

$warframes = Get-Content -Raw -LiteralPath (Join-Path $rawRoot "Warframes.json") | ConvertFrom-Json
$primary = Get-Content -Raw -LiteralPath (Join-Path $rawRoot "Primary.json") | ConvertFrom-Json
$secondary = Get-Content -Raw -LiteralPath (Join-Path $rawRoot "Secondary.json") | ConvertFrom-Json
$melee = Get-Content -Raw -LiteralPath (Join-Path $rawRoot "Melee.json") | ConvertFrom-Json
$relics = Get-Content -Raw -LiteralPath (Join-Path $rawRoot "Relics.json") | ConvertFrom-Json

$allItems = @()
$allItems += @($warframes | ForEach-Object { [pscustomobject]@{ slot = "warframe"; item = $_ } })
$allItems += @($primary | ForEach-Object { [pscustomobject]@{ slot = "primary"; item = $_ } })
$allItems += @($secondary | ForEach-Object { [pscustomobject]@{ slot = "secondary"; item = $_ } })
$allItems += @($melee | ForEach-Object { [pscustomobject]@{ slot = "melee"; item = $_ } })

$craftedCount = 0
$dropCount = 0
$partCount = 0
$relicRewardCount = 0

foreach ($entry in $allItems) {
    $parentId = Get-CanonicalItemId -Item $entry.item -Slot $entry.slot
    if (-not $entry.item.components) { continue }

    foreach ($component in $entry.item.components) {
        $componentId = Resolve-ComponentId -Component $component -ParentId $parentId -ExistingIds $existingIds
        if (-not $existingIds.ContainsKey($componentId)) {
            $partPath = Join-Path $resourceFolder ((($componentId -split "\.", 2)[1]) + ".json")
            $partRecord = New-PartRecord -PartId $componentId -Name $component.name -Description $component.description -ParentId $parentId -SourceLabel "component:$parentId"
            Write-JsonFile -Path $partPath -Object $partRecord
            $existingIds[$componentId] = $partPath
            $partCount++
        }

        $crafting = Create-CraftingRelationship -ParentId $parentId -ComponentId $componentId -Component $component
        $craftPath = Join-Path $craftingFolder ((($crafting.id -split "\.", 2)[1]) + ".json")
        Write-JsonFile -Path $craftPath -Object $crafting
        $craftedCount++

        foreach ($drop in @($component.drops)) {
            $dropRel = Create-DropRelationship -ComponentId $componentId -Drop $drop -ParentId $parentId
            $dropPath = Join-Path $dropsFolder ((($dropRel.id -split "\.", 2)[1]) + ".json")
            Write-JsonFile -Path $dropPath -Object $dropRel
            $dropCount++
        }
    }
}

foreach ($relic in $relics) {
    $relicId = "relic." + (Convert-ToSlug $relic.name)
    foreach ($reward in @($relic.rewards)) {
        $rewardName = $reward.item.name
        $rewardSlug = Convert-ToSlug $rewardName
        $partId = "part.$rewardSlug"
        if (-not $existingIds.ContainsKey($partId)) {
            $partPath = Join-Path $resourceFolder ($rewardSlug + ".json")
            $partRecord = New-PartRecord -PartId $partId -Name $rewardName -Description $null -ParentId $relicId -SourceLabel "relic:$relicId"
            Write-JsonFile -Path $partPath -Object $partRecord
            $existingIds[$partId] = $partPath
            $partCount++
        }

        $rewardRel = Create-RelicRewardRelationship -RelicId $relicId -PartId $partId -Reward $reward
        $rewardPath = Join-Path $referencesFolder ((($rewardRel.id -split "\.", 2)[1]) + ".json")
        Write-JsonFile -Path $rewardPath -Object $rewardRel
        $relicRewardCount++
    }
}

Write-Host ("Generated {0} part records, {1} crafting relationships, {2} drop relationships, {3} relic reward relationships." -f $partCount, $craftedCount, $dropCount, $relicRewardCount) -ForegroundColor Green
