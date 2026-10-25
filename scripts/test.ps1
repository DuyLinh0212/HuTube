[CmdletBinding()]
param([string]$EnvironmentFile = (Join-Path (Split-Path -Parent $PSScriptRoot) '.env.local'))
. (Join-Path $PSScriptRoot 'common.ps1')
Import-LocalEnvironment -Path $EnvironmentFile
if (Test-Path (Join-Path $script:RepositoryRoot '.env.messaging.local')) {
    & (Join-Path $PSScriptRoot 'setup-rabbitmq.ps1')
    Import-LocalEnvironment -Path (Join-Path $script:RepositoryRoot '.env.messaging.local')
    $env:TEST_RABBITMQ_PASSWORD = $env:RabbitMq__Password
    $env:TEST_RABBITMQ_HOST = $env:RabbitMq__HostName
}
Assert-EnvironmentValue 'TEST_DATABASE_CONNECTION'
Assert-EnvironmentValue 'TEST_RABBITMQ_PASSWORD'
if (-not $env:CHROME_BIN) {
    $edgePath = 'C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe'
    $chromePath = 'C:\Program Files\Google\Chrome\Application\chrome.exe'
    if (Test-Path $chromePath) {
        $env:CHROME_BIN = $chromePath
    } elseif (Test-Path $edgePath) {
        $env:CHROME_BIN = $edgePath
    }
}
Push-Location $script:RepositoryRoot
try {
    Invoke-CheckedCommand dotnet @('restore', 'backend/HuTube.sln')
    Invoke-CheckedCommand dotnet @('build', 'backend/HuTube.sln', '--no-restore', '-c', 'Release')
    Invoke-CheckedCommand dotnet @('test', 'backend/tests/HuTube.UnitTests', '--no-build', '-c', 'Release', '--logger', 'trx')
    Invoke-CheckedCommand dotnet @('test', 'backend/tests/HuTube.IntegrationTests', '--no-build', '-c', 'Release', '--logger', 'trx')
    foreach ($client in @('frontend/user-web', 'frontend/admin-web')) {
        Push-Location $client
        try {
            Invoke-CheckedCommand npm @('ci')
            Invoke-CheckedCommand npm @('test', '--', '--watch=false', '--browsers=ChromeHeadless')
            Invoke-CheckedCommand npm @('run', 'build')
        } finally { Pop-Location }
    }
    Push-Location 'mobile/user-app'
    try {
        Invoke-CheckedCommand flutter @('pub', 'get')
        Invoke-CheckedCommand flutter @('analyze', '--fatal-infos')
        Invoke-CheckedCommand flutter @('test')
    } finally { Pop-Location }
    Write-Host 'All automated backend, web and mobile checks passed.'
} finally { Pop-Location }
