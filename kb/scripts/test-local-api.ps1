param(
    [string]$Root = ".",
    [int]$Port = 4477
)

$ErrorActionPreference = "Stop"

$repoRoot = Resolve-Path $Root
$env:WARFRAME_KB_API_PORT = [string]$Port
$serverPath = Join-Path $repoRoot "local-api\\server.mjs"
$stdoutPath = Join-Path $repoRoot "local-api\\test-server.stdout.log"
$stderrPath = Join-Path $repoRoot "local-api\\test-server.stderr.log"

$server = Start-Process -FilePath "node" -ArgumentList @("`"$serverPath`"") -WorkingDirectory $repoRoot -PassThru -WindowStyle Hidden -RedirectStandardOutput $stdoutPath -RedirectStandardError $stderrPath

try {
    $baseUrl = "http://127.0.0.1:$Port"
    $ready = $false
    for ($i = 0; $i -lt 30; $i++) {
        try {
            $health = Invoke-RestMethod -Method Get -Uri "$baseUrl/api/health" -TimeoutSec 2
            if ($health.status -eq "ok") {
                $ready = $true
                break
            }
        }
        catch {
            if ($server.HasExited) {
                $stderr = if (Test-Path -LiteralPath $stderrPath) { Get-Content -Raw -LiteralPath $stderrPath } else { "" }
                $stdout = if (Test-Path -LiteralPath $stdoutPath) { Get-Content -Raw -LiteralPath $stdoutPath } else { "" }
                throw "Local API exited before readiness. stdout: $stdout stderr: $stderr"
            }
            Start-Sleep -Milliseconds 500
        }
    }

    if (-not $ready) {
        $stderr = if (Test-Path -LiteralPath $stderrPath) { Get-Content -Raw -LiteralPath $stderrPath } else { "" }
        $stdout = if (Test-Path -LiteralPath $stdoutPath) { Get-Content -Raw -LiteralPath $stdoutPath } else { "" }
        throw "Local API did not become ready on port $Port. stdout: $stdout stderr: $stderr"
    }

    $assistantBody = @{
        schemaVersion = "assistant-query-request.v1"
        playerId = "player.demo-account"
        query = "make me a Rhino build for Murmur"
        context = @{
            surface = "test"
            preferOwnedItems = $true
        }
    } | ConvertTo-Json -Depth 6

    $assistant = Invoke-RestMethod -Method Post -Uri "$baseUrl/api/assistant/query" -Body $assistantBody -ContentType "application/json" -TimeoutSec 30
    if ($assistant.responseType -ne "build.recommendation") {
        throw "Expected assistant responseType build.recommendation, got $($assistant.responseType)."
    }

    $inventory = Invoke-RestMethod -Method Get -Uri "$baseUrl/api/player/player.demo-account/inventory-summary" -TimeoutSec 10
    if (-not ($inventory.items.PSObject.Properties.Name -contains "warframe.rhino")) {
        throw "Inventory summary did not include warframe.rhino."
    }

    $liveContext = Invoke-RestMethod -Method Get -Uri "$baseUrl/api/player/player.demo-account/live-context" -TimeoutSec 10
    if ($liveContext.context.schemaVersion -ne "assistant-live-context.view.v1") {
        throw "Expected live context schema assistant-live-context.view.v1, got $($liveContext.context.schemaVersion)."
    }
    if ([int]$liveContext.context.inventoryContext.ownedItemCount -lt 1) {
        throw "Expected live context to include owned inventory count."
    }
    if (-not $liveContext.transport.changeToken) {
        throw "Expected live context response to include transport.changeToken."
    }

    $livePoll = Invoke-RestMethod -Method Get -Uri "$baseUrl/api/player/player.demo-account/live-context/poll" -TimeoutSec 10
    if ($livePoll.status -ne "modified") {
        throw "Expected first live context poll status modified, got $($livePoll.status)."
    }
    $encodedToken = [System.Uri]::EscapeDataString([string]$livePoll.transport.changeToken)
    $livePollAgain = Invoke-RestMethod -Method Get -Uri "$baseUrl/api/player/player.demo-account/live-context/poll?since=$encodedToken" -TimeoutSec 10
    if ($livePollAgain.status -ne "not-modified") {
        throw "Expected second live context poll status not-modified, got $($livePollAgain.status)."
    }

    $overlayBody = Get-Content -Raw -LiteralPath (Join-Path $repoRoot "backend-api-contracts\\examples\\overlay-inventory-sync.request.json")
    $overlay = Invoke-RestMethod -Method Post -Uri "$baseUrl/api/overlay/inventory-sync" -Body $overlayBody -ContentType "application/json" -TimeoutSec 10
    if ($overlay.status -ne "preview") {
        throw "Expected overlay sync preview status, got $($overlay.status)."
    }

    $loadoutBody = Get-Content -Raw -LiteralPath (Join-Path $repoRoot "backend-api-contracts\\examples\\overlay-loadout-sync.request.json")
    $loadout = Invoke-RestMethod -Method Post -Uri "$baseUrl/api/overlay/loadout-sync" -Body $loadoutBody -ContentType "application/json" -TimeoutSec 10
    if ($loadout.status -ne "preview") {
        throw "Expected overlay loadout sync preview status, got $($loadout.status)."
    }
    if ($loadout.equipped.warframeId -ne "warframe.rhino") {
        throw "Expected overlay loadout sync to recognize warframe.rhino, got $($loadout.equipped.warframeId)."
    }

    $missionBody = Get-Content -Raw -LiteralPath (Join-Path $repoRoot "backend-api-contracts\\examples\\overlay-mission-sync.request.json")
    $mission = Invoke-RestMethod -Method Post -Uri "$baseUrl/api/overlay/mission-sync" -Body $missionBody -ContentType "application/json" -TimeoutSec 10
    if ($mission.status -ne "preview") {
        throw "Expected overlay mission sync preview status, got $($mission.status)."
    }
    if ($mission.activityRecord.id -ne "activity.cambion-drift") {
        throw "Expected overlay mission sync to resolve activity.cambion-drift, got $($mission.activityRecord.id)."
    }

    $eventFeedBody = Get-Content -Raw -LiteralPath (Join-Path $repoRoot "backend-api-contracts\\examples\\overlay-event-feed.request.json")
    $eventFeed = Invoke-RestMethod -Method Post -Uri "$baseUrl/api/overlay/event-feed" -Body $eventFeedBody -ContentType "application/json" -TimeoutSec 10
    if ($eventFeed.status -ne "preview") {
        throw "Expected overlay event feed preview status, got $($eventFeed.status)."
    }
    if ([int]$eventFeed.eventSummary.total -ne 4) {
        throw "Expected overlay event feed to accept 4 events, got $($eventFeed.eventSummary.total)."
    }

    $contracts = Invoke-RestMethod -Method Get -Uri "$baseUrl/api/contracts/endpoints" -TimeoutSec 10
    if (@($contracts.endpoints).Count -lt 8) {
        throw "Expected at least 8 endpoint contracts."
    }

    Write-Host "Local API smoke tests passed." -ForegroundColor Green
}
finally {
    if ($server -and -not $server.HasExited) {
        Stop-Process -Id $server.Id -Force
    }
}
