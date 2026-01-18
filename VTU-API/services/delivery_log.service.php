<?php
/**
 * Delivery Log Service
 * Handles logging of daily data plan deliveries to the database
 */

namespace Binali\Services;

use Binali\Config\Database;

class DeliveryLogService {
    private $db;
    
    public function __construct() {
        $this->db = new Database();
    }
    
    /**
     * Log a delivery attempt to the database
     * 
     * @param array $data {
     *     'plan_id' => int,
     *     'user_id' => int,
     *     'phone_number' => string,
     *     'network_id' => int,
     *     'plan_code' => string,
     *     'transaction_ref' => string,
     *     'status' => 'success|failed|pending|retry',
     *     'provider_response' => string (optional, JSON),
     *     'error_message' => string (optional),
     *     'http_code' => int (optional)
     * }
     * @return bool|int Last insert ID or false on failure
     */
    public function logDelivery($data) {
        try {
            $sql = "INSERT INTO delivery_logs 
                    (plan_id, user_id, phone_number, network_id, plan_code, 
                     transaction_ref, status, provider_response, error_message, http_code)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)";
            
            $this->db->query($sql, [
                $data['plan_id'],
                $data['user_id'],
                $data['phone_number'],
                $data['network_id'],
                $data['plan_code'],
                $data['transaction_ref'] ?? null,
                $data['status'] ?? 'pending',
                $data['provider_response'] ?? null,
                $data['error_message'] ?? null,
                $data['http_code'] ?? null
            ]);
            
            return true;
        } catch (Exception $e) {
            error_log("DeliveryLogService Error: " . $e->getMessage());
            return false;
        }
    }
    
    /**
     * Update delivery log status
     * 
     * @param int $logId
     * @param string $status success|failed|pending|retry
     * @param string|null $errorMessage
     * @return bool
     */
    public function updateStatus($logId, $status, $errorMessage = null) {
        try {
            $sql = "UPDATE delivery_logs 
                    SET status = ?, error_message = ? 
                    WHERE id = ?";
            
            $this->db->query($sql, [$status, $errorMessage, $logId]);
            return true;
        } catch (Exception $e) {
            error_log("DeliveryLogService Error: " . $e->getMessage());
            return false;
        }
    }
    
    /**
     * Get delivery logs with optional filters
     * 
     * @param array $filters {
     *     'user_id' => int,
     *     'plan_id' => int,
     *     'status' => string,
     *     'start_date' => YYYY-MM-DD,
     *     'end_date' => YYYY-MM-DD,
     *     'limit' => int,
     *     'offset' => int
     * }
     * @return array
     */
    public function getDeliveryLogs($filters = []) {
        try {
            $sql = "SELECT * FROM delivery_logs WHERE 1=1";
            $params = [];
            
            if (!empty($filters['user_id'])) {
                $sql .= " AND user_id = ?";
                $params[] = $filters['user_id'];
            }
            
            if (!empty($filters['plan_id'])) {
                $sql .= " AND plan_id = ?";
                $params[] = $filters['plan_id'];
            }
            
            if (!empty($filters['status'])) {
                $sql .= " AND status = ?";
                $params[] = $filters['status'];
            }
            
            if (!empty($filters['start_date'])) {
                $sql .= " AND DATE(delivery_date) >= ?";
                $params[] = $filters['start_date'];
            }
            
            if (!empty($filters['end_date'])) {
                $sql .= " AND DATE(delivery_date) <= ?";
                $params[] = $filters['end_date'];
            }
            
            $sql .= " ORDER BY delivery_date DESC";
            
            if (!empty($filters['limit'])) {
                $sql .= " LIMIT " . intval($filters['limit']);
                if (!empty($filters['offset'])) {
                    $sql .= " OFFSET " . intval($filters['offset']);
                }
            }
            
            return $this->db->query($sql, $params);
        } catch (Exception $e) {
            error_log("DeliveryLogService Error: " . $e->getMessage());
            return [];
        }
    }
    
    /**
     * Get delivery statistics for a date range
     * 
     * @param string $startDate YYYY-MM-DD
     * @param string $endDate YYYY-MM-DD
     * @return array
     */
    public function getStatistics($startDate = null, $endDate = null) {
        try {
            $sql = "SELECT 
                        COUNT(*) as total_deliveries,
                        SUM(CASE WHEN status = 'success' THEN 1 ELSE 0 END) as successful,
                        SUM(CASE WHEN status = 'failed' THEN 1 ELSE 0 END) as failed,
                        SUM(CASE WHEN status = 'pending' THEN 1 ELSE 0 END) as pending,
                        SUM(CASE WHEN status = 'retry' THEN 1 ELSE 0 END) as retry,
                        ROUND(SUM(CASE WHEN status = 'success' THEN 1 ELSE 0 END) * 100 / COUNT(*), 2) as success_rate
                    FROM delivery_logs
                    WHERE 1=1";
            
            $params = [];
            
            if ($startDate) {
                $sql .= " AND DATE(delivery_date) >= ?";
                $params[] = $startDate;
            }
            
            if ($endDate) {
                $sql .= " AND DATE(delivery_date) <= ?";
                $params[] = $endDate;
            }
            
            $results = $this->db->query($sql, $params);
            return !empty($results) ? $results[0] : null;
        } catch (Exception $e) {
            error_log("DeliveryLogService Error: " . $e->getMessage());
            return null;
        }
    }
    
    /**
     * Get delivery logs by user
     * 
     * @param int $userId
     * @param int $limit
     * @return array
     */
    public function getUserDeliveryHistory($userId, $limit = 50) {
        return $this->getDeliveryLogs([
            'user_id' => $userId,
            'limit' => $limit
        ]);
    }
}
?>
