#!/bin/bash

echo "========================================"
echo "Building Infinity Leads Pro for Web"
echo "========================================"
echo ""

echo "Cleaning previous build..."
rm -rf build/web

echo ""
echo "Building Flutter web app (release mode)..."
EXTRA_DEFINES=""
if [ -n "${API_URL:-}" ]; then
  echo "Using API_URL=$API_URL"
  EXTRA_DEFINES="--dart-define=API_URL=$API_URL"
fi

flutter build web --release --web-renderer canvaskit $EXTRA_DEFINES

if [ $? -eq 0 ]; then
    echo ""
    echo "========================================"
    echo "Build completed successfully!"
    echo "========================================"
    echo "Output directory: build/web"
    echo ""
    echo "To test locally, run:"
    echo "  cd build/web"
    echo "  python3 -m http.server 8080"
    echo ""
else
    echo ""
    echo "========================================"
    echo "Build failed! Please check the errors above."
    echo "========================================"
    exit 1
fi
