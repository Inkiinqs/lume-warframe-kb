param(
    [string]$Root = "."
)

$ErrorActionPreference = "Stop"

function Read-Json {
    param([string]$Path)
    Get-Content -Raw -LiteralPath $Path | ConvertFrom-Json
}

function Merge-UniqueList {
    param(
        [object[]]$Existing,
        [object[]]$Incoming
    )

    $all = @()
    if ($Existing) { $all += $Existing }
    if ($Incoming) { $all += $Incoming }

    $seen = @{}
    $result = @()
    foreach ($entry in $all) {
        if ($null -eq $entry) { continue }
        $key = if ($entry -is [string]) {
            $entry
        } elseif ($entry.PSObject.Properties.Name -contains "type" -and $entry.PSObject.Properties.Name -contains "value") {
            "$($entry.type)|$($entry.value)"
        } else {
            ($entry | ConvertTo-Json -Depth 8 -Compress)
        }

        if (-not $seen.ContainsKey($key)) {
            $seen[$key] = $true
            $result += $entry
        }
    }

    return $result
}

$repoRoot = Resolve-Path $Root
$mapPath = Join-Path $repoRoot "core\\mappings\\system-source-map.json"
$map = Read-Json -Path $mapPath

$systemFiles = Get-ChildItem -Path (Join-Path $repoRoot "content\\systems") -Recurse -File -Filter *.json |
    Where-Object { $_.Name -ne "manifest.json" }

$updated = 0
foreach ($file in $systemFiles) {
    $record = Read-Json -Path $file.FullName
    if (-not $record.id) { continue }

    $folder = Split-Path -Leaf $file.DirectoryName
    $default = $map.defaults.PSObject.Properties[$folder].Value
    $specific = $map.records.PSObject.Properties[[string]$record.id].Value

    if (-not $default -and -not $specific) { continue }

    $existingSources = @($record.sources)
    $defaultSources = @()
    if ($default -and $default.sources) { $defaultSources = @($default.sources) }
    $specificSources = @()
    if ($specific -and $specific.sources) { $specificSources = @($specific.sources) }

    $mergedSources = Merge-UniqueList -Existing $existingSources -Incoming ($defaultSources + $specificSources)
    if (($defaultSources.Count + $specificSources.Count) -gt 0) {
        $mergedSources = @($mergedSources | Where-Object {
            -not ($_.PSObject.Properties.Name -contains "type" -and $_.PSObject.Properties.Name -contains "value" -and $_.type -eq "manual" -and $_.value -eq "starter scaffold")
        })
    }
    $record.sources = $mergedSources

    $existingNotes = @($record.notes)
    $noteAdds = @()
    if ($specific -and $specific.notesAppend) { $noteAdds = @($specific.notesAppend) }
    $record.notes = Merge-UniqueList -Existing $existingNotes -Incoming $noteAdds

    if ($default -and $default.verification) {
        $record | Add-Member -NotePropertyName verification -NotePropertyValue $default.verification -Force
    }
    if ($specific -and $specific.verification) {
        $record | Add-Member -NotePropertyName verification -NotePropertyValue $specific.verification -Force
    }

    $record | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $file.FullName
    $updated++
}

Write-Host "Applied source map to $updated systems records." -ForegroundColor Green
