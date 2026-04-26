param(
    [string]$Root = "."
)

$ErrorActionPreference = "Stop"

function Get-ManifestRefs {
    param(
        [string]$BasePath
    )

    Get-ChildItem -Path $BasePath -Recurse -File -Filter manifest.json |
        Where-Object { $_.FullName -notmatch "\\imports\\" } |
        ForEach-Object {
            $_.FullName.Replace((Resolve-Path $BasePath).Path + "\", "").Replace("\", "/")
        } |
        Sort-Object
}

$repoRoot = Resolve-Path $Root
$registryPath = Join-Path $repoRoot "core\\indexes\\registry.json"
$registry = Get-Content -Raw -LiteralPath $registryPath | ConvertFrom-Json

$allManifests = Get-ManifestRefs -BasePath $repoRoot

$registry.indexes.entities = @($allManifests | Where-Object { $_ -like "content/items/*/manifest.json" })
$registry.indexes.activities = @($allManifests | Where-Object { $_ -like "content/activities/*/manifest.json" -or $_ -eq "content/activities/manifest.json" })
$registry.indexes.world = @($allManifests | Where-Object { $_ -like "content/world/*/manifest.json" -or $_ -eq "content/world/manifest.json" })
$registry.indexes.relationships = @($allManifests | Where-Object { $_ -like "content/relationships/*/manifest.json" })

$registry.generatedAt = (Get-Date).ToString("s") + "Z"

$json = $registry | ConvertTo-Json -Depth 8
Set-Content -LiteralPath $registryPath -Value $json

Write-Host ("Updated registry at {0}" -f $registryPath) -ForegroundColor Green
