# Admin Settings & Auto-Approval Implementation Summary

## Phase 1: Database Migration ✅

### New Files Created
- **migrations/006_admin_settings.sql** (MySQL)
- **migrations/006_admin_settings_sqlite.sql** (SQLite)

### Schema
```sql
CREATE TABLE admin_settings (
    key TEXT PRIMARY KEY,
    value TEXT NOT NULL,
    description TEXT,
    updated_at TEXT,
    updated_by INTEGER REFERENCES users(id)
);
```

### Default Settings
- `auto_approve_users`: 'false' - Auto-approve new user registrations
- `send_approval_email`: 'true' - Send email when user is approved
- `send_welcome_email`: 'true' - Send welcome email on auto-approval
- `send_rejection_email`: 'true' - Send email when user registration is denied
- `starting_credits`: '100' - Credits given to new approved users
- `admin_notification_on_signup`: 'true' - Notify admin of new signups

---

## Phase 2: Backend Implementation ✅

### A. Admin Settings Helper Functions (main.py)

Added three helper functions:

```python
def get_admin_setting(key: str, default: str = "") -> str:
    """Get admin setting value from database."""

def set_admin_setting(key: str, value: str, admin_id: int) -> None:
    """Update admin setting in database."""

def get_all_admin_settings() -> dict:
    """Get all admin settings as a dictionary."""
```

### B. Updated Registration Endpoint (main.py)

**Endpoint**: `POST /api/auth/register`

Changes:
- Check if `auto_approve_users` setting is enabled
- If enabled:
  - Set `is_approved = 1`
  - Set `credit_balance = starting_credits`
  - Send welcome email (if `send_welcome_email = true`)
  - Return "You can now log in" message
- If disabled (default):
  - Set `is_approved = 0`
  - Set `credit_balance = 0`
  - Return "Please wait for admin approval" message

### C. Updated Approval Endpoint (main.py)

**Endpoint**: `POST /api/admin/users/{user_id}/approve`

Changes:
- Send approval email to user (if `send_approval_email = true`)
- Email includes username and starting credits granted

### D. New Deny/Rejection Endpoint (main.py)

**Endpoint**: `POST /api/admin/users/{user_id}/deny`

Features:
- Accept optional `admin_note` query parameter
- Mark user as denied (is_approved = -1)
- Send rejection email with admin note (if `send_rejection_email = true`)
- Polite notification without sensitive information

**Related endpoint**: `POST /api/admin/users/{user_id}/restore`
- Restores a denied user back to pending approval (is_approved = 0)

### E. New Settings Management Endpoints (main.py)

**Admin-only endpoints:**

1. **GET /api/admin/settings**
   - Returns all admin settings as JSON

2. **GET /api/admin/settings/{key}**
   - Returns specific setting value

3. **PUT /api/admin/settings/{key}**
   - Update a specific setting
   - Requires admin authentication
   - Records who made the change (updated_by field)

### F. Email Service Functions (email_service.py)

Added three new email functions:

```python
def send_welcome_email(
    to_email: str,
    username: str,
    email: str,
    starting_credits: int,
) -> None:
    """Send welcome email to auto-approved user"""

def send_approval_email(
    to_email: str,
    username: str,
    starting_credits: int,
) -> None:
    """Send approval notification email when admin approves user"""

def send_rejection_email(
    to_email: str,
    username: str,
    admin_note: Optional[str] = None,
) -> None:
    """Send rejection notification email when admin denies user"""
```

---

## Phase 3: Email Templates ✅

### New Templates Created

1. **notifications/templates/welcome_email.html**
   - Sent on auto-approval
   - Shows username, email, starting credits
   - Onboarding instructions
   - Purple gradient design matching app

2. **notifications/templates/approval_email.html**
   - Sent when admin approves user
   - Congratulation message
   - Login link
   - Credit information

3. **notifications/templates/rejection_email.html**
   - Sent when admin denies user
   - Polite notification
   - Space for admin note with reason
   - Support contact information

---

## Phase 4: Frontend API Service ✅

### Updated (api_service.dart)

Added four new methods:

```dart
Future<Map<String, dynamic>> getAdminSettings() async
  - Get all settings as dictionary

Future<String> getAdminSetting(String key) async
  - Get specific setting by key

Future<Map<String, dynamic>> updateAdminSetting(String key, String value) async
  - Update a specific setting

Future<Map<String, dynamic>> denyUser(int userId, {String? adminNote}) async
  - Deny a user registration with optional note
```

---

## Implementation Benefits

### For Users
✅ Instant account activation (optional)
✅ Clear communication via email
✅ Starting credits explanation
✅ Rejection feedback for improvement

### For Admins
✅ Centralized settings management
✅ Toggle auto-approval feature
✅ Control email notifications
✅ Configure starting credit amount
✅ Audit trail (who changed what setting)

### For System
✅ Flexible registration flow
✅ Email-based communication
✅ No manual credit grants needed
✅ Scalable to handle growth

---

## Integration Notes

### Database Migrations
- Run migrations in order: `001_` → `006_admin_settings`
- Will automatically create settings table on app startup
- Default values inserted automatically

### Configuration
- Requires SMTP email service to be configured
- Uses existing `config.SMTP_*` variables
- Fallback `APP_URL` defaults to `https://app.infinitleads.pro`

### Testing Checklist
- [ ] Create new user with auto-approve OFF → should wait for approval
- [ ] Create new user with auto-approve ON → should login immediately
- [ ] Approve pending user → should receive approval email
- [ ] Deny user → should receive rejection email
- [ ] Update admin settings via API → verify changes persist
- [ ] Check audit trail (updated_by field) in admin_settings

---

## Future Enhancements

- Email verification requirement
- Custom welcome message per user type
- Approval queue notifications
- Webhook integrations
- Email template customization in UI
