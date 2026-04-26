param(
    [Parameter(Mandatory = $true)]
    [string]$ManifestPath
)

$ErrorActionPreference = "Stop"

$manifest = Get-Content -Raw -LiteralPath $ManifestPath | ConvertFrom-Json

Write-Host ("Source ID: {0}" -f $manifest.sourceId)
Write-Host ("Source Type: {0}" -f $manifest.sourceType)
Write-Host ("Files: {0}" -f ($manifest.files.Count))
Write-Host ("Targets: {0}" -f (($manifest.normalizesInto -join ", ")))
Write-Host ""
Write-Host "Normalization stub only."
Write-Host "Implement source-specific mappers before writing canonical records."
