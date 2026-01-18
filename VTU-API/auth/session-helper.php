<?php
/**
 * Session Helper - Authentication via PHP sessions
 * 
 * This file provides functions to manage user authentication using PHP sessions.
 * When a user logs in, their user ID is saved in the session.
 * All API endpoints use this session user ID instead of trusting client input.
 */

/**
 * Initialize session with secure settings
 */
function initializeSession() {
    if (session_status() === PHP_SESSION_NONE) {
        // Configure session settings from .env
        $lifetime = (int)getenv('SESSION_LIFETIME') ?: 86400; // 24 hours default
        $secure = getenv('SESSION_SECURE') === 'true' || getenv('SESSION_SECURE') === '1';
        $httpOnly = getenv('SESSION_HTTPONLY') === 'true' || getenv('SESSION_HTTPONLY') === '1' ?: true;
        $sameSite = getenv('SESSION_SAMESITE') ?: 'Lax';
        
        // Ensure PHP garbage collection doesn't delete session before lifetime expires
        ini_set('session.gc_maxlifetime', $lifetime);
        ini_set('session.gc_probability', 1);
        ini_set('session.gc_divisor', 100); // 1% chance to run GC on each request
        
        // Set session configuration
        session_set_cookie_params([
            'lifetime' => $lifetime,
            'path' => '/',
            'domain' => '',
            'secure' => $secure,
            'httponly' => $httpOnly,
            'samesite' => $sameSite
        ]);
        
        session_start();
    }
}

/**
 * Save user ID to session after login
 * 
 * @param int $userId The authenticated user's ID
 * @param string $email User's email (for reference)
 * @param int $userType User type/role
 * @return void
 */
function setAuthenticatedUser($userId, $email = '', $userType = 0) {
    initializeSession();
    $_SESSION['authenticated_user_id'] = (int)$userId;
    $_SESSION['authenticated_user_email'] = $email;
    $_SESSION['authenticated_user_type'] = (int)$userType;
    $_SESSION['login_time'] = time();
}

/**
 * Get the authenticated user ID from session
 * Returns the user ID that was saved during login
 * 
 * @return int|null User ID if authenticated, null if not
 */
function getAuthenticatedUserId() {
    initializeSession();
    return isset($_SESSION['authenticated_user_id']) ? (int)$_SESSION['authenticated_user_id'] : null;
}

/**
 * Get all authenticated user info from session
 * 
 * @return array|null User info array if authenticated, null if not
 */
function getAuthenticatedUserInfo() {
    initializeSession();
    if (isset($_SESSION['authenticated_user_id'])) {
        return [
            'user_id' => (int)$_SESSION['authenticated_user_id'],
            'email' => $_SESSION['authenticated_user_email'] ?? '',
            'user_type' => (int)($_SESSION['authenticated_user_type'] ?? 0),
            'login_time' => $_SESSION['login_time'] ?? null
        ];
    }
    return null;
}

/**
 * Check if user is authenticated
 * 
 * @return bool True if user is logged in, false otherwise
 */
function isAuthenticated() {
    return getAuthenticatedUserId() !== null;
}

/**
 * Check if user is admin (user_type == 2)
 * 
 * @return bool True if user is admin, false otherwise
 */
function isAdmin() {
    initializeSession();
    return isset($_SESSION['authenticated_user_type']) && (int)$_SESSION['authenticated_user_type'] === 2;
}

/**
 * Require authentication - throw exception if not logged in
 * 
 * @return int Authenticated user ID
 * @throws Exception If user is not authenticated
 */
function requireAuth() {
    $userId = getAuthenticatedUserId();
    if ($userId === null) {
        http_response_code(401);
        throw new Exception('Unauthorized: User not authenticated. Please login first.');
    }
    return $userId;
}

/**
 * Require admin role - throw exception if not admin
 * 
 * @return int Authenticated admin user ID
 * @throws Exception If user is not admin
 */
function requireAdmin() {
    $userId = requireAuth(); // First verify authenticated
    if (!isAdmin()) {
        http_response_code(403);
        throw new Exception('Forbidden: Admin access required');
    }
    return $userId;
}

/**
 * Logout user - clear session
 * 
 * @return void
 */
function logoutUser() {
    initializeSession();
    unset($_SESSION['authenticated_user_id']);
    unset($_SESSION['authenticated_user_email']);
    unset($_SESSION['authenticated_user_type']);
    unset($_SESSION['login_time']);
    session_destroy();
}

/**
 * Load environment variables from .env file
 * 
 * @param string $path Path to .env file
 * @return void
 */
function loadEnvFile($path = __DIR__ . '/.env') {
    if (file_exists($path)) {
        $lines = file($path, FILE_IGNORE_NEW_LINES | FILE_SKIP_EMPTY_LINES);
        foreach ($lines as $line) {
            // Skip comments and empty lines
            if (strpos(trim($line), '#') === 0 || empty(trim($line))) {
                continue;
            }
            
            // Parse KEY=VALUE format
            if (strpos($line, '=') !== false) {
                list($key, $value) = explode('=', $line, 2);
                $key = trim($key);
                $value = trim($value);
                
                // Remove quotes if present
                if ((strpos($value, '"') === 0 && strpos($value, '"', 1) === strlen($value) - 1) ||
                    (strpos($value, "'") === 0 && strpos($value, "'", 1) === strlen($value) - 1)) {
                    $value = substr($value, 1, -1);
                }
                
                putenv("$key=$value");
            }
        }
    }
}

?>
