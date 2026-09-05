[CmdletBinding()]
param(
    [Parameter(Mandatory)][ValidateSet('api', 'user', 'admin', 'mobile')][string]$Component,
    [string]$Device,
    [string]$EnvironmentFile = (Join-Path (Split-Path -Parent $PSScriptRoot) '.env.local')
)
. (Join-Path $PSScriptRoot 'common.ps1')
Import-LocalEnvironment -Path $EnvironmentFile
Push-Location $script:RepositoryRoot
try {
    switch ($Component) {
        'api' {
            Assert-EnvironmentValue 'ConnectionStrings__Database'
            Assert-EnvironmentValue 'Jwt__SigningKey'
            Invoke-CheckedCommand dotnet @('run', '--project', 'backend/src/HuTube.Api', '--no-launch-profile')
        }
        { $_ -in @('user', 'admin') } {
            Push-Location "frontend/$Component-web"
            try {
                $port = if ($Component -eq 'user') { '4200' } else { '4201' }
                Invoke-CheckedCommand npm @('start', '--', '--port', $port)
            } finally { Pop-Location }
        }
        'mobile' {
            Assert-EnvironmentValue 'MOBILE_API_BASE_URL'
            Push-Location 'mobile/user-app'
            try {
                $arguments = @('run', "--dart-define=API_BASE_URL=$env:MOBILE_API_BASE_URL")
                if ($Device) { $arguments += @('-d', $Device) }
                Invoke-CheckedCommand flutter $arguments
            } finally { Pop-Location }
        }
    }
} finally { Pop-Location }
