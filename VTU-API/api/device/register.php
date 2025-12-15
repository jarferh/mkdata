<?php
/**
 * Device Token Registration Endpoint
 * 
 * POST /api/device/register
 * 
 * Accepts:
 *   user_id (string|int): User ID
 *   fcm_token (string): FCM device token
 *   device_type (string): android|ios|web
 *   device_name (string, optional): Device model/name
 * 
 * Prevents duplicate tokens and handles updates
 */

header("Access-Control-Allow-Origin: *");
header("Content-Type: application/json; charset=UTF-8");
header("Access-Control-Allow-Methods: POST, OPTIONS");
header("Access-Control-Allow-Headers: Content-Type, Authorization");

if ($_SERVER['REQUEST_METHOD'] === 'OPTIONS') {
    http_response_code(200);
    exit();
}

// Use correct path relative to this file's location (api/device/register.php)
// We need to go up two levels: device/ -> api/ -> VTU-API/db/
require_once __DIR__ . '/../../db/database.php';

$response = [
    'status' => 'error',
    'message' => 'Invalid request',
    'data' => null
];

try {
    if ($_SERVER['REQUEST_METHOD'] !== 'POST') {
        http_response_code(405);
        throw new Exception('Method not allowed');
    }
    
    $input = json_decode(file_get_contents('php://input'), true);
    
    $userId = $input['user_id'] ?? null;
    $fcmToken = $input['fcm_token'] ?? null;
    $deviceType = $input['device_type'] ?? 'android';
    $deviceName = $input['device_name'] ?? null;
    
    // Validate required fields
    if (empty($userId) || empty($fcmToken)) {
        http_response_code(400);
        throw new Exception('Missing required parameters: user_id, fcm_token');
    }
    
    // Validate device type
    $validDeviceTypes = ['android', 'ios', 'web'];
    if (!in_array($deviceType, $validDeviceTypes)) {
        http_response_code(400);
        throw new Exception('Invalid device_type. Must be: ' . implode(', ', $validDeviceTypes));
    }
    
    // Ensure token is reasonable length (FCM tokens are ~150+ chars)
    if (strlen($fcmToken) < 50) {
        http_response_code(400);
        throw new Exception('Invalid FCM token format');
    }
    
    $db = new Database();
    
    // Check if user exists
    $userCheck = $db->query(
        "SELECT sId FROM subscribers WHERE sId = ? LIMIT 1",
        [$userId]
    );
    
    if (empty($userCheck)) {
        http_response_code(404);
        throw new Exception('User not found');
    }
    
    // Check if token already exists for this user
    $existingToken = $db->query(
        "SELECT id FROM user_devices WHERE user_id = ? AND fcm_token = ? LIMIT 1",
        [$userId, $fcmToken]
    );
    
    if (!empty($existingToken)) {
        // Token already registered for this user, just update last_used
        $updateQuery = "UPDATE user_devices 
                       SET last_used = CURRENT_TIMESTAMP, is_active = 1, device_type = ?, device_name = ?
                       WHERE user_id = ? AND fcm_token = ?";
        
        $db->query($updateQuery, [$deviceType, $deviceName, $userId, $fcmToken], false);
        
        $response['status'] = 'success';
        $response['message'] = 'Device token updated';
        $response['data'] = [
            'device_id' => $existingToken[0]['id'],
            'action' => 'updated'
        ];
        http_response_code(200);
    } else {
        // New token - check if token exists for another user and deactivate it
        // (tokens should be unique, but handle migration cases)
        $conflictingToken = $db->query(
            "SELECT id, user_id FROM user_devices WHERE fcm_token = ? LIMIT 1",
            [$fcmToken]
        );
        
        if (!empty($conflictingToken)) {
            // Deactivate old token association
            $db->query(
                "UPDATE user_devices SET is_active = 0 WHERE fcm_token = ?",
                [$fcmToken],
                false
            );
            error_log("Device token reassigned from user {$conflictingToken[0]['user_id']} to user {$userId}");
        }
        
        // Insert new device token
        $insertQuery = "INSERT INTO user_devices (user_id, fcm_token, device_type, device_name, is_active)
                       VALUES (?, ?, ?, ?, 1)";
        
        $affectedRows = $db->query($insertQuery, [$userId, $fcmToken, $deviceType, $deviceName], false);
        
        if ($affectedRows) {
            $newDeviceId = $db->lastInsertId();
            
            $response['status'] = 'success';
            $response['message'] = 'Device token registered successfully';
            $response['data'] = [
                'device_id' => $newDeviceId,
                'action' => 'created'
            ];
            http_response_code(201);
        } else {
            throw new Exception('Failed to register device token');
        }
    }
    
} catch (Exception $e) {
    error_log('Device registration error: ' . $e->getMessage());
    
    if ($response['status'] !== 'error') {
        http_response_code(500);
    }
    
    $response['status'] = 'error';
    $response['message'] = $e->getMessage();
}

echo json_encode($response);
exit();
?>
