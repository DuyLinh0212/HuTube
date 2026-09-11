Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$script:RepositoryRoot = Split-Path -Parent $PSScriptRoot

function Import-LocalEnvironment {
    param([string]$Path = (Join-Path $script:RepositoryRoot '.env.local'))
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "Missing $Path. Copy .env.example and configure local credentials first."
    }
    $lineNumber = 0
    foreach ($line in Get-Content -LiteralPath $Path) {
        $lineNumber++
        if ([string]::IsNullOrWhiteSpace($line) -or $line.TrimStart().StartsWith('#')) { continue }
        if ($line -notmatch '^\s*([A-Za-z_][A-Za-z0-9_]*)\s*=(.*)$') {
            throw "Invalid environment entry at line $lineNumber. Expected KEY=value."
        }
        $key = $Matches[1]
        $value = $Matches[2].Trim()
        if ($key -in @('HOME', 'CODEX_HOME', 'PATH', 'PSModulePath', 'COMSPEC', 'PATHEXT')) {
            throw "System environment key is not allowed at line $lineNumber."
        }
        if ($value.Length -ge 2 -and (($value.StartsWith('"') -and $value.EndsWith('"')) -or
            ($value.StartsWith("'") -and $value.EndsWith("'")))) {
            $value = $value.Substring(1, $value.Length - 2)
        }
        [Environment]::SetEnvironmentVariable($key, $value, 'Process')
    }
}

function Assert-EnvironmentValue {
    param([Parameter(Mandatory)][string]$Name)
    $value = [Environment]::GetEnvironmentVariable($Name, 'Process')
    if ([string]::IsNullOrWhiteSpace($value) -or $value.Contains('REPLACE_WITH')) {
        throw "Configure $Name in .env.local before continuing."
    }
}

function Invoke-CheckedCommand {
    param([Parameter(Mandatory)][string]$FilePath, [string[]]$Arguments = @())
    if (-not (Get-Command $FilePath -ErrorAction SilentlyContinue)) { throw "Required command not found: $FilePath" }
    & $FilePath @Arguments
    if ($LASTEXITCODE -ne 0) { throw "$FilePath failed with exit code $LASTEXITCODE." }
}

function ConvertTo-PostgresConnectionSettings {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$ConnectionString)

    $raw = $ConnectionString.Trim()
    if ([string]::IsNullOrWhiteSpace($raw)) { throw 'PostgreSQL connection string is empty.' }

    $pgHost = 'localhost'
    $pgPort = 5432
    $database = $null
    $userName = $null
    $password = $null
    $sslMode = $null

    if ($raw -match '^postgres(?:ql)?:\/\/') {
        try { $uri = New-Object System.Uri($raw) }
        catch { throw 'Invalid PostgreSQL URI in the connection string.' }

        if (-not [string]::IsNullOrWhiteSpace($uri.Host)) { $pgHost = $uri.Host }
        if ($uri.Port -gt 0) { $pgPort = $uri.Port }
        $database = [Uri]::UnescapeDataString($uri.AbsolutePath.TrimStart('/'))
        if (-not [string]::IsNullOrWhiteSpace($uri.UserInfo)) {
            $userInfo = $uri.UserInfo -split ':', 2
            $userName = [Uri]::UnescapeDataString($userInfo[0])
            if ($userInfo.Count -gt 1) { $password = [Uri]::UnescapeDataString($userInfo[1]) }
        }
        if (-not [string]::IsNullOrWhiteSpace($uri.Query)) {
            foreach ($queryPart in $uri.Query.TrimStart('?') -split '&') {
                if ($queryPart -notmatch '^([^=]+)=(.*)$') { continue }
                $queryKey = [Uri]::UnescapeDataString($Matches[1]).ToLowerInvariant()
                $queryValue = [Uri]::UnescapeDataString($Matches[2])
                if ($queryKey -eq 'sslmode') { $sslMode = $queryValue }
            }
        }
    }
    else {
        $pattern = '(?i)(?:^|;)\s*([^=;]+)\s*=\s*(?:"([^"]*)"|''([^'']*)''|([^;]*))'
        foreach ($match in [regex]::Matches($raw, $pattern)) {
            $key = $match.Groups[1].Value.Trim().ToLowerInvariant()
            if ($match.Groups[2].Success) { $value = $match.Groups[2].Value }
            elseif ($match.Groups[3].Success) { $value = $match.Groups[3].Value }
            else { $value = $match.Groups[4].Value.Trim() }

            switch -Regex ($key) {
                '^(host|server|address|addr)$' { $pgHost = $value; break }
                '^port$' { $pgPort = $value; break }
                '^(database|initial catalog)$' { $database = $value; break }
                '^(username|user id|user)$' { $userName = $value; break }
                '^(password|pwd)$' { $password = $value; break }
                '^(ssl mode|sslmode)$' { $sslMode = $value; break }
            }
        }
    }

    try { $pgPort = [int]$pgPort }
    catch { throw 'PostgreSQL port must be a number.' }

    [pscustomobject]@{
        Host     = $pgHost
        Port     = $pgPort
        Database = $database
        Username = $userName
        Password = $password
        SslMode  = $sslMode
    }
}

