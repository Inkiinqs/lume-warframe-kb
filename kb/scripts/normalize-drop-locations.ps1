param(
    [string]$Root = "."
)

$ErrorActionPreference = "Stop"

function Convert-ToSlug {
    param([string]$Value)
    $slug = $Value.ToLowerInvariant()
    $slug = $slug -replace "[^a-z0-9]+", "-"
    $slug = $slug.Trim("-")
    return $slug
}

function Read-JsonFile {
    param([string]$Path)
    Get-Content -Raw -LiteralPath $Path | ConvertFrom-Json
}

function Write-JsonFile {
    param(
        [string]$Path,
        $Object
    )
    $Object | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $Path
}

function Get-SpecialActivityFamily {
    param(
        [string]$Label,
        $Taxonomy
    )

    foreach ($pattern in @($Taxonomy.patterns)) {
        if ($Label -match [string]$pattern.match) {
            return [string]$pattern.family
        }
    }

    return "special"
}

function Ensure-Directory {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) {
        New-Item -ItemType Directory -Force -Path $Path | Out-Null
    }
}

function Get-ExistingRecordMap {
    param([string]$Folder)
    $map = @{}
    if (-not (Test-Path -LiteralPath $Folder)) { return $map }
    Get-ChildItem -LiteralPath $Folder -File -Filter *.json | Where-Object { $_.Name -ne "manifest.json" } | ForEach-Object {
        try {
            $json = Read-JsonFile -Path $_.FullName
            if ($json.id) { $map[[string]$json.id] = $_.FullName }
        }
        catch {}
    }
    return $map
}

function Ensure-StringInArray {
    param(
        [array]$Array,
        [string]$Value
    )
    $output = @()
    foreach ($item in @($Array)) {
        if ($null -ne $item) {
            $output += [string]$item
        }
    }
    if ($output -notcontains $Value) {
        $output += $Value
    }
    return $output
}

function Set-ObjectProperty {
    param(
        [Parameter(Mandatory = $true)]
        [object]$Object,
        [Parameter(Mandatory = $true)]
        [string]$Name,
        $Value
    )

    if ($Object.PSObject.Properties.Name -contains $Name) {
        $Object.$Name = $Value
    }
    else {
        $Object | Add-Member -NotePropertyName $Name -NotePropertyValue $Value -Force
    }
}

function Ensure-LocationRecord {
    param(
        [string]$LocationId,
        [string]$PlanetName,
        [string]$Folder,
        [hashtable]$Existing
    )

    if ($Existing.ContainsKey($LocationId)) { return }

    $slug = ($LocationId -split "\.", 2)[1]
    $path = Join-Path $Folder ($slug + ".json")
    $record = [ordered]@{
        id = $LocationId
        name = $PlanetName
        category = "location"
        subCategory = "planet"
        aliases = @()
        summary = "$PlanetName is a generated location anchor derived from sourced drop data."
        description = "Generated from WFCD drop-location normalization."
        stats = [ordered]@{}
        mechanics = [ordered]@{
            locationType = "planet"
        }
        relationships = @()
        release = [ordered]@{}
        tags = @("location", "generated", "wfcd-derived")
        notes = @("Generated from parseable drop location strings.")
        sources = @(
            [ordered]@{
                type = "wfcd-location-normalizer"
                value = $PlanetName
            }
        )
    }
    Write-JsonFile -Path $path -Object $record
    $Existing[$LocationId] = $path
}

