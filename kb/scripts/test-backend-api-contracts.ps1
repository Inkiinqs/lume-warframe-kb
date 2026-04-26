param(
    [string]$Root = ".",
    [int]$Port = 4480,
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

function Add-Result {
    param(
        [System.Collections.ArrayList]$Results,
        [string]$EndpointId,
        [string]$Check,
        [bool]$Passed,
        [string]$Message
    )

    [void]$Results.Add([ordered]@{
        endpointId = $EndpointId
        check = $Check
        passed = $Passed
        message = $Message
    })
}

function Assert-Equal {
    param(
        [System.Collections.ArrayList]$Results,
        [string]$EndpointId,
        [string]$Check,
        $Expected,
        $Actual
    )

    $passed = [string]$Expected -eq [string]$Actual
    $message = if ($passed) { "OK" } else { "Expected '$Expected', got '$Actual'." }
    Add-Result -Results $Results -EndpointId $EndpointId -Check $Check -Passed $passed -Message $message
}

function Assert-HasProperty {
    param(
        [System.Collections.ArrayList]$Results,
        [string]$EndpointId,
        [string]$Check,
        $Object,
        [string]$PropertyName
    )

    $passed = $Object.PSObject.Properties.Name -contains $PropertyName
    $message = if ($passed) { "OK" } else { "Missing property '$PropertyName'." }
    Add-Result -Results $Results -EndpointId $EndpointId -Check $Check -Passed $passed -Message $message
}

$repoRoot = Resolve-Path $Root
$reportRoot = Join-Path $repoRoot "backend-api-contracts\\reports"
if ($WriteReport) { Ensure-Directory $reportRoot }

$env:WARFRAME_KB_API_PORT = [string]$Port
$serverPath = Join-Path $repoRoot "local-api\\server.mjs"
$stdoutPath = Join-Path $repoRoot "local-api\\contract-test-server.stdout.log"
$stderrPath = Join-Path $repoRoot "local-api\\contract-test-server.stderr.log"

$server = Start-Process -FilePath "node" -ArgumentList @("`"$serverPath`"") -WorkingDirectory $repoRoot -PassThru -WindowStyle Hidden -RedirectStandardOutput $stdoutPath -RedirectStandardError $stderrPath
$results = New-Object System.Collections.ArrayList

try {
    $baseUrl = "http://127.0.0.1:$Port/api"
    $ready = $false
    for ($i = 0; $i -lt 30; $i++) {
        try {
            $health = Invoke-RestMethod -Method Get -Uri "$baseUrl/health" -TimeoutSec 2
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

    $contracts = Read-Json -Path (Join-Path $repoRoot "backend-api-contracts\\endpoints.json")

    foreach ($endpoint in @($contracts.endpoints)) {
        $endpointId = [string]$endpoint.id
        $requestExample = Read-Json -Path (Join-Path $repoRoot (([string]$endpoint.requestExample) -replace "/", "\"))
        $responseExample = Read-Json -Path (Join-Path $repoRoot (([string]$endpoint.responseExample) -replace "/", "\"))

        if ($endpointId -eq "endpoint.assistant-query") {
            $body = $requestExample | ConvertTo-Json -Depth 10
            $actual = Invoke-RestMethod -Method Post -Uri "$baseUrl/assistant/query" -Body $body -ContentType "application/json" -TimeoutSec 30
            Assert-Equal -Results $results -EndpointId $endpointId -Check "schemaVersion" -Expected $responseExample.schemaVersion -Actual $actual.schemaVersion
            Assert-Equal -Results $results -EndpointId $endpointId -Check "responseType" -Expected $responseExample.responseType -Actual $actual.responseType
            Assert-Equal -Results $results -EndpointId $endpointId -Check "routing.intent" -Expected $responseExample.routing.intent -Actual $actual.routing.intent
            Assert-Equal -Results $results -EndpointId $endpointId -Check "target.id" -Expected $responseExample.payload.target.id -Actual $actual.payload.target.id
            Assert-Equal -Results $results -EndpointId $endpointId -Check "recommendedBuild.buildId" -Expected $responseExample.payload.recommendedBuild.buildId -Actual $actual.payload.recommendedBuild.buildId
        }
        elseif ($endpointId -eq "endpoint.player-inventory-summary") {
            $actual = Invoke-RestMethod -Method Get -Uri "$baseUrl/player/player.demo-account/inventory-summary" -TimeoutSec 10
            Assert-Equal -Results $results -EndpointId $endpointId -Check "schemaVersion" -Expected $responseExample.schemaVersion -Actual $actual.schemaVersion
            Assert-Equal -Results $results -EndpointId $endpointId -Check "playerId" -Expected $responseExample.playerId -Actual $actual.playerId
            foreach ($itemId in @($responseExample.items.PSObject.Properties.Name)) {
                Assert-HasProperty -Results $results -EndpointId $endpointId -Check "items.$itemId" -Object $actual.items -PropertyName $itemId
            }
        }
        elseif ($endpointId -eq "endpoint.player-live-context") {
            $actual = Invoke-RestMethod -Method Get -Uri "$baseUrl/player/player.demo-account/live-context" -TimeoutSec 10
            Assert-Equal -Results $results -EndpointId $endpointId -Check "schemaVersion" -Expected $responseExample.schemaVersion -Actual $actual.schemaVersion
            Assert-Equal -Results $results -EndpointId $endpointId -Check "playerId" -Expected $responseExample.playerId -Actual $actual.playerId
            Assert-Equal -Results $results -EndpointId $endpointId -Check "sourceView" -Expected $responseExample.sourceView -Actual $actual.sourceView
            Assert-Equal -Results $results -EndpointId $endpointId -Check "context.schemaVersion" -Expected $responseExample.context.schemaVersion -Actual $actual.context.schemaVersion
            Assert-Equal -Results $results -EndpointId $endpointId -Check "context.playerId" -Expected $responseExample.context.playerId -Actual $actual.context.playerId
            Assert-Equal -Results $results -EndpointId $endpointId -Check "inventoryContext.ownedItemCount" -Expected $responseExample.context.inventoryContext.ownedItemCount -Actual $actual.context.inventoryContext.ownedItemCount
            Assert-HasProperty -Results $results -EndpointId $endpointId -Check "transport.changeToken" -Object $actual.transport -PropertyName "changeToken"
        }
        elseif ($endpointId -eq "endpoint.player-live-context-poll") {
            $actual = Invoke-RestMethod -Method Get -Uri "$baseUrl/player/player.demo-account/live-context/poll" -TimeoutSec 10
            Assert-Equal -Results $results -EndpointId $endpointId -Check "schemaVersion" -Expected $responseExample.schemaVersion -Actual $actual.schemaVersion
            Assert-Equal -Results $results -EndpointId $endpointId -Check "playerId" -Expected $responseExample.playerId -Actual $actual.playerId
            Assert-Equal -Results $results -EndpointId $endpointId -Check "status" -Expected $responseExample.status -Actual $actual.status
            Assert-HasProperty -Results $results -EndpointId $endpointId -Check "transport.changeToken" -Object $actual.transport -PropertyName "changeToken"
            Assert-Equal -Results $results -EndpointId $endpointId -Check "context.schemaVersion" -Expected $responseExample.context.schemaVersion -Actual $actual.context.schemaVersion
        }
        elseif ($endpointId -eq "endpoint.overlay-inventory-sync") {
            $body = $requestExample | ConvertTo-Json -Depth 10
            $actual = Invoke-RestMethod -Method Post -Uri "$baseUrl/overlay/inventory-sync" -Body $body -ContentType "application/json" -TimeoutSec 10
            Assert-Equal -Results $results -EndpointId $endpointId -Check "schemaVersion" -Expected $responseExample.schemaVersion -Actual $actual.schemaVersion
            Assert-Equal -Results $results -EndpointId $endpointId -Check "playerId" -Expected $responseExample.playerId -Actual $actual.playerId
            Assert-Equal -Results $results -EndpointId $endpointId -Check "status" -Expected $responseExample.status -Actual $actual.status
            Assert-Equal -Results $results -EndpointId $endpointId -Check "recognizedCount" -Expected $responseExample.recognizedCount -Actual $actual.recognizedCount
            Assert-Equal -Results $results -EndpointId $endpointId -Check "unknownItems.count" -Expected @($responseExample.unknownItems).Count -Actual @($actual.unknownItems).Count
        }
        elseif ($endpointId -eq "endpoint.overlay-loadout-sync") {
            $body = $requestExample | ConvertTo-Json -Depth 12
            $actual = Invoke-RestMethod -Method Post -Uri "$baseUrl/overlay/loadout-sync" -Body $body -ContentType "application/json" -TimeoutSec 10
            Assert-Equal -Results $results -EndpointId $endpointId -Check "schemaVersion" -Expected $responseExample.schemaVersion -Actual $actual.schemaVersion
            Assert-Equal -Results $results -EndpointId $endpointId -Check "playerId" -Expected $responseExample.playerId -Actual $actual.playerId
            Assert-Equal -Results $results -EndpointId $endpointId -Check "status" -Expected $responseExample.status -Actual $actual.status
            Assert-Equal -Results $results -EndpointId $endpointId -Check "equipped.warframeId" -Expected $responseExample.equipped.warframeId -Actual $actual.equipped.warframeId
            Assert-Equal -Results $results -EndpointId $endpointId -Check "records.session" -Expected $responseExample.records.session -Actual $actual.records.session
            Assert-Equal -Results $results -EndpointId $endpointId -Check "records.buildTemplate" -Expected $responseExample.records.buildTemplate -Actual $actual.records.buildTemplate
        }
        elseif ($endpointId -eq "endpoint.overlay-mission-sync") {
            $body = $requestExample | ConvertTo-Json -Depth 12
            $actual = Invoke-RestMethod -Method Post -Uri "$baseUrl/overlay/mission-sync" -Body $body -ContentType "application/json" -TimeoutSec 10
            Assert-Equal -Results $results -EndpointId $endpointId -Check "schemaVersion" -Expected $responseExample.schemaVersion -Actual $actual.schemaVersion
            Assert-Equal -Results $results -EndpointId $endpointId -Check "playerId" -Expected $responseExample.playerId -Actual $actual.playerId
            Assert-Equal -Results $results -EndpointId $endpointId -Check "status" -Expected $responseExample.status -Actual $actual.status
            Assert-Equal -Results $results -EndpointId $endpointId -Check "mission.activityId" -Expected $responseExample.mission.activityId -Actual $actual.mission.activityId
            Assert-Equal -Results $results -EndpointId $endpointId -Check "activityRecord.id" -Expected $responseExample.activityRecord.id -Actual $actual.activityRecord.id
            Assert-Equal -Results $results -EndpointId $endpointId -Check "records.session" -Expected $responseExample.records.session -Actual $actual.records.session
        }
        elseif ($endpointId -eq "endpoint.overlay-event-feed") {
            $body = $requestExample | ConvertTo-Json -Depth 12
            $actual = Invoke-RestMethod -Method Post -Uri "$baseUrl/overlay/event-feed" -Body $body -ContentType "application/json" -TimeoutSec 10
            Assert-Equal -Results $results -EndpointId $endpointId -Check "schemaVersion" -Expected $responseExample.schemaVersion -Actual $actual.schemaVersion
            Assert-Equal -Results $results -EndpointId $endpointId -Check "playerId" -Expected $responseExample.playerId -Actual $actual.playerId
            Assert-Equal -Results $results -EndpointId $endpointId -Check "status" -Expected $responseExample.status -Actual $actual.status
            Assert-Equal -Results $results -EndpointId $endpointId -Check "eventSummary.total" -Expected $responseExample.eventSummary.total -Actual $actual.eventSummary.total
            Assert-Equal -Results $results -EndpointId $endpointId -Check "acceptedEvents.count" -Expected @($responseExample.acceptedEvents).Count -Actual @($actual.acceptedEvents).Count
            Assert-Equal -Results $results -EndpointId $endpointId -Check "records.session" -Expected $responseExample.records.session -Actual $actual.records.session
        }
    }
}
finally {
    if ($server -and -not $server.HasExited) {
        Stop-Process -Id $server.Id -Force
    }
}

$failed = @($results | Where-Object { -not $_.passed })
$report = [ordered]@{
    generatedAt = (Get-Date).ToString("s") + "Z"
    schemaVersion = "backend-api-contract-test-report.v1"
    description = "Compares local API responses against backend-api-contract examples."
    total = @($results).Count
    passed = @($results | Where-Object { $_.passed }).Count
    failed = $failed.Count
    passRate = if (@($results).Count -gt 0) { [Math]::Round(((@($results | Where-Object { $_.passed }).Count) / @($results).Count) * 100, 2) } else { 0 }
    results = @($results)
}

if ($WriteReport) {
    $report | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $reportRoot "latest.backend-api-contract-test-report.json")
}

if ($failed.Count -gt 0) {
    Write-Host ("Backend API contract tests failed: {0}/{1}" -f $failed.Count, @($results).Count) -ForegroundColor Red
    foreach ($failure in $failed) {
        Write-Host ("- {0} {1}: {2}" -f $failure.endpointId, $failure.check, $failure.message) -ForegroundColor Red
    }
    exit 1
}

Write-Host ("Backend API contract tests passed: {0}/{1}" -f @($results).Count, @($results).Count) -ForegroundColor Green
