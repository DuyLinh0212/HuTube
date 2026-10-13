[CmdletBinding()]
param()
. (Join-Path $PSScriptRoot 'common.ps1')
$names = @('Recommendation__ServiceToken', 'Recommendation__AdminToken', 'RECOMMENDER_SERVICE_TOKEN', 'RECOMMENDER_ADMIN_TOKEN')
$original = @{}
foreach ($name in $names) { $original[$name] = [Environment]::GetEnvironmentVariable($name, 'Process') }
try {
    $env:Recommendation__ServiceToken = 'test-inference'
    $env:Recommendation__AdminToken = 'test-admin'
    $env:RECOMMENDER_SERVICE_TOKEN = 'stale-inference'
    $env:RECOMMENDER_ADMIN_TOKEN = 'stale-admin'
    Sync-RecommenderEnvironment
    if ($env:RECOMMENDER_SERVICE_TOKEN -cne 'test-inference' -or $env:RECOMMENDER_ADMIN_TOKEN -cne 'test-admin') {
        throw 'Shared API credentials did not override stale Python credentials.'
    }
    $env:Recommendation__ServiceToken = ''
    $env:Recommendation__AdminToken = ''
    Sync-RecommenderEnvironment
    if ($env:RECOMMENDER_ADMIN_TOKEN -cne 'test-admin') { throw 'Standalone Python credential was overwritten.' }
    $env:Recommendation__AdminToken = 'REPLACE_WITH_ADMIN_TOKEN'
    $rejected = $false
    try { Sync-RecommenderEnvironment } catch { $rejected = $true }
    if (-not $rejected) { throw 'Placeholder admin credential was accepted.' }
    Write-Host 'PASS: shared credentials, standalone fallback, and placeholder rejection.'
} finally {
    foreach ($name in $names) { [Environment]::SetEnvironmentVariable($name, $original[$name], 'Process') }
}
