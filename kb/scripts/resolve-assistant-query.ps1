param(
    [string]$Root = ".",
    [Parameter(Mandatory = $true)]
    [string]$Query,
    [string]$OutFile = ""
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

function Normalize-Text {
    param([string]$Text)
    return $Text.ToLowerInvariant()
}

function Test-ContainsAny {
    param(
        [string]$Text,
        [string[]]$Terms
    )

    foreach ($term in $Terms) {
        if (-not [string]::IsNullOrWhiteSpace($term) -and $Text.Contains($term.ToLowerInvariant())) {
            return $true
        }
    }

    return $false
}

function Get-NamesFromFolder {
    param(
        [string]$Root,
        [string]$RelativePath
    )

    $folder = Join-Path $Root $RelativePath
    if (-not (Test-Path -LiteralPath $folder)) { return @() }

    $records = @()
    foreach ($file in Get-ChildItem -Path $folder -File -Filter *.json | Where-Object { $_.Name -ne "manifest.json" }) {
        $json = Read-Json -Path $file.FullName
        if ($json.id -and $json.name) {
            $records += [ordered]@{
                id = [string]$json.id
                name = [string]$json.name
                slug = [string]($json.id -replace '^[^.]+\.', '')
            }
        }
    }

    return @($records)
}

function Add-Score {
    param(
        [hashtable]$Scores,
        [hashtable]$Reasons,
        [string]$Intent,
        [int]$Amount,
        [string]$Reason
    )

    if (-not $Scores.ContainsKey($Intent)) {
        $Scores[$Intent] = 0
        $Reasons[$Intent] = New-Object System.Collections.ArrayList
    }

    $Scores[$Intent] += $Amount
    if (-not [string]::IsNullOrWhiteSpace($Reason)) {
        [void]$Reasons[$Intent].Add($Reason)
    }
}

function Resolve-Intent {
    param(
        [string]$Text,
        [hashtable]$Lexicon,
        $Routes
    )

    $normalized = Normalize-Text -Text $Text
    $scores = @{}
    $reasons = @{}

    $hasBuildWord = $normalized -match "\b(build|mod|mods|loadout|setup|use|bring|counter)\b"
    $hasFarmWord = $normalized -match "\b(farm|drop|drops|relic|relics|source|where|obtain|get)\b"
    $hasMissingWord = $normalized -match "\b(missing|need|own|owned|have|inventory|parts?)\b"
    $hasMechanicWord = $normalized -match "\b(what does|how does|explain|mechanic|status|armor|shield|gating|damage|formula|work)\b"
    $hasLookupWord = $normalized -match "\b(show|tell me about|what is|stats|info|lookup)\b"
    $hasMarketWord = $normalized -match "\b(price|market|trade|sell|worth|platinum|plat)\b"

    $hasFaction = Test-ContainsAny -Text $normalized -Terms $Lexicon.factions
    $hasEnemy = Test-ContainsAny -Text $normalized -Terms $Lexicon.enemies
    $hasFrame = Test-ContainsAny -Text $normalized -Terms $Lexicon.frames
    $hasWeapon = Test-ContainsAny -Text $normalized -Terms $Lexicon.weapons
    $hasMod = Test-ContainsAny -Text $normalized -Terms $Lexicon.mods
    $hasEnemyAlias = $normalized -match "\b(nullifier|heavy gunner|ancient healer|battalyst|anomaly host)\b"
    $hasFactionAlias = $normalized -match "\b(grineer|corpus|infested|corrupted|sentient|murmur)\b"
    $hasFaction = $hasFaction -or $hasFactionAlias
    $hasSpecificTarget = ($hasEnemy -and -not $hasFaction) -or $hasEnemyAlias -or $hasFrame -or $hasWeapon
    $hasFactionPlanning = $hasFaction -and ($normalized -match "\b(damage|status|statuses|weak|against|bring|mod for)\b")
    $hasDirectFactionPlanning = (
        ($normalized.Contains("grineer") -or $normalized.Contains("corpus") -or $normalized.Contains("infested") -or $normalized.Contains("corrupted") -or $normalized.Contains("sentient") -or $normalized.Contains("murmur")) -and
        ($normalized.Contains("damage") -or $normalized.Contains("status") -or $normalized.Contains("against") -or $normalized.Contains("bring") -or $normalized.Contains("mod for"))
    )

    if ($hasMarketWord) {
        Add-Score -Scores $scores -Reasons $reasons -Intent "market.price-check" -Amount 18 -Reason "market/price/trade language"
    }
    if ($hasMissingWord) {
        Add-Score -Scores $scores -Reasons $reasons -Intent "inventory.gap-analysis" -Amount 14 -Reason "owned/missing/inventory language"
    }
    if ($hasFarmWord -and -not $hasMarketWord) {
        Add-Score -Scores $scores -Reasons $reasons -Intent "farm.next-target" -Amount 10 -Reason "farm/drop/source language"
    }
    if ($normalized -match "\b(which|what|where).*\b(relic|drop|source|farm)\b" -or $normalized -match "\b(relic|drop|source).*\b(part|reward)\b") {
        Add-Score -Scores $scores -Reasons $reasons -Intent "farm.next-target" -Amount 8 -Reason "relic/source lookup language"
    }
    if ($hasBuildWord -and $hasSpecificTarget -and -not $hasFactionPlanning) {
        Add-Score -Scores $scores -Reasons $reasons -Intent "build.recommendation.for-enemy" -Amount 13 -Reason "build/loadout language with target, frame, or weapon entity"
    }
    if ($hasBuildWord -and $hasFaction) {
        Add-Score -Scores $scores -Reasons $reasons -Intent "build.recommendation.for-faction" -Amount 6 -Reason "build/loadout language with faction entity"
    }
    if (($hasFactionPlanning -and -not $hasSpecificTarget) -or $hasDirectFactionPlanning) {
        Add-Score -Scores $scores -Reasons $reasons -Intent "build.recommendation.for-faction" -Amount 9 -Reason "faction damage/status planning language"
    }
    if ($hasMechanicWord -and -not $hasMarketWord -and -not $hasMissingWord) {
        Add-Score -Scores $scores -Reasons $reasons -Intent "mechanic.explain" -Amount 8 -Reason "mechanics explanation language"
    }
    if ($hasLookupWord -or $hasMod) {
        Add-Score -Scores $scores -Reasons $reasons -Intent "item.lookup" -Amount 6 -Reason "lookup/item fact language"
    }
    if ($scores.Count -eq 0) {
        Add-Score -Scores $scores -Reasons $reasons -Intent "item.lookup" -Amount 1 -Reason "default fallback"
    }

    $routePriority = @{}
    foreach ($route in @(As-Array $Routes.routes)) {
        $routePriority[[string]$route.intent] = [int]$route.priority
    }

    $ranked = @(
        foreach ($key in $scores.Keys) {
            [pscustomobject]@{
                intent = [string]$key
                score = [int]$scores[$key]
                priority = if ($routePriority.ContainsKey($key)) { [int]$routePriority[$key] } else { 0 }
                reasons = @($reasons[$key])
            }
        }
    ) | Sort-Object -Property @(
        @{ Expression = { $_.score }; Descending = $true },
        @{ Expression = { $_.priority }; Descending = $true },
        @{ Expression = { $_.intent }; Descending = $false }
    )

    return $ranked[0]
}

function Find-BestRecord {
    param(
        [string]$Text,
        $Records
    )

    $normalized = Normalize-Text -Text $Text
    $matches = @()
    foreach ($record in @(As-Array $Records)) {
        $name = ([string]$record.name).ToLowerInvariant()
        $slug = ([string]$record.slug).ToLowerInvariant().Replace("-", " ")
        if ($normalized.Contains($name) -or ($slug -and $normalized.Contains($slug))) {
            $matches += $record
        }
    }

    if ($matches.Count -gt 0) { return $matches[0] }
    return $null
}

function Find-BestBuild {
    param(
        [string]$Text,
        $Contract
    )

    $normalized = Normalize-Text -Text $Text
    $candidates = @()

    foreach ($targetProp in @(As-Array $Contract.buildRequests.PSObject.Properties)) {
        $target = $targetProp.Value.target
        $targetScore = 0
        $targetName = ([string]$target.name).ToLowerInvariant()
        $targetFaction = ([string]$target.factionId).ToLowerInvariant() -replace "^faction\.", ""
        if ($normalized.Contains($targetName)) { $targetScore += 20 }
        if ($targetFaction -and $normalized.Contains($targetFaction)) { $targetScore += 8 }

        foreach ($build in @(As-Array $targetProp.Value.recommendedBuilds)) {
            $score = $targetScore + [int]$build.score
            if ($normalized.Contains(([string]$build.frame.name).ToLowerInvariant())) { $score += 6 }
            if ($normalized.Contains(([string]$build.weapon.name).ToLowerInvariant())) { $score += 6 }
            foreach ($alias in @(As-Array $build.queryAliases)) {
                if ($normalized.Contains(([string]$alias).ToLowerInvariant())) { $score += 10 }
            }

            $candidates += [ordered]@{
                score = $score
                target = $target
                build = $build
            }
        }
    }

    if ($candidates.Count -eq 0) { return $null }
    return @($candidates | Sort-Object -Property @{ Expression = { $_.score }; Descending = $true } | Select-Object -First 1)[0]
}

function Find-SearchDocs {
    param(
        [string]$Text,
        $SearchDocs,
        [int]$Limit = 5,
        [string[]]$PreferredPathPrefixes = @()
    )

    $normalized = Normalize-Text -Text $Text
    $terms = @($normalized -split "[^a-z0-9]+" | Where-Object { $_.Length -gt 2 } | Sort-Object -Unique)
    $matches = @()

    foreach ($doc in @(As-Array $SearchDocs)) {
        $docName = ([string]$doc.name).ToLowerInvariant()
        $sourcePath = [string]$doc.sourcePath
        $haystack = ($docName + " " + ([string]$doc.text) + " " + ([string]$doc.id)).ToLowerInvariant()
        $score = 0
        foreach ($term in $terms) {
            if ($haystack.Contains($term)) { $score += 1 }
        }
        if ($docName -and $normalized.Contains($docName)) { $score += 20 }
        foreach ($prefix in $PreferredPathPrefixes) {
            if ($sourcePath.StartsWith($prefix)) {
                $score += 8
            }
        }
        if ($score -gt 0) {
            $matches += [ordered]@{
                id = [string]$doc.id
                name = [string]$doc.name
                category = [string]$doc.category
                subCategory = [string]$doc.subCategory
                sourcePath = $sourcePath
                score = $score
            }
        }
    }

    return @($matches | Sort-Object -Property @(
        @{ Expression = { $_.score }; Descending = $true },
        @{ Expression = { $_.name }; Descending = $false }
    ) | Select-Object -First $Limit)
}

$repoRoot = Resolve-Path $Root
$viewsRoot = Join-Path $repoRoot "ai\\materialized-views"
$routerRoot = Join-Path $repoRoot "ai\\query-router"

$routes = Read-Json -Path (Join-Path $routerRoot "route-map.json")
$contract = Read-Json -Path (Join-Path $viewsRoot "assistant-build-contracts.view.json")
$factionProfiles = Read-Json -Path (Join-Path $viewsRoot "faction-combat-profiles.view.json")
$missingTargets = Read-Json -Path (Join-Path $viewsRoot "player-missing-targets.view.json")
$marketSummary = Read-Json -Path (Join-Path $viewsRoot "market-summary.view.json")
$searchDocs = Read-Json -Path (Join-Path $repoRoot "ai\\search-docs\\records.search.json")

$records = @{
    factions = @(Get-NamesFromFolder -Root $repoRoot -RelativePath "content\\world\\factions")
    enemies = @(Get-NamesFromFolder -Root $repoRoot -RelativePath "content\\world\\enemies")
    frames = @(Get-NamesFromFolder -Root $repoRoot -RelativePath "content\\items\\warframes")
    weapons = @(Get-NamesFromFolder -Root $repoRoot -RelativePath "content\\items\\weapons")
    mods = @(Get-NamesFromFolder -Root $repoRoot -RelativePath "content\\items\\mods")
}

$lexicon = @{
    factions = @($records.factions | ForEach-Object { $_.name.ToLowerInvariant(); $_.slug.ToLowerInvariant().Replace("-", " ") })
    enemies = @($records.enemies | ForEach-Object { $_.name.ToLowerInvariant(); $_.slug.ToLowerInvariant().Replace("-", " ") })
    frames = @($records.frames | ForEach-Object { $_.name.ToLowerInvariant(); $_.slug.ToLowerInvariant().Replace("-", " ") })
    weapons = @($records.weapons | ForEach-Object { $_.name.ToLowerInvariant(); $_.slug.ToLowerInvariant().Replace("-", " ") })
    mods = @($records.mods | ForEach-Object { $_.name.ToLowerInvariant(); $_.slug.ToLowerInvariant().Replace("-", " ") })
}

$intent = Resolve-Intent -Text $Query -Lexicon $lexicon -Routes $routes
$route = @($routes.routes | Where-Object { $_.intent -eq $intent.intent } | Select-Object -First 1)[0]

$response = [ordered]@{
    generatedAt = (Get-Date).ToString("s") + "Z"
    schemaVersion = "assistant-query-response.v1"
    query = $Query
    routing = [ordered]@{
        intent = [string]$intent.intent
        score = [int]$intent.score
        reasons = @(As-Array $intent.reasons)
        primaryView = [string]$route.primaryView
        fallbackViews = @(As-Array $route.fallbackViews)
    }
    responseType = ""
    payload = $null
    sources = @()
}

switch ([string]$intent.intent) {
    "build.recommendation.for-enemy" {
        $match = Find-BestBuild -Text $Query -Contract $contract
        if ($match) {
            $response.responseType = "build.recommendation"
            $response.payload = [ordered]@{
                target = $match.target
                recommendedBuild = $match.build
                responseGuidance = $contract.responseGuidance
            }
            $response.sources = @("ai/materialized-views/assistant-build-contracts.view.json")
        }
    }
    "build.recommendation.for-faction" {
        $faction = Find-BestRecord -Text $Query -Records $records.factions
        $profile = $null
        if ($faction -and $factionProfiles.factions.PSObject.Properties.Name -contains $faction.id) {
            $profile = $factionProfiles.factions.($faction.id)
        }
        $response.responseType = "faction.combat-profile"
        $response.payload = [ordered]@{
            faction = if ($faction) { $faction } else { $null }
            profile = $profile
        }
        $response.sources = @("ai/materialized-views/faction-combat-profiles.view.json")
    }
    "inventory.gap-analysis" {
        $response.responseType = "inventory.gap-analysis"
        $response.payload = [ordered]@{
            playerContext = $contract.playerContext
            wishlistMissingTargets = @(As-Array $missingTargets.missingTargets | Select-Object -First 5)
            farmableNow = @(As-Array $missingTargets.farmableNow | Select-Object -First 5)
        }
        $response.sources = @("ai/materialized-views/assistant-build-contracts.view.json", "ai/materialized-views/player-missing-targets.view.json")
    }
    "farm.next-target" {
        $response.responseType = "farm.next-target"
        $response.payload = [ordered]@{
            missingTargets = @(As-Array $missingTargets.missingTargets | Select-Object -First 3)
            farmableNow = @(As-Array $missingTargets.farmableNow | Select-Object -First 3)
        }
        $response.sources = @("ai/materialized-views/player-missing-targets.view.json")
    }
    "market.price-check" {
        $response.responseType = "market.summary"
        $response.payload = $marketSummary
        $response.sources = @("ai/materialized-views/market-summary.view.json")
    }
    default {
        $response.responseType = "search.lookup"
        $preferredPrefixes = @()
        if ([string]$intent.intent -eq "mechanic.explain") {
            $preferredPrefixes = @("content/systems/")
        }
        $response.payload = [ordered]@{
            matches = @(Find-SearchDocs -Text $Query -SearchDocs $searchDocs -Limit 5 -PreferredPathPrefixes $preferredPrefixes)
        }
        $response.sources = @("ai/search-docs/records.search.json")
    }
}

if ($null -eq $response.payload) {
    $response.responseType = "search.lookup"
    $preferredPrefixes = @()
    if ([string]$intent.intent -eq "mechanic.explain") {
        $preferredPrefixes = @("content/systems/")
    }
    $response.payload = [ordered]@{
        matches = @(Find-SearchDocs -Text $Query -SearchDocs $searchDocs -Limit 5 -PreferredPathPrefixes $preferredPrefixes)
    }
    $response.sources = @("ai/search-docs/records.search.json")
}

$json = $response | ConvertTo-Json -Depth 24
if (-not [string]::IsNullOrWhiteSpace($OutFile)) {
    $outPath = if ([System.IO.Path]::IsPathRooted($OutFile)) { $OutFile } else { Join-Path $repoRoot $OutFile }
    Ensure-Directory -Path ([System.IO.Path]::GetDirectoryName($outPath))
    $json | Set-Content -LiteralPath $outPath
}
else {
    Write-Output $json
}
