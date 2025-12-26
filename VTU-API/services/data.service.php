<?php
require_once __DIR__ . '/../config/database.php';
require_once __DIR__ . '/../api/notifications/send.php';

use Binali\Config\Database;

class DataService {
    private $db;

    public function __construct() {
        $this->db = new Database();
    }

public function getDataPlans($networkId = null, $dataType = null, $userId = null) {
    try {
        // Debug log the input parameters
        error_log("Fetching data plans with networkId: " . $networkId . ", dataType: " . $dataType . ", userId: " . $userId);

        // Determine price column based on user type
        // sType: 1 = subscriber (userprice), 2 = agent (agentprice), 3 = vendor (vendorprice)
        $priceCol = 'price';
        if ($userId !== null) {
            $u = $this->db->query("SELECT sType FROM subscribers WHERE sId = ?", [$userId]);
            if (!empty($u) && isset($u[0]['sType'])) {
                $sType = intval($u[0]['sType']);
                if ($sType === 1) {
                    $priceCol = 'userprice';
                } elseif ($sType === 2) {
                    $priceCol = 'agentprice';
                } elseif ($sType === 3) {
                    $priceCol = 'vendorprice';
                } else {
                    // fallback to userprice for unknown types
                    $priceCol = 'userprice';
                }
            } else {
                // fallback
                $priceCol = 'userprice';
            }
        } else {
            // default listing price when user not provided
            $priceCol = 'userprice';
        }

        // Safe select by inserting column name directly into SQL string
        $query = "SELECT 
                    dp.pId as id,              -- Internal DB ID
                    dp.planid as planCode,     -- API provider plan code
                    dp.name, 
                    dp." . $priceCol . " as price, 
                    dp.type as planType, 
                    dp.datanetwork as networkId, 
                    dp.day as validity
                  FROM dataplans dp";

        $params = [];
        $conditions = [];

        if ($networkId) {
            $conditions[] = "dp.datanetwork = ?";
            $params[] = $networkId;
        }

        if ($dataType) {
            $conditions[] = "dp.type = ?";
            $params[] = $dataType;
        }

        if (!empty($conditions)) {
            $query .= " WHERE " . implode(" AND ", $conditions);
        }

        $query .= " ORDER BY CAST(dp." . $priceCol . " AS DECIMAL(10,2)) ASC";

        error_log("Executing query: " . $query . " with params: " . json_encode($params));

        $result = $this->db->query($query, $params);

        error_log("Query result: " . json_encode($result));

        return $result;

    } catch (Exception $e) {
        throw new Exception("Error fetching data plans: " . $e->getMessage());
    }
}


