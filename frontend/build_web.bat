@echo off
echo ========================================
echo Building Infinity Leads Pro for Web
echo ========================================
echo.

echo Cleaning previous build...
if exist build\web rmdir /s /q build\web

echo.
echo Building Flutter web app (release mode)...
set DART_DEFINES=
if not "%API_URL%"=="" (
    echo Using API_URL=%API_URL%
    set DART_DEFINES=--dart-define=API_URL=%API_URL%
)

flutter build web --release --web-renderer canvaskit %DART_DEFINES%

if %errorlevel% == 0 (
    echo.
    echo ========================================
    echo Build completed successfully!
    echo ========================================
    echo Output directory: build\web
    echo.
    echo To test locally, run:
    echo   cd build\web
    echo   python -m http.server 8080
    echo.
) else (
    echo.
    echo ========================================
    echo Build failed! Please check the errors above.
    echo ========================================
    exit /b %errorlevel%
)
