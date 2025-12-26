<?php
require_once __DIR__ . '/../config/database.php';

use Binali\Config\Database;

class CableService {
    private $db;

    public function __construct() {
        $this->db = new Database();
    }

    public function getCableProviders() {
        try {
            $query = "SELECT cId as id, cableid, provider, providerStatus as status 
                     FROM cableid 
                     WHERE providerStatus = 'On' 
                     ORDER BY provider ASC";
            
            return $this->db->query($query);
        } catch (Exception $e) {
            throw new Exception("Error fetching cable providers: " . $e->getMessage());
        }
    }

    public function getCablePlans($providerId = null) {
        try {
            $query = "SELECT cp.*, c.provider as providerName 
                     FROM cableplans cp 
                     JOIN cableid c ON cp.cableprovider = c.cId";
            
            $params = [];
            if ($providerId) {
                $query .= " WHERE cp.cableprovider = ?";
                $params = [$providerId];
            }
            
            // Only return active plans from active providers
            $query .= " AND c.providerStatus = 'On'";
            
            return $this->db->query($query, $params);
        } catch (Exception $e) {
            throw new Exception("Error fetching cable plans: " . $e->getMessage());
        }
    }

    public function getCableProviderDetails() {
        try {
            $query = "SELECT 
                      MAX(CASE WHEN name = 'cableProvider' THEN value END) as provider,
                      MAX(CASE WHEN name = 'cableApi' THEN value END) as apiKey,
                      MAX(CASE WHEN name = 'cableVerificationProvider' THEN value END) as verificationProvider,
                      MAX(CASE WHEN name = 'cableVerificationApi' THEN value END) as verificationKey
                    FROM apiconfigs 
                    WHERE name IN ('cableProvider', 'cableApi', 'cableVerificationProvider', 'cableVerificationApi')";
            
            $result = $this->db->query($query);
            
            if (empty($result)) {
                throw new Exception("Cable provider configuration not found");
            }

            // Verify that all required configurations are present
            $config = $result[0];
            if (empty($config['provider']) || empty($config['apiKey']) || 
                empty($config['verificationProvider']) || empty($config['verificationKey'])) {
                throw new Exception("Incomplete cable provider configuration");
            }

            return $result;
        } catch (Exception $e) {
            throw new Exception("Error fetching provider details: " . $e->getMessage());
        }
    }

