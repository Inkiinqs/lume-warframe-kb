param(
    [string]$Root = ".",
    [switch]$WriteReport
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

function Get-NamesFromFolder {
    param(
        [string]$Root,
        [string]$RelativePath
    )

    $folder = Join-Path $Root $RelativePath
    if (-not (Test-Path -LiteralPath $folder)) { return @() }

    $names = @()
    foreach ($file in Get-ChildItem -Path $folder -File -Filter *.json | Where-Object { $_.Name -ne "manifest.json" }) {
        $json = Read-Json -Path $file.FullName
        if ($json.name) {
            $names += ([string]$json.name).ToLowerInvariant()
        }
    }

    return @($names | Sort-Object -Unique)
}

function Test-AnyContains {
    param(
        [string]$Text,
        [string[]]$Needles
    )

    foreach ($needle in $Needles) {
        if (-not [string]::IsNullOrWhiteSpace($needle) -and $Text.Contains($needle)) {
            return $true
        }
    }

    return $false
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

function Resolve-QueryIntent {
    param(
        [string]$Text,
        [hashtable]$Lexicon,
        $Routes
    )

    $normalized = $Text.ToLowerInvariant()
    $scores = @{}
    $reasons = @{}

    $hasBuildWord = $normalized -match "\b(build|mod|mods|loadout|setup|use|bring|counter)\b"
    $hasFarmWord = $normalized -match "\b(farm|drop|drops|relic|relics|source|where|obtain|get)\b"
    $hasMissingWord = $normalized -match "\b(missing|need|own|owned|have|inventory|parts?)\b"
    $hasMechanicWord = $normalized -match "\b(what does|how does|explain|mechanic|status|armor|shield|gating|damage|formula|work)\b"
    $hasLookupWord = $normalized -match "\b(show|tell me about|what is|stats|info|lookup)\b"
    $hasMarketWord = $normalized -match "\b(price|market|trade|sell|worth|platinum|plat)\b"

    $hasFaction = Test-AnyContains -Text $normalized -Needles $Lexicon.factions
    $hasEnemy = Test-AnyContains -Text $normalized -Needles $Lexicon.enemies
    $hasFrame = Test-AnyContains -Text $normalized -Needles $Lexicon.frames
    $hasWeapon = Test-AnyContains -Text $normalized -Needles $Lexicon.weapons
    $hasMod = Test-AnyContains -Text $normalized -Needles $Lexicon.mods
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

$repoRoot = Resolve-Path $Root
$routerRoot = Join-Path $repoRoot "ai\\query-router"
$reportRoot = Join-Path $routerRoot "reports"
Ensure-Directory $routerRoot
if ($WriteReport) { Ensure-Directory $reportRoot }

$routes = Read-Json -Path (Join-Path $routerRoot "route-map.json")
$examples = Read-Json -Path (Join-Path $routerRoot "examples.json")

$lexicon = @{
    factions = @(Get-NamesFromFolder -Root $repoRoot -RelativePath "content\\world\\factions")
    enemies = @(Get-NamesFromFolder -Root $repoRoot -RelativePath "content\\world\\enemies")
    frames = @(Get-NamesFromFolder -Root $repoRoot -RelativePath "content\\items\\warframes")
    weapons = @(Get-NamesFromFolder -Root $repoRoot -RelativePath "content\\items\\weapons")
    mods = @(Get-NamesFromFolder -Root $repoRoot -RelativePath "content\\items\\mods")
}

$results = @()
foreach ($example in @(As-Array $examples.examples)) {
    $prediction = Resolve-QueryIntent -Text ([string]$example.text) -Lexicon $lexicon -Routes $routes
    $passed = [string]$prediction.intent -eq [string]$example.expectedIntent
    $results += [ordered]@{
        text = [string]$example.text
        expectedIntent = [string]$example.expectedIntent
        actualIntent = [string]$prediction.intent
        passed = [bool]$passed
        score = [int]$prediction.score
        reasons = @(As-Array $prediction.reasons)
    }
}

$failed = @($results | Where-Object { -not $_.passed })
$report = [ordered]@{
    generatedAt = (Get-Date).ToString("s") + "Z"
    schemaVersion = "query-router-test-report.v1"
    description = "Deterministic smoke-test report for generated query router examples."
    total = @($results).Count
    passed = @($results | Where-Object { $_.passed }).Count
    failed = $failed.Count
    passRate = if (@($results).Count -gt 0) { [Math]::Round(((@($results | Where-Object { $_.passed }).Count) / @($results).Count) * 100, 2) } else { 0 }
    results = @($results)
}

if ($WriteReport) {
    $report | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $reportRoot "latest.query-router-test-report.json")
}

if ($failed.Count -gt 0) {
    Write-Host ("Query router tests failed: {0}/{1}" -f $failed.Count, @($results).Count) -ForegroundColor Red
    foreach ($failure in $failed) {
        Write-Host ("- {0}: expected {1}, got {2}" -f $failure.text, $failure.expectedIntent, $failure.actualIntent) -ForegroundColor Red
    }
    exit 1
}

Write-Host ("Query router tests passed: {0}/{1}" -f @($results).Count, @($results).Count) -ForegroundColor Green
