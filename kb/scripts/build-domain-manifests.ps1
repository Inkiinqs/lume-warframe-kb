param(
    [string]$Root = "."
)

$ErrorActionPreference = "Stop"

function Get-RecordId {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    try {
        $json = Get-Content -Raw -LiteralPath $Path | ConvertFrom-Json
        if ($json.PSObject.Properties.Name -contains "id") {
            return [string]$json.id
        }
    }
    catch {
        return $null
    }

    return $null
}

function Update-LeafManifest {
    param(
        [Parameter(Mandatory = $true)]
        [string]$FolderPath
    )

    $manifestPath = Join-Path $FolderPath "manifest.json"
    $recordFiles = Get-ChildItem -LiteralPath $FolderPath -File -Filter *.json |
        Where-Object { $_.Name -ne "manifest.json" }

    $records = @()
    foreach ($file in $recordFiles) {
        $id = Get-RecordId -Path $file.FullName
        if ($id) {
            $records += $id
        }
    }

    if (Test-Path -LiteralPath $manifestPath) {
        $manifest = Get-Content -Raw -LiteralPath $manifestPath | ConvertFrom-Json
        $output = [ordered]@{}
        foreach ($prop in $manifest.PSObject.Properties) {
            if ($prop.Name -eq "records") {
                $output.records = @($records | Sort-Object)
            }
            else {
                $output[$prop.Name] = $prop.Value
            }
        }
        if (-not $output.Contains("records")) {
            $output.records = @($records | Sort-Object)
        }
    }
    else {
        $output = [ordered]@{
            category = Split-Path -Leaf $FolderPath
            description = "Generated manifest for $(Split-Path -Leaf $FolderPath)."
            records = @($records | Sort-Object)
        }
    }

    $output | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $manifestPath
}

$repoRoot = Resolve-Path $Root
$leafFolders = @(
    "content/items/warframes",
    "content/items/weapons",
    "content/items/mods",
    "content/items/relics",
    "content/items/resources",
    "content/items/arcanes",
    "content/items/companions",
    "content/items/gear",
    "content/items/vehicles",
    "content/world/factions",
    "content/world/enemies",
    "content/world/locations",
    "content/world/syndicates",
    "content/world/tilesets",
    "content/activities",
    "content/activities/star-chart",
    "content/activities/special",
    "content/activities/open-worlds",
    "content/relationships/compatibility",
    "content/relationships/crafting",
    "content/relationships/drops",
    "content/relationships/references",
    "content/relationships/synergies",
    "content/systems/status-effects",
    "content/systems/damage",
    "content/systems/combat-formulas",
    "content/systems/modding-rules",
    "content/systems/ability-rules"
)

foreach ($folder in $leafFolders) {
    $fullPath = Join-Path $repoRoot $folder
    if (Test-Path -LiteralPath $fullPath) {
        Update-LeafManifest -FolderPath $fullPath
    }
}

Write-Host "Leaf manifests updated." -ForegroundColor Green
