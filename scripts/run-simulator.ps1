[CmdletBinding()]
param(
    [int]$Port = 5050,
    [string]$BackendUrl = "http://localhost:5080/api/v1"
)

$toolsDir = Join-Path (Split-Path -Parent $PSScriptRoot) "tools\bot-simulator"
Push-Location $toolsDir
try {
    Write-Host "Kiem tra dependencies Python..." -ForegroundColor Cyan
    python -m pip install -q -r requirements.txt
    Write-Host "Khoi dong HuTube Bot Simulator Web UI tai http://localhost:$Port ..." -ForegroundColor Green
    python run_simulator.py --port $Port --backend $BackendUrl
} finally {
    Pop-Location
}
