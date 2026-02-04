# Infinity Leads Pro - Agent Documentation

## Project Overview

**Infinity Leads Pro** is a global business lead discovery platform that scrapes Google Business listings from multiple countries (USA, UK, UAE, KSA, Australia). The application consists of:

- **Backend**: FastAPI (Python) with Playwright for web scraping
- **Frontend**: Flutter web application with modern glassmorphic UI
- **Database**: SQLite (default) or MySQL
- **Deployment**: Railway (backend), Vercel/Netlify/Firebase (frontend)

---

## Architecture

### System Components

```
┌─────────────────────────────────────────────────────────────┐
│                    Frontend (Flutter Web)                    │
│  - Material Design 3 UI                                      │
│  - Provider State Management                                 │
│  - Environment-aware API configuration                       │
│  - PWA with offline support                                  │
└─────────────────┬───────────────────────────────────────────┘
                  │ HTTP/REST API
                  │ JWT Authentication
┌─────────────────▼───────────────────────────────────────────┐
│                 Backend (FastAPI + Python)                   │
│  - REST API endpoints                                        │
│  - JWT authentication & authorization                        │
│  - Credit system with rate limiting                          │
│  - Background job processing                                 │
└─────────────────┬───────────────────────────────────────────┘
                  │
        ┌─────────┴──────────┬─────────────────┐
        ▼                    ▼                 ▼
┌───────────────┐    ┌───────────────┐  ┌──────────────┐
│   Database    │    │   Playwright  │  │  External    │
│ SQLite/MySQL  │    │ (Web Scraper) │  │  APIs        │
└───────────────┘    └───────────────┘  └──────────────┘
```

---

## Directory Structure

```
business_scraper_api/
├── backend/
│   ├── main.py                    # FastAPI application & endpoints
│   ├── database.py                # Database initialization & helpers
│   ├── auth.py                    # JWT authentication utilities
│   └── run_server.py              # Server startup script
│
├── frontend/
│   ├── lib/
│   │   ├── main.dart              # App entry point & routing
│   │   ├── config/
│   │   │   └── environment.dart   # Environment detection & API URLs
│   │   ├── core/
│   │   │   ├── error_handler.dart # Centralized error handling
│   │   │   └── theme/             # Design system (colors, typography, spacing)
│   │   ├── providers/
│   │   │   ├── auth_provider.dart # Authentication state management
│   │   │   └── scraper_provider.dart # Job state management
│   │   ├── services/
│   │   │   └── api_service.dart   # API client with all endpoints
│   │   ├── screens/              # All UI screens
│   │   │   ├── login_screen.dart
│   │   │   ├── forgot_password_screen.dart
│   │   │   ├── reset_password_screen.dart
│   │   │   ├── home_screen.dart
│   │   │   ├── scraping_screen.dart
│   │   │   ├── results_screen.dart
│   │   │   └── admin_dashboard_screen.dart
│   │   └── widgets/              # Reusable UI components
│   │       ├── gradient_button.dart
│   │       ├── glass_card.dart
│   │       └── custom_text_field.dart
│   ├── web/
│   │   ├── index.html            # HTML entry point (SEO optimized)
│   │   └── manifest.json         # PWA manifest
│   ├── pubspec.yaml              # Flutter dependencies
│   ├── build_web.bat             # Windows build script
│   ├── build_web.sh              # Unix build script
│   ├── vercel.json               # Vercel deployment config
│   ├── netlify.toml              # Netlify deployment config
│   └── firebase.json             # Firebase deployment config
│
└── AGENT.md                      # This file
```

---

## Key Implementation Details

### 1. Environment Configuration

**File**: `frontend/lib/config/environment.dart`

```dart
class Environment {
  static String get apiUrl {
    // Auto-detects localhost for development
    if (kDebugMode && Uri.base.host.contains('localhost')) {
      return 'http://127.0.0.1:8001';
    }
    // Production Railway URL
    // For production builds, pass `--dart-define=API_URL=...` to set the backend URL.
    // If omitted, the app will fall back to same-origin (requires rewrites/proxy).
    return html.window.location.origin ?? 'https://example.invalid';
  }
}
```

**Why**: No manual environment switching needed. Automatically uses localhost in debug mode, production URL when deployed.

---

