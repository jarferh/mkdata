# Security Implementation Summary - Session-Based Authentication

## Overview
Implemented pragmatic session-based authentication system to fix IDOR (Insecure Direct Object Reference) vulnerabilities across all user endpoints in the MK Data VTU API.

## Key Implementation Changes

### 1. Session Helper Library
**File**: `VTU-API/auth/session-helper.php` (Created)

Core functions implemented:
- `initializeSession()` - Configures secure PHP sessions
- `setAuthenticatedUser($userId, $email, $userType)` - Saves user to session on login
- `getAuthenticatedUserId()` - Retrieves authenticated user from session
- `requireAuth()` - Verifies authentication and throws 401 if not authenticated
- `requireAdmin()` - Verifies admin role and throws 403 if not admin
- `loadEnvFile($path)` - Loads environment variables from .env file
- `isAuthenticated()` - Checks if user is authenticated
- `isAdmin()` - Checks if user is admin

### 2. Environment Configuration
**File**: `VTU-API/.env` (Updated)

Added configuration:
```
MAIL_HOST=mail.mkdata.com.ng
MAIL_PORT=465
MAIL_USERNAME=no-reply@mkdata.com
MAIL_PASSWORD=[PRODUCTION_VALUE]
SESSION_LIFETIME=86400
SESSION_SECURE=true
SESSION_HTTPONLY=true
SESSION_SAMESITE=Strict
FCM_SA_JSON_PATH=/var/secure/mkdata/keys/mkdata-firebase-sa.json
```

### 3. Login Endpoint Update
**File**: `VTU-API/auth/login.php` (Updated)

Changes:
- Added session-helper import
- Added `loadEnvFile()` call to load environment variables
- On successful login, calls `setAuthenticatedUser($user->sId, $user->sEmail, $user->sType)`
- Session now contains authenticated user context for all subsequent requests

### 4. API Protection
**File**: `VTU-API/api/.htaccess` (Updated)

Added protections:
```apache
<FilesMatch "firebase.*\.json|\.env|\.git">
    Deny from all
</FilesMatch>
<DirectoryMatch "^/srv/keys">
    Deny from all
</DirectoryMatch>
```

Prevents direct web access to sensitive files and directories.

### 5. API Initialization
**File**: `VTU-API/api/index.php` (Updated - Top Section)

Added at start of file:
- Import of `session-helper.php`
- Call to `loadEnvFile()` to load environment variables
- Call to `initializeSession()` to initialize secure sessions

### 6. SMTP Credentials
**File**: `VTU-API/api/index.php` (Updated - Lines ~1945-1970)

Changed from hardcoded credentials to environment variables:
- `MAIL_HOST` - now uses `getenv('MAIL_HOST')`
- `MAIL_USERNAME` - now uses `getenv('MAIL_USERNAME')`
- `MAIL_PASSWORD` - now uses `getenv('MAIL_PASSWORD')`
- All with fallback values and error logging

## Endpoint Fixes - Session-Based Authentication

All the following endpoints now use `requireAuth()` to get authenticated user from session instead of client-supplied user_id:

### User Account Endpoints
1. **delete-account** - Changed from `$data->userId` to `requireAuth()`
2. **account-details** - Changed from `$_GET['id']` to `requireAuth()`
3. **update-pin** - Changed from `$data->user_id` to `requireAuth()`
4. **update-profile** - Changed from `$data->user_id` to `requireAuth()`

### Purchase Endpoints
5. **airtime** - Changed from `$data->user_id` to `requireAuth()`
6. **purchase-data** - Changed from `$data->user_id` to `requireAuth()`
7. **purchase-electricity** - Changed from `$data->userId` to `requireAuth()`
8. **purchase-recharge-pin** - Changed from `$data->userId` to `requireAuth()`
9. **exam-purchase** - Changed from `$data->userId` to `requireAuth()`
10. **purchase-data-pin** - Changed from `$data->userId` to `requireAuth()`

### Beneficiary Endpoints
11. **beneficiary** (POST) - Changed from `$data->user_id` to `requireAuth()`
12. **beneficiary** (PUT) - Changed from `$data->user_id` to `requireAuth()`
13. **beneficiary** (DELETE) - Changed from `$data->user_id` to `requireAuth()`
14. **beneficiaries** (GET) - Changed from `$_GET['user_id']` to `requireAuth()`

### Transaction Endpoints
15. **transactions** - Changed from `$_GET['user_id']` to `requireAuth()`
16. **manual-payments** - Changed from `$_GET['user_id']` to `requireAuth()`

