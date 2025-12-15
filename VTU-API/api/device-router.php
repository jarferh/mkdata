<?php
/**
 * API Router - routes /api/* requests to appropriate handlers
 * 
 * This file extends the main index.php router to handle device management endpoints
 */

// The main router (index.php) handles most endpoints.
// For cleaner code, device-related endpoints are handled here.

$uri = parse_url($_SERVER['REQUEST_URI'], PHP_URL_PATH);
$requestMethod = $_SERVER['REQUEST_METHOD'];

// Check if this is a device management request
if (strpos($uri, '/api/device/') === 0) {
    // Route to device handlers
    $deviceEndpoint = str_replace('/api/device/', '', $uri);
    $deviceEndpoint = trim($deviceEndpoint, '/');
    
    switch ($deviceEndpoint) {
        case 'register':
            require_once __DIR__ . '/device/register.php';
            return;
        default:
            http_response_code(404);
            echo json_encode([
                'status' => 'error',
                'message' => 'Device endpoint not found'
            ]);
            exit();
    }
}

// If not a device endpoint, continue to main router
// (This file should be included/required from index.php or you can update index.php directly)
?>
