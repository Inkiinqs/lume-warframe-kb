param(
    [string]$Root = "."
)

$ErrorActionPreference = "Stop"

Write-Host "Step 1/10: refresh system sources" -ForegroundColor Cyan
& powershell -ExecutionPolicy Bypass -File .\scripts\apply-system-source-map.ps1 -Root $Root
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

Write-Host "Step 2/10: normalize market snapshots" -ForegroundColor Cyan
& powershell -ExecutionPolicy Bypass -File .\scripts\normalize-market-snapshots.ps1 -Root $Root
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

Write-Host "Step 3/10: build search docs" -ForegroundColor Cyan
& powershell -ExecutionPolicy Bypass -File .\scripts\build-ai-search-docs.ps1 -Root $Root
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

Write-Host "Step 4/10: build materialized views" -ForegroundColor Cyan
& powershell -ExecutionPolicy Bypass -File .\scripts\build-ai-views.ps1 -Root $Root
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

Write-Host "Step 5/10: build market and player-aware views" -ForegroundColor Cyan
& powershell -ExecutionPolicy Bypass -File .\scripts\build-combat-views.ps1 -Root $Root
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

& powershell -ExecutionPolicy Bypass -File .\scripts\build-recommendation-views.ps1 -Root $Root
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

& powershell -ExecutionPolicy Bypass -File .\scripts\build-player-build-skeletons.ps1 -Root $Root
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

& powershell -ExecutionPolicy Bypass -File .\scripts\build-market-views.ps1 -Root $Root
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

& powershell -ExecutionPolicy Bypass -File .\scripts\build-player-views.ps1 -Root $Root
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

& powershell -ExecutionPolicy Bypass -File .\scripts\build-assistant-live-context.ps1 -Root $Root
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

& powershell -ExecutionPolicy Bypass -File .\scripts\build-assistant-contracts.ps1 -Root $Root
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

& powershell -ExecutionPolicy Bypass -File .\scripts\build-query-router.ps1 -Root $Root
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

Write-Host "Step 6/10: validate assistant contracts" -ForegroundColor Cyan
& powershell -ExecutionPolicy Bypass -File .\scripts\validate-assistant-contracts.ps1 -Root $Root
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

Write-Host "Step 7/10: validate backend API contracts" -ForegroundColor Cyan
& powershell -ExecutionPolicy Bypass -File .\scripts\validate-backend-api-contracts.ps1 -Root $Root
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

Write-Host "Step 8/10: test query router" -ForegroundColor Cyan
& powershell -ExecutionPolicy Bypass -File .\scripts\test-query-router.ps1 -Root $Root -WriteReport
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

Write-Host "Step 9/10: build backend readiness report" -ForegroundColor Cyan
& powershell -ExecutionPolicy Bypass -File .\scripts\build-backend-readiness-report.ps1 -Root $Root
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

Write-Host "Step 10/10: validate repository JSON" -ForegroundColor Cyan
& powershell -ExecutionPolicy Bypass -File .\scripts\validate-kb.ps1 -Root $Root
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

Write-Host "AI layer build completed." -ForegroundColor Green
