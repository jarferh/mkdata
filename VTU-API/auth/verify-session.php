<?php
// Set timezone to GMT+1 (Africa/Lagos)
date_default_timezone_set('Africa/Lagos');

// Allow credentials with specific origins
$allowedOrigins = [
    'http://localhost',
    'https://localhost',
    'https://api.mkdata.com.ng',
    'https://mkdata.com.ng',
];

$origin = $_SERVER['HTTP_ORIGIN'] ?? '';
if (in_array($origin, $allowedOrigins) || php_sapi_name() === 'cli') {
    header("Access-Control-Allow-Origin: $origin");
    header("Access-Control-Allow-Credentials: true");
} else {
    // For all other origins
    header("Access-Control-Allow-Origin: *");
}

header("Content-Type: application/json; charset=UTF-8");
header("Access-Control-Allow-Methods: GET, POST, OPTIONS");
header("Access-Control-Allow-Headers: Content-Type, Access-Control-Allow-Headers, Authorization, X-Requested-With");

// Load environment variables and session helper
require_once __DIR__ . '/session-helper.php';
loadEnvFile(__DIR__ . '/../.env');

// Initialize session to check if user has valid session
initializeSession();

// Log incoming request details
error_log('verify-session: Incoming COOKIE: ' . json_encode($_COOKIE));
error_log('verify-session: Incoming PHPSESSID: ' . ($_COOKIE['PHPSESSID'] ?? 'NOT SET'));
error_log('verify-session: Session ID after init: ' . session_id());
error_log('verify-session: Session save path: ' . ini_get('session.save_path'));
error_log('verify-session: Session files in save path:');
$sessPath = ini_get('session.save_path');
if (is_dir($sessPath)) {
    $files = glob($sessPath . '/sess_*');
    error_log('  Found ' . count($files) . ' session files');
    foreach ($files as $file) {
        error_log('  - ' . basename($file));
    }
}

// Handle preflight requests
if ($_SERVER['REQUEST_METHOD'] === 'OPTIONS') {
    http_response_code(200);
    exit();
}

// Handle GET request for session verification
if ($_SERVER['REQUEST_METHOD'] !== 'GET') {
    http_response_code(405);
    echo json_encode([
        'status' => 'error',
        'message' => 'Method not allowed. Use GET.'
    ]);
    exit();
}

// Check if user is authenticated
$userId = getAuthenticatedUserId();
error_log('verify-session: getAuthenticatedUserId() returned: ' . ($userId ? $userId : 'NULL'));
error_log('verify-session: $_SESSION contents: ' . json_encode($_SESSION));

if ($userId !== null) {
    // User has valid session
    http_response_code(200);
    error_log('verify-session: User authenticated, returning 200');
    echo json_encode([
        'status' => 'authenticated',
        'message' => 'User session is valid',
        'authenticated' => true
    ]);
} else {
    // User session is not valid
    http_response_code(401);
    error_log('verify-session: User not authenticated, returning 401');
    echo json_encode([
        'status' => 'unauthenticated',
        'message' => 'User not authenticated or session expired',
        'authenticated' => false
    ]);
}
?>
