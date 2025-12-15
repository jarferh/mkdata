<?php
use Binali\Models;

use PDO;
use PDOException;
use Binali\Config\Database;
use Binali\Config\Config;
require_once __DIR__ . '/../config/database.php';
require_once __DIR__ . '/../config/config.php';

class AirtimeService {
    private $db;
    private $config;
    private $networkNames = [
        1 => "MTN",
        2 => "GLO",
        3 => "9MOBILE",
        4 => "AIRTEL"
    ];

    public function __construct() {
        $this->db = new Database();
        $this->config = new Config($this->db);
    }

    private function getNetworkName($networkId) {
        return $this->networkNames[$networkId] ?? null;
    }

    public function getAirtimePlans() {
        try {
            $query = "SELECT a.*, n.networkName 
                     FROM airtime a 
                     JOIN networks n ON a.aNetwork = n.networkId";
            return $this->db->query($query);
        } catch (Exception $e) {
            throw new Exception("Error fetching airtime plans: " . $e->getMessage());
        }
    }

    public function getAirtimePinPlans() {
        try {
            $query = "SELECT ap.*, n.networkName 
                     FROM airtimepin ap 
                     JOIN networks n ON ap.aNetwork = n.networkId";
            return $this->db->query($query);
        } catch (Exception $e) {
            throw new Exception("Error fetching airtime pin plans: " . $e->getMessage());
        }
    }

    public function getAirtimeProviderDetails($networkId, $type) {
        try {
            // Debug log the parameters
            error_log("Getting provider details for networkId: " . $networkId . ", type: " . $type);
            
            // Map network IDs to config prefixes
            $networkPrefix = [
                1 => 'mtn',
                2 => 'glo',
                3 => '9mobile',
                4 => 'airtel'
            ];
            
            $prefix = $networkPrefix[$networkId] ?? null;
            if (!$prefix) {
                throw new Exception("Invalid network ID: " . $networkId);
            }
            
            $keyName = $prefix . ucfirst($type) . "Key";
            $providerName = $prefix . ucfirst($type) . "Provider";
            
            error_log("Looking for config names: keyName=" . $keyName . ", providerName=" . $providerName);

            // Fetch both configurations directly
            $query = "SELECT 
                        (SELECT value FROM apiconfigs WHERE name = ?) as apiKey,
                        (SELECT value FROM apiconfigs WHERE name = ?) as provider";
            
            $result = $this->db->query($query, [$keyName, $providerName]);
            error_log("Provider details result: " . json_encode($result));
            
            if (empty($result) || !isset($result[0]['apiKey']) || !isset($result[0]['provider'])) {
                throw new Exception("Provider configuration not found for network " . $networkPrefix[$networkId]);
            }
            
            return $result;
        } catch (Exception $e) {
            error_log("Error in getAirtimeProviderDetails: " . $e->getMessage());
            throw new Exception("Error fetching provider details: " . $e->getMessage());
        }
    }

    private function getNetworkId($network) {
        // Convert string network names to IDs
        $networkMap = [
            'MTN' => 1,
            'GLO' => 2,
            '9MOBILE' => 3,
            'AIRTEL' => 4
        ];
        
        if (is_numeric($network)) {
            return (int)$network;
        }
        
        return $networkMap[strtoupper($network)] ?? null;
    }

