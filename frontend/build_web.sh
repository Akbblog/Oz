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

# NOTE: Flutter 3.29+ removed --web-renderer. Use the default renderer.
# Disable PWA caching to avoid stale builds after deploys.
flutter build web --release --pwa-strategy=none $EXTRA_DEFINES
BUILD_STATUS=$?

# Incremental builds have been observed to report success while leaving
# build/web without its asset manifests (the app then loads as a blank page).
# Refuse to call such a bundle "successful".
# Replace the (empty) service worker with one that removes the caching worker
# older releases installed, so returning visitors get the new build.
if [ $BUILD_STATUS -eq 0 ] && [ -f web/sw_cleanup.js ]; then
    cp web/sw_cleanup.js build/web/flutter_service_worker.js
fi

if [ $BUILD_STATUS -eq 0 ]; then
    for f in build/web/main.dart.js build/web/assets/AssetManifest.bin.json build/web/assets/FontManifest.json; do
        if [ ! -s "$f" ]; then
            echo "Incomplete web bundle: missing $f. Run 'flutter clean' and build again."
            BUILD_STATUS=1
        fi
    done
fi

if [ $BUILD_STATUS -eq 0 ]; then
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
