<?php
/**
 * Renew Session Endpoint
 * Verifies user password and renews session without full re-login
 * Expects: user_id and password via POST
 */

header('Content-Type: application/json; charset=UTF-8');
header("Access-Control-Allow-Origin: *");
header("Access-Control-Allow-Methods: POST, OPTIONS");
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
    
    if ($request_method === 'POST') {
        // Get JSON data from request body
        $input = json_decode(file_get_contents('php://input'), true);
        
        if (!$input) {
            http_response_code(400);
            echo json_encode([
                'status' => 'error',
                'success' => false,
                'message' => 'Invalid request format'
            ]);
            exit();
        }
        
        $user_id = $input['user_id'] ?? null;
        $password = $input['password'] ?? null;
        
        if (!$user_id || !$password) {
            http_response_code(400);
            echo json_encode([
                'status' => 'error',
                'success' => false,
                'message' => 'User ID and password are required'
            ]);
            exit();
        }
        
        // Query database for user
        $conn = new mysqli(DB_HOST, DB_USER, DB_PASS, DB_NAME);
        if ($conn->connect_error) {
            throw new Exception('Database connection failed: ' . $conn->connect_error);
        }
        
        // Prepare and execute query
        $stmt = $conn->prepare('SELECT sId, sPass, sFname, sLname, sEmail FROM subscribers WHERE sId = ?');
        $stmt->bind_param('i', $user_id);
        $stmt->execute();
        $result = $stmt->get_result();
        
        if ($result->num_rows === 0) {
            http_response_code(401);
            echo json_encode([
                'status' => 'error',
                'success' => false,
                'message' => 'User not found'
            ]);
            $stmt->close();
            $conn->close();
            exit();
        }
        
        $user = $result->fetch_assoc();
        $stmt->close();
        
        // Verify password using the same method as login
        $computedHash = substr(sha1(md5($password)), 3, 10);
        if (!hash_equals($user['sPass'], $computedHash)) {
            http_response_code(401);
            echo json_encode([
                'status' => 'error',
                'success' => false,
                'message' => 'Invalid password'
            ]);
            $conn->close();
            exit();
        }
        
        // Initialize and renew session
        initializeSession();
        
        // Set authenticated user in session
        setAuthenticatedUser($user['sId'], $user['sFname'], $user['sLname'], $user['sEmail']);
        
        // Update last activity
        $_SESSION['last_activity'] = time();
        
        $conn->close();
        
        // Session renewed successfully
        http_response_code(200);
        echo json_encode([
            'status' => 'success',
            'success' => true,
            'message' => 'Session renewed successfully',
            'data' => [
                'user_id' => $user['sId'],
                'name' => $user['sFname'] . ' ' . $user['sLname'],
                'email' => $user['sEmail'],
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
    error_log('Error in renew-session.php: ' . $e->getMessage());
    echo json_encode([
        'status' => 'error',
        'success' => false,
        'message' => 'An error occurred while renewing session',
        'error' => $e->getMessage(),
    ]);
}
?>
