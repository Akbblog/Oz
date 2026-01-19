#!/bin/bash

echo "Setting up Business Scraper API + Flutter/Web App"
echo "================================================="

# Check if Python is installed
if ! command -v python3 &> /dev/null; then
    echo "❌ Python 3 is required but not installed"
    exit 1
fi

# Check if pip is installed
if ! command -v pip3 &> /dev/null; then
    echo "❌ pip3 is required but not installed"
    exit 1
fi

echo "✅ Python and pip are installed"

# Install backend dependencies
echo "Installing backend dependencies..."
cd backend
pip3 install -r requirements.txt

# Install Playwright browsers
echo "Installing Playwright browsers..."
playwright install chromium

cd ..

# Check if Flutter is installed (optional)
if command -v flutter &> /dev/null; then
    echo "Installing Flutter dependencies..."
    cd frontend
    flutter pub get
    cd ..
    echo "✅ Flutter setup complete"
else
    echo "⚠️  Flutter not installed - mobile app setup skipped"
fi

echo ""
echo "🎉 Setup complete!"
echo ""
echo "To start the backend:"
echo "  cd backend && uvicorn main:app --host 0.0.0.0 --port 8000 --reload"
echo ""
echo "To test the backend:"
echo "  python test_backend.py"
echo ""
echo "To run the web app:"
echo "  cd web && python -m http.server 8080"
echo ""
echo "To run the Flutter app:"
echo "  cd frontend && flutter run"