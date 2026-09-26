[CmdletBinding()]
param(
    [int]$Port = 8000,
    [string]$HostAddress = "0.0.0.0"
)

$serviceDir = Join-Path (Split-Path -Parent $PSScriptRoot) "recommendation-service"
Push-Location $serviceDir
try {
    Write-Host "=================================================" -ForegroundColor Cyan
    Write-Host "  Khởi động HuTube Collaborative Filtering Service" -ForegroundColor Green
    Write-Host "  URL: http://localhost:$Port" -ForegroundColor Yellow
    Write-Host "  Health: http://localhost:$Port/health" -ForegroundColor Yellow
    Write-Host "=================================================" -ForegroundColor Cyan

    $artifactDir = Join-Path $serviceDir "data\artifacts"
    $benchmarkPointer = Join-Path $artifactDir "benchmark-latest.json"
    if (-not (Test-Path $benchmarkPointer)) {
        Write-Host "[!] Chua co Model Artifact. Dang tu dong huan luyen khoi tao..." -ForegroundColor Yellow
        python -m training.train_hutube
    }

    $existing = Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction SilentlyContinue
    if ($existing) {
        $pids = $existing | Select-Object -ExpandProperty OwningProcess -Unique
        Write-Host "[!] Cong $Port dang duoc su dung boi PID: $($pids -join ', '). Dang giai phong cong..." -ForegroundColor Yellow
        $pids | ForEach-Object { Stop-Process -Id $_ -Force -ErrorAction SilentlyContinue }
        Start-Sleep -Seconds 1
    }

    Write-Host "Bat dau FastAPI Uvicorn Server tai cong $Port..." -ForegroundColor Green
    python -m uvicorn app.main:app --host $HostAddress --port $Port
} finally {
    Pop-Location
}
