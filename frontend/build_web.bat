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

rem NOTE: Flutter 3.29+ removed --web-renderer. Use default renderer.
rem Disable PWA caching to avoid stale builds after deploys.
flutter build web --release --pwa-strategy=none %DART_DEFINES%

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
