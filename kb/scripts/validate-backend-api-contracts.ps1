param(
    [string]$Root = "."
)

$ErrorActionPreference = "Stop"

function Read-Json {
    param([string]$Path)
    Get-Content -Raw -LiteralPath $Path | ConvertFrom-Json
}

function Add-Issue {
    param(
        [System.Collections.ArrayList]$Issues,
        [string]$Path,
        [string]$Message
    )

    [void]$Issues.Add([ordered]@{
        path = $Path
        message = $Message
    })
}

function Has-Property {
    param($Object, [string]$Name)
    return $Object.PSObject.Properties.Name -contains $Name
}

function Require-Properties {
    param(
        [System.Collections.ArrayList]$Issues,
        [string]$Path,
        $Object,
        [string[]]$Names
    )

    foreach ($name in $Names) {
        if (-not (Has-Property -Object $Object -Name $name)) {
            Add-Issue -Issues $Issues -Path $Path -Message "Missing required property '$name'."
        }
    }
}

function Test-RelativePath {
    param(
        [string]$Root,
        [string]$RelativePath
    )

    return Test-Path -LiteralPath (Join-Path $Root ($RelativePath -replace "/", "\"))
}

$repoRoot = Resolve-Path $Root
$issues = New-Object System.Collections.ArrayList

$schemaPath = "core/schemas/backend-api-contracts.schema.json"
$contractPath = "backend-api-contracts/endpoints.json"

foreach ($path in @($schemaPath, $contractPath)) {
    if (-not (Test-RelativePath -Root $repoRoot -RelativePath $path)) {
        Add-Issue -Issues $issues -Path $path -Message "Required file missing."
    }
}

if ($issues.Count -eq 0) {
    $schema = Read-Json -Path (Join-Path $repoRoot ($schemaPath -replace "/", "\"))
    Require-Properties -Issues $issues -Path $schemaPath -Object $schema -Names @('$schema', '$id', 'title', 'type', 'required', 'properties')

    $contracts = Read-Json -Path (Join-Path $repoRoot ($contractPath -replace "/", "\"))
    Require-Properties -Issues $issues -Path $contractPath -Object $contracts -Names @("schemaVersion", "basePath", "endpoints")
    if ($contracts.schemaVersion -ne "backend-api-contracts.v1") {
        Add-Issue -Issues $issues -Path $contractPath -Message "Expected schemaVersion backend-api-contracts.v1."
    }

    $allowedMethods = @("GET", "POST", "PUT", "PATCH", "DELETE")
    foreach ($endpoint in @($contracts.endpoints)) {
        $endpointPath = "$contractPath/endpoints/$($endpoint.id)"
        Require-Properties -Issues $issues -Path $endpointPath -Object $endpoint -Names @(
            "id",
            "method",
            "path",
            "summary",
            "requestExample",
            "responseExample",
            "implementationAnchor",
            "sourceContracts"
        )
        if ($allowedMethods -notcontains [string]$endpoint.method) {
            Add-Issue -Issues $issues -Path $endpointPath -Message "Unsupported method: $($endpoint.method)"
        }
        foreach ($linkedPath in @($endpoint.requestExample, $endpoint.responseExample, $endpoint.implementationAnchor) + @($endpoint.sourceContracts)) {
            if (-not (Test-RelativePath -Root $repoRoot -RelativePath ([string]$linkedPath))) {
                Add-Issue -Issues $issues -Path $endpointPath -Message "Linked path does not exist: $linkedPath"
            }
        }

        foreach ($examplePath in @($endpoint.requestExample, $endpoint.responseExample)) {
            $example = Read-Json -Path (Join-Path $repoRoot (([string]$examplePath) -replace "/", "\"))
            Require-Properties -Issues $issues -Path ([string]$examplePath) -Object $example -Names @("schemaVersion")
        }
    }
}

if ($issues.Count -gt 0) {
    Write-Host "Backend API contract validation failed:" -ForegroundColor Red
    foreach ($issue in $issues) {
        Write-Host ("- {0}: {1}" -f $issue.path, $issue.message) -ForegroundColor Red
    }
    exit 1
}

Write-Host "Backend API contract validation passed." -ForegroundColor Green
