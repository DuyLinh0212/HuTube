[CmdletBinding()]
param([string]$EnvironmentFile = (Join-Path (Split-Path -Parent $PSScriptRoot) '.env.local'))
. (Join-Path $PSScriptRoot 'common.ps1')
Import-LocalEnvironment -Path $EnvironmentFile
Assert-EnvironmentValue 'ConnectionStrings__Database'
Assert-EnvironmentValue 'Jwt__SigningKey'
if ($env:Jwt__SigningKey.Length -lt 64) { throw 'Jwt__SigningKey must contain at least 64 characters.' }
if ($env:ASPNETCORE_ENVIRONMENT -ne 'Development') { throw 'setup-local.ps1 requires ASPNETCORE_ENVIRONMENT=Development.' }
Push-Location $script:RepositoryRoot
try {
    Invoke-CheckedCommand dotnet @('restore', 'backend/HuTube.sln')
    Invoke-CheckedCommand dotnet @('run', '--project', 'backend/src/HuTube.Api', '--no-launch-profile', '--', '--migrate')
    foreach ($client in @('frontend/user-web', 'frontend/admin-web')) {
        Push-Location $client
        try { Invoke-CheckedCommand npm @('ci') } finally { Pop-Location }
    }
    Push-Location 'mobile/user-app'
    try { Invoke-CheckedCommand flutter @('pub', 'get') } finally { Pop-Location }
    Write-Host 'Dependencies restored and local migrations applied. Start each client with scripts/run-local.ps1.'
} finally { Pop-Location }
