[CmdletBinding()]
param(
    [int]$Port = 8000,
    [string]$HostAddress = "127.0.0.1"
)

$serviceDir = Join-Path (Split-Path -Parent $PSScriptRoot) "recommendation-service"
Push-Location $serviceDir
try {
    Write-Host "=================================================" -ForegroundColor Cyan
    Write-Host "  Khởi động HuTube Collaborative Filtering Service" -ForegroundColor Green
    Write-Host "  URL: http://localhost:$Port" -ForegroundColor Yellow
    Write-Host "  Health: http://localhost:$Port/health" -ForegroundColor Yellow
    Write-Host "=================================================" -ForegroundColor Cyan

    $existing = Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction SilentlyContinue
    if ($existing) {
        $pids = $existing | Select-Object -ExpandProperty OwningProcess -Unique
        throw "Cong $Port dang duoc su dung boi PID: $($pids -join ', ')."
    }

    $venvPython = Join-Path $serviceDir ".venv\Scripts\python.exe"
    if (-not (Test-Path -LiteralPath $venvPython)) {
        throw "Chua co Python virtual environment. Chay: py -3 -m venv recommendation-service/.venv; recommendation-service/.venv/Scripts/python.exe -m pip install -e recommendation-service"
    }
    Write-Host "Bat dau FastAPI Uvicorn Server tai cong $Port..." -ForegroundColor Green
    & $venvPython -m uvicorn app.main:app --host $HostAddress --port $Port
} finally {
    Pop-Location
}