function Ensure-ActivityRecord {
    param(
        [string]$ActivityId,
        [string]$PlanetName,
        [string]$NodeName,
        [string]$MissionType,
        [string]$RawLocation,
        [string]$LocationId,
        [string]$Folder,
        [hashtable]$Existing
    )

    $slug = ($ActivityId -split "\.", 2)[1]
    $path = Join-Path $Folder ($slug + ".json")

    if ($Existing.ContainsKey($ActivityId)) {
        $record = Read-JsonFile -Path $Existing[$ActivityId]
        $record.relationships = @(Ensure-StringInArray -Array $record.relationships -Value $LocationId)
        if (-not $record.mechanics) { $record | Add-Member -NotePropertyName mechanics -NotePropertyValue ([ordered]@{}) -Force }
        $aliases = @()
        if ($record.mechanics.PSObject.Properties.Name -contains "sourceAliases") {
            $aliases = @($record.mechanics.sourceAliases)
        }
        Set-ObjectProperty -Object $record.mechanics -Name "sourceAliases" -Value @(Ensure-StringInArray -Array $aliases -Value $RawLocation)
        if (-not $record.mechanics.PSObject.Properties.Name -contains "missionType" -and $MissionType) {
            Set-ObjectProperty -Object $record.mechanics -Name "missionType" -Value $MissionType
        }
        $normalizedMechanics = [ordered]@{}
        foreach ($prop in $record.mechanics.PSObject.Properties) {
            if ($prop.Name -eq "sourceAliases") {
                $normalizedMechanics[$prop.Name] = @($prop.Value)
            }
            else {
                $normalizedMechanics[$prop.Name] = $prop.Value
            }
        }
        $normalizedRecord = [ordered]@{}
        foreach ($prop in $record.PSObject.Properties) {
            if ($prop.Name -eq "relationships") {
                $normalizedRecord[$prop.Name] = @($prop.Value)
            }
            elseif ($prop.Name -eq "mechanics") {
                $normalizedRecord[$prop.Name] = $normalizedMechanics
            }
            else {
                $normalizedRecord[$prop.Name] = $prop.Value
            }
        }
        Write-JsonFile -Path $path -Object $normalizedRecord
        return
    }

    $record = [ordered]@{
        id = $ActivityId
        name = "$NodeName, $PlanetName"
        category = "activity"
        subCategory = "star-chart-node"
        aliases = @()
        summary = "$NodeName on $PlanetName is a generated star-chart activity anchor derived from sourced drop data."
        description = "Generated from WFCD drop-location normalization."
        stats = [ordered]@{}
        mechanics = [ordered]@{
            activityType = "star-chart-node"
            missionType = $MissionType
            sourceAliases = @($RawLocation)
        }
        relationships = @($LocationId)
        release = [ordered]@{}
        tags = @("activity", "star-chart", "generated", "wfcd-derived")
        notes = @("Generated from parseable drop location strings.")
        sources = @(
            [ordered]@{
                type = "wfcd-location-normalizer"
                value = $RawLocation
            }
        )
    }
    Write-JsonFile -Path $path -Object $record
    $Existing[$ActivityId] = $path
}

function Ensure-SpecialActivityRecord {
    param(
        [string]$ActivityId,
        [string]$Label,
        [string]$Rotation,
        $Taxonomy,
        [string]$Folder,
        [hashtable]$Existing
    )

    $slug = ($ActivityId -split "\.", 2)[1]
    $path = Join-Path $Folder ($slug + ".json")

    $activityFamily = Get-SpecialActivityFamily -Label $Label -Taxonomy $Taxonomy

    if ($Existing.ContainsKey($ActivityId)) {
        $record = Read-JsonFile -Path $Existing[$ActivityId]
        if (-not $record.mechanics) { $record | Add-Member -NotePropertyName mechanics -NotePropertyValue ([ordered]@{}) -Force }
        Set-ObjectProperty -Object $record.mechanics -Name "activityType" -Value "special-reward-source"
        Set-ObjectProperty -Object $record.mechanics -Name "activityFamily" -Value $activityFamily
        if ($Rotation) {
            Set-ObjectProperty -Object $record.mechanics -Name "rotation" -Value $Rotation
        }
        Write-JsonFile -Path $path -Object $record
        return
    }

    $record = [ordered]@{
        id = $ActivityId
        name = if ($Rotation) { "$Label, Rotation $Rotation" } else { $Label }
        category = "activity"
        subCategory = "special-source"
        aliases = @()
        summary = "$Label is a generated special activity source derived from sourced drop data."
        description = "Generated from WFCD drop-location normalization."
        stats = [ordered]@{}
        mechanics = [ordered]@{
            activityType = "special-reward-source"
            activityFamily = $activityFamily
            rotation = $Rotation
            sourceAliases = @($Label)
        }
        relationships = @()
        release = [ordered]@{}
        tags = @("activity", "special", "generated", "wfcd-derived", $activityFamily)
        notes = @("Generated from non-node drop location strings.")
        sources = @(
            [ordered]@{
                type = "wfcd-location-normalizer"
                value = $Label
            }
        )
    }
    Write-JsonFile -Path $path -Object $record
    $Existing[$ActivityId] = $path
}