### 2. Error Handling System

**File**: `frontend/lib/core/error_handler.dart`

**Features**:
- Specific exception types (NetworkException, AuthenticationException, ValidationException, etc.)
- User-friendly error messages
- Automatic token refresh detection
- Network error detection

**Usage**:
```dart
try {
  await apiService.login(...);
} catch (e) {
  final message = ErrorHandler.getUserFriendlyMessage(e);
  // Show message to user
}
```

---

### 3. Password Reset Flow

**Backend Endpoints** (`backend/main.py`):
1. `POST /api/auth/forgot-password` - Generates secure token, logs reset URL
2. `GET /api/auth/verify-reset-token/{token}` - Validates token is valid & not expired
3. `POST /api/auth/reset-password` - Resets password & marks token as used

**Frontend Flow**:
1. User clicks "Forgot Password?" → [ForgotPasswordScreen](frontend/lib/screens/forgot_password_screen.dart)
2. User enters email → API request → Success message shown
3. User clicks reset link with token → [ResetPasswordScreen](frontend/lib/screens/reset_password_screen.dart)
4. Token verified automatically on screen load
5. User enters new password → Password reset → Redirect to login

**Database Table**:
```sql
CREATE TABLE password_reset_tokens (
  id INTEGER PRIMARY KEY,
  user_id INTEGER NOT NULL,
  token_hash TEXT NOT NULL UNIQUE,  -- SHA-256 hash of token
  expires_at TEXT NOT NULL,         -- 24 hours from creation
  used INTEGER DEFAULT 0,           -- Prevents token reuse
  created_at TEXT NOT NULL,
  used_at TEXT
);
```

---

### 4. Credit System

**How it Works**:
- Each user has a credit balance
- Jobs cost credits: `base (2) + per_city (1) × cities + per_result (1) × results_per_city`
- Admins can grant credits manually
- Users can request credits (admin approval required)
- All transactions logged in `credit_ledger` table

**Key Functions** (`backend/main.py`):
- `estimate_credit_cost()` - Calculate job cost
- `deduct_credits()` - Charge user for job
- `add_credits()` - Grant credits (admin only)

---

### 5. API Client Structure

**File**: `frontend/lib/services/api_service.dart`

**Pattern**:
```dart
Future<Map<String, dynamic>> methodName({params}) async {
  try {
    final response = await http.method(
      Uri.parse('$baseUrl/api/endpoint'),
      headers: await _getHeaders(),
      body: jsonEncode(data),
    ).timeout(timeout);  // 30 seconds

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      ErrorHandler.handleHttpError(response, context: 'Operation name');
      throw ApiException('Operation failed');
    }
  } on TimeoutException {
    throw NetworkException('Request timed out');
  } catch (e) {
    if (e is ApiException) rethrow;
    throw ErrorHandler.handleNetworkError(e);
  }
}
```

---

## Common Tasks

### Adding a New API Endpoint

1. **Backend** (`backend/main.py`):
   ```python
   @app.post("/api/your-endpoint")
   async def your_endpoint(
       request: YourRequestModel,
       current_user: dict = Depends(get_current_user)
   ):
       # Implementation
       return {"result": "success"}
   ```

2. **Frontend** (`frontend/lib/services/api_service.dart`):
   ```dart
   Future<Map<String, dynamic>> yourMethod({params}) async {
     try {
       final response = await http.post(
         Uri.parse('$baseUrl/api/your-endpoint'),
         headers: await _getHeaders(),
         body: jsonEncode(params),
       ).timeout(timeout);

       if (response.statusCode == 200) {
         return jsonDecode(response.body);
       } else {
         ErrorHandler.handleHttpError(response);
         throw ApiException('Operation failed');
       }
     } on TimeoutException {
       throw NetworkException('Request timed out');
     } catch (e) {
       if (e is ApiException) rethrow;
       throw ErrorHandler.handleNetworkError(e);
     }
   }
   ```

---

### Adding a New Screen

