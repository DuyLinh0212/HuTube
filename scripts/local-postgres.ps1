[CmdletBinding()]
param(
    [Parameter(Mandatory)][ValidateSet('Start', 'Stop', 'Status')][string]$Action,
    [ValidateRange(1024, 65535)][int]$Port = 55432,
    [string]$PostgresBin
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$repositoryPath = [IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot))
$localPath = [IO.Path]::GetFullPath((Join-Path $repositoryPath '.local'))
$clusterPath = [IO.Path]::GetFullPath((Join-Path $localPath 'postgres'))
$repositoryPrefix = $repositoryPath.TrimEnd([IO.Path]::DirectorySeparatorChar) + [IO.Path]::DirectorySeparatorChar
if (-not $clusterPath.StartsWith($repositoryPrefix, [StringComparison]::OrdinalIgnoreCase)) {
    throw 'The PostgreSQL data directory must remain inside this repository.'
}
foreach ($path in @($localPath, $clusterPath)) {
    if (-not (Test-Path -LiteralPath $path -PathType Container)) {
        throw 'The managed PostgreSQL cluster is not present at .local/postgres. This command never initializes or replaces data.'
    }
    if ((Get-Item -LiteralPath $path -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) {
        throw 'The managed PostgreSQL directory must not be a symbolic link or junction.'
    }
}
$versionPath = Join-Path $clusterPath 'PG_VERSION'
if (-not (Test-Path -LiteralPath $versionPath -PathType Leaf) -or
    (Get-Content -LiteralPath $versionPath -Raw).Trim() -ne '18') {
    throw 'Expected an existing PostgreSQL 18 cluster at .local/postgres.'
}

if ($PostgresBin) {
    $binaryPath = [IO.Path]::GetFullPath($PostgresBin)
} else {
    $pgCommand = Get-Command pg_ctl.exe -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    $binaryPath = if ($pgCommand) { Split-Path -Parent $pgCommand.Source } else { 'D:\PostgreSQL\18\bin' }
}
$controlExecutable = Join-Path $binaryPath 'pg_ctl.exe'
$postgresExecutable = Join-Path $binaryPath 'postgres.exe'
if (-not (Test-Path -LiteralPath $controlExecutable -PathType Leaf) -or
    -not (Test-Path -LiteralPath $postgresExecutable -PathType Leaf)) {
    throw 'PostgreSQL binaries were not found. Set -PostgresBin to the PostgreSQL 18 bin directory.'
}
$binaryVersion = & $postgresExecutable --version
if ($LASTEXITCODE -ne 0 -or $binaryVersion -notmatch '\b18(?:\.|\b)') {
    throw 'Use PostgreSQL 18 binaries for this existing cluster.'
}

& $controlExecutable -D $clusterPath status *> $null
$statusCode = $LASTEXITCODE
if ($statusCode -notin @(0, 3)) { throw "Unable to inspect the managed PostgreSQL cluster (pg_ctl exit $statusCode)." }
$isRunning = $statusCode -eq 0

switch ($Action) {
    'Status' {
        if ($isRunning) {
            # postmaster.pid contains operational metadata only; never read connection secrets.
            $pidMetadata = Get-Content -LiteralPath (Join-Path $clusterPath 'postmaster.pid') -TotalCount 4
            $activePort = if ($pidMetadata.Count -ge 4) { $pidMetadata[3] } else { 'unknown' }
            Write-Output "Managed PostgreSQL is running (port $activePort)."
        } else { Write-Output 'Managed PostgreSQL is stopped.' }
    }
    'Start' {
        if ($isRunning) {
            Write-Output 'Managed PostgreSQL is already running. Use Status to inspect its current port.'
            break
        }
        $logPath = Join-Path $localPath 'postgres.log'
        & $controlExecutable -D $clusterPath -l $logPath -o "-h 127.0.0.1 -p $Port" -w -t 30 start
        if ($LASTEXITCODE -ne 0) { throw 'PostgreSQL did not start. Inspect .local/postgres.log and check whether the requested port is occupied.' }
        Write-Output "Managed PostgreSQL started at 127.0.0.1:$Port."
    }
    'Stop' {
        if (-not $isRunning) {
            Write-Output 'Managed PostgreSQL is already stopped.'
            break
        }
        # Fast shutdown disconnects clients and rolls back unfinished transactions cleanly.
        & $controlExecutable -D $clusterPath -m fast -w -t 30 stop
        if ($LASTEXITCODE -ne 0) { throw 'PostgreSQL did not stop cleanly. Inspect .local/postgres.log.' }
        Write-Output 'Managed PostgreSQL stopped. Database files are retained.'
    }
}
