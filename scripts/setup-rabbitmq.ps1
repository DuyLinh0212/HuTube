[CmdletBinding()]
param([string]$Distribution = 'Ubuntu')
. (Join-Path $PSScriptRoot 'common.ps1')
$windowsRoot = $script:RepositoryRoot.Replace('\', '/')
$wslPath = & wsl.exe -d $Distribution --exec wslpath -a $windowsRoot
if ($LASTEXITCODE -ne 0) { throw 'An Ubuntu WSL distribution is required for native local RabbitMQ setup.' }
$wslRoot = ($wslPath | Select-Object -Last 1).Trim()
Invoke-CheckedCommand wsl.exe @('-d', $Distribution, '-u', 'root', '--', 'bash',
    "$wslRoot/scripts/deploy/install-local-rabbitmq-wsl.sh", "$wslRoot/.env.messaging.local")
$envPath = Join-Path $script:RepositoryRoot '.env.messaging.local'
$owner = [System.Security.Principal.WindowsIdentity]::GetCurrent().User
$acl = New-Object System.Security.AccessControl.FileSecurity
$acl.SetOwner($owner)
$acl.SetAccessRuleProtection($true, $false)
$acl.AddAccessRule((New-Object System.Security.AccessControl.FileSystemAccessRule($owner, 'FullControl', 'Allow')))
Set-Acl -LiteralPath $envPath -AclObject $acl
Write-Host 'RabbitMQ ready: AMQP 127.0.0.1:5672; management http://127.0.0.1:15672. Credentials: .env.messaging.local'
