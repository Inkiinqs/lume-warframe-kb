param(
    [string]$Root = ".",
    [int]$Port = 4481
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
$stdoutPath = Join-Path $repoRoot "local-api\\overlay-write-test-server.stdout.log"
$stderrPath = Join-Path $repoRoot "local-api\\overlay-write-test-server.stderr.log"
$testInventoryPath = Join-Path $repoRoot "player\\inventory-tracking\\local-api-write-test-inventory.json"
$createdPaths = New-Object System.Collections.ArrayList

$testInventory = [ordered]@{
    id = "player.local-api-write-test-inventory"
    playerId = "player.local-api-write-test"
    category = "inventory"
    updatedAt = "2026-04-10T00:00:00Z"
    data = [ordered]@{
        owned = @(
            [ordered]@{
                itemId = "resource.neurodes"
                quantity = 1
            }
        )
    }
    sources = @(
        [ordered]@{
            type = "test-fixture"
            value = "local-api-write-mode"
        }
    )
}

Write-JsonFile -Path $testInventoryPath -Value $testInventory
[void]$createdPaths.Add($testInventoryPath)

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
        schemaVersion = "overlay-inventory-sync-request.v1"
        playerId = "player.local-api-write-test"
        capturedAt = "2026-04-11T00:00:00Z"
        source = "overlay-write-test"
        snapshotType = "inventory"
        mode = "delta"
        writeMode = "persistent"
        confirmWrite = $true
        recognizedItems = @(
            @{
                rawLabel = "Neurodes"
                canonicalItemId = "resource.neurodes"
                quantity = 5
                confidence = 0.99
            },
            @{
                rawLabel = "Unknown Test Token"
                quantity = 1
                confidence = 0.25
            }
        )
    } | ConvertTo-Json -Depth 8

    $blocked = $false
    try {
        Invoke-RestMethod -Method Post -Uri "$baseUrl/api/overlay/inventory-sync" -Body $body -ContentType "application/json" -TimeoutSec 10 | Out-Null
    }
    catch {
        if ($_.Exception.Response.StatusCode.value__ -eq 403) {
            $blocked = $true
        }
    }

    if (-not $blocked) {
        throw "Expected persistent overlay sync without API key to be blocked with HTTP 403."
    }

    $headers = @{
        "x-warframe-kb-api-key" = "dev-local-key"
        "x-warframe-kb-session-id" = "overlay-write-test"
        "x-warframe-kb-client-id" = "codex-test"
    }
    $response = Invoke-RestMethod -Method Post -Uri "$baseUrl/api/overlay/inventory-sync" -Headers $headers -Body $body -ContentType "application/json" -TimeoutSec 10
    if ($response.status -ne "merged") {
        throw "Expected persistent overlay sync status merged, got $($response.status)."
    }

    $backupPath = Join-Path $repoRoot ($response.backupRecord -replace "/", "\")
    $normalizedPath = Join-Path $repoRoot ($response.normalizedOutput -replace "/", "\")
    [void]$createdPaths.Add($backupPath)
    [void]$createdPaths.Add($normalizedPath)

    if (-not (Test-Path -LiteralPath $backupPath)) {
        throw "Expected backup file was not created: $backupPath"
    }
    if (-not (Test-Path -LiteralPath $normalizedPath)) {
        throw "Expected normalized output file was not created: $normalizedPath"
    }

    $updated = Get-Content -Raw -LiteralPath $testInventoryPath | ConvertFrom-Json
    $neurodes = @($updated.data.owned | Where-Object { $_.itemId -eq "resource.neurodes" })[0]
    if ([int]$neurodes.quantity -ne 5) {
        throw "Expected resource.neurodes quantity 5 after write, got $($neurodes.quantity)."
    }
    if ($updated.sources[0].type -ne "overlay-api") {
        throw "Expected first inventory source to be overlay-api."
    }
    if ($response.liveContextRefresh.status -ne "skipped") {
        throw "Expected temp-player live context refresh to be skipped, got $($response.liveContextRefresh.status)."
    }

    Write-Host "Overlay persistent write mode test passed." -ForegroundColor Green
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