function Assert-PostgresConnectionSettings {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Settings,
        [switch]$RequirePassword
    )

    if ([string]::IsNullOrWhiteSpace([string]$Settings.Host)) { throw 'PostgreSQL host is missing.' }
    if ([int]$Settings.Port -lt 1 -or [int]$Settings.Port -gt 65535) { throw 'PostgreSQL port must be between 1 and 65535.' }
    if ([string]::IsNullOrWhiteSpace([string]$Settings.Database)) { throw 'PostgreSQL database name is missing.' }
    if ([string]::IsNullOrWhiteSpace([string]$Settings.Username)) { throw 'PostgreSQL username is missing.' }
    if ($RequirePassword -and [string]::IsNullOrWhiteSpace([string]$Settings.Password)) { throw 'PostgreSQL password is missing.' }
}

function Resolve-PostgresExecutable {
    [CmdletBinding()]
    param([Parameter(Mandatory)][ValidateSet('pg_dump', 'pg_restore', 'psql')][string]$Name)

    $command = Get-Command $Name -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($null -ne $command) { return $command.Source }

    $candidates = @(
        (Join-Path 'D:\PostgreSQL\18\bin' "$Name.exe"),
        (Join-Path 'C:\Program Files\PostgreSQL\18\bin' "$Name.exe"),
        (Join-Path 'C:\Program Files\PostgreSQL\17\bin' "$Name.exe")
    )
    foreach ($candidate in $candidates) {
        if (Test-Path -LiteralPath $candidate -PathType Leaf) { return $candidate }
    }
    throw "PostgreSQL client '$Name' was not found in PATH or the common PostgreSQL installation folders."
}

function Invoke-PostgresTool {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Executable,
        [Parameter(Mandatory)][string[]]$Arguments,
        [Parameter(Mandatory)]$Settings,
        [switch]$CaptureOutput
    )

    $oldPassword = [Environment]::GetEnvironmentVariable('PGPASSWORD', 'Process')
    $oldSslMode = [Environment]::GetEnvironmentVariable('PGSSLMODE', 'Process')
    try {
        [Environment]::SetEnvironmentVariable('PGPASSWORD', [string]$Settings.Password, 'Process')
        if (-not [string]::IsNullOrWhiteSpace([string]$Settings.SslMode)) {
            [Environment]::SetEnvironmentVariable('PGSSLMODE', [string]$Settings.SslMode, 'Process')
        }

        if ($CaptureOutput) {
            $output = & $Executable @Arguments 2>&1
            $exitCode = $LASTEXITCODE
            if ($exitCode -ne 0) { throw "PostgreSQL command failed with exit code $exitCode." }
            return @($output)
        }

        & $Executable @Arguments
        $exitCode = $LASTEXITCODE
        if ($exitCode -ne 0) { throw "PostgreSQL command failed with exit code $exitCode." }
    }
    finally {
        [Environment]::SetEnvironmentVariable('PGPASSWORD', $oldPassword, 'Process')
        [Environment]::SetEnvironmentVariable('PGSSLMODE', $oldSslMode, 'Process')
    }
}