1. **Create screen file**: `frontend/lib/screens/your_screen.dart`
   ```dart
   import 'package:flutter/material.dart';
   import '../core/theme/app_colors.dart';
   import '../core/theme/app_typography.dart';
   import '../widgets/gradient_background.dart';

   class YourScreen extends StatefulWidget {
     const YourScreen({super.key});

     @override
     State<YourScreen> createState() => _YourScreenState();
   }

   class _YourScreenState extends State<YourScreen> {
     @override
     Widget build(BuildContext context) {
       return Scaffold(
         body: GradientBackground(
           child: SafeArea(
             child: // Your UI
           ),
         ),
       );
     }
   }
   ```

2. **Add route** in `frontend/lib/main.dart`:
   ```dart
   routes: {
     '/your-route': (context) => const YourScreen(),
   }
   ```

3. **Navigate**: `Navigator.of(context).pushNamed('/your-route');`

---

### Modifying the Theme

**Color Scheme** (`frontend/lib/core/theme/app_colors.dart`):
```dart
static const Color primaryStart = Color(0xFF6366F1);  // Indigo
static const Color primaryEnd = Color(0xFFA855F7);    // Purple
```

**Typography** (`frontend/lib/core/theme/app_typography.dart`):
- Use Material 3 text styles: `displayLarge`, `headlineLarge`, `bodyMedium`, etc.
- All styles include proper sizing, weight, and letter spacing

**Spacing** (`frontend/lib/core/theme/app_spacing.dart`):
- Consistent spacing: `xxs` (4px) to `xxxl` (64px)
- Use `const EdgeInsets.all(AppSpacing.md)` for consistent padding

---

## Database Schema

### Core Tables

**users**
- `id`, `username`, `email`, `password_hash`
- `is_approved`, `is_admin`, `credit_balance`
- `created_at`, `last_login`

**jobs**
- `job_id` (UUID), `user_id`, `category`, `cities_data`
- `status`, `progress`, `total_cities`, `current_city`
- `credit_estimate`, `credit_charged`, `credit_refund`
- `created_at`, `completed_at`

**results**
- `job_id`, `business_name`, `phone`, `website`, `address`
- `category`, `city`, `state`, `google_maps_url`

**credit_ledger**
- `user_id`, `job_id`, `amount`, `balance_after`
- `transaction_type` (credit/debit), `reason`, `created_by`

**credit_requests**
- `user_id`, `amount_requested`, `reason`, `status`
- `admin_note`, `reviewed_by`, `created_at`, `reviewed_at`

**password_reset_tokens** *(NEW)*
- `user_id`, `token_hash`, `expires_at`, `used`
- `created_at`, `used_at`

**rate_limits**
- `user_id`, `window_start`, `jobs_in_window`, `last_job_at`

---

## Authentication Flow

1. **Registration**:
   - User registers → Account created with `is_approved = 0`
   - Admin approves → User can login + receives starting credits

2. **Login**:
   - POST `/api/auth/login` with username/password
   - Backend validates + checks approval status
   - Returns JWT token (7-day expiration) + user data
   - Frontend stores token in SharedPreferences (localStorage equivalent)

3. **API Requests**:
   - All protected endpoints require `Authorization: Bearer {token}` header
   - Backend validates token via `get_current_user()` dependency
   - Invalid/expired token → 401 Unauthorized

4. **Admin Access**:
   - Protected with `get_admin_user()` dependency
   - Checks `is_admin = 1` flag
   - Returns 403 Forbidden if not admin

---

## Development Workflow

### Backend Development

1. **Setup**:
   ```bash
   cd backend
   pip install -r requirements.txt
   python run_server.py
   ```

2. **Database Initialization**:
   - Automatically creates tables on first run
   - Default admin: `admin` / `tool.com`

3. **Testing Endpoints**:
   - Use Postman/curl or built-in scripts:
   ```bash
   python scripts/test_login.py
   python scripts/print_users.py
   ```

### Frontend Development

1. **Setup**:
   ```bash
   cd frontend
   flutter pub get
   ```

2. **Run in browser**:
   ```bash
   flutter run -d chrome
   ```

3. **Build for production**:
   ```bash
   # Windows
   build_web.bat

   # Mac/Linux
   ./build_web.sh
   ```

---

## Deployment

### Backend (Railway)
- Backend deployment URL depends on your Railway project (set via env vars / build defines).
- Environment: Python 3.11+, Playwright installed
- Database: SQLite (persistent volume required for production)

### Frontend (Multiple Options)

