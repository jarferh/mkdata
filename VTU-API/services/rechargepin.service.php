<?php
require_once __DIR__ . '/../config/database.php';
require_once __DIR__ . '/../config/config.php';

use Binali\Config\Database;
use Binali\Config\Config;

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

    public function purchaseRechargePin($planId, $quantity, $userId, $pin) {
        try {
            // Card PIN purchase is not fully implemented yet
            // The external provider integration is missing
            // Return failure but still record the transaction attempt
            error_log("RechargePinService: Card PIN purchase attempted but not implemented. PlanId=$planId, Quantity=$quantity, UserId=$userId");

            // Get network price for record keeping
            $networkPrices = [
                'MTN' => 1000,
                'Airtel' => 1000,
                'Glo' => 1000,
                '9mobile' => 1000,
            ];
            
            if (!isset($networkPrices[$planId])) {
                throw new Exception("Invalid network or plan: $planId");
            }

            $price = $networkPrices[$planId];
            $totalAmount = $price * $quantity;

            // Get user balance for record
            $userQuery = "SELECT sWallet FROM subscribers WHERE sId = ?";
            $userResult = $this->db->query($userQuery, [$userId]);
            
            if (empty($userResult)) {
                throw new Exception("User not found");
            }

            $userBalance = $userResult[0]['sWallet'] ?? 0;
            $transactionRef = "CARD_PIN_" . time() . "_" . rand(1000, 9999);

            // Record failed transaction attempt (don't deduct balance)
            $transactionQuery = "INSERT INTO transactions 
                                (sId, transref, servicename, servicedesc, amount, status, oldbal, newbal, date) 
                                VALUES (?, ?, ?, ?, ?, ?, ?, ?, NOW())";
            
            $this->db->execute($transactionQuery, [
                $userId,
                $transactionRef,
                'card_pin',
                'Card PIN Purchase Attempt - ' . $planId,
                $totalAmount,
                2,  // status: 2 = pending/failed
                $userBalance,
                $userBalance  // balance unchanged
            ]);

            $transactionId = $this->db->lastInsertId();
            error_log("RechargePinService: Failed transaction recorded. TransactionID=$transactionId, Reference=$transactionRef");

            return [
                'status' => 'error',
                'message' => 'Card PIN purchase service is currently unavailable. Please try again later.',
                'data' => [
                    'transactionId' => $transactionId,
                    'amount' => $totalAmount,
                    'quantity' => $quantity,
                    'reference' => $transactionRef,
                    'status' => 'failed'
                ]
            ];

        } catch (Exception $e) {
            error_log("RechargePinService: Error - " . $e->getMessage());
            
            return [
                'status' => 'error',
                'message' => $e->getMessage(),
                'data' => null
            ];
        }
    }
}
