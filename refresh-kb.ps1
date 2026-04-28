param(
    [string]$KbRoot = "kb"
)

$ErrorActionPreference = "Stop"

$root = Resolve-Path $KbRoot

function Get-WfcdSnapshotHash {
    param(
        [Parameter(Mandatory = $true)]
        [string]$RawRoot
    )

    $files = Get-ChildItem -LiteralPath $RawRoot -File -Filter "*.json" | Sort-Object Name
    if (-not $files) {
        throw "No WFCD raw snapshot files found in $RawRoot"
    }

    $hashInput = foreach ($file in $files) {
        $file.Name
        Get-Content -LiteralPath $file.FullName -Raw
    }

    $bytes = [System.Text.Encoding]::UTF8.GetBytes(($hashInput -join "`n"))
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        [BitConverter]::ToString($sha.ComputeHash($bytes)).Replace("-", "").ToLowerInvariant()
    }
    finally {
        $sha.Dispose()
    }
}

Push-Location $root
try {
    Write-Host "Refreshing WFCD public static snapshots..." -ForegroundColor Cyan
    powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\fetch-wfcd-static.ps1 -Root .
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

    $rawRoot = Join-Path (Get-Location) "imports\static\source-snapshots\wfcd\raw"
    $hashPath = Join-Path (Get-Location) "imports\static\manifests\wfcd-raw-snapshot.sha256"
    $nextHash = Get-WfcdSnapshotHash -RawRoot $rawRoot
    $previousHash = if (Test-Path -LiteralPath $hashPath) {
        (Get-Content -LiteralPath $hashPath -Raw).Trim()
    } else {
        ""
    }

    if ($previousHash -eq $nextHash) {
        Write-Host "WFCD snapshots unchanged; skipping derived KB rebuild." -ForegroundColor Green
        return
    }

    Set-Content -LiteralPath $hashPath -Value $nextHash -Encoding ascii

    Write-Host "Converting WFCD snapshots into KB import records..." -ForegroundColor Cyan
    powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\convert-wfcd-static.ps1 -Root .
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

    Write-Host "Writing canonical KB records..." -ForegroundColor Cyan
    powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\run-static-pipeline.ps1 `
        -ManifestPath .\imports\static\manifests\wfcd-static-import.json `
        -Root . `
        -WriteCanonical `
        -MergeExisting
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

    Write-Host "Regenerating WFCD relationships..." -ForegroundColor Cyan
    powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\generate-wfcd-relationships.ps1 -Root .
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

    Write-Host "Normalizing drop locations..." -ForegroundColor Cyan
    powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\normalize-drop-locations.ps1 -Root .
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

    Write-Host "Refreshing manifests..." -ForegroundColor Cyan
    powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\build-domain-manifests.ps1 -Root .
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

    Write-Host "Rebuilding assistant/search/materialized views..." -ForegroundColor Cyan
    powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\build-ai-layer.ps1 -Root .
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
}
finally {
    Pop-Location
}

Write-Host "Warframe KB refresh completed." -ForegroundColor Green
