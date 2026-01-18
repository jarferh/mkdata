<?php
/**
 * Debug Endpoint - Destroy Session by User ID
 * ONLY FOR TESTING - Remove in production
 * Accepts user_id parameter to destroy that user's session
 * Call this endpoint to deliberately expire a user's session
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

try {
    // Get user_id from GET or POST
    $user_id = $_GET['user_id'] ?? $_POST['user_id'] ?? null;
    
    if (!$user_id) {
        http_response_code(400);
        echo json_encode([
            'status' => 'error',
            'message' => 'user_id parameter is required',
            'example' => 'GET: /api/debug-destroy-session.php?user_id=1',
            'example_post' => 'POST: /api/debug-destroy-session.php with {"user_id": 1}'
        ]);
        exit();
    }
    
    // Get session directory
    $session_save_path = session_save_path();
    if (empty($session_save_path) || $session_save_path === 'N/A') {
        $session_save_path = sys_get_temp_dir();
    }
    
    // Find and delete session file for this user
    $session_files = glob($session_save_path . '/sess_*');
    $found = false;
    $deleted_sessions = [];
    
    foreach ($session_files as $session_file) {
        if (is_file($session_file)) {
            $session_data = file_get_contents($session_file);
            
            // Check if this session contains the user_id
            if (strpos($session_data, (string)$user_id) !== false) {
                // Found a session for this user, delete it
                if (unlink($session_file)) {
                    $found = true;
                    $deleted_sessions[] = basename($session_file);
                }
            }
        }
    }
    
    if ($found) {
        http_response_code(200);
        echo json_encode([
            'status' => 'success',
            'message' => 'User session(s) destroyed successfully',
            'user_id' => $user_id,
            'deleted_sessions' => $deleted_sessions,
            'session_count' => count($deleted_sessions),
            'test_flow' => [
                'step_1' => 'Go to WelcomePage (lock screen)',
                'step_2' => 'Enter your PIN or use biometric',
                'step_3' => 'Password verification dialog should appear',
                'step_4' => 'Enter your password to renew session',
                'step_5' => 'If correct, session renewed and dashboard loads'
            ]
        ]);
    } else {
        http_response_code(404);
        echo json_encode([
            'status' => 'warning',
            'message' => 'No active session found for this user_id',
            'user_id' => $user_id,
            'note' => 'User might already be logged out or session already expired'
        ]);
    }
    
} catch (Exception $e) {
    http_response_code(500);
    echo json_encode([
        'status' => 'error',
        'message' => 'Error destroying session: ' . $e->getMessage(),
    ]);
}
?>