    public function purchaseAirtime($network, $phone, $amount, $userId, $airtimeType = 'VTU') {
        try {
            // Convert network name to ID if needed
            $networkId = $this->getNetworkId($network);
            if ($networkId === null) {
                throw new Exception("Invalid network provider");
            }

            // Debug log
            error_log("Starting airtime purchase with params: " . json_encode([
                'network' => $network,
                'networkId' => $networkId,
                'phone' => $phone,
                'amount' => $amount,
                'userId' => $userId,
                'airtimeType' => $airtimeType
            ]));

            // Validate user exists and get their type and balance
            $query = "SELECT sWallet, sType FROM subscribers WHERE sId = ?";
            error_log("Executing query: " . $query . " with userId: " . $userId);
            $user = $this->db->query($query, [$userId]);
            error_log("Query result: " . json_encode($user));
            if (empty($user)) {
                throw new Exception("User not found");
            }

            $wallet = floatval($user[0]['sWallet']);
            $sType = intval($user[0]['sType']);
            error_log("User wallet balance: " . $wallet . ", sType: " . $sType);

            // Fetch airtime pricing/discount information for the network
            $airConf = $this->db->query("SELECT * FROM airtime WHERE aNetwork = ? LIMIT 1", [strval($networkId)]);
            $airConf = !empty($airConf) ? $airConf[0] : null;

            // Determine the applicable discount/value to compute charge to user
            // Default to 100 (i.e., user pays full face amount) if not set
            $userDiscount = isset($airConf['aUserDiscount']) ? floatval($airConf['aUserDiscount']) : 100.0;
            $agentDiscount = isset($airConf['aAgentDiscount']) ? floatval($airConf['aAgentDiscount']) : $userDiscount;
            $vendorDiscount = isset($airConf['aVendorDiscount']) ? floatval($airConf['aVendorDiscount']) : $userDiscount;

            // Select discount based on sType: 1=subscriber, 2=agent, 3=vendor
            if ($sType === 2) {
                $selectedDiscount = $agentDiscount;
            } elseif ($sType === 3) {
                $selectedDiscount = $vendorDiscount;
            } else {
                $selectedDiscount = $userDiscount;
            }

            // Interpret discount as percentage to multiply face amount (e.g., 100 => 100% => pay full amount)
            $multiplier = max(0.0, $selectedDiscount) / 100.0;
            $faceAmount = floatval($amount);
            $chargeAmount = round($faceAmount * $multiplier, 2);

            error_log("Airtime pricing: faceAmount=" . $faceAmount . ", selectedDiscount=" . $selectedDiscount . ", chargeAmount=" . $chargeAmount);

            if ($wallet < $chargeAmount) {
                throw new Exception("Insufficient balance");
            }

            // Create reference for tracking
            $reference = 'AIR' . time() . rand(1000, 9999);
            
            // Get provider details for the network based on airtime type
            $type = $airtimeType === 'VTU' ? 'Vtu' : 'Sharesell';
            $providerDetails = $this->getAirtimeProviderDetails($networkId, $type);
            if (empty($providerDetails)) {
                throw new Exception("Provider configuration not found for network ID: $networkId");
            }
            
            error_log("Provider details: " . json_encode($providerDetails));
            
            // Prepare API call
            $apiUrl = $providerDetails[0]['provider'];
            $apiKey = $providerDetails[0]['apiKey'];

            // Prepare API call using ALRAHUZDATA API
            $curl = curl_init();
            
            // Set up request to ALRAHUZDATA API
            curl_setopt_array($curl, options: [
                CURLOPT_URL => "$apiUrl",
                CURLOPT_RETURNTRANSFER => true,
                CURLOPT_CUSTOMREQUEST => "POST",
                CURLOPT_POSTFIELDS => json_encode([
                    "network" => $networkId,
                    "network_id" => $networkId,
                    "amount" => $amount,
                    "mobile_number" => $phone,
                    "Ported_number" => true,
                    "airtime_type" => $airtimeType,
                    "phone" => $phone,
                    "ref" => (string)(time() . mt_rand(1000, 9999)),
                ]),
                CURLOPT_HTTPHEADER => (strpos($apiUrl, 'smeplug.ng') !== false)
                    ? [
                        "Authorization: Bearer " . $apiKey,
                        "Content-Type: application/json"
                    ]
                    : [
                        "Authorization: Token " . $apiKey,
                        "Content-Type: application/json"
                    ]
            ]);

            $response = curl_exec($curl);
            $err = curl_error($curl);
            $httpCode = curl_getinfo($curl, CURLINFO_HTTP_CODE);
            curl_close($curl);

            error_log("API Response Code: " . $httpCode);
            error_log("API Response: " . $response);
            error_log("API Error (if any): " . $err);

            if ($err) {
                throw new Exception("Server Connection Error: " . $err);
            }

            if ($httpCode >= 500) {
                throw new Exception("Server error occurred. Please try again later. Status: " . $httpCode);
            }

            $result = json_decode($response, true);
            
            // Create transaction record. Initialize newbal to current wallet; we'll update it after provider response
            $oldBal = $wallet;
            $newBal = $wallet; // assume no change until provider confirms success

            // Use chargeAmount as the amount to record and deduct; provider receives faceAmount
            $insertQuery = "INSERT INTO transactions (sId, transref, servicename, servicedesc, amount, status, oldbal, newbal, profit, date, api_response, api_response_log) 
                          VALUES (?, ?, 'airtime', ?, ?, ?, ?, ?, 0, NOW(), ?, ?)";
            
            // Get API Status based on ALRAHUZDATA response format
            $transactionStatus = 0;
            $responseMessage = "Transaction Failed, Please Try Again Later";

        if ($httpCode === 200 || $httpCode === 201) {
                if (isset($result['Status']) && strtolower($result['Status']) === 'successful' OR isset($result['Status']) && strtolower($result['Status']) === 'success' ) {
                    $transactionStatus = 0;
                    $responseMessage = "Airtime purchase successful";
                    
                    // Deduct from wallet on success
            $updateQuery = "UPDATE subscribers SET sWallet = sWallet - ? WHERE sId = ?";
            $this->db->query($updateQuery, [$chargeAmount, $userId]);
                } elseif (isset($result['Status']) && strtolower($result['Status']) === 'pending') {
                    $transactionStatus = 2;
                    $responseMessage = "Transaction is processing";
                    error_log("Airtime processing log: " . json_encode($result));
                } else {
                    $transactionStatus = 1;
                    $responseMessage = isset($result['message']) ? $result['message'] : "Transaction failed";
                    error_log("Airtime fail log: " . json_encode($result));
                }
            } else {
                $transactionStatus = 2;
                $responseMessage = "Transaction failed due to server error";
                error_log("Airtime fail log: " . json_encode($result));
            }
            
            // Calculate profit (if any)
            $profit = 0; // Set profit calculation logic here if needed
            
            // Insert transaction record - ensure all values are properly formatted
            $this->db->query($insertQuery, [
                $userId, 
                $reference,
                "Airtime purchase for $phone",
                (string)$chargeAmount, // store charged amount
                (int)$transactionStatus, // Cast to int as status is tinyint in DB
                (string)$oldBal, // Cast to string as oldbal is VARCHAR in DB
                (string)$newBal, // Cast to string as newbal is VARCHAR in DB
                $response,
                "API Error: " . $err . "\nAPI Response: " . $response
            ]);

            $transIdQuery = "SELECT LAST_INSERT_ID() as id";
            $transResult = $this->db->query($transIdQuery);
            $transactionId = $transResult[0]['id'];

            // After creating the record and determining transaction status, ensure newbal reflects actual result
            $finalNewBal = ($transactionStatus === 0) ? ($wallet - $chargeAmount) : $wallet;
            try {
                $this->db->query("UPDATE transactions SET status = ?, newbal = ? WHERE tId = ?", [(int)$transactionStatus, (string)$finalNewBal, $transactionId]);
            } catch (Exception $e) {
                error_log("Failed to update transaction newbal/status: " . $e->getMessage());
            }

            // Generate MK transaction ID
            $binTransactionId = 'MK_' . strtoupper(substr(uniqid() . bin2hex(random_bytes(4)), 0, 15));
            
            // Map internal transactionStatus to API response status:
            // 0 => success, 1 => failed, 2 => processing
            if ($transactionStatus === 0) {
                return [
                    'status' => 'success',
                    'message' => $responseMessage,
                    'data' => [
                        'transactionId' => $binTransactionId,
                        'reference' => $reference,
                        'amount' => $faceAmount,
                        'charged' => $chargeAmount,
                        'phone' => $phone,
                        'network' => $network,
                        'status' => 'successful'
                    ]
                ];
            } else if ($transactionStatus === 2) {
                return [
                    'status' => 'processing',
                    'message' => $responseMessage,
                    'data' => [
                        'transactionId' => $binTransactionId,
                        'reference' => $reference
                    ]
                ];
            } else {
                return [
                    'status' => 'failed',
                    'message' => $responseMessage,
                    'data' => [
                        'transactionId' => $binTransactionId,
                        'reference' => $reference,
                        'amount' => $faceAmount,
                        'charged' => $chargeAmount,
                        'phone' => $phone,
                        'network' => $network,
                        'status' => 'failed'
                    ]
                ];
            }
        } catch (Exception $e) {
            $errorMessage = $e->getMessage();
            error_log("Airtime purchase error: " . $errorMessage);
            
            // Log the error
            error_log("Airtime error log: " . $errorMessage);
            
            // Create failed transaction record if we have the necessary info
            if (isset($userId) && isset($reference) && isset($amount) && isset($phone)) {
                try {
                    $insertQuery = "INSERT INTO transactions (sId, transref, servicename, servicedesc, amount, status, oldbal, newbal, profit, date, api_response_log) 
                                  VALUES (?, ?, 'airtime', ?, ?, 1, ?, ?, 0, NOW(), ?)";
                    $this->db->query($insertQuery, [
                        $userId,
                        $reference,
                        "Failed airtime purchase for $phone",
                        (string)$amount,
                        (string)($wallet ?? '0'),
                        (string)($wallet ?? '0'),
                        $errorMessage
                    ]);
                } catch (Exception $logError) {
                    error_log("Error logging failed transaction: " . $logError->getMessage());
                }
            }

            // Generate MK transaction ID for failed transaction
            $binTransactionId = 'MK_' . strtoupper(substr(uniqid() . bin2hex(random_bytes(4)), 0, 15));

            // Return error response
            return [
                'status' => 'failed',
                'message' => $errorMessage,
                'data' => [
                    'transactionId' => $binTransactionId,
                    'phone' => $phone ?? null,
                    'amount' => $amount ?? null,
                    'reference' => $reference ?? null,
                    'status' => 'failed'
                ]
            ];
        }
    }
}
?>
