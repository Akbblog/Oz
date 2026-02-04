# Business Scraper API + Flutter App

End-to-end Google Business data scraping platform with a FastAPI backend and a Flutter client (mobile + web). The backend handles authentication, credit/rate limiting, job execution with Playwright, and Excel exports. The Flutter app provides login, job creation, progress tracking, results, and admin tools.

## Features

Backend
- Auth with JWT, user approval, and admin roles
- Credit system with ledgers, rate limits, and credit requests
- Job lifecycle management with live progress + logs
- Countries/regions data: USA, UK, UAE, KSA, Australia
- Formatted Excel export (.xlsx) with hyperlinks

Flutter App (mobile + web)
- Login/register flow and profile
- City/region selection and job creation
- Progress view, results list, and job history
- Admin dashboard for approvals and credits
- Modern UI system (gradients, glass cards, custom fields)

Deploy
- Docker support for backend
- Vercel serverless API (static data endpoints only)

## Project Structure

```
business_scraper_api/
+-- backend/                 # FastAPI backend (scraping, auth, credits)
�   +-- main.py              # API routes and scraping logic
�   +-- database.py          # SQLite/MySQL + credit system
�   +-- auth.py              # JWT auth helpers
�   +-- run_server.py        # Windows-friendly server entry
�   +-- requirements.txt     # Python deps
+-- api/                     # Vercel serverless (no Playwright)
�   +-- index.py             # Static data endpoints
�   +-- requirements.txt
+-- frontend/                # Flutter app (mobile + web)
�   +-- lib/                 # UI, providers, services
�   +-- pubspec.yaml
+-- docker-compose.yml       # Backend container setup
+-- setup.bat / setup.sh     # Local setup helpers
+-- test_backend.py          # Basic backend smoke test
```

## Quick Start (Backend)

1) Install dependencies

```bash
cd backend
pip install -r requirements.txt
playwright install chromium
```

2) Run the API

Windows (recommended):
```bash
python run_server.py
```

Cross-platform:
```bash
uvicorn main:app --host 0.0.0.0 --port 8000 --reload
```

Note: `run_server.py` starts on port 8001 by default. Match your frontend `baseUrl` accordingly.

3) Health check

```bash
curl http://localhost:8001/api/health
```

## Flutter App (Mobile + Web)

1) Install dependencies

```bash
cd frontend
flutter pub get
```

2) Set API base URL

Update `baseUrl` in `frontend/lib/services/api_service.dart`:
- Local dev: `http://127.0.0.1:8001`
- Production: your deployed backend URL

3) Run

```bash
flutter run
```

For web builds:
```bash
flutter build web
```


## Configuration (Environment Variables)

Backend options in `backend/database.py` and `backend/auth.py`:
- `SECRET_KEY` (JWT secret)
- `DB_TYPE` (`sqlite` or `mysql`)
- `SQLITE_DB`, `MYSQL_HOST`, `MYSQL_USER`, `MYSQL_PASSWORD`, `MYSQL_DB`
- Credits: `CREDITS_BASE`, `CREDITS_PER_CITY`, `CREDITS_PER_RESULT`, `CREDITS_MIN_JOB`, `CREDITS_STARTING`
- Rate limits: `MAX_JOBS_PER_HOUR`, `MAX_CONCURRENT_JOBS`

## API Endpoints (Summary)

Auth
- `POST /api/auth/register`
- `POST /api/auth/login`
- `GET /api/auth/me`

Credits / Admin
- `GET /api/credits/balance`
- `POST /api/credits/estimate`
- `POST /api/credits/request`
- `GET /api/admin/users`
- `POST /api/admin/users/{user_id}/approve`
- `POST /api/admin/users/{user_id}/credits`

Jobs
- `POST /api/jobs`
- `GET /api/jobs`
- `GET /api/jobs/{job_id}`
- `GET /api/jobs/{job_id}/results`
- `GET /api/jobs/{job_id}/download`

Reference Data
- `GET /api/countries`
- `GET /api/states`
- `GET /api/states/{state}/cities`

## Deployment Notes

- Docker: use `docker-compose.yml` for backend.
- Vercel: `api/index.py` is a serverless entry that serves static data endpoints only (no scraping/Playwright).

## Troubleshooting

- Playwright errors: run `playwright install chromium`.
- Auth errors: ensure `SECRET_KEY` is set in production.
- Frontend failing to connect: verify `baseUrl` and CORS settings.