**Vercel** (Recommended):
```bash
cd frontend
vercel --prod
```

**Netlify**:
```bash
cd frontend
netlify deploy --prod
```

**Firebase**:
```bash
cd frontend
firebase deploy --only hosting
```

See [README_DEPLOYMENT.md](frontend/README_DEPLOYMENT.md) for detailed instructions.

---

## Design System

### Visual Style
- **Theme**: Dark mode with glassmorphism effects
- **Primary Colors**: Indigo (#6366F1) → Purple (#A855F7) gradient
- **Secondary Colors**: Teal → Emerald gradient
- **Status Colors**: Green (success), Red (error), Amber (warning), Blue (info)

### Components
- `GradientButton` - Primary action button with gradient
- `GradientOutlineButton` - Secondary action with gradient border
- `GlassCard` - Glassmorphic container with blur effect
- `CustomTextField` - Themed input field with validation
- `GradientBackground` - Full-screen gradient background

### Typography
- Font: System default (Inter-like)
- Material 3 scale: display, headline, title, label, body
- Consistent sizing and weights

---

## Security Considerations

### Implemented
- ✅ JWT token authentication
- ✅ Password hashing (bcrypt/pbkdf2)
- ✅ CORS configuration
- ✅ SQL injection prevention (parameterized queries)
- ✅ Token-based password reset with expiration
- ✅ Rate limiting (5 jobs/hour, 2 concurrent)
- ✅ Admin authorization checks

### TODO
- [ ] HTTPS enforcement
- [ ] Email verification for registration
- [ ] 2FA for admin accounts
- [ ] API rate limiting per user
- [ ] CAPTCHA for login/registration

---

## Testing Checklist

### Backend
- [ ] All endpoints return correct status codes
- [ ] Authentication works (login, token validation, logout)
- [ ] Admin-only endpoints reject non-admin users
- [ ] Credit system charges correctly
- [ ] Rate limiting enforces limits
- [ ] Password reset flow works end-to-end

### Frontend
- [ ] Environment detection works (localhost vs production)
- [ ] Login/register flows complete successfully
- [ ] Error messages display properly
- [ ] Password reset flow works
- [ ] Job creation and tracking works
- [ ] Admin dashboard accessible for admins
- [ ] Responsive on mobile, tablet, desktop
- [ ] PWA installs on mobile devices

---

## Troubleshooting

### "API connection failed"
- Check if backend is running
- Verify CORS settings in `backend/main.py`
- Check browser console for CORS errors
- Ensure API URL is correct in environment config

### "Token expired" errors
- JWT tokens expire after 7 days
- User needs to login again
- Consider implementing refresh token mechanism

### Build fails on deployment
- Ensure Flutter is installed and in PATH
- Run `flutter clean && flutter pub get`
- Check deployment logs for specific errors
- Verify deployment config files are correct

### Password reset link doesn't work
- Check backend console for logged reset URL
- Verify token hasn't expired (24 hours)
- Ensure routing is configured in `main.dart`
- Check token format in URL

---

## Performance Optimization

### Current Optimizations
- CanvasKit renderer for Flutter web
- Asset caching headers
- Gzip compression (handled by hosting)
- API request timeouts (30 seconds)
- PWA with service worker

### Future Improvements
- [ ] Implement WebSocket for real-time job updates (replace 2-second polling)
- [ ] Add lazy loading for large result lists
- [ ] Implement pagination for job history
- [ ] Cache frequently accessed data
- [ ] Optimize image assets
- [ ] Add bundle size optimization

---

## Contributing

### Code Style
- **Dart**: Follow Flutter/Dart conventions (dartfmt)
- **Python**: Follow PEP 8 style guide
- **Comments**: Use doc comments for public APIs
- **Commits**: Descriptive commit messages

### Pull Request Checklist
- [ ] Code follows style guide
- [ ] All tests pass
- [ ] No console errors or warnings
- [ ] Documentation updated (if needed)
- [ ] Changes tested on multiple browsers
- [ ] Mobile responsiveness verified

---

## Contact & Support

- **Project**: Infinity Leads Pro
- **Framework**: Flutter Web + FastAPI
- **Version**: 1.0.0
- **Last Updated**: 2026-02-03

---

**Built with ❤️ using Flutter & FastAPI**
