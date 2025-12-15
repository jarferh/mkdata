<?php
require_once __DIR__ . '/../config/database.php';
require_once __DIR__ . '/../config/config.php';

use Binali\Config\Database;

class RechargePinService {
    private $db;
    private $config;

    public function __construct() {
        $this->db = new Database();
        $this->config = new Config($this->db);
    }

    public function getAvailablePins($networkId) {
        try {
            $query = "SELECT rp.*, n.networkName 
                     FROM rechargepins rp 
                     JOIN networks n ON rp.networkId = n.networkId 
                     WHERE rp.networkId = ? AND rp.status = 'active'";
            return $this->db->query($query, [$networkId]);
        } catch (Exception $e) {
            throw new Exception("Error fetching available pins: " . $e->getMessage());
        }
    }

    public function getPricing($networkId) {
        try {
            $query = "SELECT * FROM rechargepinprice WHERE networkId = ?";
            return $this->db->query($query, [$networkId]);
        } catch (Exception $e) {
            throw new Exception("Error fetching pricing: " . $e->getMessage());
        }
    }

    public function getProviderDetails() {
        try {
            $query = "SELECT 
                        (SELECT value FROM apiconfigs WHERE name = 'rechargePinProvider') as provider,
                        (SELECT value FROM apiconfigs WHERE name = 'rechargePinApi') as apiKey";
            return $this->db->query($query);
        } catch (Exception $e) {
            throw new Exception("Error fetching provider details: " . $e->getMessage());
        }
    }

    public function validatePurchase($networkId, $amount, $quantity, $userType) {
        try {
            // Get pricing for user type
            $pricing = $this->getPricing($networkId);
            if (empty($pricing)) {
                throw new Exception("Invalid network or pricing not found");
            }

            // Calculate total cost based on user type discount
            $discountField = $userType . 'Discount';
            $discount = $pricing[0][$discountField] ?? 0;
            $totalCost = ($amount * $quantity * (100 - $discount)) / 100;

            return [
                'discount' => $discount,
                'totalCost' => $totalCost,
                'quantity' => $quantity,
                'unitCost' => $amount
            ];
        } catch (Exception $e) {
            throw new Exception("Validation error: " . $e->getMessage());
        }
    }

    public function recordTransaction($userId, $networkId, $amount, $quantity, $totalCost, $reference) {
        try {
            $query = "INSERT INTO rechargepin_transactions 
                     (userId, networkId, amount, quantity, totalCost, reference, created_at) 
                     VALUES (?, ?, ?, ?, ?, ?, NOW())";
            
            return $this->db->query($query, [
                $userId, $networkId, $amount, $quantity, $totalCost, $reference
            ]);
        } catch (Exception $e) {
            throw new Exception("Error recording transaction: " . $e->getMessage());
        }
    }
}
?>
