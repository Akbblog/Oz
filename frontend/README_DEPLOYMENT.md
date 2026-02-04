# Infinity Leads Pro - Deployment Guide

## Quick Start

### Building for Production

**Windows:**
```bash
build_web.bat
```

**Mac/Linux:**
```bash
chmod +x build_web.sh
./build_web.sh
```

---

## Deployment Options

### Option 1: Vercel (Recommended - Easiest)

#### Prerequisites
- Install Vercel CLI: `npm install -g vercel`
- Have Flutter installed and in PATH

#### Deploy Steps
1. Navigate to the frontend folder:
   ```bash
   cd frontend
   ```

2. Login to Vercel:
   ```bash
   vercel login
   ```

3. Deploy:
   ```bash
   vercel
   ```

4. Follow the prompts:
   - Set up and deploy? **Y**
   - Which scope? Select your account
   - Link to existing project? **N**
   - Project name? `infinity-leads-pro`
   - Directory? `./`
   - Override settings? **N**

5. Your app will be live at `https://infinity-leads-pro.vercel.app` (or similar)

#### Production Deployment
```bash
vercel --prod
```

---

### Option 2: Netlify

#### Prerequisites
- Install Netlify CLI: `npm install -g netlify-cli`
- Have Flutter installed and in PATH

#### Deploy Steps

**Method A: CLI Deployment**
1. Navigate to the frontend folder:
   ```bash
   cd frontend
   ```

2. Login to Netlify:
   ```bash
   netlify login
   ```

3. Initialize and deploy:
   ```bash
   netlify init
   ```

4. Follow the prompts to create a new site

5. Deploy:
   ```bash
   netlify deploy --prod
   ```

**Method B: Git-Based Deployment (Recommended)**
1. Push your code to GitHub/GitLab/Bitbucket
2. Go to [Netlify](https://app.netlify.com)
3. Click "Add new site" → "Import an existing project"
4. Connect your repository
5. Netlify will auto-detect the `netlify.toml` configuration
6. Click "Deploy site"

---

### Option 3: Firebase Hosting

#### Prerequisites
- Install Firebase CLI: `npm install -g firebase-tools`
- Have a Firebase project created

#### Deploy Steps
1. Navigate to the frontend folder:
   ```bash
   cd frontend
   ```

2. Login to Firebase:
   ```bash
   firebase login
   ```

3. Initialize Firebase (first time only):
   ```bash
   firebase init hosting
   ```
   - Select your Firebase project
   - Public directory: `build/web`
   - Single-page app: **Yes**
   - Set up automatic builds with GitHub: **No** (or Yes if preferred)
   - Overwrite index.html: **No**

4. Build the app:
   ```bash
   flutter build web --release
   ```

5. Deploy:
   ```bash
   firebase deploy --only hosting
   ```

6. Your app will be live at `https://your-project.web.app`

---

## Testing Locally Before Deployment

After building with the build script, test locally:

```bash
cd build/web
python -m http.server 8080
```

Then open: `http://localhost:8080`

---

## Environment Configuration

The frontend reads the API base URL from a build-time define:

- **Recommended**: pass `--dart-define=API_URL=...` during your `flutter build web` (works with Vercel/Netlify/Firebase build pipelines).
- **Local dev fallback**: uses `http://<current-host>:8080` (fallback `http://localhost:8080`).
- **Production fallback**: same-origin (requires rewrites/proxy), otherwise set `API_URL`.

---

## Post-Deployment Checklist

- [ ] App loads successfully
- [ ] Login/Register works
- [ ] API calls reach the backend
- [ ] Password reset flow works
- [ ] Job creation and tracking works
- [ ] Admin dashboard accessible (for admin users)
- [ ] PWA install prompt appears on mobile
- [ ] All pages are responsive

---

## Troubleshooting

### Build Fails
- Ensure Flutter is installed: `flutter --version`
- Run `flutter pub get` to install dependencies
- Clean build: `flutter clean && flutter pub get`

### API Connection Issues
- Check CORS settings in backend (`main.py`)
- Verify API URL is correct in `lib/config/environment.dart`
- Check browser console for CORS errors

### White Screen on Deployment
- Check browser console for errors
- Ensure all assets are loading (check Network tab)
- Verify `base href` is set correctly in `web/index.html`

---

## Custom Domain Setup

### Vercel
1. Go to project settings → Domains
2. Add your custom domain
3. Configure DNS records as instructed

### Netlify
1. Go to site settings → Domain management
2. Add custom domain
3. Configure DNS records as instructed

### Firebase
1. Run: `firebase hosting:channel:deploy production`
2. Go to Firebase Console → Hosting
3. Add custom domain and follow DNS instructions

---

## Performance Optimization

The app is built with:
- CanvasKit renderer for better performance
- Gzip compression (handled by hosting providers)
- Asset caching headers
- PWA support for offline capability

---

## Support

For issues or questions:
- Check the browser console for errors
- Verify backend is running and accessible
- Review CORS configuration in backend

---

**Built with Flutter Web | Infinity Leads Pro**
