[CmdletBinding()]
param([string]$BaseUrl = 'http://localhost:5080', [string]$ExpectedCommit)
$ErrorActionPreference = 'Stop'
$BaseUrl = $BaseUrl.TrimEnd('/')
$health = Invoke-WebRequest -Uri "$BaseUrl/health" -TimeoutSec 15
if ($health.StatusCode -ne 200) { throw 'API health check failed.' }
$info = Invoke-RestMethod -Uri "$BaseUrl/api/v1/system/info" -TimeoutSec 15
if ($ExpectedCommit -and $info.commitSha -ne $ExpectedCommit) { throw 'The API is not running the expected commit.' }
Write-Host "Health and public diagnostic endpoint passed at $BaseUrl."
