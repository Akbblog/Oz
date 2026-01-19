# Business Scraper API + Flutter/Web App

A complete end-to-end solution for scraping Google Business data with API-first architecture. Works as both a Flutter mobile app and web application.

## 🚀 Features

- **REST API Backend** - FastAPI with async Playwright scraping
- **Flutter Mobile App** - Cross-platform mobile application
- **Web Interface** - Responsive web app with Bootstrap
- **Real-time Progress** - Live progress tracking during scraping
- **CSV Export** - Download results in CSV format
- **Docker Support** - Containerized deployment
- **GitHub Actions** - CI/CD automation

## 📁 Project Structure

```
business_scraper_api/
├── backend/                 # FastAPI backend
│   ├── main.py             # FastAPI application
│   ├── requirements.txt    # Python dependencies
│   └── Dockerfile         # Container configuration
├── frontend/               # Flutter mobile app
│   ├── lib/
│   │   ├── main.dart      # Flutter app entry
│   │   ├── screens/       # UI screens
│   │   ├── services/      # API service layer
│   │   └── providers/     # State management
│   └── pubspec.yaml       # Flutter dependencies
├── web/                    # Web interface
│   ├── index.html         # Main HTML page
│   ├── styles.css         # CSS styles
│   └── app.js             # JavaScript application
├── docker-compose.yml     # Docker setup
└── .github/workflows/     # CI/CD pipelines
```

## 🛠 Installation & Setup

### Backend Setup

1. **Install dependencies:**
```bash
cd backend
pip install -r requirements.txt
playwright install chromium
```

2. **Run backend:**
```bash
uvicorn main:app --host 0.0.0.0 --port 8000 --reload
```

3. **Test API:**
```bash
curl http://localhost:8000/api/health
```

### Flutter Setup

1. **Install Flutter SDK**
2. **Install dependencies:**
```bash
cd frontend
flutter pub get
```

3. **Run Flutter app:**
```bash
flutter run
```

### Web Setup

1. **Serve web files:**
```bash
cd web
# Use any static file server
python -m http.server 8080
```

2. **Open in browser:** http://localhost:8080

## 🐳 Docker Deployment

### Local Development
```bash
docker-compose up --build
```

### Production Build
```bash
docker build -t business-scraper-backend ./backend
```

## 📱 Mobile App Usage

1. **Start the backend API**
2. **Update API URL** in `frontend/lib/services/api_service.dart`
3. **Build Flutter app:**
```bash
cd frontend
flutter build apk --release
```

4. **Install APK** on Android device

## 🌐 Web App Usage

1. **Deploy backend** to a public URL
2. **Update API URL** in `web/app.js`
3. **Deploy web files** to any static hosting service

## 🔧 API Endpoints

- `POST /api/jobs` - Create scraping job
- `GET /api/jobs/{job_id}` - Get job status
- `GET /api/jobs/{job_id}/results` - Get results
- `GET /api/jobs/{job_id}/download` - Download CSV
- `GET /api/health` - Health check

## 📊 Sample Data

The app includes California cities data:
- Los Angeles, California
- San Diego, California
- San Jose, California
- ...and 17 more cities

## 🚀 Deployment Options

### Backend Deployment
- **Render** - Easy Python hosting
- **Railway** - Modern app platform
- **Heroku** - Traditional PaaS
- **AWS/GCP** - Cloud providers

### Frontend Deployment
- **Flutter** - Build APK/AAB for Play Store
- **Web** - Deploy to Vercel, Netlify, GitHub Pages

## 🔒 Security Considerations

- Use environment variables for API keys
- Implement rate limiting
- Add authentication for production
- Use HTTPS in production

## 🤝 Contributing

1. Fork the repository
2. Create feature branch
3. Commit changes
4. Push to branch
5. Open pull request

## 📄 License

MIT License - see LICENSE file for details

## 🆘 Troubleshooting

### Common Issues

**Backend won't start:**
- Check Python version (3.8+ required)
- Install Playwright browsers: `playwright install chromium`

**Flutter build fails:**
- Ensure Flutter SDK is installed
- Run `flutter doctor` to check setup

**Web app can't connect to API:**
- Update API URL in `web/app.js`
- Check CORS settings

## 📞 Support

For issues and questions:
1. Check existing GitHub issues
2. Create new issue with details
3. Include error logs and environment info

---

Built with ❤️ using FastAPI, Flutter, and modern web technologies.