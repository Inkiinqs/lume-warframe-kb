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

function Test-RelativePath {
    param(
        [string]$Root,
        [string]$RelativePath
    )

    return Test-Path -LiteralPath (Join-Path $Root ($RelativePath -replace "/", "\"))
}

$repoRoot = Resolve-Path $Root
$routerRoot = Join-Path $repoRoot "ai\\query-router"
Ensure-Directory $routerRoot

$viewsRoot = Join-Path $repoRoot "ai\\materialized-views"
$searchPath = "ai/search-docs/records.search.json"

$routeSpecs = @(
    [ordered]@{
        intent = "build.recommendation.for-enemy"
        description = "Answer requests for a build, loadout, or mod plan against a named enemy or benchmark target."
        priority = 100
        requiredSignals = @("build", "enemy")
        optionalSignals = @("warframe", "weapon", "owned inventory", "missing mods")
        primaryView = "ai/materialized-views/assistant-build-contracts.view.json"
        fallbackViews = @(
            "ai/materialized-views/player-build-skeletons.view.json",
            "ai/materialized-views/player-combat-recommendations.view.json",
            "ai/materialized-views/enemy-matchups.view.json",
            $searchPath
        )
        contentScopes = @("content/world/enemies", "content/items/warframes", "content/items/weapons", "content/items/mods", "content/systems/status-effects", "content/systems/damage")
        examples = @(
            "make me a Rhino build for Murmur",
            "what should I use against a Nullifier",
            "build my Acceltra for Corrupted Heavy Gunner"
        )
    }
    [ordered]@{
        intent = "build.recommendation.for-faction"
        description = "Answer faction-level loadout and damage-type questions."
        priority = 90
        requiredSignals = @("build", "faction")
        optionalSignals = @("damage type", "status effect", "owned inventory")
        primaryView = "ai/materialized-views/faction-combat-profiles.view.json"
        fallbackViews = @(
            "ai/materialized-views/player-combat-recommendations.view.json",
            "ai/materialized-views/combat-mod-profiles.view.json",
            $searchPath
        )
        contentScopes = @("content/world/factions", "content/systems/status-effects", "content/systems/damage", "content/items/mods")
        examples = @(
            "what damage should I bring against Corpus",
            "best statuses for Grineer",
            "how do I mod for Infested"
        )
    }
    [ordered]@{
        intent = "inventory.gap-analysis"
        description = "Answer owned-versus-missing questions for builds, mods, parts, and wishlist targets."
        priority = 85
        requiredSignals = @("inventory", "missing")
        optionalSignals = @("build", "wishlist", "crafting", "owned mods")
        primaryView = "ai/materialized-views/assistant-build-contracts.view.json"
        fallbackViews = @(
            "ai/materialized-views/player-owned-summary.view.json",
            "ai/materialized-views/player-missing-targets.view.json",
            "ai/materialized-views/item-to-parts.view.json",
            $searchPath
        )
        contentScopes = @("player/inventory-tracking", "player/wishlist", "content/items")
        examples = @(
            "what am I missing for this build",
            "do I own the mods for Acceltra",
            "what parts am I missing for Saryn Prime"
        )
    }
    [ordered]@{
        intent = "farm.next-target"
        description = "Answer where-to-farm and what-to-farm-next questions."
        priority = 80
        requiredSignals = @("farm", "target")
        optionalSignals = @("relic", "drop source", "wishlist", "progression")
        primaryView = "ai/materialized-views/player-missing-targets.view.json"
        fallbackViews = @(
            "ai/materialized-views/part-to-sources.view.json",
            "ai/materialized-views/part-to-relics.view.json",
            "ai/materialized-views/relic-to-rewards.view.json",
            "ai/materialized-views/market-summary.view.json",
            $searchPath
        )
        contentScopes = @("content/items/relics", "content/items/resources", "content/activities", "content/relationships/drops")
        examples = @(
            "where do I farm Saryn Prime Systems",
            "what should I farm next",
            "which relic has this part"
        )
    }
    [ordered]@{
        intent = "mechanic.explain"
        description = "Explain Warframe systems such as status effects, damage, scaling, modding rules, drops, abilities, and mission rules."
        priority = 75
        requiredSignals = @("mechanic", "explain")
        optionalSignals = @("status effect", "damage type", "formula", "mission rule")
        primaryView = $searchPath
        fallbackViews = @(
            "ai/materialized-views/faction-combat-profiles.view.json",
            "ai/materialized-views/enemy-matchups.view.json"
        )
        contentScopes = @("content/systems/status-effects", "content/systems/damage", "content/systems/combat-formulas", "content/systems/modding-rules", "content/systems/ability-rules", "content/systems/drop-rules", "content/systems/enemy-scaling", "content/systems/mission-rules")
        examples = @(
            "what does Heat status do",
            "how does armor work",
            "explain shield gating"
        )
    }
    [ordered]@{
        intent = "item.lookup"
        description = "Look up canonical item facts, stats, relationships, and source paths."
        priority = 65
        requiredSignals = @("item", "lookup")
        optionalSignals = @("warframe", "weapon", "mod", "resource", "relic", "arcane")
        primaryView = $searchPath
        fallbackViews = @(
            "ai/materialized-views/item-to-parts.view.json",
            "ai/materialized-views/part-to-sources.view.json",
            "ai/materialized-views/market-summary.view.json"
        )
        contentScopes = @("content/items")
        examples = @(
            "show me Acceltra stats",
            "what is Condition Overload",
            "tell me about Rhino"
        )
    }
    [ordered]@{
        intent = "market.price-check"
        description = "Answer market-aware questions when normalized market snapshots exist."
        priority = 55
        requiredSignals = @("market", "price")
        optionalSignals = @("trade", "wishlist", "owned inventory")
        primaryView = "ai/materialized-views/market-summary.view.json"
        fallbackViews = @($searchPath)
        contentScopes = @("imports/market", "content/items")
        examples = @(
            "is this part worth selling",
            "price check Saryn Prime Systems",
            "what should I trade"
        )
    }
)

$routes = [ordered]@{
    generatedAt = (Get-Date).ToString("s") + "Z"
    schemaVersion = "query-router.v1"
    description = "Routes assistant intents to the correct generated views and canonical content scopes."
    defaultRoute = [ordered]@{
        intent = "item.lookup"
        primaryView = $searchPath
        reason = "Generic lookup is the safest fallback because search docs cover canonical content records."
    }
    routes = @()
}

$examples = [ordered]@{
    generatedAt = $routes.generatedAt
    schemaVersion = "query-router-examples.v1"
    description = "Example utterances for query-router tests and future classifier prompts."
    examples = @()
}

foreach ($spec in $routeSpecs) {
    $allPaths = @($spec.primaryView) + @($spec.fallbackViews) + @($spec.contentScopes)
    $available = @()
    $missing = @()
    foreach ($path in $allPaths) {
        if (Test-RelativePath -Root $repoRoot -RelativePath $path) {
            $available += $path
        }
        else {
            $missing += $path
        }
    }

    $routes.routes += [ordered]@{
        intent = $spec.intent
        description = $spec.description
        priority = $spec.priority
        requiredSignals = @($spec.requiredSignals)
        optionalSignals = @($spec.optionalSignals)
        primaryView = $spec.primaryView
        fallbackViews = @($spec.fallbackViews)
        contentScopes = @($spec.contentScopes)
        availability = [ordered]@{
            availablePaths = @($available)
            missingPaths = @($missing)
        }
    }

    foreach ($example in @($spec.examples)) {
        $examples.examples += [ordered]@{
            text = $example
            expectedIntent = $spec.intent
            primaryView = $spec.primaryView
        }
    }
}

$intentIndex = [ordered]@{
    generatedAt = $routes.generatedAt
    schemaVersion = "query-router-intents.v1"
    description = "Compact intent catalog for assistant routing prompts."
    intents = @($routes.routes | ForEach-Object {
        [ordered]@{
            intent = $_.intent
            description = $_.description
            priority = $_.priority
            requiredSignals = @($_.requiredSignals)
            optionalSignals = @($_.optionalSignals)
        }
    })
}

$routes | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath (Join-Path $routerRoot "route-map.json")
$intentIndex | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath (Join-Path $routerRoot "intents.json")
$examples | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $routerRoot "examples.json")

Write-Host ("Generated query router with {0} routes and {1} examples." -f $routes.routes.Count, $examples.examples.Count) -ForegroundColor Green
