param(
    [string]$Root = "."
)

$ErrorActionPreference = "Stop"

function Get-JsonFiles {
    param(
        [string]$BasePath
    )

    Get-ChildItem -Path $BasePath -Recurse -File -Filter *.json |
        Where-Object { $_.FullName -notmatch "\\imports\\" -or $_.Name -like "*.template.json" -eq $false }
}

function Test-JsonParse {
    param(
        [string]$Path
    )

    try {
        Get-Content -Raw -LiteralPath $Path | ConvertFrom-Json | Out-Null
        [PSCustomObject]@{
            Path = $Path
            Valid = $true
            Message = "OK"
        }
    }
    catch {
        [PSCustomObject]@{
            Path = $Path
            Valid = $false
            Message = $_.Exception.Message
        }
    }
}

$repoRoot = Resolve-Path $Root
$jsonFiles = Get-JsonFiles -BasePath $repoRoot
$results = foreach ($file in $jsonFiles) {
    Test-JsonParse -Path $file.FullName
}

$invalid = $results | Where-Object { -not $_.Valid }

if ($invalid) {
    Write-Host "Invalid JSON files found:" -ForegroundColor Red
    $invalid | ForEach-Object {
        Write-Host ("- {0}: {1}" -f $_.Path, $_.Message) -ForegroundColor Red
    }
    exit 1
}

Write-Host ("Validated {0} JSON files." -f $results.Count) -ForegroundColor Green
