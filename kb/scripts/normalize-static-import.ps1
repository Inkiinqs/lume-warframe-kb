param(
    [Parameter(Mandatory = $true)]
    [string]$ManifestPath,
    [string]$Root = ".",
    [switch]$WriteCanonical,
    [switch]$MergeExisting
)

$ErrorActionPreference = "Stop"

function Convert-ToSlug {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Value
    )

    $slug = $Value.ToLowerInvariant()
    $slug = $slug -replace "[^a-z0-9]+", "-"
    $slug = $slug.Trim("-")
    return $slug
}

function Test-FieldPresent {
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$Item,
        [Parameter(Mandatory = $true)]
        [string]$FieldName
    )

    return $Item.PSObject.Properties.Name -contains $FieldName
}

function Get-OptionalValue {
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$Item,
        [string]$FieldName,
        $DefaultValue = $null
    )

    if ([string]::IsNullOrWhiteSpace($FieldName)) {
        return $DefaultValue
    }

    if (Test-FieldPresent -Item $Item -FieldName $FieldName) {
        return $Item.$FieldName
    }

    return $DefaultValue
}

function New-CanonicalEntityRecord {
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$Item,
        [Parameter(Mandatory = $true)]
        [pscustomobject]$Rule,
        [Parameter(Mandatory = $true)]
        [string]$SourcePath
    )

    $explicitId = Get-OptionalValue -Item $Item -FieldName $Rule.idField
    $slugValue = if ($explicitId) {
        $null
    }
    elseif (Test-FieldPresent -Item $Item -FieldName $Rule.slugField) {
        [string]$Item.($Rule.slugField)
    }
    else {
        Convert-ToSlug -Value ([string]$Item.($Rule.nameField))
    }

    $recordId = if ($explicitId) { [string]$explicitId } else { "{0}{1}" -f $Rule.idPrefix, $slugValue }
    $name = [string]$Item.($Rule.nameField)
    $summary = if (Test-FieldPresent -Item $Item -FieldName $Rule.summaryField) { [string]$Item.($Rule.summaryField) } else { "" }
    $description = if (Test-FieldPresent -Item $Item -FieldName $Rule.descriptionField) { [string]$Item.($Rule.descriptionField) } else { $null }
    $subCategory = if (Test-FieldPresent -Item $Item -FieldName $Rule.subCategoryField) { [string]$Item.($Rule.subCategoryField) } else { $null }
    $aliases = @((Get-OptionalValue -Item $Item -FieldName $Rule.aliasesField -DefaultValue @()))
    $stats = Get-OptionalValue -Item $Item -FieldName $Rule.statsField -DefaultValue ([ordered]@{})
    $mechanics = Get-OptionalValue -Item $Item -FieldName $Rule.mechanicsField -DefaultValue ([ordered]@{})
    $relationships = @((Get-OptionalValue -Item $Item -FieldName $Rule.relationshipsField -DefaultValue @()))
    $release = Get-OptionalValue -Item $Item -FieldName $Rule.releaseField -DefaultValue ([ordered]@{})
    $tags = @((Get-OptionalValue -Item $Item -FieldName $Rule.tagsField -DefaultValue @()))
    $sourceNotes = @((Get-OptionalValue -Item $Item -FieldName $Rule.notesField -DefaultValue @()))
    $notes = @("Normalized from static import source.")
    if ($sourceNotes.Count -gt 0) {
        $notes += $sourceNotes
    }

    $targetSlug = if ($recordId -match "\.") { ($recordId -split "\.", 2)[1] } else { Convert-ToSlug -Value $recordId }

    [ordered]@{
        id = $recordId
        name = $name
        category = $Rule.category
        subCategory = $subCategory
        aliases = $aliases
        summary = $summary
        description = $description
        stats = $stats
        mechanics = $mechanics
        relationships = $relationships
        release = $release
        tags = $tags
        notes = $notes
        sources = @(
            [ordered]@{
                type = "static-import"
                value = $SourcePath.Replace("\", "/")
            }
        )
        _targetSlug = $targetSlug
    }
}

function Merge-UniqueArray {
    param(
        [array]$Primary,
        [array]$Secondary
    )

    $combined = @()
    foreach ($value in @($Primary) + @($Secondary)) {
        if ($null -eq $value) { continue }
        if ($value -is [string]) {
            if ($combined -notcontains $value) {
                $combined += $value
            }
        }
        else {
            $json = $value | ConvertTo-Json -Depth 10 -Compress
            $existingJson = @($combined | ForEach-Object { $_ | ConvertTo-Json -Depth 10 -Compress })
            if ($existingJson -notcontains $json) {
                $combined += $value
            }
        }
    }
    return $combined
}

