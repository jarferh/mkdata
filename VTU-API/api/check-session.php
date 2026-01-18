<?php
/**
 * Session Check Endpoint
 * Lightweight endpoint to verify if user session is still valid
 * Used during authentication flows (PIN, biometric) to avoid expensive transaction fetches
 */

header('Content-Type: application/json; charset=UTF-8');
header("Access-Control-Allow-Origin: *");
header("Access-Control-Allow-Methods: GET, POST, OPTIONS");
header("Access-Control-Allow-Headers: Content-Type");

// Handle preflight requests
if ($_SERVER['REQUEST_METHOD'] === 'OPTIONS') {
    http_response_code(200);
    exit();
}

require_once(__DIR__ . '/../config/db_config.php');
require_once(__DIR__ . '/../auth/session-helper.php');

try {
    $request_method = $_SERVER['REQUEST_METHOD'];
    
    // Handle GET and POST requests
    if ($request_method === 'GET' || $request_method === 'POST') {
        
        // Log incoming request details BEFORE initializing session
        error_log('check-session: Incoming COOKIE: ' . json_encode($_COOKIE));
        error_log('check-session: Incoming PHPSESSID: ' . ($_COOKIE['PHPSESSID'] ?? 'NOT SET'));
        
        // Initialize session
        initializeSession();
        
        error_log('check-session: Session ID after init: ' . session_id());
        error_log('check-session: Session save path: ' . ini_get('session.save_path'));
        error_log('check-session: $_SESSION contents: ' . json_encode($_SESSION));
        
        // Log session files in save path
        $sessPath = ini_get('session.save_path');
        if (is_dir($sessPath)) {
            $files = glob($sessPath . '/sess_*');
            error_log('check-session: Found ' . count($files) . ' session files');
            foreach ($files as $file) {
                error_log('  - ' . basename($file));
            }
        }
        
        // Check if user is authenticated
        $user_id = getAuthenticatedUserId();
        error_log('check-session: getAuthenticatedUserId() returned: ' . ($user_id ? $user_id : 'NULL'));
        
        if ($user_id === null) {
            http_response_code(401);
            echo json_encode([
                'status' => 'error',
                'success' => false,
                'message' => 'User not authenticated. Session has expired.',
            ]);
            exit();
        }
        
        // Touch session to keep it alive
        $_SESSION['last_activity'] = time();
        
        // Session is valid - return success
        http_response_code(200);
        echo json_encode([
            'status' => 'success',
            'success' => true,
            'message' => 'Session is valid',
            'data' => [
                'user_id' => $user_id,
                'authenticated' => true,
            ]
        ]);
        
    } else {
        http_response_code(405);
        echo json_encode([
            'status' => 'error',
            'message' => 'Method not allowed'
        ]);
    }
    
} catch (Exception $e) {
    http_response_code(500);
    error_log('Error in check-session.php: ' . $e->getMessage());
    echo json_encode([
        'status' => 'error',
        'success' => false,
        'message' => 'An error occurred while checking session',
        'error' => $e->getMessage(),
    ]);
}
?>
