<#
.SYNOPSIS
    Runs `dab validate` on a DAB config against the host-exposed database port.

.DESCRIPTION
    The committed config connects by container name (for example local-mssql),
    which only resolves on the pilot-net Docker network. This script copies the
    config to a temporary file, points the connection string at localhost, sets
    DATABASE_PASSWORD for this process only (read from the secrets file, never
    printed), and runs `dab validate`. The temporary file is always removed.
#>
param(
    [Parameter(Mandatory)] [string] $ConfigPath,
    [Parameter(Mandatory)] [string] $SecretsFile,
    [Parameter(Mandatory)] [string] $PasswordKey,
    [Parameter(Mandatory)] [string] $ContainerHost
)

$ErrorActionPreference = 'Stop'

# Read KEY=value or KEY='value' lines; ignore comments and blanks.
$secrets = @{}
foreach ($line in Get-Content -LiteralPath $SecretsFile) {
    if ($line -match '^\s*#' -or $line -notmatch '=') { continue }
    $key, $value = $line.Split('=', 2)
    $value = $value.Trim()
    if ($value.Length -ge 2 -and $value[0] -eq "'" -and $value[-1] -eq "'") { $value = $value.Substring(1, $value.Length - 2) }
    $secrets[$key.Trim()] = $value
}

if (-not $secrets[$PasswordKey]) {
    Write-Host "$PasswordKey is missing or empty in $SecretsFile."
    exit 1
}

$tempConfig = Join-Path ([IO.Path]::GetTempPath()) ("dab-validate-{0}.json" -f [guid]::NewGuid())
try {
    (Get-Content -LiteralPath $ConfigPath -Raw).Replace($ContainerHost, 'localhost') |
        Set-Content -LiteralPath $tempConfig -Encoding UTF8

    $env:DATABASE_PASSWORD = $secrets[$PasswordKey]
    # The generated config reads OpenTelemetry settings from the environment.
    $env:OTEL_EXPORTER_OTLP_ENDPOINT = 'http://localhost:4317'
    $env:OTEL_EXPORTER_OTLP_HEADERS = ''
    $env:OTEL_SERVICE_NAME = 'dab-validate'

    Write-Host "Validating $ConfigPath ..."
    & dab validate -c $tempConfig
    exit $LASTEXITCODE
}
finally {
    Remove-Item -LiteralPath $tempConfig -ErrorAction SilentlyContinue
    Remove-Item Env:DATABASE_PASSWORD -ErrorAction SilentlyContinue
}
