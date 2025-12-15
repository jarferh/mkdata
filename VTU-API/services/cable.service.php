<?php
require_once __DIR__ . '/../config/database.php';

use Binali\Config\Database;

class CableService {
    private $db;

    public function __construct() {
        $this->db = new Database();
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

            // Get provider name for the API
            $query = "SELECT provider FROM cableid WHERE cId = ? AND providerStatus = 'On'";
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

            if (strpos(strtolower($verificationUrl), 'n3tdata.com') !== false || 
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
                CURLOPT_HTTPHEADER => array(
                    'Accept: application/json',
                    "Authorization: {$authType} {$apiKey}"
                )
            );

            // Add Content-Type and POST data only for POST requests
            if ($method === 'POST' && $postData) {
                $curlOpts[CURLOPT_HTTPHEADER][] = 'Content-Type: application/json';
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

            // For 403 responses with 'Invalid IUC NUMBER', provide a clearer message
            if ($httpCode == 403 && 
                isset($result['message']) && 
                strtolower($result['message']) === 'invalid iuc number') {
                throw new Exception("The IUC/Smart Card number provided is not valid. Please check and try again.");
            }

            // For other error status codes
            if ($httpCode >= 400) {
                $errorMsg = isset($result['message']) ? $result['message'] : "Unknown error occurred";
                throw new Exception("API Error (HTTP $httpCode): " . $errorMsg);
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
                    isset($result['data']['name']) || isset($result['data']['customer_name'])) {
                    $status = true;
                    $customerName = $result['name'] ?? $result['customer_name'] ?? 
                                  $result['data']['name'] ?? $result['data']['customer_name'];
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

            throw new Exception($message);

        } catch (Exception $e) {
            // Log the error for debugging
            error_log("IUC Verification Error: " . $e->getMessage());
            throw new Exception("Error validating IUC number: " . $e->getMessage());
        }
    }

    public function processCableSubscription($providerId, $planId, $iucNumber, $phoneNumber, $amount, $pin) {
        try {
            // Validate required parameters
            $missingParams = [];
            if (empty($providerId)) $missingParams[] = 'providerId';
            if (empty($planId)) $missingParams[] = 'planId';
            if (empty($iucNumber)) $missingParams[] = 'iucNumber';
            if (empty($phoneNumber)) $missingParams[] = 'phoneNumber';
            if (empty($amount)) $missingParams[] = 'amount';
            if (empty($pin)) $missingParams[] = 'pin';

            if (!empty($missingParams)) {
                throw new Exception("Missing required parameters: " . implode(", ", $missingParams));
            }

            // Check user's balance
            $query = "SELECT sWallet FROM subscribers WHERE sId = ?";
            $balanceResult = $this->db->query($query, [1]); // Using 1 as default sId for now
            
            if (empty($balanceResult)) {
                throw new Exception("Unable to retrieve user's wallet balance");
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
            // Start transaction
            $this->db->beginTransaction();

            try {
                // Get current balance again within transaction
                $balanceResult = $this->db->query("SELECT sWallet FROM subscribers WHERE sId = ?", [1]);
                $oldBalance = $balanceResult[0]['sWallet'];
                $newBalance = $oldBalance - $amount;

                // Update user's wallet balance
                $this->db->query(
                    "UPDATE subscribers SET sWallet = sWallet - ? WHERE sId = ?",
                    [$amount, 1] // Using 1 as default sId
                );

                // Insert into transactions table
                $transactionQuery = "INSERT INTO transactions 
                    (sId, transref, servicename, servicedesc, amount, status, oldbal, newbal) 
                    VALUES (?, ?, 'CABLE', ?, ?, 0, ?, ?)";
                
                $transRef = 'CABLE-' . time(); // We'll update this with transaction ID later
                $serviceDesc = "Cable subscription: {$plan[0]['providerName']} - IUC: {$iucNumber}";
                
                $this->db->query(
                    $transactionQuery, 
                    [1, $transRef, $serviceDesc, $amount, $oldBalance, $newBalance] // Using 1 as default sId for now
                );
                
                // Get the last inserted ID
                $transactionId = $this->db->query("SELECT LAST_INSERT_ID() as id")[0]['id'];

                // Get provider configuration
                $providerDetails = $this->getCableProviderDetails();
                if (empty($providerDetails)) {
                    throw new Exception("Cable provider configuration not found");
                }
                $details = $providerDetails[0];

                // Get provider name
                $cableProvider = $plan[0]['providerName'];
                
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
                if (strpos($purchaseUrl, 'n3tdata.com') !== false || 
                    strpos($purchaseUrl, 'n3tdata247') !== false) {
                    $postData = json_encode([
                        'request-id' => $transRef,
                        'cable' => $providerId,
                        'iuc' => $iucNumber,
                        'cable_plan' => $planId,
                        'bypass' => false
                    ]);
                } else {
                    $postData = json_encode([
                        'cablename' => $cableProvider,
                        'smart_card_number' => $iucNumber,
                        'cableplan' => $planId,
                        'reference' => $transRef
                    ]);
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
                    CURLOPT_HTTPHEADER => array(
                        'Content-Type: application/json',
                        'Authorization: Token ' . $apiKey
                    ),
                ));

                $response = curl_exec($curl);
                $err = curl_error($curl);
                curl_close($curl);

                if ($err) {
                    throw new Exception("Connection error: " . $err);
                }

                $result = json_decode($response, true);
                $status = 'PENDING';
                $message = 'Transaction processing';

                if (isset($result['status'])) {
                    $apiStatus = strtolower($result['status']);
                    if ($apiStatus == 'success' || $apiStatus == 'successful') {
                        $status = 'SUCCESS';
                        $message = $result['message'] ?? 'Subscription successful';
                    } elseif ($apiStatus == 'failed' || $apiStatus == 'fail') {
                        $status = 'FAILED';
                        $message = $result['message'] ?? 'Transaction failed';
                    }
                }
                
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
                    'reference' => $transRef
                ]);

                // Convert status to numeric for database
                $dbStatus = ($status === 'SUCCESS') ? 1 : 
                           (($status === 'FAILED') ? 2 : 0); // 0 for PENDING

                // Update the transaction with the API response
                $this->db->query(
                    "UPDATE transactions 
                     SET status = ?, 
                         api_response = ?,
                         api_response_log = ? 
                     WHERE tId = ?",
                    [$dbStatus, $result ? json_encode($result) : null, $responseData, $transactionId]
                );

                // Commit transaction
                $this->db->commit();

                if ($status === 'FAILED') {
                    // Restore user's wallet balance if transaction failed
                    $this->db->query(
                        "UPDATE subscribers SET sWallet = sWallet + ? WHERE sId = ?",
                        [$amount, 1] // Using 1 as default sId
                    );
                    throw new Exception(json_encode([
                        'type' => 'API_ERROR',
                        'message' => $message,
                        'transactionId' => $transactionId,
                        'reference' => $transRef,
                        'status' => $status
                    ]));
                }

                return [
                    'transactionId' => $transactionId,
                    'reference' => $transRef,
                    'status' => $status,
                    'message' => $message
                ];

            } catch (Exception $e) {
                // Rollback transaction on error
                $this->db->rollback();
                throw $e;
            }

        } catch (Exception $e) {
            throw new Exception("Error processing cable subscription: " . $e->getMessage());
        }
    }
}
?>
