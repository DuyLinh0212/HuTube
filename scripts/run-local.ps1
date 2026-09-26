[CmdletBinding()]
param(
    [Parameter(Mandatory)][ValidateSet('api', 'recommender', 'user', 'admin', 'mobile')][string]$Component,
    [string]$Device,
    [string]$EnvironmentFile
)
. (Join-Path $PSScriptRoot 'common.ps1')
if (-not $EnvironmentFile) {
    $EnvironmentFile = Join-Path $script:RepositoryRoot '.env.local'
}
Import-LocalEnvironment -Path $EnvironmentFile
Push-Location $script:RepositoryRoot
try {
    switch ($Component) {
        'api' {
            Assert-EnvironmentValue 'ConnectionStrings__Database'
            Assert-EnvironmentValue 'Jwt__SigningKey'
            $existing = Get-NetTCPConnection -LocalPort 5080 -State Listen -ErrorAction SilentlyContinue
            if ($existing) {
                $pids = $existing | Select-Object -ExpandProperty OwningProcess -Unique
                Write-Host "[!] Cong 5080 dang duoc su dung boi PID: $($pids -join ', '). Dang giai phong cong..." -ForegroundColor Yellow
                $pids | ForEach-Object { Stop-Process -Id $_ -Force -ErrorAction SilentlyContinue }
                Start-Sleep -Seconds 1
            }
            Invoke-CheckedCommand dotnet @('run', '--project', 'backend/src/HuTube.Api', '--no-launch-profile')
        }
        'recommender' {
            & (Join-Path $PSScriptRoot 'run-recommender.ps1')
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
                $googleWebClientId = $env:Google__ClientId
                if (-not [string]::IsNullOrWhiteSpace($googleWebClientId) -and -not $googleWebClientId.Contains('REPLACE_WITH')) {
                    $arguments += "--dart-define=GOOGLE_WEB_CLIENT_ID=$googleWebClientId"
                }
                if ($Device) { $arguments += @('-d', $Device) }
                Invoke-CheckedCommand flutter $arguments
            } finally { Pop-Location }
        }
    }
} finally { Pop-Location }