function Ensure-ActivityLocationReference {
    param(
        [string]$ActivityId,
        [string]$LocationId,
        [string]$Folder,
        [hashtable]$Existing
    )

    $rid = "relationship.activity-location-" + (Convert-ToSlug ((($ActivityId -split "\.", 2)[1]) + "-" + (($LocationId -split "\.", 2)[1])))
    if ($Existing.ContainsKey($rid)) { return }

    $path = Join-Path $Folder ((($rid -split "\.", 2)[1]) + ".json")
    $record = [ordered]@{
        id = $rid
        type = "activity_location"
        from = $ActivityId
        to = $LocationId
        summary = "$ActivityId belongs to $LocationId."
        conditions = [ordered]@{}
        values = [ordered]@{}
        tags = @("activity", "location", "generated")
        sources = @(
            [ordered]@{
                type = "wfcd-location-normalizer"
                value = $ActivityId
            }
        )
    }
    Write-JsonFile -Path $path -Object $record
    $Existing[$rid] = $path
}

function Parse-LocationString {
    param([string]$Value)

    $trimmed = $Value.Trim()

    $slashPattern = "^(?<planet>[^/]+)/(?<node>[^,(]+?)(?: \((?<mission>[^)]+)\))?(?:, Rotation (?<rotation>.+))?$"
    if ($trimmed -match $slashPattern) {
        return [pscustomobject]@{
            kind = "activity"
            planet = $Matches.planet.Trim()
            node = $Matches.node.Trim()
            missionType = $Matches.mission
            rotation = $Matches.rotation
            raw = $trimmed
        }
    }

    $specialRotationPattern = "^(?<label>.+?), Rotation (?<rotation>[A-Z])$"
    if ($trimmed -match $specialRotationPattern) {
        return [pscustomobject]@{
            kind = "special"
            label = $Matches.label.Trim()
            rotation = $Matches.rotation
            raw = $trimmed
        }
    }

    $commaPattern = "^(?<node>[^,]+), (?<planet>[^,]+?)(?:, Rotation (?<rotation>.+))?$"
    if ($trimmed -match $commaPattern) {
        return [pscustomobject]@{
            kind = "activity"
            planet = $Matches.planet.Trim()
            node = $Matches.node.Trim()
            missionType = $null
            rotation = $Matches.rotation
            raw = $trimmed
        }
    }

    if ($trimmed -match "^(?<relic>.+?) Relic(?: (?<refinement>Intact|Exceptional|Flawless|Radiant))?$") {
        $baseName = $Matches.relic.Trim()
        $refinement = $Matches.refinement
        $combined = if ($refinement) { "$baseName $refinement" } else { $baseName }
        return [pscustomobject]@{
            kind = "relic"
            relicId = "relic." + (Convert-ToSlug $combined)
            refinement = $refinement
            raw = $trimmed
        }
    }

    return $null
}

$repoRoot = Resolve-Path $Root
$dropsFolder = Join-Path $repoRoot "content\\relationships\\drops"
$locationsFolder = Join-Path $repoRoot "content\\world\\locations"
$activitiesFolder = Join-Path $repoRoot "content\\activities\\star-chart"
$specialActivitiesFolder = Join-Path $repoRoot "content\\activities\\special"
$referencesFolder = Join-Path $repoRoot "content\\relationships\\references"
$specialTaxonomy = Read-JsonFile -Path (Join-Path $repoRoot "core\\mappings\\special-activity-taxonomy.json")

Ensure-Directory $locationsFolder
Ensure-Directory $activitiesFolder
Ensure-Directory $specialActivitiesFolder
Ensure-Directory $referencesFolder

$existingLocations = Get-ExistingRecordMap -Folder $locationsFolder
$existingActivities = Get-ExistingRecordMap -Folder $activitiesFolder
$existingSpecialActivities = Get-ExistingRecordMap -Folder $specialActivitiesFolder
$existingReferences = Get-ExistingRecordMap -Folder $referencesFolder

$normalizedActivities = 0
$normalizedRelics = 0
$createdLocations = 0
$createdActivities = 0
$createdRefs = 0

$dropFiles = Get-ChildItem -LiteralPath $dropsFolder -File -Filter *.json | Where-Object { $_.Name -ne "manifest.json" }

