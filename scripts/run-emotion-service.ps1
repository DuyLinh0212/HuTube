[CmdletBinding()]
param(
    [int]$Port = 8001,
    [string]$HostAddress = "127.0.0.1"
)

$rootDir = Split-Path -Parent $PSScriptRoot
$serviceDir = Join-Path $rootDir "emotion-service"
if (-not (Test-Path -LiteralPath $serviceDir)) {
    $parentDir = Split-Path -Parent $rootDir
    $serviceDir = Join-Path $parentDir "emotion-service"
}

if (-not (Test-Path -LiteralPath $serviceDir)) {
    throw "Khong tim thay thu muc emotion-service tai: $serviceDir"
}

Push-Location $serviceDir
try {
    Write-Host "=================================================" -ForegroundColor Cyan
    Write-Host "  Khoi dong HuTube Emotion & Sentiment Service" -ForegroundColor Green
    Write-Host "  URL: http://${HostAddress}:$Port" -ForegroundColor Yellow
    Write-Host "  Health: http://${HostAddress}:$Port/health" -ForegroundColor Yellow
    Write-Host "  Docs: http://${HostAddress}:$Port/docs" -ForegroundColor Yellow
    Write-Host "=================================================" -ForegroundColor Cyan

    $existing = Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction SilentlyContinue
    if ($existing) {
        $pids = $existing | Select-Object -ExpandProperty OwningProcess -Unique
        Write-Host "[!] Cong $Port dang duoc su dung boi PID: $($pids -join ', '). Dang giai phong cong..." -ForegroundColor Yellow
        $pids | ForEach-Object { Stop-Process -Id $_ -Force -ErrorAction SilentlyContinue }
        Start-Sleep -Seconds 1
    }

    # Uu tien venv neu co, nguoc lai dung python he thong
    $pythonExe = "python"
    $venvPython = Join-Path $serviceDir ".venv\Scripts\python.exe"
    if (Test-Path -LiteralPath $venvPython) {
        $pythonExe = $venvPython
    }

    Write-Host "Bat dau FastAPI Uvicorn Server tai cong $Port..." -ForegroundColor Green
    & $pythonExe -m uvicorn api.main:app --host $HostAddress --port $Port
} finally {
    Pop-Location
}
