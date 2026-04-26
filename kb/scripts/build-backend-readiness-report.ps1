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

function Count-Files {
    param(
        [string]$Path,
        [string]$Filter = "*.json"
    )

    if (-not (Test-Path -LiteralPath $Path)) { return 0 }
    return @(Get-ChildItem -Path $Path -Recurse -File -Filter $Filter).Count
}

function Get-ViewSummaries {
    param([string]$ViewsRoot)

    if (-not (Test-Path -LiteralPath $ViewsRoot)) { return @() }
    return @(Get-ChildItem -Path $ViewsRoot -File -Filter *.json | Sort-Object Name | ForEach-Object {
        [ordered]@{
            name = $_.Name
            path = $_.FullName.Replace((Resolve-Path ".").Path + "\", "").Replace("\", "/")
            bytes = $_.Length
        }
    })
}

function Test-PathStatus {
    param(
        [string]$Root,
        [string]$RelativePath
    )

    return Test-Path -LiteralPath (Join-Path $Root ($RelativePath -replace "/", "\"))
}

$repoRoot = Resolve-Path $Root
$outRoot = Join-Path $repoRoot "backend-readiness"
Ensure-Directory $outRoot

$viewsRoot = Join-Path $repoRoot "ai\\materialized-views"
$routerPath = Join-Path $repoRoot "ai\\query-router\\route-map.json"
$routerTestPath = Join-Path $repoRoot "ai\\query-router\\reports\\latest.query-router-test-report.json"
$backendApiTestPath = Join-Path $repoRoot "backend-api-contracts\\reports\\latest.backend-api-contract-test-report.json"
$endpointPath = Join-Path $repoRoot "backend-api-contracts\\endpoints.json"
$assistantContractPath = Join-Path $viewsRoot "assistant-build-contracts.view.json"

$router = Read-Json -Path $routerPath
$routerTest = Read-Json -Path $routerTestPath
$backendApiTest = if (Test-Path -LiteralPath $backendApiTestPath) { Read-Json -Path $backendApiTestPath } else { $null }
$endpoints = Read-Json -Path $endpointPath
$assistantContract = Read-Json -Path $assistantContractPath

$routeMissingPaths = @()
foreach ($route in @($router.routes)) {
    foreach ($missing in @($route.availability.missingPaths)) {
        $routeMissingPaths += [ordered]@{
            intent = [string]$route.intent
            path = [string]$missing
        }
    }
}

$endpointSummaries = @()
foreach ($endpoint in @($endpoints.endpoints)) {
    $linkedPaths = @($endpoint.requestExample, $endpoint.responseExample, $endpoint.implementationAnchor) + @($endpoint.sourceContracts)
    $missingLinks = @($linkedPaths | Where-Object { -not (Test-PathStatus -Root $repoRoot -RelativePath ([string]$_)) })
    $endpointSummaries += [ordered]@{
        id = [string]$endpoint.id
        method = [string]$endpoint.method
        path = [string]$endpoint.path
        implementationAnchor = [string]$endpoint.implementationAnchor
        linkedPathCount = @($linkedPaths).Count
        missingLinks = @($missingLinks)
    }
}

$buildTargetCount = @($assistantContract.buildRequests.PSObject.Properties).Count
$buildRecommendationCount = 0
foreach ($target in @($assistantContract.buildRequests.PSObject.Properties)) {
    $buildRecommendationCount += @($target.Value.recommendedBuilds).Count
}

$report = [ordered]@{
    generatedAt = (Get-Date).ToString("s") + "Z"
    schemaVersion = "backend-readiness-report.v1"
    summary = [ordered]@{
        status = if ($routerTest.failed -eq 0 -and $routeMissingPaths.Count -eq 0 -and ($null -eq $backendApiTest -or $backendApiTest.failed -eq 0)) { "ready-for-local-api-prototype" } else { "needs-attention" }
        repoJsonFiles = Count-Files -Path $repoRoot -Filter "*.json"
        canonicalContentFiles = Count-Files -Path (Join-Path $repoRoot "content") -Filter "*.json"
        aiMaterializedViewCount = @(Get-ChildItem -Path $viewsRoot -File -Filter *.json).Count
        backendEndpointCount = @($endpoints.endpoints).Count
        queryRouteCount = @($router.routes).Count
        queryExampleCount = [int]$routerTest.total
        queryExamplePassRate = [double]$routerTest.passRate
        backendApiContractPassRate = if ($backendApiTest) { [double]$backendApiTest.passRate } else { $null }
        assistantBuildTargets = $buildTargetCount
        assistantBuildRecommendations = $buildRecommendationCount
    }
    implementedLayers = @(
        [ordered]@{
            id = "canonical-knowledge-base"
            status = "implemented"
            paths = @("content", "core/schemas", "core/mappings")
        },
        [ordered]@{
            id = "ai-search-and-views"
            status = "implemented"
            paths = @("ai/search-docs", "ai/materialized-views")
        },
        [ordered]@{
            id = "combat-recommendation-layer"
            status = "implemented"
            paths = @("ai/materialized-views/faction-combat-profiles.view.json", "ai/materialized-views/enemy-matchups.view.json", "ai/materialized-views/player-combat-recommendations.view.json")
        },
        [ordered]@{
            id = "assistant-contract-layer"
            status = "implemented"
            paths = @("ai/materialized-views/assistant-build-contracts.view.json", "core/schemas/assistant-query-response.schema.json")
        },
        [ordered]@{
            id = "assistant-live-context-layer"
            status = "implemented"
            paths = @("ai/materialized-views/assistant-live-context.view.json", "scripts/build-assistant-live-context.ps1", "local-api/src/services/live-context-service.mjs")
        },
        [ordered]@{
            id = "live-context-polling-transport"
            status = "prototype"
            paths = @("local-api/src/services/live-context-service.mjs", "backend-api-contracts/examples/player-live-context-poll.request.json", "scripts/test-local-api.ps1")
        },
        [ordered]@{
            id = "live-context-auto-refresh"
            status = "prototype"
            paths = @("local-api/src/services/live-context-refresh-service.mjs", "scripts/test-live-context-auto-refresh.ps1", "ai/materialized-views/assistant-live-context.view.json")
        },
        [ordered]@{
            id = "query-router-layer"
            status = "implemented"
            paths = @("ai/query-router/route-map.json", "ai/query-router/examples.json", "scripts/test-query-router.ps1")
        },
        [ordered]@{
            id = "backend-api-contract-layer"
            status = "implemented"
            paths = @("backend-api-contracts/endpoints.json", "backend-api-contracts/examples")
        },
        [ordered]@{
            id = "local-http-api-prototype"
            status = "implemented"
            paths = @("local-api/server.mjs", "scripts/test-local-api.ps1")
        },
        [ordered]@{
            id = "overlay-inventory-sync"
            status = "prototype"
            paths = @("imports/overlay-sync", "scripts/import-overlay-inventory.ps1", "scripts/test-overlay-write-mode.ps1")
        },
        [ordered]@{
            id = "overlay-loadout-sync"
            status = "prototype"
            paths = @("local-api/src/services/loadout-service.mjs", "backend-api-contracts/examples/overlay-loadout-sync.request.json", "scripts/test-overlay-loadout-sync.ps1")
        },
        [ordered]@{
            id = "overlay-mission-sync"
            status = "prototype"
            paths = @("local-api/src/services/mission-service.mjs", "backend-api-contracts/examples/overlay-mission-sync.request.json", "scripts/test-overlay-mission-sync.ps1")
        },
        [ordered]@{
            id = "overlay-event-feed"
            status = "prototype"
            paths = @("local-api/src/services/event-feed-service.mjs", "backend-api-contracts/examples/overlay-event-feed.request.json", "scripts/test-overlay-event-feed.ps1")
        }
    )
    endpointContracts = @($endpointSummaries)
    validations = [ordered]@{
        queryRouterExamples = [ordered]@{
            status = if ($routerTest.failed -eq 0) { "passed" } else { "failed" }
            total = [int]$routerTest.total
            passed = [int]$routerTest.passed
            failed = [int]$routerTest.failed
            passRate = [double]$routerTest.passRate
            report = "ai/query-router/reports/latest.query-router-test-report.json"
        }
        assistantContracts = [ordered]@{
            status = "passed-in-build"
            script = "scripts/validate-assistant-contracts.ps1"
        }
        backendApiContracts = [ordered]@{
            status = "passed-in-build"
            script = "scripts/validate-backend-api-contracts.ps1"
        }
        localApiSmokeTest = [ordered]@{
            status = "available"
            script = "scripts/test-local-api.ps1"
            note = "Run separately when HTTP smoke coverage is needed; it starts and stops the local Node server."
        }
        overlayPersistentWriteTest = [ordered]@{
            status = "available"
            script = "scripts/test-overlay-write-mode.ps1"
            note = "Uses a temporary test player to verify unauthenticated writes are blocked, confirmed authenticated writes succeed, backups are created, and cleanup runs."
        }
        overlayLoadoutWriteTest = [ordered]@{
            status = "available"
            script = "scripts/test-overlay-loadout-sync.ps1"
            note = "Uses a temporary test player to verify unauthenticated loadout writes are blocked, confirmed authenticated writes update session/build upgrade state, backups are created, and cleanup runs."
        }
        overlayMissionWriteTest = [ordered]@{
            status = "available"
            script = "scripts/test-overlay-mission-sync.ps1"
            note = "Uses a temporary test player to verify unauthenticated mission writes are blocked, confirmed authenticated writes update current mission context, backups are created, and cleanup runs."
        }
        overlayEventFeedWriteTest = [ordered]@{
            status = "available"
            script = "scripts/test-overlay-event-feed.ps1"
            note = "Uses a temporary test player to verify unauthenticated event-feed writes are blocked, confirmed authenticated writes append rolling session history, backups are created, recent drops are promoted, and cleanup runs."
        }
        liveContextAutoRefreshTest = [ordered]@{
            status = "available"
            script = "scripts/test-live-context-auto-refresh.ps1"
            note = "Uses a backed-up demo session to verify confirmed overlay writes refresh assistant live context and change-token polling returns modified context, then restores the session."
        }
        backendApiContractTests = [ordered]@{
            status = if ($backendApiTest -and $backendApiTest.failed -eq 0) { "passed" } elseif ($backendApiTest) { "failed" } else { "not-run" }
            total = if ($backendApiTest) { [int]$backendApiTest.total } else { 0 }
            passed = if ($backendApiTest) { [int]$backendApiTest.passed } else { 0 }
            failed = if ($backendApiTest) { [int]$backendApiTest.failed } else { 0 }
            passRate = if ($backendApiTest) { [double]$backendApiTest.passRate } else { 0 }
            report = "backend-api-contracts/reports/latest.backend-api-contract-test-report.json"
        }
        repositoryJson = [ordered]@{
            status = "passed-in-build"
            script = "scripts/validate-kb.ps1"
        }
        routeMissingPaths = @($routeMissingPaths)
    }
    generatedViews = @(Get-ChildItem -Path $viewsRoot -File -Filter *.json | Sort-Object Name | ForEach-Object {
        [ordered]@{
            name = $_.Name
            path = $_.FullName.Replace($repoRoot.Path + "\", "").Replace("\", "/")
            bytes = $_.Length
        }
    })
    knownGaps = @(
        [ordered]@{
            id = "local-http-server"
            status = "prototype"
            note = "Dependency-free local Node API exists. It is suitable for local smoke testing, not production hosting."
        },
        [ordered]@{
            id = "live-game-state-ingest"
            status = "partial-prototype"
            note = "Overlay inventory, loadout, mission context, and append-only event-feed sync have preview and confirmed write paths. Assistant live context now has change-token polling transport and automatic refresh for supported materialized players; websocket streaming is not implemented."
        },
        [ordered]@{
            id = "full-build-optimizer"
            status = "starter-skeleton-with-fit-estimates"
            note = "Build recommendations are target-aware starter skeletons with first-pass mastery, capacity, mod rank, polarity, reactor/catalyst, aura/stance, and forma-polarity estimates when player upgradeState provides those fields. Overlay loadout sync can now capture that upgradeState, but exilus, exact slot layout, arcanes, shards, helminth, rivens, and exact level tuning are not fully modeled yet."
        },
        [ordered]@{
            id = "live-market-refresh"
            status = "partial"
            note = "Market snapshot normalization exists for sample/current watched items, but broad live market coverage is not complete."
        },
        [ordered]@{
            id = "external-app-integration"
            status = "not-started"
            note = "Backend contracts are ready for a future app adapter, but no app code is wired here."
        }
    )
    nextRecommendedSteps = @(
        "Extend loadout upgrade-state capture with exilus slots, exact mod slot layout, arcanes, shards, helminth, rivens, and exact rank/level details.",
        "Generalize player-aware materialized views beyond player.demo-account so live-context refresh can support multiple local profiles."
    )
}

$report | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath (Join-Path $outRoot "latest.backend-readiness.json")

Write-Host "Generated backend readiness report." -ForegroundColor Green
