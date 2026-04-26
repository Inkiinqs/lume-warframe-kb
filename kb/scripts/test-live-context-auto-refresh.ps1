param(
    [string]$Root = ".",
    [int]$Port = 4485
)

$ErrorActionPreference = "Stop"

$repoRoot = Resolve-Path $Root
$env:WARFRAME_KB_API_PORT = [string]$Port
$env:WARFRAME_KB_API_KEY = "dev-local-key"
$serverPath = Join-Path $repoRoot "local-api\\server.mjs"
$stdoutPath = Join-Path $repoRoot "local-api\\live-context-refresh-test-server.stdout.log"
$stderrPath = Join-Path $repoRoot "local-api\\live-context-refresh-test-server.stderr.log"
$demoSessionPath = Join-Path $repoRoot "player\\sessions\\demo-account-session-latest.json"
$originalSession = Get-Content -Raw -LiteralPath $demoSessionPath
$createdPaths = New-Object System.Collections.ArrayList

& powershell -ExecutionPolicy Bypass -File .\scripts\build-assistant-live-context.ps1 -Root $repoRoot | Out-Null
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

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

    $before = Invoke-RestMethod -Method Get -Uri "$baseUrl/api/player/player.demo-account/live-context" -TimeoutSec 10
    $beforeToken = [string]$before.transport.changeToken
    if (-not $beforeToken) {
        throw "Expected live context to provide an initial change token."
    }

    $eventId = "event.test.live-context-refresh.autopulse"
    $body = @{
        schemaVersion = "overlay-event-feed-request.v1"
        playerId = "player.demo-account"
        capturedAt = "2026-04-12T00:00:00Z"
        source = "live-context-refresh-test"
        snapshotType = "event-feed"
        mode = "append"
        writeMode = "persistent"
        confirmWrite = $true
        activityId = "activity.cambion-drift"
        events = @(
            @{
                eventId = $eventId
                eventType = "objective-progress"
                occurredAt = "2026-04-12T00:00:01Z"
                objective = "live-context-refresh"
                confidence = 0.99
                rawText = "Live context refresh test"
                payload = @{
                    test = $true
                }
            }
        )
    } | ConvertTo-Json -Depth 12

    $headers = @{
        "x-warframe-kb-api-key" = "dev-local-key"
        "x-warframe-kb-session-id" = "live-context-refresh-test"
        "x-warframe-kb-client-id" = "codex-test"
    }
    $response = Invoke-RestMethod -Method Post -Uri "$baseUrl/api/overlay/event-feed" -Headers $headers -Body $body -ContentType "application/json" -TimeoutSec 30
    if ($response.status -ne "merged") {
        throw "Expected event-feed write status merged, got $($response.status)."
    }
    if ($response.liveContextRefresh.status -ne "refreshed") {
        throw "Expected liveContextRefresh status refreshed, got $($response.liveContextRefresh.status)."
    }

    $backupPath = Join-Path $repoRoot ($response.backupRecord -replace "/", "\")
    $normalizedPath = Join-Path $repoRoot ($response.normalizedOutput -replace "/", "\")
    [void]$createdPaths.Add($backupPath)
    [void]$createdPaths.Add($normalizedPath)

    $encodedToken = [System.Uri]::EscapeDataString($beforeToken)
    $poll = Invoke-RestMethod -Method Get -Uri "$baseUrl/api/player/player.demo-account/live-context/poll?since=$encodedToken" -TimeoutSec 10
    if ($poll.status -ne "modified") {
        throw "Expected live context poll after write to return modified, got $($poll.status)."
    }
    $matchedEvent = @($poll.context.context.recentOverlayEvents | Where-Object { $_.eventId -eq $eventId })
    if ($matchedEvent.Count -ne 1) {
        throw "Expected refreshed live context to include event $eventId."
    }

    Write-Host "Live context auto-refresh test passed." -ForegroundColor Green
}
finally {
    if ($server -and -not $server.HasExited) {
        Stop-Process -Id $server.Id -Force
    }

    Set-Content -LiteralPath $demoSessionPath -Value $originalSession
    & powershell -ExecutionPolicy Bypass -File .\scripts\build-assistant-live-context.ps1 -Root $repoRoot | Out-Null

    foreach ($path in @($createdPaths)) {
        $resolved = Resolve-Path -LiteralPath $path -ErrorAction SilentlyContinue
        if ($resolved -and $resolved.Path.StartsWith($repoRoot.Path)) {
            Remove-Item -LiteralPath $resolved.Path -Force -ErrorAction SilentlyContinue
        }
    }
}