    public function getDataProviderDetails($networkId, $dataGroup) {
        try {
            // Ensure dataGroup is not null and has a value
            if (empty($dataGroup)) {
                throw new Exception("Data group cannot be empty");
            }
            
            // Standardize network ID format (ensure it's a valid number)
            $networkId = intval($networkId);
            if ($networkId <= 0 || $networkId > 4) {
                throw new Exception("Invalid network ID: $networkId");
            }

            // Convert dataGroup to the correct format (SME, Corporate, Gifting)
            // Handle common variations in case
            $dataGroup = strtolower(trim($dataGroup));
            if ($dataGroup === 'sme') {
                $formattedGroup = 'SME';
            } elseif ($dataGroup === 'corporate' || $dataGroup === 'corp') {
                $formattedGroup = 'Corporate';
            } elseif ($dataGroup === 'gifting') {
                $formattedGroup = 'Gifting';
            } else {
                throw new Exception("Invalid data group type: $dataGroup. Expected: SME, Corporate, or Gifting");
            }
            
            // Debug logs for troubleshooting
            error_log("Getting provider details for network: $networkId, group: $formattedGroup");
            error_log("Original data group: $dataGroup, Formatted group: $formattedGroup");
            
            // First, let's log the current configuration (use network prefix for a useful LIKE)
            error_log("Checking apiconfigs table contents...");
            // build a loose pattern using network prefix so the LIKE returns relevant rows
            $previewPattern = '%';
            // We'll set a preview pattern if we can map the numeric network to a prefix
            $previewPattern = '%';

            // Get network name for better error messages
            $networkNames = ['1' => 'MTN', '2' => 'Airtel', '3' => 'Glo', '4' => '9mobile'];
            $networkName = $networkNames[strval($networkId)] ?? "Unknown";

            // Map network IDs to prefix names
                       $networkPrefixes = [
                1 => 'mtn',
                4 => 'airtel',
                2 => 'glo',
                3 => '9mobile'
            ];
            
            $networkPrefix = $networkPrefixes[$networkId] ?? strtolower($networkId);
            
            // Build config names using database convention
            $keyName = $networkPrefix . $formattedGroup . "Api";
            $providerName = $networkPrefix . $formattedGroup . "Provider";
            
            // Debug log the exact names we're looking for
            error_log("Searching for configurations:");
            error_log("Key config name: $keyName");
            error_log("Provider config name: $providerName");
            
            // Get configurations from apiconfigs table (fetch any matching names to be robust)
            $configQuery = "SELECT name, value FROM apiconfigs WHERE name IN (?, ?)";
            $configs = $this->db->query($configQuery, [$keyName, $providerName]);

            // Debug log all found configurations
            error_log("Found configurations: " . json_encode($configs));

            // Process results (case-insensitive match to tolerate naming variants like 'mtnSmeApi')
            $apiKey = null;
            $provider = null;
            $expectedApiName = strtolower($keyName);
            $expectedProviderName = strtolower($providerName);
            foreach ($configs as $config) {
                $cfgName = strtolower($config['name']);
                if ($cfgName === $expectedApiName) {
                    $apiKey = $config['value'];
                } elseif ($cfgName === $expectedProviderName) {
                    $provider = $config['value'];
                }
            }
            
            // Detailed error logging
            if (!$apiKey && !$provider) {
                error_log("ERROR: Both API key and provider configurations are missing");
                throw new Exception("No provider configuration found for $networkName $formattedGroup services");
            } else if (!$apiKey) {
                error_log("ERROR: API key configuration is missing");
                throw new Exception("API key not found for $networkName $formattedGroup services");
            } else if (!$provider) {
                error_log("ERROR: Provider configuration is missing");
                throw new Exception("Provider URL not found for $networkName $formattedGroup services");
            }
            
            return [[
                'apiKey' => $apiKey,
                'provider' => $provider
            ]];
        } catch (Exception $e) {
            throw new Exception("Error fetching provider details: " . $e->getMessage());
        }
    }

public function purchaseData($networkId, $phoneNumber, $planCode, $userId) {
    try {
        error_log("\n=== Data Purchase Debug Info ===");
        error_log("Input Parameters:");
        error_log("Network ID: " . $networkId);
        error_log("Phone Number: " . $phoneNumber);
        error_log("Plan Code: " . $planCode);
        error_log("User ID: " . $userId);

        // Determine user type and price column before starting transaction
        $userInfo = $this->db->query("SELECT sType, sWallet as balance FROM subscribers WHERE sId = ?", [$userId]);
        if (empty($userInfo)) {
            throw new Exception("User not found");
        }
        $sType = intval($userInfo[0]['sType']);
        if ($sType === 1) {
            $priceCol = 'userprice';
        } elseif ($sType === 2) {
            $priceCol = 'agentprice';
        } elseif ($sType === 3) {
            $priceCol = 'vendorprice';
        } else {
            $priceCol = 'userprice';
        }
        error_log("User sType: " . $sType . ", using price column: " . $priceCol);

        // Start transaction
        if (!$this->db->beginTransaction()) {
            error_log("Transaction start failed!");
            throw new Exception("Could not start transaction");
        }

        // Get plan details using API planCode with the correct price column
        // Also fetch the stored buy price (dp.price) so we can compute profit = sell_price - price
        $planQuery = "SELECT pId, name, dp.price as buy_price, " . $priceCol . " as price, type as planType, datanetwork, day, planid as planCode 
              FROM dataplans dp 
              WHERE planid = ?";
        error_log("\nQuerying Database:");
        error_log("SQL Query: " . $planQuery);
        error_log("Parameters: " . json_encode([strval($planCode)]));
        
        $plan = $this->db->query($planQuery, [strval($planCode)]);
        error_log("Query Result: " . json_encode($plan));
        
        if (empty($plan)) {
            error_log("No plan found in database with planid: " . $planCode);
            // Let's check what plans actually exist
            $allPlans = $this->db->query("SELECT planid FROM dataplans LIMIT 10");
            error_log("Available planids (first 10): " . json_encode($allPlans));
            $this->db->rollBack();
            throw new Exception("Invalid plan selected");
        }
        $plan = $plan[0];
        error_log("\nSelected Plan Details:");
        error_log(json_encode($plan, JSON_PRETTY_PRINT));

        // Verify user balance (we already fetched balance earlier)
        $currentBalance = floatval($userInfo[0]['balance']);
        $planPrice = floatval($plan['price']);

        if ($currentBalance < $planPrice) {
            throw new Exception("Insufficient balance");
        }

    // Create transaction record - without deducting balance yet
    $reference = 'DATA_' . time() . '_' . rand(1000, 9999);
    $description = $plan['name'] . ' Data Purchase for ' . $phoneNumber;
    // Initialize newBalance to currentBalance; update after provider response to reflect actual outcome
    $newBalance = $currentBalance;
    $apiLog = json_encode([
            'network' => $networkId,
            'phone' => $phoneNumber,
            'plan' => $plan['name'],
            'planId' => $plan['planCode'],
            'type' => $plan['planType']
        ]);

        $transactionQuery = "INSERT INTO transactions 
            (sId, servicename, servicedesc, amount, status, oldbal, newbal, transref, api_response_log) 
            VALUES (?, 'data', ?, ?, 0, ?, ?, ?, ?)";
        $this->db->query($transactionQuery, [
            $userId,
            $description,
            $planPrice,
            $currentBalance,
            $newBalance,
            $reference,
            $apiLog
        ]);
        $transactionId = $this->db->lastInsertId();

        // Get provider details for the network and plan type
        $providerDetails = $this->getDataProviderDetails($networkId, $plan['planType']);
        if (empty($providerDetails)) {
            throw new Exception("Could not get provider details");
        }
        $providerConfig = $providerDetails[0];
        
        error_log("\nAPI Request Details:");
        error_log("Provider URL: " . $providerConfig['provider']);
        error_log("Network ID: " . $networkId);
        error_log("Phone: " . $phoneNumber);
        error_log("Plan Code: " . $plan['planCode']);

        // Prepare the exact request payload
        $requestBody = [
            'network' => intval($networkId),
            'network_id' => intval($networkId),
            'mobile_number' => $phoneNumber,
            'plan' => intval($planCode),  // Use the original planCode parameter
            'plan_id' => intval($plan['planCode']),
            'Ported_number' => true,
            "ref" => (string)(time() . mt_rand(1000, 9999)),
            "phone" => $phoneNumber

        ];
        error_log("Exact Request Body being sent: " . json_encode($requestBody, JSON_PRETTY_PRINT));
        
        // API request to provider
        $curl = curl_init();
        curl_setopt_array($curl, array(
            CURLOPT_URL => $providerConfig['provider'],
            CURLOPT_RETURNTRANSFER => true,
            CURLOPT_ENCODING => '',
            CURLOPT_MAXREDIRS => 10,
            CURLOPT_TIMEOUT => 0,
            CURLOPT_FOLLOWLOCATION => true,
            CURLOPT_HTTP_VERSION => CURL_HTTP_VERSION_1_1,
            CURLOPT_CUSTOMREQUEST => 'POST',
            CURLOPT_SSL_VERIFYPEER => false,  // Added to handle HTTPS
            CURLOPT_SSL_VERIFYHOST => false,  // Added to handle HTTPS
            CURLOPT_POSTFIELDS => json_encode($requestBody),
            CURLOPT_HTTPHEADER => (strpos($providerConfig['provider'], 'smeplug.ng') !== false)
                ? array(
                    'Authorization: Bearer ' . $providerConfig['apiKey'],
                    'Content-Type: application/json',
                    'Accept: application/json'
                )
                : array(
                    'Authorization: Token ' . $providerConfig['apiKey'],
                    'Content-Type: application/json',
                    'Accept: application/json'
                ),
        ));


        $response = curl_exec($curl);
        $err = curl_error($curl);
        $httpCode = curl_getinfo($curl, CURLINFO_HTTP_CODE);
        curl_close($curl);

        error_log("\nAPI Response:");
        error_log("HTTP Code: " . $httpCode);
        error_log("Response: " . $response);
        error_log("Curl Error: " . ($err ?: 'None'));

        if ($err) {
            throw new Exception("API Call Failed: " . $err);
        }

        $result = json_decode($response);
        
        if (!$result) {
            error_log("Failed to decode JSON response");
            throw new Exception("Invalid API response format");
        }
        
        error_log("Decoded Response: " . json_encode($result, JSON_PRETTY_PRINT));

        // Update API response
        $updateApiResponseQuery = "UPDATE transactions SET api_response = ? WHERE tId = ?";
        $this->db->query($updateApiResponseQuery, [$response, $transactionId]);


        // Check API status (robust parsing to handle different provider response shapes)
        $status = 2; // 0 = success, 1 = failed, 2 = processing
        $message = '';

        // Helper: read various fields that providers might return
        $providerStatus = null;
        $providerMessage = null;

        // SMEPlug and some APIs: status (bool), current_status (string), data.status, etc.
        if (isset($result->current_status)) {
            $providerStatus = strtolower((string)$result->current_status);
        } elseif (isset($result->status) && is_string($result->status)) {
            $providerStatus = strtolower((string)$result->status);
        } elseif (isset($result->Status)) {
            $providerStatus = strtolower((string)$result->Status);
        } elseif (isset($result->data->status)) {
            $providerStatus = strtolower((string)$result->data->status);
        } elseif (isset($result->data->Status)) {
            $providerStatus = strtolower((string)$result->data->Status);
        }

        if (isset($result->message)) {
            $providerMessage = $result->message;
        } elseif (isset($result->msg)) {
            $providerMessage = $result->msg;
        } elseif (isset($result->api_response)) {
            $providerMessage = $result->api_response;
        } elseif (isset($result->data->msg)) {
            $providerMessage = $result->data->msg;
        }

        // Normalize status detection
        if ($providerStatus !== null) {
            if (in_array($providerStatus, ['success', 'successful', 'ok', 'completed', 'true'], true)) {
                $status = 0;
            } elseif (in_array($providerStatus, ['failed', 'error', 'failed_transaction', 'false'], true)) {
                $status = 1;
            } else {
                $status = 2; // unknown -> processing
            }
        } elseif (isset($result->status) && is_bool($result->status)) {
            // SMEPlug: status: true/false
            $status = $result->status ? 0 : 1;
        } else {
            // No explicit status field: try to infer from known keys
            if (!empty($result->Status) || !empty($result->status)) {
                $s = strtolower((string)($result->Status ?? $result->status));
                if (strpos($s, 'success') !== false) {
                    $status = 0;
                } elseif (strpos($s, 'fail') !== false || strpos($s, 'error') !== false) {
                    $status = 1;
                }
            }
        }

        // Handle transaction status
        if ($status === 0) {
            // Success - now deduct the amount from user's wallet
            $message = $providerMessage ?? ($result->message ?? 'Data purchase successful');
            $this->db->query("UPDATE subscribers SET sWallet = sWallet - ? WHERE sId = ?", [$planPrice, $userId]);
        } else if ($status === 1) {
            // Failed - no need to refund since we haven't deducted
            $message = $providerMessage ?? ($result->message ?? 'Transaction failed');
        } else {
            // Processing
            $message = $providerMessage ?? ($result->message ?? 'Data purchase processing');
        }

    // Final transaction status update - ensure newbal reflects actual deduction only on success
    $finalNewBal = ($status === 0) ? ($currentBalance - $planPrice) : $currentBalance;
    // Compute profit for successful transactions when buy_price/price is available
    $profit = 0.0;
    // prefer explicit buy_price (if dataplans has it), otherwise fallback to plan price
    $buyPrice = isset($plan['buy_price']) ? floatval($plan['buy_price']) : (isset($plan['price']) ? floatval($plan['price']) : 0.0);
    $sellPrice = isset($plan['price']) ? floatval($plan['price']) : 0.0;
    if ($status === 0) {
        $profit = round($sellPrice - $buyPrice, 2);
    }
    // Log profit calculation and DB update details
    error_log("Data Profit Calc - buyPrice=" . $buyPrice . ", sellPrice=" . $sellPrice . ", profit=" . $profit);
    error_log("Data Transaction Update - tId=" . $transactionId . ", status=" . $status . ", newbal=" . $finalNewBal . ", profit=" . $profit);
    $this->db->query("UPDATE transactions SET status = ?, api_response = ?, newbal = ?, profit = ? WHERE tId = ?", [$status, $response, (string)$finalNewBal, $profit, $transactionId]);
        $this->db->commit();

        // Send notification based on transaction status
        try {
            $notificationStatus = ($status === 0) ? 'success' : ($status === 2 ? 'processing' : 'failed');
            sendTransactionNotification($userId, 'data', [
                'status' => $notificationStatus,
                'amount' => $planPrice,
                'network' => $networkId,
                'plan' => $plan['name'] ?? 'Data Bundle',
                'phone' => $phoneNumber,
                'reference' => $reference
            ]);
        } catch (Exception $notifErr) {
            error_log("Notification send error (non-critical): " . $notifErr->getMessage());
        }

        return [
            'status' => $status === 0 ? 'success' : ($status === 2 ? 'processing' : 'failed'),
            'message' => $message,
            'data' => [
                'transactionId' => 'MK_' . strtoupper(uniqid()),
                'reference' => $reference,
                'amount' => $planPrice,
                'phone' => $phoneNumber,
                'network' => $networkId,
                'status' => $status === 0 ? 'success' : ($status === 2 ? 'processing' : 'failed')
            ]
        ];

    } catch (Exception $e) {
        if (isset($transactionId)) {
            $this->db->query("UPDATE transactions SET status = 1, api_response = ? WHERE tId = ?", [json_encode(['error' => $e->getMessage()]), $transactionId]);
            // No need to refund since we haven't deducted yet
            $this->db->commit();
            
            // Send failure notification
            try {
                sendTransactionNotification($userId, 'data', [
                    'status' => 'failed',
                    'amount' => $planPrice ?? null,
                    'network' => $networkId ?? null,
                    'plan' => $plan['name'] ?? 'Data Bundle',
                    'phone' => $phoneNumber ?? null,
                    'reference' => $reference ?? null,
                    'error' => $e->getMessage()
                ]);
            } catch (Exception $notifErr) {
                error_log("Notification send error (non-critical): " . $notifErr->getMessage());
            }
        } elseif ($this->db->inTransaction()) {
            $this->db->rollBack();
        }

        return [
            'status' => 'failed',
            'message' => $e->getMessage(),
            'data' => [
                'transactionId' => 'MK_' . strtoupper(uniqid()),
                'reference' => $reference ?? null,
                'amount' => $planPrice ?? null,
                'phone' => $phoneNumber,
                'network' => $networkId,
                'status' => 'failed'
            ]
        ];
    }
}
}
?>