    public function validateIUCNumber($iucNumber, $providerId) {
        try {
            // Input validation
            if (empty($iucNumber) || empty($providerId)) {
                throw new Exception("IUC number and provider ID are required");
            }

            // Get provider details from database
            $providerDetails = $this->getCableProviderDetails();
            if (empty($providerDetails)) {
                throw new Exception("Cable provider configuration not found");
            }
            $details = $providerDetails[0];

            if (empty($details['verificationProvider']) || empty($details['verificationKey'])) {
                throw new Exception("Invalid verification configuration");
            }

            // Get provider name and cableid for the API
            $query = "SELECT provider, cableid FROM cableid WHERE cId = ? AND providerStatus = 'On'";
            $providerResult = $this->db->query($query, [$providerId]);
            if (empty($providerResult)) {
                throw new Exception("Invalid or inactive provider");
            }
            $cableProvider = $providerResult[0]['provider'];

            // Initialize cURL
            $curl = curl_init();
            $verificationUrl = trim($details['verificationProvider']);
            $apiKey = trim($details['verificationKey']);

            // Determine authentication type and API structure based on provider URL
            $authType = "Basic";
            $method = 'POST';
            $postData = null;

            if (strpos(strtolower($verificationUrl), 'strowallet.com') !== false) {
                // Strowallet verification endpoint expects public_key, service_id and customer_id
                // Map our provider names to strowallet service ids
                $serviceMap = [
                    'dstv' => 'dstv',
                    'gotv' => 'gotv',
                    'startimes' => 'startimes',
                    'showmax' => 'showmax'
                ];

                // Try to derive service_id from cable provider name or cableid field
                $provKey = strtolower(preg_replace('/[^a-z0-9]/', '', $cableProvider));
                $serviceId = null;
                foreach ($serviceMap as $k => $v) {
                    if (strpos($provKey, $k) !== false) {
                        $serviceId = $v;
                        break;
                    }
                }
                // Fallback: try to use cableid (string) if provided in DB
                if ($serviceId === null) {
                    $serviceId = strtolower($providerResult[0]['cableid'] ?? '');
                }

                // Debug: log resolved service id to help diagnose empty values
                error_log("IUC Verification - resolved service_id: " . ($serviceId !== null ? $serviceId : 'NULL'));

                $postData = json_encode([
                    'public_key' => $apiKey,
                    'service_id' => $serviceId,
                    'customer_id' => $iucNumber
                ]);
            } else if (strpos(strtolower($verificationUrl), 'n3tdata.com') !== false || 
                strpos(strtolower($verificationUrl), 'n3tdata247') !== false) {
                // N3tdata API format
                $postData = json_encode([
                    'iuc' => $iucNumber,
                    'cable' => $providerId
                ]);
            } else if (strpos(strtolower($verificationUrl), 'legitdataway.com') !== false) {
                // Legitdataway API format
                $method = 'GET';
                // Remove any existing query string
                $baseUrl = strtok($verificationUrl, '?');
                $verificationUrl = $baseUrl . "?iuc={$iucNumber}&cable={$providerId}";
            } else if (strpos(strtolower($verificationUrl), 'nabatulu') !== false) {
                // Nabatulu API format
                $postData = json_encode([
                    'decoder_number' => $iucNumber,
                    'cable_name' => $cableProvider,
                    'cable_id' => $providerId
                ]);
            } else {
                // Generic API format
                $authType = "Token";
                $postData = json_encode([
                    'smart_card_number' => $iucNumber,
                    'cablename' => $cableProvider
                ]);
            }

            // Debug log the request
            error_log("IUC Verification Request - URL: " . $verificationUrl);
            if ($postData) {
                error_log("IUC Verification Request - Data: " . $postData);
            }

            // Build headers conditionally (Strowallet uses public_key in body, no Authorization header)
            $isStrowallet = (strpos(strtolower($verificationUrl), 'strowallet.com') !== false);
            $headers = [
                'Accept: application/json'
            ];
            if (!$isStrowallet && !empty($authType)) {
                $headers[] = "Authorization: {$authType} {$apiKey}";
            }
            if ($method === 'POST' && $postData) {
                $headers[] = 'Content-Type: application/json';
            }

            $curlOpts = array(
                CURLOPT_URL => $verificationUrl,
                CURLOPT_RETURNTRANSFER => true,
                CURLOPT_ENCODING => '',
                CURLOPT_MAXREDIRS => 10,
                CURLOPT_TIMEOUT => 30,
                CURLOPT_FOLLOWLOCATION => true,
                CURLOPT_HTTP_VERSION => CURL_HTTP_VERSION_1_1,
                CURLOPT_CUSTOMREQUEST => $method,
                CURLOPT_SSL_VERIFYPEER => false, // Some APIs might use self-signed certs
                CURLOPT_HTTPHEADER => $headers
            );

            if ($method === 'POST' && $postData) {
                $curlOpts[CURLOPT_POSTFIELDS] = $postData;
            }

            curl_setopt_array($curl, $curlOpts);

            $response = curl_exec($curl);
            $httpCode = curl_getinfo($curl, CURLINFO_HTTP_CODE);
            $err = curl_error($curl);
            curl_close($curl);

            // Debug log the response
            error_log("IUC Verification Response - HTTP Code: " . $httpCode);
            error_log("IUC Verification Response: " . $response);
            
            if ($err) {
                throw new Exception("Connection error: " . $err);
            }

            $result = json_decode($response, true);
            if (!$result) {
                throw new Exception("Invalid JSON response from verification service");
            }

            // Some providers (including Strowallet) use a top-level 'success' boolean
            if (isset($result['success'])) {
                $s = $result['success'];
                if ($s === true || (is_string($s) && strtolower($s) === 'true')) {
                    // Populate message if available
                    $message = $result['message'] ?? $message;
                    // Keep details for return
                    $details = $result;
                    // Attempt to extract customer name from common locations
                    $customerName = $result['response']['content']['CustomerName'] ?? $result['response']['content']['customer_name'] ?? $result['CustomerName'] ?? $result['customer_name'] ?? null;
                    if ($customerName) {
                        return [
                            'status' => true,
                            'message' => 'Customer Name: ' . $customerName,
                            'details' => $result
                        ];
                    }
                    // If success but no explicit name, we'll continue normal checks below
                }
            }

            // For 403 responses with 'Invalid IUC NUMBER', provide a clearer message
            if ($httpCode == 403 && 
                isset($result['message']) && 
                (is_string($result['message']) && strtolower($result['message']) === 'invalid iuc number')) {
                // Return structured error instead of throwing
                return [
                    'status' => false,
                    'message' => 'The IUC/Smart Card number provided is not valid. Please check and try again.',
                    'details' => $result
                ];
            }

            // For other error status codes, return structured error
            if ($httpCode >= 400) {
                $errorMsg = isset($result['message']) ? $result['message'] : "Unknown error occurred";
                // Flatten array messages if present
                if (is_array($errorMsg)) {
                    $flat = [];
                    array_walk_recursive($errorMsg, function($v) use (&$flat) { $flat[] = (string)$v; });
                    $errorMsg = implode('; ', $flat);
                }
                return [
                    'status' => false,
                    'message' => "API Error (HTTP $httpCode): " . (is_string($errorMsg) ? $errorMsg : json_encode($errorMsg)),
                    'details' => $result
                ];
            }

            // Initialize response variables
            $status = false;
            $message = "IUC verification failed";
            $details = [];

            // Handle different API response formats
            if (strpos(strtolower($verificationUrl), 'legitdataway.com') !== false) {
                // Legitdataway specific response handling
                if (isset($result['status'])) {
                    $status = filter_var($result['status'], FILTER_VALIDATE_BOOLEAN);
                    $message = $result['message'] ?? $message;
                    
                    if (!$status && strtolower($message) === 'contact admin') {
                        throw new Exception("Service temporarily unavailable. Please try again later.");
                    }
                    
                    if ($status && isset($result['data']['Customer_Name'])) {
                        $customerName = $result['data']['Customer_Name'];
                        $message = "Customer Name: " . $customerName;
                    }
                }
                $details = $result;
            } else {
                // Standard response format check
                if (isset($result['status'])) {
                    $status = strtolower($result['status']) === 'success' || 
                             strtolower($result['status']) === 'successful' ||
                             filter_var($result['status'], FILTER_VALIDATE_BOOLEAN);
                    $message = $result['message'] ?? $message;
                    $details = $result;
                }
                
                // Check for customer name in various possible response formats
                if (isset($result['name']) || isset($result['customer_name']) || 
                    isset($result['data']['name']) || isset($result['data']['customer_name']) ||
                    isset($result['response']['content']['CustomerName']) || isset($result['response']['content']['CustomerName'])) {
                    $status = true;
                    $customerName = $result['name'] ?? $result['customer_name'] ?? 
                                  $result['data']['name'] ?? $result['data']['customer_name'] ??
                                  ($result['response']['content']['CustomerName'] ?? $result['response']['content']['customer_name'] ?? null);
                    $message = "Customer Name: " . $customerName;
                    $details = $result;
                }
            }

            if ($status) {
                return [
                    'status' => true,
                    'message' => $message,
                    'details' => $details
                ];
            }

            // If we reach here, treat as verification failure and return structured error
            // Flatten possible array messages from provider
            $finalMsg = $message;
            if (isset($result['message'])) {
                $m = $result['message'];
                if (is_array($m)) {
                    $flat = [];
                    array_walk_recursive($m, function($v) use (&$flat) { $flat[] = (string)$v; });
                    $finalMsg = implode('; ', $flat);
                } else if (is_string($m)) {
                    $finalMsg = $m;
                }
            }

            return [
                'status' => false,
                'message' => $finalMsg ?: 'IUC verification failed',
                'details' => $result
            ];

        } catch (Exception $e) {
            // Log the error for debugging and return structured error
            error_log("IUC Verification Error: " . $e->getMessage());
            return [
                'status' => false,
                'message' => 'Error validating IUC number: ' . $e->getMessage(),
                'details' => null
            ];
        }
    }

