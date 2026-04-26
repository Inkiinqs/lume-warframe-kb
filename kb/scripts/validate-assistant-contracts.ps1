param(
    [string]$Root = "."
)

$ErrorActionPreference = "Stop"

function Read-Json {
    param([string]$Path)
    Get-Content -Raw -LiteralPath $Path | ConvertFrom-Json
}

function Add-Issue {
    param(
        [System.Collections.ArrayList]$Issues,
        [string]$Path,
        [string]$Message
    )

    [void]$Issues.Add([ordered]@{
        path = $Path
        message = $Message
    })
}

function Has-Property {
    param(
        $Object,
        [string]$Name
    )

    return $Object.PSObject.Properties.Name -contains $Name
}

function Require-Properties {
    param(
        [System.Collections.ArrayList]$Issues,
        [string]$Path,
        $Object,
        [string[]]$Names
    )

    foreach ($name in $Names) {
        if (-not (Has-Property -Object $Object -Name $name)) {
            Add-Issue -Issues $Issues -Path $Path -Message "Missing required property '$name'."
        }
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
$issues = New-Object System.Collections.ArrayList

$schemaFiles = @(
    "core/schemas/assistant-build-contract.schema.json",
    "core/schemas/query-router.schema.json",
    "core/schemas/assistant-query-response.schema.json"
)

foreach ($schemaFile in $schemaFiles) {
    $path = Join-Path $repoRoot ($schemaFile -replace "/", "\")
    if (-not (Test-Path -LiteralPath $path)) {
        Add-Issue -Issues $issues -Path $schemaFile -Message "Schema file missing."
        continue
    }

    $schema = Read-Json -Path $path
    Require-Properties -Issues $issues -Path $schemaFile -Object $schema -Names @('$schema', '$id', 'title', 'type', 'required', 'properties')
}

$buildContractPath = "ai/materialized-views/assistant-build-contracts.view.json"
$routeMapPath = "ai/query-router/route-map.json"
$sampleResponseGlob = Join-Path $repoRoot "ai\\query-router\\reports\\sample-*-response.json"

$buildContract = Read-Json -Path (Join-Path $repoRoot ($buildContractPath -replace "/", "\"))
Require-Properties -Issues $issues -Path $buildContractPath -Object $buildContract -Names @(
    "generatedAt",
    "schemaVersion",
    "playerId",
    "supportedIntents",
    "responseGuidance",
    "playerContext",
    "buildRequests",
    "fallbackViews"
)
if ($buildContract.schemaVersion -ne "assistant-build-contract.v1") {
    Add-Issue -Issues $issues -Path $buildContractPath -Message "Expected schemaVersion assistant-build-contract.v1."
}
if (@($buildContract.buildRequests.PSObject.Properties).Count -eq 0) {
    Add-Issue -Issues $issues -Path $buildContractPath -Message "buildRequests must contain at least one target."
}
foreach ($targetProp in @($buildContract.buildRequests.PSObject.Properties)) {
    $targetPath = "$buildContractPath/buildRequests/$($targetProp.Name)"
    Require-Properties -Issues $issues -Path $targetPath -Object $targetProp.Value -Names @("target", "recommendedBuilds")
    if (@($targetProp.Value.recommendedBuilds).Count -eq 0) {
        Add-Issue -Issues $issues -Path $targetPath -Message "recommendedBuilds must contain at least one build."
    }
}

$routeMap = Read-Json -Path (Join-Path $repoRoot ($routeMapPath -replace "/", "\"))
Require-Properties -Issues $issues -Path $routeMapPath -Object $routeMap -Names @("generatedAt", "schemaVersion", "defaultRoute", "routes")
if ($routeMap.schemaVersion -ne "query-router.v1") {
    Add-Issue -Issues $issues -Path $routeMapPath -Message "Expected schemaVersion query-router.v1."
}
foreach ($route in @($routeMap.routes)) {
    $routePath = "$routeMapPath/routes/$($route.intent)"
    Require-Properties -Issues $issues -Path $routePath -Object $route -Names @(
        "intent",
        "description",
        "priority",
        "requiredSignals",
        "optionalSignals",
        "primaryView",
        "fallbackViews",
        "contentScopes",
        "availability"
    )
    if (-not (Test-RelativePath -Root $repoRoot -RelativePath ([string]$route.primaryView))) {
        Add-Issue -Issues $issues -Path $routePath -Message "primaryView does not exist: $($route.primaryView)"
    }
    if (@($route.availability.missingPaths).Count -gt 0) {
        Add-Issue -Issues $issues -Path $routePath -Message "Route has missing paths: $(@($route.availability.missingPaths) -join ', ')"
    }
}

$allowedResponseTypes = @(
    "build.recommendation",
    "faction.combat-profile",
    "inventory.gap-analysis",
    "farm.next-target",
    "market.summary",
    "search.lookup"
)

$sampleFiles = @(Get-ChildItem -Path $sampleResponseGlob -File -ErrorAction SilentlyContinue)
foreach ($file in $sampleFiles) {
    $relative = $file.FullName.Replace($repoRoot.Path + "\", "").Replace("\", "/")
    $response = Read-Json -Path $file.FullName
    Require-Properties -Issues $issues -Path $relative -Object $response -Names @(
        "generatedAt",
        "schemaVersion",
        "query",
        "routing",
        "responseType",
        "payload",
        "sources"
    )
    if ($response.schemaVersion -ne "assistant-query-response.v1") {
        Add-Issue -Issues $issues -Path $relative -Message "Expected schemaVersion assistant-query-response.v1."
    }
    if ($allowedResponseTypes -notcontains [string]$response.responseType) {
        Add-Issue -Issues $issues -Path $relative -Message "Unknown responseType: $($response.responseType)"
    }
    Require-Properties -Issues $issues -Path "$relative/routing" -Object $response.routing -Names @("intent", "score", "reasons", "primaryView", "fallbackViews")
    if (-not (Test-RelativePath -Root $repoRoot -RelativePath ([string]$response.routing.primaryView))) {
        Add-Issue -Issues $issues -Path "$relative/routing" -Message "routing.primaryView does not exist: $($response.routing.primaryView)"
    }
}

if ($issues.Count -gt 0) {
    Write-Host "Assistant contract validation failed:" -ForegroundColor Red
    foreach ($issue in $issues) {
        Write-Host ("- {0}: {1}" -f $issue.path, $issue.message) -ForegroundColor Red
    }
    exit 1
}

Write-Host ("Assistant contract validation passed for {0} schemas, route map, build contract, and {1} sample responses." -f $schemaFiles.Count, $sampleFiles.Count) -ForegroundColor Green
