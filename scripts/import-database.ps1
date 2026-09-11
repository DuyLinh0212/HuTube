[CmdletBinding()]
param(
    [string]$BackupFile,
    [string]$Server,
    [int]$Port = 0,
    [string]$Database,
    [string]$Username,
    [switch]$ReplaceExisting,
    [switch]$SkipTargetBackup
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot 'common.ps1')

function Select-DatabaseBackup {
    param([string]$CurrentPath)

    if (-not [string]::IsNullOrWhiteSpace($CurrentPath)) { return $CurrentPath }

    try {
        Add-Type -AssemblyName System.Windows.Forms -ErrorAction Stop
        $dialog = New-Object System.Windows.Forms.OpenFileDialog
        $dialog.Title = 'Select HuTube PostgreSQL backup'
        $dialog.Filter = 'PostgreSQL backup (*.dump;*.backup;*.sql)|*.dump;*.backup;*.sql|All files (*.*)|*.*'
        $dialog.Multiselect = $false
        try {
            if ($dialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) { return $dialog.FileName }
        }
        finally { $dialog.Dispose() }
    }
    catch {
        Write-Verbose 'Could not open the file picker; falling back to a console path prompt.'
    }

    return (Read-Host 'Enter the PostgreSQL backup file path')
}

function Get-AvailableBackupPath {
    param([Parameter(Mandatory)][string]$RepositoryRoot)

    $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $base = Join-Path $RepositoryRoot "hutube-before-import-$stamp"
    $candidate = "$base.dump"
    $index = 1
    while ([System.IO.File]::Exists($candidate)) {
        $candidate = "$base-$index.dump"
        $index++
        if ($index -gt 1000) { throw 'Could not find an unused target backup filename.' }
    }
    return $candidate
}

function New-PostgresSettings {
    param(
        [Parameter(Mandatory)][string]$HostName,
        [Parameter(Mandatory)][int]$PortNumber,
        [Parameter(Mandatory)][string]$DatabaseName,
        [Parameter(Mandatory)][System.Management.Automation.PSCredential]$Credential
    )

    [pscustomobject]@{
        Host     = $HostName
        Port     = $PortNumber
        Database = $DatabaseName
        Username = $Credential.UserName
        Password = $Credential.GetNetworkCredential().Password
        SslMode  = $null
    }
}

