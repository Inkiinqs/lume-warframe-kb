param(
    [string]$Root = "."
)

$ErrorActionPreference = "Stop"

$repoRoot = Resolve-Path $Root
$sourceConfigPath = Join-Path $repoRoot "imports\\static\\sources\\wfcd-source.json"
$sourceConfig = Get-Content -Raw -LiteralPath $sourceConfigPath | ConvertFrom-Json

foreach ($category in $sourceConfig.categories) {
    $uri = "{0}/{1}.json" -f $sourceConfig.baseUrl.TrimEnd("/"), $category.name
    $targetPath = Join-Path $repoRoot $category.target
    $targetDir = Split-Path -Parent $targetPath
    if (-not (Test-Path -LiteralPath $targetDir)) {
        New-Item -ItemType Directory -Force -Path $targetDir | Out-Null
    }

    Write-Host ("Fetching {0}" -f $uri) -ForegroundColor Cyan
    Invoke-WebRequest -Uri $uri -OutFile $targetPath
}

Write-Host "WFCD static snapshots fetched." -ForegroundColor Green
