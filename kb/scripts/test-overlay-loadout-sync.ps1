param(
    [string]$Root = ".",
    [int]$Port = 4482
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
$stdoutPath = Join-Path $repoRoot "local-api\\overlay-loadout-test-server.stdout.log"
$stderrPath = Join-Path $repoRoot "local-api\\overlay-loadout-test-server.stderr.log"
$testSessionPath = Join-Path $repoRoot "player\\sessions\\local-api-loadout-test-session-latest.json"
$testBuildPath = Join-Path $repoRoot "player\\build-templates\\local-api-loadout-test-rhino-build.json"
$createdPaths = New-Object System.Collections.ArrayList

$testSession = [ordered]@{
    id = "player.local-api-loadout-test-session-latest"
    playerId = "player.local-api-loadout-test"
    category = "session"
    updatedAt = "2026-04-10T00:00:00Z"
    data = [ordered]@{
        currentGoalItemId = "warframe.rhino"
    }
    sources = @(
        [ordered]@{
            type = "test-fixture"
            value = "local-api-loadout-sync"
        }
    )
}

$testBuild = [ordered]@{
    id = "player.local-api-loadout-test-rhino-build"
    playerId = "player.local-api-loadout-test"
    category = "build"
    updatedAt = "2026-04-10T00:00:00Z"
    data = [ordered]@{
        name = "Loadout Sync Test Build"
        frameId = "warframe.rhino"
        weaponIds = @("weapon.acceltra")
        modIds = @()
        goalTags = @("test")
        upgradeState = [ordered]@{
            warframes = [ordered]@{
                "warframe.rhino" = [ordered]@{
                    reactorInstalled = $false
                    auraModId = $null
                    formaPolarities = @()
                }
            }
            weapons = [ordered]@{}
        }
    }
    sources = @(
        [ordered]@{
            type = "test-fixture"
            value = "local-api-loadout-sync"
        }
    )
}

Write-JsonFile -Path $testSessionPath -Value $testSession
Write-JsonFile -Path $testBuildPath -Value $testBuild
[void]$createdPaths.Add($testSessionPath)
[void]$createdPaths.Add($testBuildPath)

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
        schemaVersion = "overlay-loadout-sync-request.v1"
        playerId = "player.local-api-loadout-test"
        capturedAt = "2026-04-11T00:00:00Z"
        source = "overlay-loadout-test"
        snapshotType = "loadout"
        mode = "snapshot"
        writeMode = "persistent"
        confirmWrite = $true
        equipped = @{
            warframeId = "warframe.rhino"
            primaryWeaponId = "weapon.acceltra"
            secondaryWeaponId = "weapon.lex"
            meleeWeaponId = "weapon.skana"
        }
        upgradeState = @{
            warframes = @{
                "warframe.rhino" = @{
                    reactorInstalled = $true
                    auraModId = "mod.steel-charge"
                    formaPolarities = @("madurai")
                }
            }
            weapons = @{
                "weapon.acceltra" = @{
                    catalystInstalled = $true
                    stanceModId = $null
                    formaPolarities = @("naramon")
                }
            }
        }
    } | ConvertTo-Json -Depth 12

    $blocked = $false
    try {
        Invoke-RestMethod -Method Post -Uri "$baseUrl/api/overlay/loadout-sync" -Body $body -ContentType "application/json" -TimeoutSec 10 | Out-Null
    }
    catch {
        if ($_.Exception.Response.StatusCode.value__ -eq 403) {
            $blocked = $true
        }
    }

    if (-not $blocked) {
        throw "Expected persistent overlay loadout sync without API key to be blocked with HTTP 403."
    }

    $headers = @{
        "x-warframe-kb-api-key" = "dev-local-key"
        "x-warframe-kb-session-id" = "overlay-loadout-test"
        "x-warframe-kb-client-id" = "codex-test"
    }
    $response = Invoke-RestMethod -Method Post -Uri "$baseUrl/api/overlay/loadout-sync" -Headers $headers -Body $body -ContentType "application/json" -TimeoutSec 10
    if ($response.status -ne "merged") {
        throw "Expected persistent overlay loadout sync status merged, got $($response.status)."
    }

    $sessionBackupPath = Join-Path $repoRoot ($response.backupRecords.session -replace "/", "\")
    $buildBackupPath = Join-Path $repoRoot ($response.backupRecords.buildTemplate -replace "/", "\")
    $normalizedPath = Join-Path $repoRoot ($response.normalizedOutput -replace "/", "\")
    [void]$createdPaths.Add($sessionBackupPath)
    [void]$createdPaths.Add($buildBackupPath)
    [void]$createdPaths.Add($normalizedPath)

    foreach ($path in @($sessionBackupPath, $buildBackupPath, $normalizedPath)) {
        if (-not (Test-Path -LiteralPath $path)) {
            throw "Expected file was not created: $path"
        }
    }

    $updatedSession = Get-Content -Raw -LiteralPath $testSessionPath | ConvertFrom-Json
    if ($updatedSession.data.currentLoadout.equipped.primaryWeaponId -ne "weapon.acceltra") {
        throw "Expected session currentLoadout primary weapon to be weapon.acceltra."
    }
    if ($updatedSession.sources[0].type -ne "overlay-api") {
        throw "Expected first session source to be overlay-api."
    }

    $updatedBuild = Get-Content -Raw -LiteralPath $testBuildPath | ConvertFrom-Json
    if (-not $updatedBuild.data.upgradeState.warframes."warframe.rhino".reactorInstalled) {
        throw "Expected Rhino reactorInstalled to be true after write."
    }
    if (-not $updatedBuild.data.upgradeState.weapons."weapon.acceltra".catalystInstalled) {
        throw "Expected Acceltra catalystInstalled to be true after write."
    }
    if (@($updatedBuild.data.weaponIds).Count -ne 3) {
        throw "Expected build weaponIds to include primary, secondary, and melee IDs."
    }
    if ($response.liveContextRefresh.status -ne "skipped") {
        throw "Expected temp-player live context refresh to be skipped, got $($response.liveContextRefresh.status)."
    }

    Write-Host "Overlay loadout persistent write mode test passed." -ForegroundColor Green
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