function Merge-Record {
    param(
        [hashtable]$Existing,
        [hashtable]$Incoming
    )

    $merged = [ordered]@{}
    $keys = @($Existing.Keys + $Incoming.Keys | Select-Object -Unique)
    foreach ($key in $keys) {
        $existingValue = $Existing[$key]
        $incomingValue = $Incoming[$key]

        switch ($key) {
            "aliases" { $merged[$key] = Merge-UniqueArray -Primary $existingValue -Secondary $incomingValue; continue }
            "tags" { $merged[$key] = Merge-UniqueArray -Primary $existingValue -Secondary $incomingValue; continue }
            "relationships" { $merged[$key] = Merge-UniqueArray -Primary $existingValue -Secondary $incomingValue; continue }
            "notes" { $merged[$key] = Merge-UniqueArray -Primary $existingValue -Secondary $incomingValue; continue }
            "sources" { $merged[$key] = Merge-UniqueArray -Primary $existingValue -Secondary $incomingValue; continue }
        }

        if ($null -eq $incomingValue -or ($incomingValue -is [string] -and [string]::IsNullOrWhiteSpace($incomingValue))) {
            $merged[$key] = $existingValue
            continue
        }

        if ($incomingValue -is [System.Collections.IDictionary] -or $incomingValue -is [pscustomobject]) {
            if ($existingValue -is [System.Collections.IDictionary] -or $existingValue -is [pscustomobject]) {
                $existingHash = @{}
                foreach ($prop in $existingValue.PSObject.Properties) { $existingHash[$prop.Name] = $prop.Value }
                $incomingHash = @{}
                foreach ($prop in $incomingValue.PSObject.Properties) { $incomingHash[$prop.Name] = $prop.Value }
                $merged[$key] = Merge-Record -Existing $existingHash -Incoming $incomingHash
            }
            else {
                $merged[$key] = $incomingValue
            }
            continue
        }

        $merged[$key] = $incomingValue
    }

    return $merged
}

$repoRoot = Resolve-Path $Root
$mappingPath = Join-Path $repoRoot "core\\mappings\\static-import.map.json"
$map = Get-Content -Raw -LiteralPath $mappingPath | ConvertFrom-Json
$manifestFullPath = Resolve-Path $ManifestPath
$manifest = Get-Content -Raw -LiteralPath $manifestFullPath | ConvertFrom-Json

$outputs = @()
$entries = @()

if ($manifest.PSObject.Properties.Name -contains "entries" -and $manifest.entries) {
    $entries = @($manifest.entries)
}
else {
    foreach ($file in $manifest.files) {
        $sourceName = [System.IO.Path]::GetFileNameWithoutExtension($file)
        $entries += [pscustomobject]@{
            file = $file
            domain = ($sourceName -replace "^sample-", "")
        }
    }
}

foreach ($entry in $entries) {
    $file = $entry.file
    $domainName = $entry.domain
    $sourcePath = Join-Path $repoRoot $file
    if (-not (Test-Path -LiteralPath $sourcePath)) {
        throw "Source file not found: $sourcePath"
    }

    $rule = $map.domains | Where-Object { $_.domain -eq $domainName } | Select-Object -First 1

    if (-not $rule) {
        Write-Host ("Skipping unmapped source file: {0}" -f $file) -ForegroundColor Yellow
        continue
    }

    $items = Get-Content -Raw -LiteralPath $sourcePath | ConvertFrom-Json
    foreach ($item in $items) {
        $record = New-CanonicalEntityRecord -Item $item -Rule $rule -SourcePath $file
        $targetFolder = Join-Path $repoRoot $rule.targetFolder
        $targetFile = Join-Path $targetFolder ($record._targetSlug + ".json")

        $writeRecord = [ordered]@{}
        foreach ($property in $record.Keys) {
            if ($property -ne "_targetSlug") {
                $writeRecord[$property] = $record[$property]
            }
        }

        $output = [ordered]@{
            domain = $rule.domain
            id = $writeRecord.id
            target = $targetFile
            record = $writeRecord
        }
        $outputs += [pscustomobject]$output

        if ($WriteCanonical) {
            if (-not (Test-Path -LiteralPath $targetFolder)) {
                New-Item -ItemType Directory -Force -Path $targetFolder | Out-Null
            }

            $finalRecord = $writeRecord
            if ($MergeExisting -and (Test-Path -LiteralPath $targetFile)) {
                $existingRecord = Get-Content -Raw -LiteralPath $targetFile | ConvertFrom-Json
                $existingHash = @{}
                foreach ($prop in $existingRecord.PSObject.Properties) { $existingHash[$prop.Name] = $prop.Value }
                $incomingHash = @{}
                foreach ($prop in $writeRecord.Keys) { $incomingHash[$prop] = $writeRecord[$prop] }
                $finalRecord = Merge-Record -Existing $existingHash -Incoming $incomingHash
            }
            $json = $finalRecord | ConvertTo-Json -Depth 12
            Set-Content -LiteralPath $targetFile -Value $json
        }
    }
}

$normalizedFolder = Join-Path $repoRoot "imports\\static\\normalized"
$outputPath = Join-Path $normalizedFolder "last-static-normalization.json"
$outputs | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $outputPath

Write-Host ("Normalized {0} records." -f $outputs.Count) -ForegroundColor Green
Write-Host ("Wrote normalization preview to {0}" -f $outputPath) -ForegroundColor Green

if ($WriteCanonical) {
    Write-Host "Canonical files were written." -ForegroundColor Green
}
else {
    Write-Host "Preview mode only. Use -WriteCanonical to write canonical files." -ForegroundColor Yellow
}
