param(
    [Parameter(Mandatory = $true)]
    [string]$ManifestPath,
    [string]$Root = ".",
    [switch]$WriteCanonical,
    [switch]$MergeExisting
)

$ErrorActionPreference = "Stop"

$repoRoot = Resolve-Path $Root
$normalizeArgs = @(
    "-ExecutionPolicy", "Bypass",
    "-File", ".\scripts\normalize-static-import.ps1",
    "-ManifestPath", $ManifestPath,
    "-Root", "."
)

if ($WriteCanonical) {
    $normalizeArgs += "-WriteCanonical"
    if ($MergeExisting) {
        $normalizeArgs += "-MergeExisting"
    }
}

Write-Host "Step 1/3: normalize static import" -ForegroundColor Cyan
& powershell @normalizeArgs
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

Write-Host "Step 2/3: validate repository JSON" -ForegroundColor Cyan
& powershell -ExecutionPolicy Bypass -File .\scripts\validate-kb.ps1 -Root .
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

Write-Host "Step 3/3: rebuild registry" -ForegroundColor Cyan
& powershell -ExecutionPolicy Bypass -File .\scripts\build-registry.ps1 -Root .
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

Write-Host "Static pipeline completed." -ForegroundColor Green