    public function processCableSubscription($providerId, $planId, $iucNumber, $phoneNumber, $amount, $pin, $userId = null) {
        try {
            // Log the initial request
            error_log("=== CABLE SUBSCRIPTION INIT START ===");
            error_log("Provider ID: " . $providerId);
            error_log("Plan ID: " . $planId);
            error_log("IUC Number: " . $iucNumber);
            error_log("Phone Number: " . $phoneNumber);
            error_log("Amount: " . $amount);
            error_log("User ID: " . $userId);
            error_log("=== CABLE SUBSCRIPTION INIT END ===");
            
            // Validate required parameters
            $missingParams = [];
            if (empty($providerId)) $missingParams[] = 'providerId';
            if (empty($planId)) $missingParams[] = 'planId';
            if (empty($iucNumber)) $missingParams[] = 'iucNumber';
            if (empty($phoneNumber)) $missingParams[] = 'phoneNumber';
            if (empty($amount)) $missingParams[] = 'amount';
            if (empty($pin)) $missingParams[] = 'pin';
            if (empty($userId)) $missingParams[] = 'userId';

            if (!empty($missingParams)) {
                throw new Exception("Missing required parameters: " . implode(", ", $missingParams));
            }

            // Check user's balance
            $query = "SELECT sWallet FROM subscribers WHERE sId = ?";
            $balanceResult = $this->db->query($query, [$userId]);
            
            if (empty($balanceResult)) {
                throw new Exception("User not found or wallet not accessible");
            }
            
            $userBalance = $balanceResult[0]['sWallet'];
            
            if ($userBalance < $amount) {
                throw new Exception(json_encode([
                    'type' => 'INSUFFICIENT_BALANCE',
                    'message' => "Insufficient balance. Available balance: ₦" . number_format($userBalance, 2)
                ]));
            }

            // 1. Start with getting plan details
            $query = "SELECT cp.*, c.provider as providerName 
                     FROM cableplans cp 
                     JOIN cableid c ON cp.cableprovider = c.cId 
                     WHERE cp.planid = ? AND cp.cableprovider = ?";
            $plan = $this->db->query($query, [$planId, $providerId]);
            
            if (empty($plan)) {
                throw new Exception("Invalid plan selected");
            }

            // Compare with userprice since that's what the customer should pay
            if ($plan[0]['userprice'] != $amount) {
                throw new Exception("Amount mismatch: Expected {$plan[0]['userprice']}, got {$amount}");
            }

            // 3. Process the transaction
            // Start transaction using the underlying PDO connection
            $this->db->getConnection()->beginTransaction();

            try {
                // Get current balance again within transaction
                $balanceResult = $this->db->query("SELECT sWallet FROM subscribers WHERE sId = ?", [$userId]);
                $oldBalance = $balanceResult[0]['sWallet'];
                $newBalance = $oldBalance - $amount;

                // Update user's wallet balance
                $this->db->query(
                    "UPDATE subscribers SET sWallet = sWallet - ? WHERE sId = ?",
                    [$amount, $userId]
                );

                // Insert into transactions table
                $transactionQuery = "INSERT INTO transactions 
                    (sId, transref, servicename, servicedesc, amount, status, oldbal, newbal) 
                    VALUES (?, ?, 'CABLE', ?, ?, 0, ?, ?)";
                
                $transRef = 'CABLE-' . time(); // We'll update this with transaction ID later
                $serviceDesc = "Cable subscription: {$plan[0]['providerName']} - IUC: {$iucNumber}";
                
                $this->db->query(
                    $transactionQuery, 
                    [$userId, $transRef, $serviceDesc, $amount, $oldBalance, $newBalance]
                );
                
                // Get the last inserted ID using the database helper
                $transactionId = $this->db->lastInsertId();

                // Get provider configuration
                $providerDetails = $this->getCableProviderDetails();
                if (empty($providerDetails)) {
                    throw new Exception("Cable provider configuration not found");
                }
                $details = $providerDetails[0];

                // Get provider name and cableid for service_id derivation
                $cableProvider = $plan[0]['providerName'];
                
                // Fetch cableid from the cableid table for service_id derivation
                $cableIdQuery = "SELECT cableid FROM cableid WHERE cId = ? AND providerStatus = 'On'";
                $cableIdResult = $this->db->query($cableIdQuery, [$providerId]);
                $cableId = !empty($cableIdResult) ? $cableIdResult[0]['cableid'] : null;
                
                // Initialize purchase request
                $curl = curl_init();
                $purchaseUrl = $details['provider'];
                $apiKey = $details['apiKey'];
                // Update the transaction reference with the ID
                $transRef = $transRef . '-' . $transactionId;
                
                // Update the reference in the transactions table
                $this->db->query(
                    "UPDATE transactions SET transref = ? WHERE tId = ?",
                    [$transRef, $transactionId]
                );

                // Determine API type and set request data
                if (strpos($purchaseUrl, 'strowallet.com') !== false) {
                    // Strowallet purchase format
                    $serviceMap = [
                        'dstv' => 'dstv',
                        'gotv' => 'gotv',
                        'startimes' => 'startimes',
                        'showmax' => 'showmax'
                    ];

                    $provKey = strtolower(preg_replace('/[^a-z0-9]/', '', $cableProvider));
                    $serviceId = null;
                    foreach ($serviceMap as $k => $v) {
                        if (strpos($provKey, $k) !== false) {
                            $serviceId = $v;
                            break;
                        }
                    }
                    if ($serviceId === null) {
                        $serviceId = strtolower($cableId ?? '');
                    }

                    // Debug: log resolved service id
                    error_log("Cable Purchase - resolved service_id: " . ($serviceId !== null && $serviceId !== '' ? $serviceId : 'EMPTY'));

                    // Use plan name as service_name and planid as variation_code where available
                    $serviceName = $plan[0]['name'] ?? '';
                    $variationCode = $plan[0]['planid'] ?? $planId;

                    $postData = json_encode([
                        'public_key' => $details['verificationKey'] ?? $apiKey,
                        'amount' => (string)$amount,
                        'phone' => (string)$phoneNumber,
                        'service_name' => $serviceName,
                        'service_id' => $serviceId,
                        'variation_code' => (string)$variationCode,
                        'customer_id' => (string)$iucNumber
                    ]);
                } elseif (strpos($purchaseUrl, 'n3tdata.com') !== false || 
                    strpos($purchaseUrl, 'n3tdata247') !== false) {
                    $postData = json_encode([
                        'request-id' => $transRef,
                        'cable' => $providerId,
                        'iuc' => $iucNumber,
                        'cable_plan' => $planId,
                        'bypass' => true
                    ]);
                } else {
                    $postData = json_encode([
                        'cablename' => $providerId,
                        'cable' => $providerId,
                        // Include multiple common keys some providers expect
                        'smart_card_number' => $iucNumber,
                        'iuc' => $iucNumber,
                        'decoder_number' => $iucNumber,
                        // Provide several aliases for the cable plan field to satisfy various providers
                        'cableplan' => $planId,
                        'cable_plan' => $planId,
                        'plan' => $planId,
                        'plan_id' => $planId,
                        'reference' => $transRef,
                        // Some providers (e.g., n3tdata variants) require a bypass field
                        'bypass' => false,
                        // Some providers expect 'request-id' as the transaction reference
                        'request-id' => $transRef
                    ]);
                }

                // Log the outgoing request
                error_log("=== CABLE SUBSCRIPTION REQUEST START ===");
                error_log("Transaction ID: " . $transactionId);
                error_log("Transaction Ref: " . $transRef);
                error_log("URL: " . $purchaseUrl);
                error_log("API Key: " . substr($apiKey, 0, 10) . "...");
                error_log("Request Data: " . $postData);
                error_log("=== CABLE SUBSCRIPTION REQUEST END ===");

                // Set headers conditionally for Strowallet (no Authorization header, public_key in body)
                $isStrowalletPurchase = (strpos($purchaseUrl, 'strowallet.com') !== false);
                $headers = ['Content-Type: application/json'];
                if (!$isStrowalletPurchase) {
                    $headers[] = 'Authorization: Token ' . $apiKey;
                }

                curl_setopt_array($curl, array(
                    CURLOPT_URL => $purchaseUrl,
                    CURLOPT_RETURNTRANSFER => true,
                    CURLOPT_ENCODING => '',
                    CURLOPT_MAXREDIRS => 10,
                    CURLOPT_TIMEOUT => 0,
                    CURLOPT_FOLLOWLOCATION => true,
                    CURLOPT_HTTP_VERSION => CURL_HTTP_VERSION_1_1,
                    CURLOPT_CUSTOMREQUEST => 'POST',
                    CURLOPT_POSTFIELDS => $postData,
                    CURLOPT_HTTPHEADER => $headers,
                ));

                $response = curl_exec($curl);
                $err = curl_error($curl);
                curl_close($curl);

                // Log the response
                error_log("=== CABLE SUBSCRIPTION RESPONSE START ===");
                error_log("Transaction ID: " . $transactionId);
                error_log("Transaction Ref: " . $transRef);
                if ($err) {
                    error_log("CURL Error: " . $err);
                }
                error_log("Raw Response: " . $response);
                error_log("=== CABLE SUBSCRIPTION RESPONSE END ===");

                if ($err) {
                    throw new Exception("Connection error: " . $err);
                }

                $result = json_decode($response, true);
                
                // Log the parsed result
                error_log("=== CABLE SUBSCRIPTION PARSED RESULT START ===");
                error_log("Transaction ID: " . $transactionId);
                error_log("Parsed Result: " . json_encode($result));
                error_log("=== CABLE SUBSCRIPTION PARSED RESULT END ===");
                
                $status = 'PENDING';
                $message = 'Transaction processing';

                // Check for error responses first
                // Treat explicit success boolean from some providers (e.g., Strowallet)
                if (isset($result['success'])) {
                    $s = $result['success'];
                    if ($s === true || (is_string($s) && strtolower($s) === 'true')) {
                        $status = 'SUCCESS';
                        $message = $result['message'] ?? 'Subscription successful';
                    } elseif ($s === false || (is_string($s) && strtolower($s) === 'false')) {
                        $status = 'FAILED';
                        $message = $result['message'] ?? 'Subscription failed';
                    }
                }

                if (isset($result['error'])) {
                    $status = 'FAILED';
                    if (is_array($result['error']) && !empty($result['error'])) {
                        $message = $result['error'][0];
                    } else {
                        $message = $result['error'];
                    }
                } elseif (isset($result['status'])) {
                    $apiStatus = strtolower($result['status']);
                    if ($apiStatus == 'success' || $apiStatus == 'successful') {
                        $status = 'SUCCESS';
                        $message = $result['message'] ?? 'Subscription successful';
                    } elseif ($apiStatus == 'failed' || $apiStatus == 'fail') {
                        $status = 'FAILED';
                        $message = $result['message'] ?? 'Transaction failed';
                    }
                }
                
                // Log the status determination
                error_log("=== CABLE SUBSCRIPTION STATUS DETERMINATION ===");
                error_log("Transaction ID: " . $transactionId);
                error_log("Determined Status: " . $status);
                error_log("Message: " . $message);
                error_log("=== END STATUS DETERMINATION ===");
                
                // Update transaction status
                $updateQuery = "UPDATE transactions 
                              SET status = ?, 
                                  responseData = ?, 
                                  reference = ?,
                                  updatedAt = NOW() 
                              WHERE transactionId = ?";
                
                $responseData = json_encode([
                    'api_response' => $result,
                    'message' => $message,
                    'reference' => $transRef,
                    'provider_txn' => $providerTxn
                ]);
                // Try to extract provider transaction id / reference from common locations
                $providerTxn = null;
                if (is_array($result)) {
                    $providerTxn = $result['transactionId'] ?? $result['transaction_id'] ?? null;
                    if (empty($providerTxn) && isset($result['response']['content']['transactions']['transactionId'])) {
                        $providerTxn = $result['response']['content']['transactions']['transactionId'];
                    }
                    if (empty($providerTxn) && isset($result['response']['content']['transactions']['transaction_id'])) {
                        $providerTxn = $result['response']['content']['transactions']['transaction_id'];
                    }
                }

                // Convert status to numeric for database
                $dbStatus = ($status === 'SUCCESS') ? 1 : 
                           (($status === 'FAILED') ? 2 : 0); // 0 for PENDING

                // Log before database update
                error_log("=== UPDATING TRANSACTION IN DB ===");
                error_log("Transaction ID: " . $transactionId);
                error_log("DB Status: " . $dbStatus . " (0=PENDING, 1=SUCCESS, 2=FAILED)");
                error_log("Response Data: " . $responseData);
                error_log("=== END DB UPDATE LOG ===");

                // Update the transaction with the API response
                $this->db->query(
                    "UPDATE transactions 
                     SET status = ?, 
                         api_response = ?,
                         api_response_log = ? 
                     WHERE tId = ?",
                    [$dbStatus, $result ? json_encode($result) : null, $responseData, $transactionId]
                );

                // Commit transaction using the underlying PDO connection
                $this->db->getConnection()->commit();

                if ($status === 'FAILED') {
                    // Restore user's wallet balance if transaction failed
                    $this->db->query(
                        "UPDATE subscribers SET sWallet = sWallet + ? WHERE sId = ?",
                        [$amount, $userId]
                    );
                    
                    error_log("=== CABLE SUBSCRIPTION FAILED ===");
                    error_log("Transaction ID: " . $transactionId);
                    error_log("Message: " . $message);
                    error_log("Wallet restored for user: " . $userId);
                    error_log("=== END CABLE SUBSCRIPTION FAILED ===");
                    
                    throw new Exception(json_encode([
                        'type' => 'API_ERROR',
                        'message' => $message,
                        'transactionId' => $transactionId,
                        'reference' => $transRef,
                        'status' => $status
                    ]));
                }

                // Log successful completion
                error_log("=== CABLE SUBSCRIPTION SUCCESS ===");
                error_log("Transaction ID: " . $transactionId);
                error_log("Reference: " . $transRef);
                error_log("Status: " . $status);
                error_log("Message: " . $message);
                error_log("=== END CABLE SUBSCRIPTION SUCCESS ===");

                return [
                    'transactionId' => $transactionId,
                    'reference' => $transRef,
                    'status' => $status,
                    'message' => $message
                ];

            } catch (Exception $e) {
                // Rollback transaction on error using PDO if a transaction is active
                try {
                    $conn = $this->db->getConnection();
                    if ($conn instanceof PDO && $conn->inTransaction()) {
                        $conn->rollBack();
                    }
                } catch (Exception $__rollEx) {
                    error_log('Rollback failed: ' . $__rollEx->getMessage());
                }
                throw $e;
            }

        } catch (Exception $e) {
            throw new Exception("Error processing cable subscription: " . $e->getMessage());
        }
    }
}
?>
