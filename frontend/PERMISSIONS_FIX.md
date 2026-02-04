# Storage Permission Fix for Android

## Problem
The app was showing "storage permission denied" error when trying to download CSV files on Android devices.

## Solution
Added comprehensive storage permission handling for all Android versions.

### Changes Made:

#### 1. **AndroidManifest.xml** - Added Required Permissions
```xml
<!-- Storage permissions for downloading files -->
<uses-permission android:name="android.permission.WRITE_EXTERNAL_STORAGE"
    android:maxSdkVersion="32" />
<uses-permission android:name="android.permission.READ_EXTERNAL_STORAGE"
    android:maxSdkVersion="32" />

<!-- For Android 13+ (API 33+) -->
<uses-permission android:name="android.permission.READ_MEDIA_IMAGES" />
<uses-permission android:name="android.permission.READ_MEDIA_VIDEO" />
<uses-permission android:name="android.permission.READ_MEDIA_AUDIO" />

<!-- Request legacy external storage for Android 10 (API 29) -->
<application
    android:requestLegacyExternalStorage="true"
    ...>
```

#### 2. **permission_helper.dart** - Smart Permission Handler
Created a new helper class that:
- Automatically detects Android version
- Requests appropriate permissions based on OS version
- Handles Android 13+ (doesn't need storage permission)
- Handles Android 10-12 (requests storage permission)
- Handles Android 9 and below (requests WRITE_EXTERNAL_STORAGE)
- Opens app settings if permission is permanently denied
- Works seamlessly on iOS and Web without extra permissions

#### 3. **download_helper.dart** - Updated Download Function
Enhanced the CSV download function to:
- Request permissions automatically before downloading
- Show user-friendly permission dialogs
- Display success messages when file is saved
- Show error messages if download fails
- Handle all platforms (Web, Android, iOS)

#### 4. **Updated Screens**
- `results_screen.dart` - Uses new permission-aware download
- `job_history_screen.dart` - Uses new permission-aware download

## How It Works

1. When user clicks download:
   - App checks if permission is needed (based on Android version)
   - If needed, requests permission with a dialog
   - If granted, downloads the file
   - Shows success message with file name
   - If denied, shows dialog with option to open settings

2. On Android 13+ (API 33+):
   - No permission needed (uses scoped storage)
   - Files saved to Downloads folder automatically

3. On Android 10-12 (API 29-32):
   - Requests READ/WRITE_EXTERNAL_STORAGE permission
   - Uses legacy storage with scoped storage fallback

4. On Android 9 and below:
   - Requests WRITE_EXTERNAL_STORAGE permission
   - Uses traditional external storage

5. On iOS and Web:
   - No permissions needed
   - Works out of the box

## Testing

After rebuilding the APK:
1. Install the app on your device
2. Login and scrape some data
3. Go to Results screen
4. Click "Download CSV"
5. App will request storage permission (if needed)
6. Grant the permission
7. File will be saved to Downloads folder
8. Success message will appear

## File Locations

Downloaded CSV files are saved to:
- **Android**: `Downloads` folder (accessible via Files app)
- **iOS**: App's documents directory (accessible via Files app)
- **Web**: Browser's default download location

## Notes

- The app now handles all Android versions correctly
- Permission requests are shown only when needed
- Users can retry permission if initially denied
- Clear error messages guide users if something goes wrong
- App name in manifest changed to "Business Scraper Pro"
