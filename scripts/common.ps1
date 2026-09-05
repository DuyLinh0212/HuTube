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
