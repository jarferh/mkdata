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
if (isAuthenticated()) {
    // User has valid session
    http_response_code(200);
    echo json_encode([
        'status' => 'authenticated',
        'message' => 'User session is valid',
        'authenticated' => true
    ]);
} else {
    // User session is not valid
    http_response_code(401);
    echo json_encode([
        'status' => 'unauthenticated',
        'message' => 'User not authenticated or session expired',
        'authenticated' => false
    ]);
}
?>