try {
    if (-not $ReplaceExisting) {
        throw 'Import is destructive. Re-run with -ReplaceExisting after reviewing the command.'
    }

    $backupPath = Select-DatabaseBackup -CurrentPath $BackupFile
    if ([string]::IsNullOrWhiteSpace($backupPath)) { throw 'No backup file was selected.' }
    $backupPath = (Resolve-Path -LiteralPath $backupPath -ErrorAction Stop).Path
    $backupInfo = Get-Item -LiteralPath $backupPath
    if (-not $backupInfo.PSIsContainer -and $backupInfo.Length -gt 0) { }
    else { throw "Backup file is empty or is not a file: $backupPath" }

    if ([string]::IsNullOrWhiteSpace($Server)) { $Server = 'localhost' }
    if ($Port -eq 0) { $Port = 5432 }
    if ([string]::IsNullOrWhiteSpace($Database)) { $Database = 'hutube_local' }
    if ([string]::IsNullOrWhiteSpace($Username)) { $Username = 'postgres' }
    if ($Database -notmatch '^[A-Za-z_][A-Za-z0-9_]*$') {
        throw 'Database name must contain only letters, numbers, and underscores, and must not start with a number.'
    }
    if ($Database.ToLowerInvariant() -in @('postgres', 'template0', 'template1')) {
        throw "Refusing to replace protected PostgreSQL database '$Database'."
    }
    if ($Port -lt 1 -or $Port -gt 65535) { throw 'PostgreSQL port must be between 1 and 65535.' }

    $credential = Get-Credential -UserName $Username -Message "Enter the PostgreSQL password for $Server`:$Port (the password is not put on the command line)."
    if ($null -eq $credential) { throw 'PostgreSQL credentials were not provided.' }
    if ([string]::IsNullOrWhiteSpace($credential.UserName)) { throw 'PostgreSQL username is missing.' }

    $targetSettings = New-PostgresSettings -HostName $Server -PortNumber $Port -DatabaseName $Database -Credential $credential
    $maintenanceSettings = New-PostgresSettings -HostName $Server -PortNumber $Port -DatabaseName 'postgres' -Credential $credential
    Assert-PostgresConnectionSettings -Settings $targetSettings -RequirePassword
    Assert-PostgresConnectionSettings -Settings $maintenanceSettings -RequirePassword

    $repositoryRoot = (Resolve-Path -LiteralPath (Split-Path -Parent $PSScriptRoot)).Path
    $backupTargetPath = $null

    Write-Warning "This will DROP database '$Database' on $Server`:$Port and restore '$backupPath'."
    Write-Warning 'Any data currently in that database will be replaced.'
    $confirmation = Read-Host "Type REPLACE to continue"
    if ($confirmation -cne 'REPLACE') {
        Write-Host 'Import cancelled. No database changes were made.'
        exit 0
    }

    $databaseIdentifier = '"' + $Database.Replace('"', '""') + '"'
    $sqlQuote = [char]39
    $databaseExistsCommand = 'SELECT 1 FROM pg_database WHERE datname = ' + $sqlQuote + $Database + $sqlQuote + ';'
    $databaseExistsArguments = @(
        '--no-password',
        '--tuples-only',
        '--no-align',
        "--host=$($maintenanceSettings.Host)",
        "--port=$($maintenanceSettings.Port)",
        "--username=$($maintenanceSettings.Username)",
        "--dbname=$($maintenanceSettings.Database)",
        "--command=$databaseExistsCommand"
    )
    $databaseExistsOutput = @(Invoke-PostgresTool -Executable (Resolve-PostgresExecutable -Name 'psql') -Arguments $databaseExistsArguments -Settings $maintenanceSettings -CaptureOutput)
    $databaseExistsText = $databaseExistsOutput -join ' '
    $databaseExists = ($databaseExistsText.Trim() -match '(?m)^1$')

    if (-not $SkipTargetBackup -and $databaseExists) {
        $backupTargetPath = Get-AvailableBackupPath -RepositoryRoot $repositoryRoot
        $pgDump = Resolve-PostgresExecutable -Name 'pg_dump'
        $targetBackupArguments = @(
            '--format=custom',
            '--no-owner',
            '--no-acl',
            '--blobs',
            "--file=$backupTargetPath",
            "--host=$($targetSettings.Host)",
            "--port=$($targetSettings.Port)",
            "--username=$($targetSettings.Username)",
            "--dbname=$($targetSettings.Database)"
        )
        Write-Host "Creating a safety backup of '$Database' before replacement..."
        Invoke-PostgresTool -Executable $pgDump -Arguments $targetBackupArguments -Settings $targetSettings
        Write-Host "Safety backup: $backupTargetPath"
    }
    elseif (-not $SkipTargetBackup) {
        Write-Host "Target database '$Database' does not exist yet; no pre-import backup is needed."
    }
    else {
        Write-Warning 'Pre-import target backup was skipped because -SkipTargetBackup was supplied.'
    }

    $terminateCommand = 'SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE datname = ' + $sqlQuote + $Database + $sqlQuote + ' AND pid <> pg_backend_pid();'
    $terminateArguments = @(
        '--no-password',
        "--host=$($maintenanceSettings.Host)",
        "--port=$($maintenanceSettings.Port)",
        "--username=$($maintenanceSettings.Username)",
        "--dbname=$($maintenanceSettings.Database)",
        "--command=$terminateCommand"
    )
    Invoke-PostgresTool -Executable (Resolve-PostgresExecutable -Name 'psql') -Arguments $terminateArguments -Settings $maintenanceSettings | Out-Null

    $dropArguments = @(
        '--no-password',
        "--host=$($maintenanceSettings.Host)",
        "--port=$($maintenanceSettings.Port)",
        "--username=$($maintenanceSettings.Username)",
        "--dbname=$($maintenanceSettings.Database)",
        "--command=DROP DATABASE IF EXISTS $databaseIdentifier;"
    )
    Invoke-PostgresTool -Executable (Resolve-PostgresExecutable -Name 'psql') -Arguments $dropArguments -Settings $maintenanceSettings | Out-Null

    $createArguments = @(
        '--no-password',
        "--host=$($maintenanceSettings.Host)",
        "--port=$($maintenanceSettings.Port)",
        "--username=$($maintenanceSettings.Username)",
        "--dbname=$($maintenanceSettings.Database)",
        "--command=CREATE DATABASE $databaseIdentifier;"
    )
    Invoke-PostgresTool -Executable (Resolve-PostgresExecutable -Name 'psql') -Arguments $createArguments -Settings $maintenanceSettings | Out-Null

    if ([System.IO.Path]::GetExtension($backupPath).ToLowerInvariant() -eq '.sql') {
        $restoreArguments = @(
            '--no-password',
            '--set=ON_ERROR_STOP=1',
            "--host=$($targetSettings.Host)",
            "--port=$($targetSettings.Port)",
            "--username=$($targetSettings.Username)",
            "--dbname=$($targetSettings.Database)",
            "--file=$backupPath"
        )
        Invoke-PostgresTool -Executable (Resolve-PostgresExecutable -Name 'psql') -Arguments $restoreArguments -Settings $targetSettings
    }
    else {
        $restoreArguments = @(
            '--no-password',
            '--exit-on-error',
            '--no-owner',
            '--no-acl',
            "--host=$($targetSettings.Host)",
            "--port=$($targetSettings.Port)",
            "--username=$($targetSettings.Username)",
            "--dbname=$($targetSettings.Database)",
            $backupPath
        )
        Invoke-PostgresTool -Executable (Resolve-PostgresExecutable -Name 'pg_restore') -Arguments $restoreArguments -Settings $targetSettings
    }

    Write-Host "Database import completed into '$Database'."
    Write-Host 'In DBeaver, refresh the connection or reconnect to see the restored schema and data.'
    if ($null -ne $backupTargetPath) { Write-Host "If needed, the previous database is recoverable from: $backupTargetPath" }
    Write-Warning 'The database backup contains records and media URLs, not the actual R2/Cloudinary video or image files.'
}
catch {
    Write-Error $_
    exit 1
}
