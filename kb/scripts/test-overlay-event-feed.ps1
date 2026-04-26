param(
    [string]$Root = ".",
    [int]$Port = 4484
)

$ErrorActionPreference = "Stop"

function Write-JsonFile {
    param(
        [string]$Path,
        $Value
    )

    $dir = Split-Path -Parent $Path
    if (-not (Test-Path -LiteralPath $dir)) {
        New-Item -ItemType Directory -Force -Path $dir | Out-Null
    }
    $Value | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $Path
}

$repoRoot = Resolve-Path $Root
$env:WARFRAME_KB_API_PORT = [string]$Port
$env:WARFRAME_KB_API_KEY = "dev-local-key"
$serverPath = Join-Path $repoRoot "local-api\\server.mjs"
$stdoutPath = Join-Path $repoRoot "local-api\\overlay-event-feed-test-server.stdout.log"
$stderrPath = Join-Path $repoRoot "local-api\\overlay-event-feed-test-server.stderr.log"
$testSessionPath = Join-Path $repoRoot "player\\sessions\\local-api-event-feed-test-session-latest.json"
$createdPaths = New-Object System.Collections.ArrayList

$testSession = [ordered]@{
    id = "player.local-api-event-feed-test-session-latest"
    playerId = "player.local-api-event-feed-test"
    category = "session"
    updatedAt = "2026-04-10T00:00:00Z"
    data = [ordered]@{
        recentDropsSeen = @("resource.plastids")
        overlayEvents = @(
            [ordered]@{
                eventId = "event.old.pickup.plastids"
                eventType = "pickup"
                occurredAt = "2026-04-10T00:00:00Z"
                source = "test-fixture"
                itemId = "resource.plastids"
                quantity = 8
                payload = [ordered]@{}
            }
        )
    }
    sources = @(
        [ordered]@{
            type = "test-fixture"
            value = "local-api-event-feed"
        }
    )
}

Write-JsonFile -Path $testSessionPath -Value $testSession
[void]$createdPaths.Add($testSessionPath)

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
        throw "Local API did not become ready on port $Port."
    }

    $body = @{
        schemaVersion = "overlay-event-feed-request.v1"
        playerId = "player.local-api-event-feed-test"
        capturedAt = "2026-04-11T00:00:00Z"
        source = "overlay-event-feed-test"
        snapshotType = "event-feed"
        mode = "append"
        writeMode = "persistent"
        confirmWrite = $true
        activityId = "activity.cambion-drift"
        events = @(
            @{
                eventId = "event.test.pickup.orokin-cell"
                eventType = "pickup"
                occurredAt = "2026-04-11T00:00:01Z"
                itemId = "resource.orokin-cell"
                quantity = 1
                confidence = 0.96
                rawText = "Orokin Cell"
            },
            @{
                eventId = "event.test.objective.bounty-stage"
                eventType = "objective-progress"
                occurredAt = "2026-04-11T00:00:02Z"
                objective = "bounty-stage"
                confidence = 0.9
                rawText = "Bounty Stage 2/5"
                payload = @{
                    stage = 2
                    stageCount = 5
                }
            }
        )
    } | ConvertTo-Json -Depth 12

    $blocked = $false
    try {
        Invoke-RestMethod -Method Post -Uri "$baseUrl/api/overlay/event-feed" -Body $body -ContentType "application/json" -TimeoutSec 10 | Out-Null
    }
    catch {
        if ($_.Exception.Response.StatusCode.value__ -eq 403) {
            $blocked = $true
        }
    }

    if (-not $blocked) {
        throw "Expected persistent overlay event feed without API key to be blocked with HTTP 403."
    }

    $headers = @{
        "x-warframe-kb-api-key" = "dev-local-key"
        "x-warframe-kb-session-id" = "overlay-event-feed-test"
        "x-warframe-kb-client-id" = "codex-test"
    }
    $response = Invoke-RestMethod -Method Post -Uri "$baseUrl/api/overlay/event-feed" -Headers $headers -Body $body -ContentType "application/json" -TimeoutSec 10
    if ($response.status -ne "merged") {
        throw "Expected persistent overlay event feed status merged, got $($response.status)."
    }
    if ([int]$response.eventSummary.total -ne 2) {
        throw "Expected 2 accepted event-feed events, got $($response.eventSummary.total)."
    }

    $backupPath = Join-Path $repoRoot ($response.backupRecord -replace "/", "\")
    $normalizedPath = Join-Path $repoRoot ($response.normalizedOutput -replace "/", "\")
    [void]$createdPaths.Add($backupPath)
    [void]$createdPaths.Add($normalizedPath)

    foreach ($path in @($backupPath, $normalizedPath)) {
        if (-not (Test-Path -LiteralPath $path)) {
            throw "Expected file was not created: $path"
        }
    }

    $updatedSession = Get-Content -Raw -LiteralPath $testSessionPath | ConvertFrom-Json
    if (@($updatedSession.data.overlayEvents).Count -ne 3) {
        throw "Expected session overlayEvents to contain 3 merged events."
    }
    if (@($updatedSession.data.recentDropsSeen)[0] -ne "resource.orokin-cell") {
        throw "Expected recentDropsSeen to promote resource.orokin-cell first."
    }
    if ($updatedSession.sources[0].type -ne "overlay-api") {
        throw "Expected first session source to be overlay-api."
    }
    if ($response.liveContextRefresh.status -ne "skipped") {
        throw "Expected temp-player live context refresh to be skipped, got $($response.liveContextRefresh.status)."
    }

    Write-Host "Overlay event feed persistent write mode test passed." -ForegroundColor Green
}
finally {
    if ($server -and -not $server.HasExited) {
        Stop-Process -Id $server.Id -Force
    }

    foreach ($path in @($createdPaths)) {
        $resolved = Resolve-Path -LiteralPath $path -ErrorAction SilentlyContinue
        if ($resolved -and $resolved.Path.StartsWith($repoRoot.Path)) {
            Remove-Item -LiteralPath $resolved.Path -Force -ErrorAction SilentlyContinue
        }
    }
}
