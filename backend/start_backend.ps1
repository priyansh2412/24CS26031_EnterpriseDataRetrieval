# Enterprise Data Retrieval - Backend Startup PowerShell Script
Write-Host "===================================================" -ForegroundColor Cyan
Write-Host "  Enterprise Data Retrieval - Backend Startup" -ForegroundColor Cyan
Write-Host "===================================================" -ForegroundColor Cyan

Set-Location $PSScriptRoot

if (-not (Test-Path "venv")) {
    Write-Host "[INFO] Creating Python virtual environment..." -ForegroundColor Yellow
    python -m venv venv
}

Write-Host "[INFO] Activating virtual environment..." -ForegroundColor Green
& ".\venv\Scripts\Activate.ps1"

Write-Host "[INFO] Installing / verifying dependencies..." -ForegroundColor Yellow
pip install -r requirements.txt

if (-not (Test-Path ".env") -and (Test-Path "..\.env.example")) {
    Write-Host "[INFO] Copying .env.example to .env..." -ForegroundColor Yellow
    Copy-Item "..\.env.example" ".env"
}

Write-Host "[INFO] Starting FastAPI Uvicorn server on http://127.0.0.1:8000 ..." -ForegroundColor Green
uvicorn app.main:app --reload --host 127.0.0.1 --port 8000
