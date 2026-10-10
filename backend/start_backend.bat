@echo off
echo ===================================================
echo   Enterprise Data Retrieval - Backend Startup
echo ===================================================

cd /d "%~dp0"

IF NOT EXIST "venv" (
    echo [INFO] Creating Python virtual environment...
    python -m venv venv
)

echo [INFO] Activating virtual environment...
call venv\Scripts\activate.bat

echo [INFO] Installing / verifying dependencies...
pip install -r requirements.txt

IF NOT EXIST ".env" (
    IF EXIST "..\.env.example" (
        echo [INFO] Copying .env.example to .env...
        copy "..\.env.example" ".env"
    )
)

echo [INFO] Starting FastAPI Uvicorn server on http://127.0.0.1:8000 ...
uvicorn app.main:app --reload --host 127.0.0.1 --port 8000
pause
