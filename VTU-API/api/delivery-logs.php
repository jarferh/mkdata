<?php
header("Access-Control-Allow-Origin: *");
header("Content-Type: application/json; charset=UTF-8");
header("Access-Control-Allow-Methods: GET, POST, OPTIONS");
header("Access-Control-Max-Age: 3600");
header("Access-Control-Allow-Headers: Content-Type, Access-Control-Allow-Headers, Authorization, X-Requested-With");

if ($_SERVER['REQUEST_METHOD'] == 'OPTIONS') {
    http_response_code(200);
    exit();
}

include_once '../config/database.php';
include_once '../services/delivery_log.service.php';

use Binali\Config\Database;
use Binali\Services\DeliveryLogService;

try {
    $logService = new DeliveryLogService();
    
    // Get request method and parameters
    $method = $_SERVER['REQUEST_METHOD'];
    $data = json_decode(file_get_contents("php://input"), true);
    
    if ($method === 'GET') {
        // Get delivery logs with filters
        $userId = $_GET['user_id'] ?? null;
        $planId = $_GET['plan_id'] ?? null;
        $status = $_GET['status'] ?? null;
        $startDate = $_GET['start_date'] ?? null;
        $endDate = $_GET['end_date'] ?? null;
        $limit = intval($_GET['limit'] ?? 50);
        $offset = intval($_GET['offset'] ?? 0);
        
        // Validate user_id if provided (for security)
        if ($userId && !is_numeric($userId)) {
            http_response_code(400);
            echo json_encode(['success' => false, 'message' => 'Invalid user_id']);
            exit();
        }
        
        $filters = [
            'user_id' => $userId,
            'plan_id' => $planId,
            'status' => $status,
            'start_date' => $startDate,
            'end_date' => $endDate,
            'limit' => $limit,
            'offset' => $offset
        ];
        
        $logs = $logService->getDeliveryLogs($filters);
        
        http_response_code(200);
        echo json_encode([
            'success' => true,
            'data' => $logs,
            'count' => count($logs)
        ]);
        
    } elseif ($method === 'POST') {
        // Get statistics
        $startDate = $data['start_date'] ?? null;
        $endDate = $data['end_date'] ?? null;
        
        $stats = $logService->getStatistics($startDate, $endDate);
        
        http_response_code(200);
        echo json_encode([
            'success' => true,
            'data' => $stats
        ]);
        
    } else {
        http_response_code(405);
        echo json_encode(['success' => false, 'message' => 'Method not allowed']);
    }
    
} catch (Exception $e) {
    error_log("Delivery logs API error: " . $e->getMessage());
    http_response_code(500);
    echo json_encode([
        'success' => false,
        'message' => 'Server error: ' . $e->getMessage()
    ]);
}
?>