foreach ($file in $dropFiles) {
    $record = Read-JsonFile -Path $file.FullName
    if (-not $record.values -or -not $record.values.location) { continue }

    $parsed = Parse-LocationString -Value ([string]$record.values.location)
    if (-not $parsed) { continue }

    if ($parsed.kind -eq "activity") {
        $planetSlug = Convert-ToSlug $parsed.planet
        $nodeSlug = Convert-ToSlug $parsed.node
        $locationId = "location.$planetSlug"
        $activityId = "activity.$planetSlug-$nodeSlug"

        if (-not $existingLocations.ContainsKey($locationId)) { $createdLocations++ }
        Ensure-LocationRecord -LocationId $locationId -PlanetName $parsed.planet -Folder $locationsFolder -Existing $existingLocations

        if (-not $existingActivities.ContainsKey($activityId)) { $createdActivities++ }
        Ensure-ActivityRecord -ActivityId $activityId -PlanetName $parsed.planet -NodeName $parsed.node -MissionType $parsed.missionType -RawLocation $parsed.raw -LocationId $locationId -Folder $activitiesFolder -Existing $existingActivities

        $beforeRefs = $existingReferences.Count
        Ensure-ActivityLocationReference -ActivityId $activityId -LocationId $locationId -Folder $referencesFolder -Existing $existingReferences
        if ($existingReferences.Count -gt $beforeRefs) { $createdRefs++ }

        $record.from = $activityId
        if (-not $record.conditions) { $record | Add-Member -NotePropertyName conditions -NotePropertyValue ([ordered]@{}) -Force }
        if ($parsed.rotation) {
            Set-ObjectProperty -Object $record.conditions -Name "rotation" -Value $parsed.rotation
        }
        Set-ObjectProperty -Object $record.values -Name "rawLocation" -Value $record.values.location
        Set-ObjectProperty -Object $record.values -Name "locationPlanet" -Value $parsed.planet
        Set-ObjectProperty -Object $record.values -Name "locationNode" -Value $parsed.node
        if ($parsed.missionType) {
            Set-ObjectProperty -Object $record.values -Name "missionType" -Value $parsed.missionType
        }
        $record.tags = @(Ensure-StringInArray -Array $record.tags -Value "activity-normalized")
        Write-JsonFile -Path $file.FullName -Object $record
        $normalizedActivities++
        continue
    }

    if ($parsed.kind -eq "relic") {
        $record.from = $parsed.relicId
        if (-not $record.conditions) { $record | Add-Member -NotePropertyName conditions -NotePropertyValue ([ordered]@{}) -Force }
        if ($parsed.refinement) {
            Set-ObjectProperty -Object $record.conditions -Name "refinement" -Value $parsed.refinement
        }
        Set-ObjectProperty -Object $record.values -Name "rawLocation" -Value $record.values.location
        $record.tags = @(Ensure-StringInArray -Array $record.tags -Value "relic-normalized")
        Write-JsonFile -Path $file.FullName -Object $record
        $normalizedRelics++
        continue
    }

    if ($parsed.kind -eq "special") {
        $activityId = "activity." + (Convert-ToSlug ($parsed.label))
        Ensure-SpecialActivityRecord -ActivityId $activityId -Label $parsed.label -Rotation $parsed.rotation -Taxonomy $specialTaxonomy -Folder $specialActivitiesFolder -Existing $existingSpecialActivities
        $record.from = $activityId
        if (-not $record.conditions) { $record | Add-Member -NotePropertyName conditions -NotePropertyValue ([ordered]@{}) -Force }
        if ($parsed.rotation) {
            Set-ObjectProperty -Object $record.conditions -Name "rotation" -Value $parsed.rotation
        }
        Set-ObjectProperty -Object $record.values -Name "rawLocation" -Value $record.values.location
        Set-ObjectProperty -Object $record.values -Name "specialActivityLabel" -Value $parsed.label
        $record.tags = @(Ensure-StringInArray -Array $record.tags -Value "special-activity-normalized")
        Write-JsonFile -Path $file.FullName -Object $record
        $normalizedActivities++
    }
}

Write-Host ("Normalized {0} activity-based drop sources and {1} relic-based drop sources." -f $normalizedActivities, $normalizedRelics) -ForegroundColor Green
Write-Host ("Created {0} locations, {1} activities, and {2} activity-location references." -f $createdLocations, $createdActivities, $createdRefs) -ForegroundColor Green
