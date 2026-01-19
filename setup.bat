@echo off
echo Setting up Business Scraper API + Flutter/Web App
echo =================================================

REM Check if Python is installed
python --version >nul 2>&1
if errorlevel 1 (
    echo ❌ Python is required but not installed
    pause
    exit /b 1
)

REM Check if pip is installed
pip --version >nul 2>&1
if errorlevel 1 (
    echo ❌ pip is required but not installed
    pause
    exit /b 1
)

echo ✅ Python and pip are installed

REM Install backend dependencies
echo Installing backend dependencies...
cd backend
pip install -r requirements.txt

REM Install Playwright browsers
echo Installing Playwright browsers...
playwright install chromium

cd ..

REM Check if Flutter is installed (optional)
flutter --version >nul 2>&1
if not errorlevel 1 (
    echo Installing Flutter dependencies...
    cd frontend
    flutter pub get
    cd ..
    echo ✅ Flutter setup complete
) else (
    echo ⚠️  Flutter not installed - mobile app setup skipped
)

echo.
echo 🎉 Setup complete!
echo.
echo To start the backend:
echo   cd backend & uvicorn main:app --host 0.0.0.0 --port 8000 --reload
echo.
echo To test the backend:
echo   python test_backend.py
echo.
echo To run the web app:
echo   cd web & python -m http.server 8080
echo.
echo To run the Flutter app:
echo   cd frontend & flutter run
echo.
pause