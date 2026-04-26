param(
    [string]$Root = ".",
    [string]$ManifestPath = "imports/market/manifests/sample-market-import.json",
    [string]$ApiBase = "https://api.warframe.market/v1"
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

$repoRoot = Resolve-Path $Root
$manifest = Read-Json -Path (Join-Path $repoRoot $ManifestPath)
$outputDir = Join-Path $repoRoot "imports\\market\\source-snapshots\\live"
Ensure-Directory $outputDir

$headers = @{
    "User-Agent" = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/135.0 Safari/537.36"
    "Accept" = "application/json"
    "Language" = "en"
    "Platform" = "pc"
}

$results = @()

foreach ($entry in @($manifest.entries)) {
    foreach ($snapshotType in @($entry.snapshotTypes)) {
        $uri = switch ($snapshotType) {
            "orders" { "$ApiBase/items/$($entry.marketItemId)/orders" }
            "statistics" { "$ApiBase/items/$($entry.marketItemId)/statistics" }
            default { $null }
        }

        if (-not $uri) { continue }

        $record = [ordered]@{
            id = "market.live.$($entry.marketItemId).$snapshotType"
            source = [string]$manifest.source
            capturedAt = (Get-Date).ToString("s") + "Z"
            marketItemId = [string]$entry.marketItemId
            canonicalItemId = [string]$entry.canonicalItemId
            snapshotType = [string]$snapshotType
            payload = @{}
            metadata = [ordered]@{
                requestUri = $uri
                success = $false
            }
        }

        try {
            $response = Invoke-WebRequest -UseBasicParsing -Headers $headers -Uri $uri
            $record.payload = ($response.Content | ConvertFrom-Json)
            $record.metadata.success = $true
            $record.metadata.httpStatus = [int]$response.StatusCode
        }
        catch {
            $record.metadata.error = $_.Exception.Message
            if ($_.Exception.Response) {
                try {
                    $record.metadata.httpStatus = [int]$_.Exception.Response.StatusCode
                }
                catch { }
            }
        }

        $results += $record
    }
}

$outPath = Join-Path $outputDir ("market-fetch-" + (Get-Date -Format "yyyyMMdd-HHmmss") + ".json")
$results | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $outPath

Write-Host "Wrote $($results.Count) market fetch snapshots to $outPath" -ForegroundColor Green
