<?php
require_once __DIR__ . '/../config/database.php';
require_once __DIR__ . '/../config/config.php';

use Binali\Config\Database;

class RechargeCardService {
    private $db;
    private $config;

    public function __construct() {
        $this->db = new Database();
        $this->config = new Config($this->db);
    }

    public function getRechargeCardPlans() {
        try {
            $query = "SELECT rc.*, n.networkName 
                     FROM airtimepin rc 
                     JOIN networks n ON rc.aNetwork = n.networkId 
                     WHERE rc.status = 'active'";
            return $this->db->query($query);
        } catch (Exception $e) {
            throw new Exception("Error fetching recharge card plans: " . $e->getMessage());
        }
    }

    public function getAvailableStock($networkId, $amount) {
        try {
            $query = "SELECT COUNT(*) as stock 
                     FROM airtimepinstock 
                     WHERE aNetwork = ? AND amount = ? AND status = 'Unused'";
            $result = $this->db->query($query, [$networkId, $amount]);
            return $result[0]['stock'] ?? 0;
        } catch (Exception $e) {
            throw new Exception("Error checking stock: " . $e->getMessage());
        }
    }

    public function getProviderDetails() {
        try {
            $query = "SELECT 
                        (SELECT value FROM apiconfigs WHERE name = 'rechargePinProvider') as provider,
                        (SELECT value FROM apiconfigs WHERE name = 'rechargePinApi') as apiKey,
                        (SELECT value FROM apiconfigs WHERE name = 'rechargePinMethod') as method";
            return $this->db->query($query);
        } catch (Exception $e) {
            throw new Exception("Error fetching provider details: " . $e->getMessage());
        }
    }

    public function getPinFromStock($networkId, $amount, $quantity) {
        try {
            $query = "SELECT * FROM airtimepinstock 
                     WHERE aNetwork = ? AND amount = ? AND status = 'Unused' 
                     LIMIT ?";
            return $this->db->query($query, [$networkId, $amount, $quantity]);
        } catch (Exception $e) {
            throw new Exception("Error fetching pins: " . $e->getMessage());
        }
    }

    public function markPinsAsUsed($pinIds, $userId) {
        try {
            $query = "UPDATE airtimepinstock 
                     SET status = 'Used', soldto = ?, sold_date = NOW() 
                     WHERE id IN (" . str_repeat('?,', count($pinIds) - 1) . "?)";
            
            $params = array_merge([$userId], $pinIds);
            return $this->db->query($query, $params);
        } catch (Exception $e) {
            throw new Exception("Error updating pins: " . $e->getMessage());
        }
    }
}
?>
