<?php
require_once __DIR__ . '/../config/database.php';
require_once __DIR__ . '/../config/config.php';
use Binali\Models;

use PDO;
use PDOException;
use Binali\Config\Database;
use Binali\Config\Config;

class DataPinService {
    private $db;
    private $config;

    public function __construct() {
        $this->db = new Database();
        $this->config = new Config($this->db);
    }

    public function getDataPinPlans($networkId = null, $type = null, $userId = null) {
        try {
            // Determine which price column to expose based on user type
            $priceCol = 'price';
            if ($userId) {
                $u = $this->db->query("SELECT sType FROM subscribers WHERE sId = ?", [$userId]);
                if (!empty($u) && isset($u[0]['sType'])) {
                    $sType = intval($u[0]['sType']);
                    if ($sType === 2) $priceCol = 'agentprice';
                    else if ($sType === 3) $priceCol = 'vendorprice';
                    else $priceCol = 'userprice';
                }
            }

            $query = "SELECT 
                        dpId as id,
                        name,
                        planid as planCode,
                        type,
                        datanetwork as networkId,
                        day as validity,
                        userprice as userPrice,
                        agentprice as agentPrice,
                        vendorprice as vendorPrice,
                        " . $priceCol . " AS price
                     FROM datapins";
            
            $params = [];
            $conditions = [];

            if ($networkId) {
                $conditions[] = "datanetwork = ?";
                $params[] = $networkId;
            }

            if ($type) {
                $conditions[] = "type = ?";
                $params[] = $type;
            }

            if (!empty($conditions)) {
                $query .= " WHERE " . implode(" AND ", $conditions);
            }
            
            $query .= " ORDER BY CAST(price AS DECIMAL(10,2)) ASC";
            
            $result = $this->db->query($query, $params);
            
            if (empty($result)) {
                return [
                    'status' => 'success',
                    'message' => 'No data pin plans found',
                    'data' => []
                ];
            }
            
            return [
                'status' => 'success',
                'message' => 'Data pin plans fetched successfully',
                'data' => $result
            ];
        } catch (Exception $e) {
            return [
                'status' => 'error',
                'message' => "Error fetching data pin plans: " . $e->getMessage(),
                'data' => null
            ];
        }
    }

    public function getProviderDetails() {
        try {
            $query = "SELECT 
                        (SELECT value FROM apiconfigs WHERE name = 'dataPinProvider') as provider,
                        (SELECT value FROM apiconfigs WHERE name = 'dataPinApi') as apiKey";
            return $this->db->query($query);
        } catch (Exception $e) {
            throw new Exception("Error fetching provider details: " . $e->getMessage());
        }
    }

    public function validatePurchase($planId, $quantity, $userType) {
        try {
            // Get plan details
            $query = "SELECT * FROM datapin_plans WHERE planId = ?";
            $plan = $this->db->query($query, [$planId]);
            
            if (empty($plan)) {
                throw new Exception("Invalid plan selected");
            }

            // Get pricing based on user type
            $priceField = $userType . 'Price';
            $unitPrice = $plan[0][$priceField] ?? 0;
            
            if ($unitPrice <= 0) {
                throw new Exception("Invalid pricing for user type");
            }

            return [
                'planDetails' => $plan[0],
                'quantity' => $quantity,
                'unitPrice' => $unitPrice,
                'totalCost' => $unitPrice * $quantity
            ];
        } catch (Exception $e) {
            throw new Exception("Validation error: " . $e->getMessage());
        }
    }

