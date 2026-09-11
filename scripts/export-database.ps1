[CmdletBinding()]
param(
    [string]$EnvironmentFile = (Join-Path (Split-Path -Parent $PSScriptRoot) '.env.local'),
    [string]$OutputFile
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot 'common.ps1')

try {
    Import-LocalEnvironment -Path $EnvironmentFile
    Assert-EnvironmentValue -Name 'ConnectionStrings__Database'

    $settings = ConvertTo-PostgresConnectionSettings -ConnectionString $env:ConnectionStrings__Database
    Assert-PostgresConnectionSettings -Settings $settings -RequirePassword

    $repositoryRoot = (Resolve-Path -LiteralPath (Split-Path -Parent $PSScriptRoot)).Path
    if ([string]::IsNullOrWhiteSpace($OutputFile)) {
        $fileName = 'hutube-backup-{0}.dump' -f (Get-Date -Format 'yyyyMMdd-HHmmss')
        $outputPath = Join-Path $repositoryRoot $fileName
    }
    else {
        if ([System.IO.Path]::IsPathRooted($OutputFile)) { $outputPath = [System.IO.Path]::GetFullPath($OutputFile) }
        else { $outputPath = [System.IO.Path]::GetFullPath((Join-Path $repositoryRoot $OutputFile)) }
    }

    $rootPrefix = $repositoryRoot.TrimEnd('\') + '\'
    $normalizedOutput = $outputPath.TrimEnd('\')
    if (-not $normalizedOutput.StartsWith($rootPrefix, [System.StringComparison]::OrdinalIgnoreCase) -and
        -not [string]::Equals($normalizedOutput, $repositoryRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Backup output must be inside the HuTube repository root: $repositoryRoot"
    }
    if ([System.IO.Directory]::Exists($outputPath)) { throw "Backup output is a directory: $outputPath" }
    if ([System.IO.File]::Exists($outputPath)) { throw "Backup file already exists. Choose another path: $outputPath" }

    $parentDirectory = Split-Path -Parent $outputPath
    if (-not [System.IO.Directory]::Exists($parentDirectory)) {
        [System.IO.Directory]::CreateDirectory($parentDirectory) | Out-Null
    }

    $pgDump = Resolve-PostgresExecutable -Name 'pg_dump'
    $arguments = @(
        '--format=custom',
        '--no-owner',
        '--no-acl',
        '--blobs',
        "--file=$outputPath",
        "--host=$($settings.Host)",
        "--port=$($settings.Port)",
        "--username=$($settings.Username)",
        "--dbname=$($settings.Database)"
    )

    Write-Host "Exporting PostgreSQL database '$($settings.Database)' from $($settings.Host):$($settings.Port)..."
    Invoke-PostgresTool -Executable $pgDump -Arguments $arguments -Settings $settings

    $fileInfo = Get-Item -LiteralPath $outputPath
    Write-Host "Database export completed: $($fileInfo.FullName)"
    Write-Host ('File size: {0:N2} MB' -f ($fileInfo.Length / 1MB))
    Write-Warning 'This export contains PostgreSQL records and media URLs, not the actual R2/Cloudinary video or image files.'
}
catch {
    Write-Error $_
    exit 1
}
