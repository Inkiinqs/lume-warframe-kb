param(
    [string]$Root = "."
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
$searchRoot = Join-Path $repoRoot "ai\\search-docs"
Ensure-Directory $searchRoot

$contentFiles = Get-ChildItem -Path (Join-Path $repoRoot "content") -Recurse -File -Filter *.json |
    Where-Object { $_.Name -ne "manifest.json" }

$docs = @()
foreach ($file in $contentFiles) {
    $json = Read-Json -Path $file.FullName
    if (-not $json.id -or -not $json.name) { continue }

    $tags = @()
    if ($json.PSObject.Properties.Name -contains "tags") { $tags = @($json.tags) }
    $relationships = @()
    if ($json.PSObject.Properties.Name -contains "relationships") { $relationships = @($json.relationships) }
    $notes = @()
    if ($json.PSObject.Properties.Name -contains "notes") { $notes = @($json.notes) }
    $statsText = ""
    if ($json.PSObject.Properties.Name -contains "stats" -and $json.stats) {
        $statsText = $json.stats | ConvertTo-Json -Depth 8 -Compress
    }
    $mechanicsText = ""
    if ($json.PSObject.Properties.Name -contains "mechanics" -and $json.mechanics) {
        $mechanicsText = $json.mechanics | ConvertTo-Json -Depth 8 -Compress
    }

    $textParts = @(
        [string]$json.name,
        [string]$json.category,
        [string]$json.subCategory,
        [string]$json.summary,
        [string]$json.description,
        $statsText,
        $mechanicsText
    ) + $tags + $relationships + $notes

    $doc = [ordered]@{
        id = [string]$json.id
        name = [string]$json.name
        category = [string]$json.category
        subCategory = [string]$json.subCategory
        sourcePath = $file.FullName.Replace($repoRoot.Path + "\", "").Replace("\", "/")
        tags = $tags
        relationships = $relationships
        text = (($textParts | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }) -join "`n")
    }
    $docs += [pscustomobject]$doc
}

$outPath = Join-Path $searchRoot "records.search.json"
$docs | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $outPath

Write-Host ("Generated {0} search docs." -f $docs.Count) -ForegroundColor Green