    public function purchaseDataPin($planId, $quantity, $nameOnCard, $userId) {
        try {
            // Get plan details first
            $planQuery = "SELECT * FROM datapins WHERE planid = ?";
            $plan = $this->db->query($planQuery, [$planId]);
            
            if (empty($plan)) {
                throw new Exception("Invalid plan selected");
            }

            // Get user balance
            $balanceQuery = "SELECT sWallet FROM subscribers WHERE sId = ?";
            $userBalance = $this->db->query($balanceQuery, [$userId]);
            
            if (empty($userBalance)) {
                throw new Exception("User not found");
            }

            // Determine user's type and select unit price accordingly
            $u = $this->db->query("SELECT sType, sWallet FROM subscribers WHERE sId = ?", [$userId]);
            if (empty($u)) throw new Exception("User not found");
            $sType = intval($u[0]['sType']);
            $unitPrice = $plan[0]['price'];
            if ($sType === 2 && isset($plan[0]['agentPrice'])) $unitPrice = $plan[0]['agentPrice'];
            else if ($sType === 3 && isset($plan[0]['vendorPrice'])) $unitPrice = $plan[0]['vendorPrice'];

            $totalAmount = $unitPrice * $quantity;
            $currentBalance = $userBalance[0]['sWallet'];

            if ($currentBalance < $totalAmount) {
                throw new Exception("Insufficient balance. Required: ₦{$totalAmount}, Available: ₦{$currentBalance}");
            }

            // Get provider details
            $providerQuery = "SELECT 
                (SELECT value FROM apiconfigs WHERE name = 'dataPinApi') as apiKey,
                (SELECT value FROM apiconfigs WHERE name = 'dataPinProvider') as provider";
            $provider = $this->db->query($providerQuery);

            if (empty($provider)) {
                throw new Exception("Provider configuration not found");
            }

            // Make API request first
            $curl = curl_init();
            curl_setopt_array($curl, [
                CURLOPT_URL => $provider[0]['provider'],
                CURLOPT_RETURNTRANSFER => true,
                CURLOPT_ENCODING => '',
                CURLOPT_MAXREDIRS => 10,
                CURLOPT_TIMEOUT => 30,
                CURLOPT_HTTP_VERSION => CURL_HTTP_VERSION_1_1,
                CURLOPT_CUSTOMREQUEST => 'POST',
                CURLOPT_POSTFIELDS => json_encode([
                    'plan' => $planId,
                    'quantity' => $quantity,
                    'name_on_card' => $nameOnCard,
                    'network' => $plan[0]['datanetwork']
                ]),
                CURLOPT_HTTPHEADER => [
                    'Authorization: Token ' . $provider[0]['apiKey'],
                    'Content-Type: application/json'
                ],
            ]);

            $response = curl_exec($curl);
            $err = curl_error($curl);
            curl_close($curl);

            if ($err) {
                throw new Exception("API Error: " . $err);
            }

            $apiResponse = json_decode($response, true);
            if (!$apiResponse) {
                throw new Exception("Invalid API response");
            }

            // Check API response status
            if (isset($apiResponse['status']) && ($apiResponse['status'] === 'error' || $apiResponse['status'] === 'fail')) {
                throw new Exception($apiResponse['message'] ?? 'API returned an error');
            }

            // Verify we have the pins in the response
            if (!isset($apiResponse['pins']) || empty($apiResponse['pins'])) {
                throw new Exception("No data pins received in the response");
            }

            // Start transaction only after confirming we have pins
            $this->db->beginTransaction();

            // Deduct user balance
            $updateBalanceQuery = "UPDATE subscribers SET sWallet = sWallet - ? WHERE sId = ?";
            $this->db->query($updateBalanceQuery, [$totalAmount, $userId]);

            // Record transaction
            $reference = 'DPIN_' . time() . rand(1000, 9999);
            $description = "{$quantity} {$plan[0]['name']} data pin(s)";
            
            $insertTxnQuery = "INSERT INTO transactions (
                sId, transref, servicename, servicedesc, amount, status, oldbal, newbal, api_response
            ) VALUES (?, ?, 'data_pin', ?, ?, ?, ?, ?, ?)";
            
            $this->db->query($insertTxnQuery, [
                $userId,
                $reference,
                $description,
                $totalAmount,
                1, // success
                $currentBalance,
                ($currentBalance - $totalAmount),
                $response
            ]);

            $this->db->commit();
            
            return [
                'status' => 'success',
                'message' => 'Data pin purchase successful',
                'data' => [
                    'reference' => $reference,
                    'amount' => $totalAmount,
                    'pins' => $apiResponse['pins'] ?? []
                ]
            ];

        } catch (Exception $e) {
            if (isset($this->db) && $this->db->inTransaction()) {
                $this->db->rollBack();

                // Refund user if needed
                if (isset($totalAmount) && isset($userId)) {
                    try {
                        $this->db->beginTransaction();
                        $this->db->query("UPDATE subscribers SET sWallet = sWallet + ? WHERE sId = ?", 
                            [$totalAmount, $userId]);
                        
                        // Record failed transaction
                        $reference = 'DPIN_' . time() . rand(1000, 9999);
                        $this->db->query(
                            "INSERT INTO transactions (sId, transref, servicename, servicedesc, amount, status, oldbal, newbal, api_response_log) 
                             VALUES (?, ?, 'data_pin', ?, ?, 2, ?, ?, ?)",
                            [
                                $userId,
                                $reference,
                                $description ?? "Data pin purchase failed",
                                $totalAmount,
                                $currentBalance ?? 0,
                                $currentBalance ?? 0,
                                $e->getMessage()
                            ]
                        );
                        $this->db->commit();
                    } catch (Exception $e2) {
                        error_log("Failed to record failed transaction: " . $e2->getMessage());
                        $this->db->rollBack();
                    }
                }
            }

            return [
                'status' => 'error',
                'message' => $e->getMessage(),
                'data' => null
            ];
        }
    }
}
?>