### Admin Endpoints
17. **a2c-submit** - Changed from `$data->user_id` to `requireAuth()`
18. **a2c-requests** - Changed from `$_GET['user_id']` to `requireAuth()`
19. **a2c-approve** - Changed from `$data->admin_id` to `requireAdmin()`

## Security Pattern Applied

### Before (Vulnerable):
```php
case 'update-pin':
    if (!isset($data->user_id) || !isset($data->pin)) {
        throw new Exception('Missing required parameters: user_id, pin');
    }
    $userService->updatePin($data->user_id, $data->pin);  // Uses client-supplied user_id
```

### After (Secure):
```php
case 'update-pin':
    $authenticatedUserId = requireAuth();  // Get user from session
    if (!isset($data->pin)) {
        throw new Exception('Missing required parameters: pin');
    }
    $userService->updatePin($authenticatedUserId, $data->pin);  // Uses session user
```

## Key Security Principles

1. **Never Trust Client Input**: Client can send `user_id` but it's ignored
2. **Session-Based Authority**: Server verifies user via `$_SESSION` variables
3. **Secure Session Configuration**: 
   - httpOnly flag prevents JavaScript access
   - Secure flag for HTTPS-only transmission
   - SameSite=Strict prevents CSRF attacks
4. **Environment Secrets**: Credentials stored in .env (not committed to git)
5. **File Protection**: .htaccess blocks web access to sensitive files

## Deployment Instructions

### Step 1: .env File Setup
Copy and edit `.env` file on production server:
```bash
cp VTU-API/.env.example VTU-API/.env
```

Update with production values:
- `MAIL_PASSWORD` - Set to actual SMTP password
- `FCM_SA_JSON_PATH` - Adjust path if needed

### Step 2: .env File Protection
Ensure .env is NOT in web root:
- Place in parent directory of /api
- Or use .htaccess rule (already added): `Deny from all`
- Add to `.gitignore` to prevent accidental commits

### Step 3: Firebase Key Protection
Verify .htaccess blocks Firebase key access:
```bash
curl https://your-domain.com/api/mkdata-firebase-sa.json
# Should return 403 Forbidden
```

### Step 4: Session Directory
Ensure PHP session directory is writable:
```bash
chmod 755 /path/to/sessions
```

### Step 5: Flutter App Updates
Update Flutter app to:
- Remove hardcoded `user_id` from requests
- Remove `user_id` parameter where applicable
- Ensure session cookies are preserved in HTTP client

## Breaking Changes

### For Flutter Clients
Endpoints that previously required `user_id` parameter now:
- **Ignore** any client-supplied `user_id`
- **Require** valid session/authentication
- **Return 401** if not authenticated

### API Requests Before and After

**Delete Account**
```
BEFORE: POST /api?action=delete-account { user_id: 123 }
AFTER: POST /api?action=delete-account (requires session)
```

**Update PIN**
```
BEFORE: POST /api?action=update-pin { user_id: 123, pin: "1234" }
AFTER: POST /api?action=update-pin { pin: "1234" } (requires session)
```

**Get Transactions**
```
BEFORE: GET /api?action=transactions&user_id=123
AFTER: GET /api?action=transactions (requires session)
```

## Remaining Security Improvements

These were documented but not yet implemented:

### Phase 2 Recommendations:
- Password complexity requirements
- Rate limiting on purchase endpoints
- Transaction verification (2FA for large amounts)
- Account lockout after failed attempts

### Phase 3 Recommendations:
- Audit logging for all sensitive operations
- Payment webhook verification
- IP whitelist for admin operations
- Regular security testing (penetration testing)

## Verification Checklist

- [x] Session helper library created
- [x] Login endpoint saves user to session
- [x] All user endpoints use `requireAuth()`
- [x] Admin endpoints use `requireAdmin()`
- [x] .env file created with SMTP configuration
- [x] SMTP credentials removed from hardcoded values
- [x] .htaccess protects Firebase key and .env
- [x] Session cookie flags configured (httpOnly, secure, SameSite)
- [x] All 19 vulnerable endpoints updated
- [ ] Flutter app updated to handle session authentication
- [ ] Production .env deployed with real credentials
- [ ] Session cookie testing verified
- [ ] HTTPS enabled for secure transmission

## Support

For questions or issues with the implementation:
1. Check session-helper.php for available functions
2. Review error logs for authentication failures
3. Verify .env file is correctly placed and readable
4. Ensure PHP session directory is writable
