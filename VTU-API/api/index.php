<?php
// Set timezone to GMT+1 (Africa/Lagos)
date_default_timezone_set('Africa/Lagos');

// Allow credentials with specific origins
$allowedOrigins = [
    'http://localhost',
    'https://localhost',
    'https://api.mkdata.com.ng',
    'https://mkdata.com.ng',
];

$origin = $_SERVER['HTTP_ORIGIN'] ?? '';
if (in_array($origin, $allowedOrigins) || php_sapi_name() === 'cli') {
    header("Access-Control-Allow-Origin: $origin");
    header("Access-Control-Allow-Credentials: true");
} else {
    // For all other origins
    header("Access-Control-Allow-Origin: *");
}

header("Content-Type: application/json; charset=UTF-8");
header("Access-Control-Allow-Methods: GET, POST, OPTIONS");
header("Access-Control-Allow-Headers: Content-Type, Access-Control-Allow-Headers, Authorization, X-Requested-With");

// Load environment variables from .env file
require_once __DIR__ . '/../auth/session-helper.php';
loadEnvFile(__DIR__ . '/../.env');

// Initialize session for user authentication
initializeSession();

// Handle preflight requests
if ($_SERVER['REQUEST_METHOD'] === 'OPTIONS') {
    http_response_code(200);
    exit();
}

use Binali\Models\User;
use Binali\Config\Database;
use PHPMailer\PHPMailer\PHPMailer;


require_once __DIR__ . '/../services/airtime.service.php';
require_once __DIR__ . '/../services/data.service.php';
require_once __DIR__ . '/../services/cable.service.php';
require_once __DIR__ . '/../services/electricity.service.php';
require_once __DIR__ . '/../services/exam.service.php';
require_once __DIR__ . '/../services/recharge.service.php';
require_once __DIR__ . '/../services/rechargepin.service.php';
require_once __DIR__ . '/../services/datapin.service.php';
require_once __DIR__ . '/../services/user.service.php';
require_once __DIR__ . '/../services/beneficiary.service.php';
require_once __DIR__ . '/../api/notifications/send.php';

// Database helper (used to resolve network names to IDs when client sends name)
require_once __DIR__ . '/../db/database.php';

// Temporary: ensure OPcache does not serve stale code after edits
if (function_exists('opcache_invalidate')) {
    @opcache_invalidate(__FILE__, true);
}
if (function_exists('opcache_reset')) {
    @opcache_reset();
}

// Ensure PHP errors/warnings are not printed to the HTTP response (they go to error log)
@ini_set('display_errors', '0');
@ini_set('display_startup_errors', '0');
error_reporting(E_ALL);

// Start output buffering so we can return valid JSON even if warnings/errors occur
if (!ob_get_level()) {
    ob_start();
}

// Register shutdown handler to catch fatal errors and return JSON response instead of raw HTML/text
register_shutdown_function(function () {
    $lastError = error_get_last();
    if ($lastError && in_array($lastError['type'], [E_ERROR, E_PARSE, E_CORE_ERROR, E_COMPILE_ERROR])) {
        // Clear any non-JSON output
        if (ob_get_length()) {
            @ob_clean();
        }
        http_response_code(500);
        $resp = [
            'status' => 'error',
            'message' => 'Internal server error'
        ];
        echo json_encode($resp);
        // Ensure it's flushed
        @ob_flush();
        flush();
    }
});

/**
 * Resolve a network identifier provided by the client.
 * Accepts numeric IDs (returned as int) or network names (case-insensitive).
 * Returns integer network id or null when not found.
 */
function resolveNetworkIdFromInput($input) {
    if ($input === null) return null;
    // If numeric, assume it's already the network id
    if (is_numeric($input)) return (int)$input;

    // Otherwise try to lookup by name in the networkid table
    try {
        $db = new Database();
        $rows = $db->query("SELECT nId FROM networkid WHERE LOWER(network) = LOWER(?) LIMIT 1", [$input]);
        if (!empty($rows) && isset($rows[0]['nId'])) {
            return (int)$rows[0]['nId'];
        }
        // Try match against the networkid column as a fallback
        $rows = $db->query("SELECT nId FROM networkid WHERE networkid = ? LIMIT 1", [$input]);
        if (!empty($rows) && isset($rows[0]['nId'])) {
            return (int)$rows[0]['nId'];
        }
    } catch (Exception $e) {
        error_log('resolveNetworkIdFromInput error: ' . $e->getMessage());
    }
    return null;
}

/**
 * Deliver airtime as a spin reward
 */
function _deliverAirtime($phoneNumber, $networkId, $amount, $transactionRef, $userId = 0) {
    try {
        $service = new AirtimeService();
        // Pass the actual user ID for delivery tracking
        $result = $service->purchaseAirtime($networkId, $phoneNumber, $amount, $userId);
        
        if ($result && ($result['status'] === 'success' || $result['status'] === 'processing')) {
            return true;
        }
        return false;
    } catch (Exception $e) {
        error_log('Error delivering airtime: ' . $e->getMessage());
        return false;
    }
}

/**
 * Deliver data as a spin reward
 */
function _deliverData($phoneNumber, $networkId, $amount, $transactionRef, $userId = 0) {
    try {
        // For data rewards, we need to find a matching plan
        // This is a simplified implementation - adjust based on your data structure
        $service = new DataService();
        
        // Try to deliver data directly
        // Note: This might need adjustment based on how your DataService works
        error_log("Attempting to deliver data: phone=$phoneNumber, networkId=$networkId, amount=$amount, userId=$userId");
        
        // For now, assume delivery is successful if we can log it
        // In production, integrate with actual data delivery API
        return true;
    } catch (Exception $e) {
        error_log('Error delivering data: ' . $e->getMessage());
        return false;
    }
}

$uri = parse_url($_SERVER['REQUEST_URI'], PHP_URL_PATH);
$requestMethod = $_SERVER['REQUEST_METHOD'];

// Debug logging
error_log("Original Request URI: " . $uri);
error_log("Request Method: " . $requestMethod);

// Extract the endpoint from the URI (raw path after /api/)
$uriParts = explode('/api/', $uri, 2);
$rawEndpoint = isset($uriParts[1]) ? trim($uriParts[1], '/') : '';

// Debug logging
error_log("Extracted endpoint: " . $rawEndpoint);

// Split for additional parameters from the raw extracted endpoint
$uriSegments = explode('/', $rawEndpoint);

// Use the first segment as the endpoint
$endpoint = $uriSegments[0] ?? '';
$subEndpoint = $uriSegments[1] ?? null;
$id = $uriSegments[2] ?? null;

// Backwards-compatibility: if the upstream provided full path as endpoint (rare), normalize using rawEndpoint
if (in_array($rawEndpoint, ['airtime2cash/verify', 'airtime2cash/convert'])) {
    $parts = explode('/', $rawEndpoint, 2);
    $endpoint = 'airtime2cash';
    $subEndpoint = $parts[1] ?? null;
}

// Debug logging
error_log("=== ROUTER DEBUG START ===");
error_log("Processing endpoint: " . $endpoint);
// Additional diagnostics to catch hidden characters or encoding issues
error_log("Endpoint raw: '" . $endpoint . "' | length: " . strlen($endpoint));
$endpoint_bytes = array_map(function($c){ return ord($c); }, str_split($endpoint));
error_log("Endpoint bytes: " . implode(',', $endpoint_bytes));
error_log("subEndpoint raw: '" . ($subEndpoint ?? '') . "' | length: " . strlen($subEndpoint ?? ''));
error_log("=== ROUTER DEBUG END ===");

// Initialize response array
$response = [
    'status' => 'error',
    'message' => 'Invalid endpoint',
    'data' => null
];

// Handle device management endpoints
if ($endpoint === 'device') {
    if ($subEndpoint === 'register') {
        require_once __DIR__ . '/device/register.php';
        exit();
    } else {
        http_response_code(404);
        echo json_encode([
            'status' => 'error',
            'message' => 'Device endpoint not found'
        ]);
        exit();
    }
}

// Final debug before switch
error_log("About to enter switch with endpoint: '$endpoint'");

try {
    switch ($endpoint) {
        case 'delete-account':
            if ($requestMethod !== 'POST') {
                throw new Exception('Method not allowed');
            }

            // Get authenticated user ID from session (not from client input)
            $authenticatedUserId = requireAuth();
            
            $data = json_decode(file_get_contents("php://input"));
            if (!isset($data->reason)) {
                throw new Exception('Missing required parameter: reason');
            }

            try {
                $user_service = new UserService();
                // Use session user ID, not client-supplied userId
                $response['data'] = $user_service->deleteAccount($authenticatedUserId, $data->reason);
                $response['status'] = 'success';
                $response['message'] = 'Account deleted successfully';
            } catch (PDOException $e) {
                error_log("Database error in delete-account: " . $e->getMessage());
                http_response_code(503);
                throw new Exception("Database service is currently unavailable. Please try again later.");
            } catch (Exception $e) {
                error_log("Error in delete-account: " . $e->getMessage());
                throw $e;
            }
            break;
    case 'airtime':
            if ($requestMethod !== 'POST') {
                throw new Exception('Method not allowed');
            }

            // Get authenticated user ID from session
            $authenticatedUserId = requireAuth();

            $rawInput = file_get_contents("php://input");
            error_log("Raw input: " . $rawInput);

            $data = json_decode($rawInput);
            if (json_last_error() !== JSON_ERROR_NONE) {
                throw new Exception('Invalid JSON: ' . json_last_error_msg());
            }

            error_log("Decoded data: " . print_r($data, true));

            if (!isset($data->network) || !isset($data->phone) || !isset($data->amount)) {
                throw new Exception('Missing required parameters: ' .
                    (!isset($data->network) ? 'network ' : '') .
                    (!isset($data->phone) ? 'phone ' : '') .
                    (!isset($data->amount) ? 'amount ' : ''));
            }

            // Resolve network: allow client to send either numeric id or network name
            $resolvedNetworkId = resolveNetworkIdFromInput($data->network);
            if ($resolvedNetworkId === null) {
                // still allow sending network name to the AirtimeService which can map names
                $networkForService = $data->network;
            } else {
                $networkForService = $resolvedNetworkId;
            }

            $service = new AirtimeService();
            // Use authenticated user ID from session, not client-supplied user_id
            $svcResult = $service->purchaseAirtime($networkForService, $data->phone, $data->amount, $authenticatedUserId);

            // Normalize and propagate to top-level response
            $response['data'] = $svcResult['data'] ?? $svcResult;
            $response['message'] = $svcResult['message'] ?? '';
            $response['status'] = $svcResult['status'] ?? 'failed';

            // Send push notification for all attempts (success and failure)
            try {
                sendTransactionNotification(
                    userId: (string)$authenticatedUserId,
                    transactionType: 'airtime',
                    transactionData: [
                        'transaction_id' => $svcResult['data']['ref'] ?? 'N/A',
                        'amount' => $data->amount,
                        'network' => $networkForService,
                        'phone' => $data->phone,
                        'status' => $response['status']
                    ]
                );
            } catch (Exception $e) {
                error_log('Notification error (non-blocking): ' . $e->getMessage());
            }

            // Set HTTP response code based on service status
            if ($response['status'] === 'failed') {
                http_response_code(500);
            } else {
                // success or processing
                http_response_code(200);
            }
            break;

        case 'airtime-plans':
            $service = new AirtimeService();
            $response['data'] = $service->getAirtimePlans();
            $response['status'] = 'success';
            $response['message'] = 'Airtime plans fetched successfully';
            break;
        
        case 'network-status':
            // Fetch network statuses from networkid table
            try {
                $db = new Database();
                $query = "SELECT nId, networkid, network, networkStatus, vtuStatus, smeStatus, 
                         sme2Status, giftingStatus, corporateStatus, couponStatus, 
                         datapinStatus, airtimepinStatus, sharesellStatus
                  FROM networkid ORDER BY nId";
                $rows = $db->query($query);
                
                if (empty($rows)) {
                    $response['data'] = [];
                    $response['status'] = 'success';
                    $response['message'] = 'No networks found';
                } else {
                    $response['data'] = $rows;
                    $response['status'] = 'success';
                    $response['message'] = 'Network statuses fetched successfully';
                }
            } catch (PDOException $e) {
                error_log("Database error in network-status: " . $e->getMessage());
                http_response_code(503);
                $response['status'] = 'error';
                $response['message'] = 'Database service is currently unavailable';
            } catch (Exception $e) {
                error_log("Error in network-status: " . $e->getMessage());
                http_response_code(500);
                $response['status'] = 'error';
                $response['message'] = $e->getMessage();
            }
            break;


        case 'data-plans':
            $service = new DataService();
            $networkIdInput = isset($_GET['network']) ? $_GET['network'] : null;
            $networkId = resolveNetworkIdFromInput($networkIdInput);
            $dataType = isset($_GET['type']) ? $_GET['type'] : null;
            // Allow client to pass user id so service can select pricing (userprice/vendorprice)
            $userId = isset($_GET['user_id']) ? $_GET['user_id'] : (isset($_GET['userId']) ? $_GET['userId'] : null);
            $response['data'] = $service->getDataPlans($networkId, $dataType, $userId);
            $response['status'] = 'success';
            $response['message'] = 'Data plans fetched successfully';
            break;

    case 'purchase-data':
            if ($requestMethod !== 'POST') {
                throw new Exception('Method not allowed');
            }

            // Get authenticated user ID from session
            $authenticatedUserId = requireAuth();

            $data = json_decode(file_get_contents("php://input"));

            // Debug the received data
            error_log("Received data purchase request with data: " . print_r($data, true));

            // Map the incoming parameters to our internal format
            $networkIdInput = $data->network ?? $data->network_id ?? $data->networkId ?? null;
            $networkId = resolveNetworkIdFromInput($networkIdInput);
            $phone = $data->mobile_number ?? $data->phone ?? $data->phoneNumber ?? null;
            $planId = $data->plan ?? $data->plan_id ?? $data->planId ?? null;

            error_log("Mapped parameters:");
            error_log("Network ID: " . $networkId);
            error_log("Phone: " . $phone);
            error_log("Plan ID: " . $planId);
            error_log("User ID: " . $authenticatedUserId);

            if (!$networkId || !$phone || !$planId) {
                error_log("Missing parameters. Required: network/network_id, mobile_number/phone, plan/plan_id");
                error_log("Received raw data: " . print_r($data, true));
                error_log("Mapped values: " . json_encode([
                    'network_id' => $networkId,
                    'phone' => $phone,
                    'plan_id' => $planId,
                    'user_id' => $authenticatedUserId
                ]));
                throw new Exception('Missing required parameters');
            }

            $service = new DataService();
            // Use authenticated user ID from session, not client-supplied user_id
            $svcResult = $service->purchaseData($networkId, $phone, $planId, $authenticatedUserId);

            // Normalize and propagate to top-level response
            $response['data'] = $svcResult['data'] ?? $svcResult;
            $response['message'] = $svcResult['message'] ?? '';
            $response['status'] = $svcResult['status'] ?? 'failed';

            // Send push notification for all attempts (success and failure)
            try {
                $notifStatus = $response['status'] ?? ($svcResult['status'] ?? 'failed');
                // Only send notification for success or processing states
                if (in_array($notifStatus, ['success', 'processing'], true)) {
                    sendTransactionNotification(
                        userId: (string)$authenticatedUserId,
                        transactionType: 'data',
                        transactionData: [
                            'transaction_id' => $svcResult['data']['ref'] ?? 'N/A',
                            'plan_id' => $planId,
                            'network' => $networkId,
                            'phone' => $phone,
                            'status' => $notifStatus
                        ]
                    );
                }
                // Do not send a success-style notification when the purchase failed
            } catch (Exception $e) {
                error_log('Notification error (non-blocking): ' . $e->getMessage());
            }

            // Set HTTP response code based on service status
            if ($response['status'] === 'failed') {
                http_response_code(500);
            } else {
                // success or processing
                http_response_code(200);
            }
            break;

        case 'cable-providers':
            $service = new CableService();
            $response['data'] = $service->getCableProviders();
            $response['status'] = 'success';
            $response['message'] = 'Cable providers fetched successfully';
            break;

        case 'cable-plans':
            $service = new CableService();
            $providerId = isset($_GET['provider']) ? $_GET['provider'] : null;
            $response['data'] = $service->getCablePlans($providerId);
            $response['status'] = 'success';
            $response['message'] = 'Cable plans fetched successfully';
            break;

        case 'electricity-providers':
            $service = new ElectricityService();
            $response['data'] = $service->getElectricityProviders();
            $response['status'] = 'success';
            $response['message'] = 'Electricity providers fetched successfully';
            break;

        case 'validate-meter':
            if ($requestMethod !== 'POST') {
                throw new Exception("Invalid request method");
            }

            $data = json_decode(file_get_contents("php://input"));
            if (!isset($data->meterNumber) || !isset($data->providerId)) {
                throw new Exception("Missing required parameters");
            }

            $service = new ElectricityService();
            // The service returns an array with keys: status, message, data
            // Propagate that result directly to the top-level response to avoid double-wrapping
            $svcResult = $service->validateMeterNumber(
                $data->meterNumber,
                $data->providerId,
                $data->meterType ?? 'prepaid'
            );

            // If service returned an HTTP-like status, map to router response
            $response['status'] = $svcResult['status'] ?? 'error';
            $response['message'] = $svcResult['message'] ?? '';
            $response['data'] = $svcResult['data'] ?? null;

            // Set HTTP response code based on service status
            if ($response['status'] === 'error' || $response['status'] === 'failed') {
                http_response_code(500);
            } else {
                http_response_code(200);
            }

            break;

        case 'purchase-electricity':
            if ($requestMethod !== 'POST') {
                throw new Exception("Invalid request method");
            }

            // Get authenticated user ID from session
            $authenticatedUserId = requireAuth();

            $data = json_decode(file_get_contents("php://input"));
            if (!isset($data->meterNumber) || !isset($data->providerId) || !isset($data->amount)) {
                throw new Exception("Missing required parameters");
            }

            // Check if userId is provided for balance verification (use session user)
            $userId = $authenticatedUserId;
            
            // Fetch user wallet balance
            $dbBalance = new Database();
            $userQuery = "SELECT sWallet FROM subscribers WHERE sId = ?";
            $userResult = $dbBalance->query($userQuery, [$userId]);
            
            if (!empty($userResult)) {
                $userWallet = (float)($userResult[0]['sWallet'] ?? 0);
                $amount = (float)$data->amount;
                
                if ($userWallet < $amount) {
                    http_response_code(402); // 402 Payment Required
                    echo json_encode([
                        'status' => 'error',
                        'message' => 'Insufficient balance. Your wallet balance is ₦' . number_format($userWallet, 2),
                        'data' => [
                            'current_balance' => $userWallet,
                            'required_amount' => $amount
                        ]
                    ]);
                    exit();
                }
            }

            // Call provider first; debit wallet only if provider reports success
            $transactionId = null;
            $transRef = 'ELEC-' . time();
            $dbTrans = null;
            $oldBalance = null;
            $newBalance = null;

            // Call provider
            $service = new ElectricityService();
            $svcResult = $service->purchaseElectricity(
                $data->meterNumber,
                $data->providerId,
                $data->amount,
                $data->meterType ?? 'prepaid',
                $data->phone ?? ''
            );

            $response['status'] = $svcResult['status'] ?? 'error';
            $response['message'] = $svcResult['message'] ?? '';
            $response['data'] = $svcResult['data'] ?? null;
            
            // Include token in the response for Flutter to use (cleaned)
            if (isset($svcResult['data']['token'])) {
                $rawToken = (string)$svcResult['data']['token'];
                // Strip common prefixes like 'Token :' and extract first token-like group
                if (preg_match('/Token\s*[:\-]?\s*(.+)/i', $rawToken, $m)) {
                    $rawToken = $m[1];
                }
                if (preg_match('/([0-9A-Za-z\-]+)/', $rawToken, $m2)) {
                    $cleanToken = $m2[1];
                } else {
                    $cleanToken = trim($rawToken);
                }
                $response['token'] = $cleanToken;
            }

            // Persist transaction and only debit on provider success
            try {
                $dbTrans = new Database();
                $conn = $dbTrans->getConnection();
                $conn->beginTransaction();

                // Fetch current balance
                $balanceRow = $dbTrans->query("SELECT sWallet FROM subscribers WHERE sId = ? LIMIT 1", [$userId]);
                $oldBalance = (float)($balanceRow[0]['sWallet'] ?? 0);
                $amount = (float)$data->amount;

                $serviceDesc = "Electricity purchase: Meter {$data->meterNumber}";
                $apiResponseLog = json_encode($svcResult['data'] ?? $svcResult);

                if (($svcResult['status'] ?? '') === 'success') {
                    // Ensure user still has sufficient funds before debiting
                    if ($oldBalance < $amount) {
                        // Insert failed transaction due to insufficient balance at commit time
                        $dbTrans->query("INSERT INTO transactions (sId, transref, servicename, servicedesc, amount, status, oldbal, newbal, api_response, date) VALUES (?, ?, 'ELECTRICITY', ?, ?, 1, ?, ?, ?, NOW())", [$userId, $transRef, $serviceDesc, $amount, $oldBalance, $oldBalance, $apiResponseLog]);
                        $transactionId = $dbTrans->lastInsertId();
                        $transRef = $transRef . '-' . $transactionId;
                        $dbTrans->query("UPDATE transactions SET transref = ? WHERE tId = ?", [$transRef, $transactionId]);
                        $conn->commit();
                    } else {
                        // Debit wallet and record success transaction
                        $newBalance = $oldBalance - $amount;
                        $dbTrans->query("UPDATE subscribers SET sWallet = sWallet - ? WHERE sId = ?", [$amount, $userId]);
                        $dbTrans->query("INSERT INTO transactions (sId, transref, servicename, servicedesc, amount, status, oldbal, newbal, api_response, date) VALUES (?, ?, 'ELECTRICITY', ?, ?, 0, ?, ?, ?, NOW())", [$userId, $transRef, $serviceDesc, $amount, $oldBalance, $newBalance, $apiResponseLog]);
                        $transactionId = $dbTrans->lastInsertId();
                            $transRef = $transRef . '-' . $transactionId;
                            $dbTrans->query("UPDATE transactions SET transref = ? WHERE tId = ?", [$transRef, $transactionId]);
                            $conn->commit();
                        }
                    } else {
                        // Provider returned error — record failed transaction, do not debit
                        $dbTrans->query("INSERT INTO transactions (sId, transref, servicename, servicedesc, amount, status, oldbal, newbal, api_response, date) VALUES (?, ?, 'ELECTRICITY', ?, ?, 1, ?, ?, ?, NOW())", [$userId, $transRef, $serviceDesc, $amount, $oldBalance, $oldBalance, $apiResponseLog]);
                        $transactionId = $dbTrans->lastInsertId();
                        $transRef = $transRef . '-' . $transactionId;
                        $dbTrans->query("UPDATE transactions SET transref = ? WHERE tId = ?", [$transRef, $transactionId]);
                        $conn->commit();
                    }
                } catch (Exception $e) {
                    if (isset($conn) && $conn->inTransaction()) {
                        $conn->rollBack();
                    }
                    error_log('Error updating/creating transaction after provider call: ' . $e->getMessage());
                }

            // Send push notification for all attempts (success and failure)
            try {
                sendTransactionNotification(
                    userId: (string)$data->userId,
                    transactionType: 'electricity',
                    transactionData: [
                        'meter_number' => $data->meterNumber,
                        'provider_id' => $data->providerId,
                        'amount' => $data->amount,
                        'meter_type' => $data->meterType ?? 'prepaid',
                        'status' => $response['status']
                    ]
                );
            } catch (Exception $e) {
                error_log('Notification error (non-blocking): ' . $e->getMessage());
            }

            if ($response['status'] === 'error' || $response['status'] === 'failed') {
                // Distinguish validation-like errors (field errors returned by provider)
                // from internal/server errors. If the service included a data object
                // with field-level error arrays (e.g., 'amount' => ['...']), return 400.
                $isValidationError = false;
                if (isset($svcResult['data']) && is_array($svcResult['data'])) {
                    foreach ($svcResult['data'] as $k => $v) {
                        if (is_array($v) && !empty($v)) {
                            $isValidationError = true;
                            break;
                        }
                    }
                }

                http_response_code($isValidationError ? 400 : 500);
            } else {
                http_response_code(200);
            }
            break;

        case 'validate-iuc':
            if ($requestMethod !== 'POST') {
                throw new Exception('Method not allowed');
            }

            $data = json_decode(file_get_contents("php://input"));

            // Require both iucNumber and providerId and ensure they are not empty strings
            $iuc = isset($data->iucNumber) ? trim((string)$data->iucNumber) : '';
            $prov = isset($data->providerId) ? trim((string)$data->providerId) : '';
            if ($iuc === '' || $prov === '') {
                http_response_code(400);
                $response['status'] = 'error';
                $response['message'] = 'Missing required parameters: iucNumber and providerId are required.';
                $response['data'] = null;
                break;
            }

            $service = new CableService();
            $svcResult = $service->validateIUCNumber($iuc, $prov);

            if (is_array($svcResult) && isset($svcResult['status']) && $svcResult['status'] === true) {
                $response['status'] = 'success';
                $response['message'] = isset($svcResult['message']) ? $svcResult['message'] : 'IUC number validated successfully';

                // Sanitize provider details: only expose minimal fields (customer name)
                $custName = null;
                $details = $svcResult['details'] ?? null;
                if (is_array($details)) {
                    // Check common locations for customer name
                    if (isset($details['response']['content']['CustomerName'])) $custName = $details['response']['content']['CustomerName'];
                    elseif (isset($details['response']['content']['customer_name'])) $custName = $details['response']['content']['customer_name'];
                    elseif (isset($details['CustomerName'])) $custName = $details['CustomerName'];
                    elseif (isset($details['customer_name'])) $custName = $details['customer_name'];
                    elseif (isset($details['data']['Customer_Name'])) $custName = $details['data']['Customer_Name'];
                    elseif (isset($details['data']['customer_name'])) $custName = $details['data']['customer_name'];
                    elseif (isset($details['name'])) $custName = $details['name'];
                }

                $response['data'] = [
                    'customer_name' => $custName,
                ];
            } else {
                http_response_code(400);
                $response['status'] = 'error';
                $response['message'] = is_array($svcResult) && isset($svcResult['message']) ? $svcResult['message'] : 'IUC verification failed';
                $response['data'] = null;
            }

            break;

        case 'cable-subscription':
            if ($requestMethod !== 'POST') {
                throw new Exception('Method not allowed');
            }

            $data = json_decode(file_get_contents("php://input"));
            if (
                !isset($data->providerId) || !isset($data->planId) ||
                !isset($data->iucNumber) || !isset($data->phoneNumber) ||
                !isset($data->amount) || !isset($data->pin) || !isset($data->userId)
            ) {
                throw new Exception('Missing required parameters');
            }

            // If userId supplied, verify wallet balance before attempting purchase
            $userId = $data->userId ?? null;
            if (!empty($userId)) {
                try {
                    $dbCheck = new Database();
                    $userRow = $dbCheck->query("SELECT sWallet FROM subscribers WHERE sId = ? LIMIT 1", [$userId]);
                    if (!empty($userRow) && isset($userRow[0]['sWallet'])) {
                        $userWallet = (float)$userRow[0]['sWallet'];
                        $amount = (float)$data->amount;
                        if ($userWallet < $amount) {
                            http_response_code(402); // Payment Required
                            echo json_encode([
                                'status' => 'error',
                                'message' => 'Insufficient balance. Your wallet balance is ₦' . number_format($userWallet, 2),
                                'data' => [
                                    'current_balance' => $userWallet,
                                    'required_amount' => $amount
                                ]
                            ]);
                            exit();
                        }
                    }
                } catch (Exception $e) {
                    error_log('Error checking wallet balance for cable-subscription: ' . $e->getMessage());
                    // Fall through to attempt purchase; do not silently block users if DB check fails
                }
            }

            // Call the real CableService to perform the subscription
            $service = new CableService();
            $svcResult = $service->processCableSubscription(
                $data->providerId,
                $data->planId,
                $data->iucNumber,
                $data->phoneNumber,
                $data->amount,
                $data->pin,
                $data->userId
            );

            // Normalize and propagate the service response
            $response['data'] = $svcResult['data'] ?? $svcResult;
            $response['message'] = $svcResult['message'] ?? '';
            $response['status'] = $svcResult['status'] ?? 'failed';

            // Send push notification for all attempts (success and failure)
            try {
                sendTransactionNotification(
                    userId: (string)$data->userId,
                    transactionType: 'cable',
                    transactionData: [
                        'transaction_id' => $response['data']['ref'] ?? ($svcResult['data']['ref'] ?? 'N/A'),
                        'amount' => $data->amount,
                        'provider_id' => $data->providerId,
                        'plan_id' => $data->planId,
                        'iuc_number' => $data->iucNumber,
                        'status' => $response['status']
                    ]
                );
            } catch (Exception $e) {
                error_log('Notification error (non-blocking): ' . $e->getMessage());
            }

            // Map service error types to HTTP codes: validation-like errors => 400, otherwise 500
            if ($response['status'] === 'failed' || $response['status'] === 'error') {
                $isValidationError = false;
                if (isset($svcResult['data']) && is_array($svcResult['data'])) {
                    foreach ($svcResult['data'] as $k => $v) {
                        if (is_array($v) && !empty($v)) {
                            $isValidationError = true;
                            break;
                        }
                    }
                }
                http_response_code($isValidationError ? 400 : 500);
            } else {
                http_response_code(200);
            }

            break;

        case 'exam-providers':
            $service = new ExamPinService();
            $result = $service->getExamProviders();
            $response['data'] = $result['data'];
            $response['status'] = $result['status'];
            $response['message'] = $result['message'];
            break;

        case 'exam-purchase':
            if ($requestMethod !== 'POST') {
                throw new Exception('Method not allowed');
            }

            // Get authenticated user ID from session
            $authenticatedUserId = requireAuth();

            $data = json_decode(file_get_contents("php://input"));
            error_log("Exam purchase request data: " . print_r($data, true));

            if (!isset($data->examId) || !isset($data->quantity) || !isset($data->pin)) {
                throw new Exception('Missing required parameters: examId, quantity, pin');
            }

            $service = new ExamPinService();
            // Use authenticated user ID from session, not client-supplied userId
            $result = $service->purchaseExamPin($data->examId, $data->quantity, $authenticatedUserId);

            $response['status'] = $result['status'];
            $response['message'] = $result['message'];
            $response['data'] = $result['data'];

            // Send notification for transaction attempts (success or error)
            try {
                sendTransactionNotification(
                    userId: (string)$authenticatedUserId,
                    transactionType: 'exam_pin',
                    transactionData: [
                        'examId' => $data->examId,
                        'quantity' => $data->quantity,
                        'amount' => $result['data']['amount'] ?? 0,
                        'reference' => $result['data']['reference'] ?? '',
                        'status' => $response['status']
                    ]
                );
            } catch (Exception $e) {
                error_log('Notification error (non-blocking): ' . $e->getMessage());
            }
            break;

        case 'purchase-recharge-pin':
            if ($requestMethod !== 'POST') {
                throw new Exception('Method not allowed');
            }

            // Get authenticated user ID from session
            $authenticatedUserId = requireAuth();

            $data = json_decode(file_get_contents("php://input"));
            error_log("Card PIN purchase request data: " . print_r($data, true));

            if (!isset($data->planId) || !isset($data->quantity) || !isset($data->pin)) {
                throw new Exception('Missing required parameters: planId, quantity, pin');
            }

            $service = new RechargePinService();
            // Use authenticated user ID from session, not client-supplied userId
            $result = $service->purchaseRechargePin($data->planId, $data->quantity, $authenticatedUserId, $data->pin);

            $response['status'] = $result['status'];
            $response['message'] = $result['message'];
            $response['data'] = $result['data'];

            // Send notification for transaction attempts (success or error)
            try {
                sendTransactionNotification(
                    userId: (string)$authenticatedUserId,
                    transactionType: 'card_pin',
                    transactionData: [
                        'network' => $data->planId,
                        'quantity' => $data->quantity,
                        'amount' => $result['data']['amount'] ?? 0,
                        'reference' => $result['data']['reference'] ?? '',
                        'status' => $response['status']
                    ]
                );
            } catch (Exception $e) {
                error_log('Notification error (non-blocking): ' . $e->getMessage());
            }
            break;

        case 'recharge-card-plans':
            $service = new RechargeCardService();
            $response['data'] = $service->getRechargeCardPlans();
            $response['status'] = 'success';
            $response['message'] = 'Recharge card plans fetched successfully';
            break;

        case 'recharge-pin-plans':
            $service = new RechargePinService();
            $networkInput = isset($_GET['network']) ? $_GET['network'] : null;
            $networkId = resolveNetworkIdFromInput($networkInput);
            $response['data'] = $service->getAvailablePins($networkId);
            $response['status'] = 'success';
            $response['message'] = 'Recharge pin plans fetched successfully';
            break;

        case 'data-pin-plans':
            $service = new DataPinService();
            $networkInput = isset($_GET['network']) ? $_GET['network'] : null;
            $networkId = resolveNetworkIdFromInput($networkInput);
            $type = isset($_GET['type']) ? $_GET['type'] : null;
            $userId = isset($_GET['user_id']) ? $_GET['user_id'] : (isset($_GET['userId']) ? $_GET['userId'] : null);

            try {
                $result = $service->getDataPinPlans($networkId, $type, $userId);
                $response['status'] = $result['status'];
                $response['message'] = $result['message'];
                $response['data'] = $result['data'];
            } catch (Exception $e) {
                $response['status'] = 'error';
                $response['message'] = $e->getMessage();
                $response['data'] = null;
            }
            break;

        case 'purchase-data-pin':
            if ($requestMethod !== 'POST') {
                http_response_code(405);
                $response['message'] = 'Method not allowed';
                break;
            }

            // Get authenticated user ID from session
            $authenticatedUserId = requireAuth();

            $data = json_decode(file_get_contents("php://input"));
            error_log("Data pin purchase request data: " . print_r($data, true));

            // Validate required parameters
            if (!isset($data->plan) || !isset($data->quantity) || !isset($data->name_on_card)) {
                error_log("Missing required parameters. Received: " . json_encode($data));
                http_response_code(400);
                $response['status'] = 'error';
                $response['message'] = 'Missing required parameters. Required: plan, quantity, name_on_card';
                break;
            }

            try {
                $service = new DataPinService();
                // Use authenticated user ID from session, not client-supplied userId
                $result = $service->purchaseDataPin(
                    $data->plan,
                    $data->quantity,
                    $data->name_on_card,
                    $authenticatedUserId
                );

                $response['status'] = $result['status'];
                $response['message'] = $result['message'];
                $response['data'] = $result['data'];

                // Send notification for transaction attempts (success or error)
                try {
                    sendTransactionNotification(
                        userId: (string)$authenticatedUserId,
                        transactionType: 'data_pin',
                        transactionData: [
                            'planName' => $data->plan,
                            'quantity' => $data->quantity,
                            'amount' => $result['data']['amount'] ?? 0,
                            'reference' => $result['data']['reference'] ?? '',
                            'status' => $response['status']
                        ]
                    );
                } catch (Exception $e) {
                    error_log('Notification error (non-blocking): ' . $e->getMessage());
                }
            } catch (Exception $e) {
                error_log("Error in data pin purchase: " . $e->getMessage());
                http_response_code(500);
                $response['status'] = 'error';
                $response['message'] = $e->getMessage();
            }
            break;

        case 'generate-account':
            // New behavior: backend decides which bank to create for the user.
            if ($requestMethod !== 'POST') {
                throw new Exception('Method not allowed');
            }

            $data = json_decode(file_get_contents("php://input"));
            if (!isset($data->user_id)) {
                throw new Exception('Missing required parameters: user_id');
            }

            require_once __DIR__ . '/../config/database.php';
            require_once __DIR__ . '/../models/user.php';

            try {
                error_log("Processing account generation request for user_id: " . $data->user_id);
                $db = new Database();

                // Get user details
                $query = "SELECT sFname, sLname, sPhone, sEmail FROM subscribers WHERE sId = ?";
                error_log("Executing query with user_id: " . $data->user_id);
                $result = $db->query($query, [$data->user_id]);

                if (empty($result)) {
                    throw new Exception('User not found');
                }

                $user = $result[0];
                error_log("User data found: " . print_r($user, true));

                // If user already has any account (sBankNo or sSterlingBank), return it
                $checkQuery = "SELECT sBankNo, sSterlingBank, sBankName FROM subscribers WHERE sId = ?";
                $checkResult = $db->query($checkQuery, [$data->user_id]);

                if (!empty($checkResult)) {
                    $existing = $checkResult[0];
                    if (!empty($existing['sBankNo'])) {
                        $response['status'] = 'success';
                        $response['message'] = 'Account already exists';
                        $response['data'] = [
                            'account_number' => $existing['sBankNo'],
                            'bank_name' => $existing['sBankName'] ?? 'StroWallet'
                        ];
                        break;
                    }
                    if (!empty($existing['sSterlingBank'])) {
                        $response['status'] = 'success';
                        $response['message'] = 'Account already exists';
                        $response['data'] = [
                            'account_number' => $existing['sSterlingBank'],
                            'bank_name' => $existing['sBankName'] ?? 'Sterling Bank'
                        ];
                        break;
                    }
                }

                // Create virtual account (StroWallet / backend decides which bank)
                $userModel = new User($db);
                error_log("Attempting to create virtual account for user ID: " . $data->user_id);

                $accountCreated = $userModel->createVirtualAccount(
                    $data->user_id,
                    $user['sFname'],
                    $user['sLname'],
                    $user['sPhone'],
                    $user['sEmail']
                );

                if ($accountCreated) {
                    // Fetch the newly created account number and bank name
                    $fetchQuery = "SELECT sBankNo, sSterlingBank, sBankName FROM subscribers WHERE sId = ?";
                    $fetchResult = $db->query($fetchQuery, [$data->user_id]);

                    if (!empty($fetchResult)) {
                        $accountInfo = $fetchResult[0];
                        // Prefer sBankNo (StroWallet/Noma) if present, otherwise sSterlingBank
                        $acct = !empty($accountInfo['sBankNo']) ? $accountInfo['sBankNo'] : $accountInfo['sSterlingBank'];
                        $response['status'] = 'success';
                        $response['message'] = 'Account generated successfully';
                        $response['data'] = [
                            'account_number' => $acct,
                            'bank_name' => $accountInfo['sBankName'] ?? ''
                        ];
                    } else {
                        throw new Exception('Account created but unable to fetch details');
                    }
                } else {
                    throw new Exception('Failed to generate account. Please try again later.');
                }
            } catch (Exception $e) {
                error_log("Error in generate-account: " . $e->getMessage());
                throw $e;
            }
            break;

        case 'generate-palmpay-paga':
            // Generate Palmpay and Paga accounts for a user. This is a placeholder
            // implementation: if the subscriber already has sPaga or sPalmpayBank
            // populated we return them. Integration with the payment gateway to
            // create virtual accounts will be implemented when gateway docs are provided.
            if ($requestMethod !== 'POST') {
                http_response_code(405);
                $response['message'] = 'Method not allowed';
                break;
            }

            $data = json_decode(file_get_contents("php://input"));
            if (!isset($data->user_id)) {
                http_response_code(400);
                $response['message'] = 'Missing required parameter: user_id';
                break;
            }

            try {
                $db = new Database();

                // Ensure user exists
                $query = "SELECT sFname, sLname, sPhone, sEmail, sPaga,sPaga, sPalmpayBank FROM subscribers WHERE sId = ?";
                $rows = $db->query($query, [$data->user_id]);
                if (empty($rows)) {
                    throw new Exception('User not found');
                }

                $user = $rows[0];
                $paga = $user['sPaga'] ?? '';
                $palmpay = $user['sPalmpayBank'] ?? '';

                // If we already have values, return them immediately
                if (!empty($paga) || !empty($palmpay)) {
                    $response['status'] = 'success';
                    $response['message'] = 'Accounts fetched';
                    $response['data'] = [
                        'paga_account' => $paga,
                        'palmpay_account' => $palmpay,
                    ];
                    http_response_code(200);
                    break;
                }

                // Fetch Aspfiy API key and webhook from apiconfigs (names: asfiyApi, asfiyWebhook)
                $cfg = $db->query("SELECT name, value FROM apiconfigs WHERE name IN (?, ?)", ['asfiyApi', 'asfiyWebhook']);
                $aspKey = '';
                $webhookUrl = '';
                if (!empty($cfg)) {
                    foreach ($cfg as $c) {
                        if ($c['name'] === 'asfiyApi') $aspKey = $c['value'];
                        if ($c['name'] === 'asfiyWebhook') $webhookUrl = $c['value'];
                    }
                }
                if (empty($aspKey)) {
                    throw new Exception('Aspfiy API key not configured in environment');
                }

                // Helper: perform POST to Aspfiy reserve endpoints
                $callAspfiy = function($endpoint, $payload) use ($aspKey) {
                    $url = rtrim('https://api-v1.aspfiy.com', '/') . '/' . ltrim($endpoint, '/');
                    $ch = curl_init($url);
                    $body = json_encode($payload);
                    curl_setopt($ch, CURLOPT_RETURNTRANSFER, true);
                    curl_setopt($ch, CURLOPT_HTTPHEADER, [
                        'Content-Type: application/json',
                        'Authorization: Bearer ' . $aspKey,
                        'Content-Length: ' . strlen($body)
                    ]);
                    curl_setopt($ch, CURLOPT_POST, true);
                    curl_setopt($ch, CURLOPT_POSTFIELDS, $body);
                    curl_setopt($ch, CURLOPT_TIMEOUT, 20);
                    $resp = curl_exec($ch);
                    $err = curl_error($ch);
                    $code = curl_getinfo($ch, CURLINFO_HTTP_CODE);
                    curl_close($ch);

                    if ($err) {
                        throw new Exception('HTTP request error: ' . $err);
                    }

                    $decoded = json_decode($resp, true);
                    if (json_last_error() !== JSON_ERROR_NONE) {
                        throw new Exception('Invalid JSON from Aspfiy: ' . json_last_error_msg());
                    }

                    return ['code' => $code, 'body' => $decoded];
                };

                // Build reference and webhook (use application config or fallback)
                $referenceBase = 'PALMPAGA-' . $data->user_id . '-' . time();
                // If webhook was found in apiconfigs use it, otherwise fall back to global
                $webhookUrl = !empty($webhookUrl) ? $webhookUrl : (isset($GLOBALS['ASPFIY_WEBHOOK']) && !empty($GLOBALS['ASPFIY_WEBHOOK']) ? $GLOBALS['ASPFIY_WEBHOOK'] : null);

                // Prepare common payload fields
                $firstName = $user['sFname'] ?? '';
                $lastName = $user['sLname'] ?? '';
                $phone = $user['sPhone'] ?? '';

                // Reserve Paga
                $pagaPayload = [
                    'reference' => $referenceBase . '-PAGA',
                    'firstName' => $firstName,
                    'lastName' => $lastName,
                    'phone' => $phone,
                    // include email if available (Aspfiy may require it)
                    'email' => $user['sEmail'] ?? '',
                    // webhookUrl is required by Aspfiy - include if configured
                ];
                if (!empty($webhookUrl)) $pagaPayload['webhookUrl'] = $webhookUrl;

                error_log('Calling Aspfiy reserve-paga with payload: ' . json_encode($pagaPayload));
                $pagaResp = $callAspfiy('reserve-paga/', $pagaPayload);

                // Reserve Palmpay
                $palmpayPayload = [
                    'reference' => $referenceBase . '-PALMPAY',
                    'firstName' => $firstName,
                    'lastName' => $lastName,
                    'phone' => $phone,
                    // include email if available
                    'email' => $user['sEmail'] ?? '',
                ];
                if (!empty($webhookUrl)) $palmpayPayload['webhookUrl'] = $webhookUrl;

                error_log('Calling Aspfiy reserve-palmpay with payload: ' . json_encode($palmpayPayload));
                $palmpayResp = $callAspfiy('reserve-palmpay/', $palmpayPayload);

                // Interpret responses and persist to subscribers
                $pagaAcct = '';
                $palmpayAcct = '';
                $pagaAcctName = '';
                $pagaBankName = '';
                $palmpayAcctName = '';
                $palmpayBankName = '';

                // Robust success detection: some 200 responses may not include `data` and instead
                // return status/message. Consider success when `data` exists or `status` indicates success.
                if ($pagaResp['code'] >= 200 && $pagaResp['code'] < 300) {
                    $body = $pagaResp['body'];
                    $pagaOk = (!empty($body['data'])) || (!empty($body['status']) && (strtolower((string)$body['status']) === 'success' || $body['status'] === true || $body['status'] === 'true'));
                    if ($pagaOk && !empty($body['data']) && is_array($body['data'])) {
                        $d = $body['data'];
                        // Aspfiy may return account_number/account_name/bank_name
                        $pagaAcct = $d['account_number'] ?? $d['account'] ?? $d['accountNo'] ?? $d['reference'] ?? '';
                        $pagaAcctName = $d['account_name'] ?? $d['name'] ?? '';
                        $pagaBankName = $d['bank_name'] ?? $d['bank'] ?? '';
                        // If the extracted value is itself an array/object, try to normalize
                        if (is_array($pagaAcct) || is_object($pagaAcct)) {
                            $cand = (array)$pagaAcct;
                            $pagaAcct = $cand['account_number'] ?? $cand['accountNo'] ?? $cand['account'] ?? $cand['reference'] ?? '';
                            // Also try to pull name/bank from nested structure if empty
                            if (empty($pagaAcctName)) $pagaAcctName = $cand['account_name'] ?? $cand['name'] ?? '';
                            if (empty($pagaBankName)) $pagaBankName = $cand['bank_name'] ?? $cand['bank'] ?? '';
                        }
                        if (!empty($pagaAcct)) {
                            error_log('Aspfiy reserve-paga created account: ' . $pagaAcct);
                        } else {
                            error_log('Aspfiy reserve-paga response (no account number): ' . print_r($pagaResp, true));
                        }
                    } else {
                        // Not a success or no account returned
                        error_log('Aspfiy reserve-paga response (no account): ' . print_r($pagaResp, true));
                    }
                } else {
                    error_log('Aspfiy reserve-paga failed (http): ' . print_r($pagaResp, true));
                }

                if ($palmpayResp['code'] >= 200 && $palmpayResp['code'] < 300) {
                    $body = $palmpayResp['body'];
                    $palmOk = (!empty($body['data'])) || (!empty($body['status']) && (strtolower((string)$body['status']) === 'success' || $body['status'] === true || $body['status'] === 'true'));
                    if ($palmOk && !empty($body['data']) && is_array($body['data'])) {
                        $d = $body['data'];
                        $palmpayAcct = $d['account_number'] ?? $d['account'] ?? $d['accountNo'] ?? $d['reference'] ?? '';
                        $palmpayAcctName = $d['account_name'] ?? $d['name'] ?? '';
                        $palmpayBankName = $d['bank_name'] ?? $d['bank'] ?? '';
                        if (is_array($palmpayAcct) || is_object($palmpayAcct)) {
                            $cand = (array)$palmpayAcct;
                            $palmpayAcct = $cand['account_number'] ?? $cand['accountNo'] ?? $cand['account'] ?? $cand['reference'] ?? '';
                            if (empty($palmpayAcctName)) $palmpayAcctName = $cand['account_name'] ?? $cand['name'] ?? '';
                            if (empty($palmpayBankName)) $palmpayBankName = $cand['bank_name'] ?? $cand['bank'] ?? '';
                        }
                        if (!empty($palmpayAcct)) {
                            error_log('Aspfiy reserve-palmpay created account: ' . $palmpayAcct);
                        } else {
                            error_log('Aspfiy reserve-palmpay response (no account number): ' . print_r($palmpayResp, true));
                        }
                    } else {
                        error_log('Aspfiy reserve-palmpay response (no account): ' . print_r($palmpayResp, true));
                    }
                } else {
                    error_log('Aspfiy reserve-palmpay failed (http): ' . print_r($palmpayResp, true));
                }

                // Update subscribers table when we have values
                // Normalize account values as plain strings
                $pagaAcct = is_null($pagaAcct) ? '' : trim((string)$pagaAcct);
                $palmpayAcct = is_null($palmpayAcct) ? '' : trim((string)$palmpayAcct);

                if (!empty($pagaAcct) || !empty($palmpayAcct)) {
                    $updateParts = [];
                    $params = [];
                    if (!empty($pagaAcct)) {
                        // Save Paga account in sAsfiyBank
                        $updateParts[] = 'sAsfiyBank = ?';
                        $params[] = $pagaAcct;
                    }
                    if (!empty($palmpayAcct)) {
                        // Save Palmpay account in sPaga
                        $updateParts[] = 'sPaga = ?';
                        $params[] = $palmpayAcct;
                    }
                    // Always mark that accounts were generated in the app
                    $updateParts[] = 'sBankName = ?';
                    $params[] = 'application';
                    $params[] = $data->user_id;
                    $updateQuery = 'UPDATE subscribers SET ' . implode(', ', $updateParts) . ' WHERE sId = ?';
                    $db->query($updateQuery, $params);

                    $response['status'] = 'success';
                    $response['message'] = 'Accounts generated/updated';
                    $response['data'] = [
                        'paga_account' => $pagaAcct,
                        'paga_account_name' => $pagaAcctName,
                        'paga_bank_name' => $pagaBankName,
                        'palmpay_account' => $palmpayAcct,
                        'palmpay_account_name' => $palmpayAcctName,
                        'palmpay_bank_name' => $palmpayBankName,
                    ];
                    http_response_code(200);
                } else {
                    $response['status'] = 'error';
                    $response['message'] = 'Failed to reserve Palmpay/Paga accounts. See server logs.';
                    http_response_code(502);
                }
            } catch (PDOException $e) {
                error_log('Database error in generate-palmpay-paga: ' . $e->getMessage());
                http_response_code(503);
                $response['status'] = 'error';
                $response['message'] = 'Database service is currently unavailable.';
            } catch (Exception $e) {
                error_log('Error in generate-palmpay-paga: ' . $e->getMessage());
                http_response_code(500);
                $response['status'] = 'error';
                $response['message'] = $e->getMessage();
            }
            break;

        case 'generate-paga-only':
            // Generate Paga account only and save to sAsfiyBank
            if ($requestMethod !== 'POST') {
                http_response_code(405);
                $response['message'] = 'Method not allowed';
                break;
            }

            $data = json_decode(file_get_contents("php://input"));
            if (!isset($data->user_id)) {
                http_response_code(400);
                $response['message'] = 'Missing required parameter: user_id';
                break;
            }

            try {
                $db = new Database();

                // Ensure user exists
                $query = "SELECT sFname, sLname, sPhone, sEmail, sAsfiyBank FROM subscribers WHERE sId = ?";
                $rows = $db->query($query, [$data->user_id]);
                if (empty($rows)) {
                    throw new Exception('User not found');
                }

                $user = $rows[0];
                $paga = $user['sAsfiyBank'] ?? '';

                // If we already have Paga account, return it immediately
                if (!empty($paga)) {
                    $response['status'] = 'success';
                    $response['message'] = 'Paga account fetched';
                    $response['data'] = [
                        'paga_account' => $paga,
                    ];
                    http_response_code(200);
                    break;
                }

                // Fetch Aspfiy API key and webhook from apiconfigs
                $cfg = $db->query("SELECT name, value FROM apiconfigs WHERE name IN (?, ?)", ['asfiyApi', 'asfiyWebhook']);
                $aspKey = '';
                $webhookUrl = '';
                if (!empty($cfg)) {
                    foreach ($cfg as $c) {
                        if ($c['name'] === 'asfiyApi') $aspKey = $c['value'];
                        if ($c['name'] === 'asfiyWebhook') $webhookUrl = $c['value'];
                    }
                }
                if (empty($aspKey)) {
                    throw new Exception('Aspfiy API key not configured');
                }

                // Helper: perform POST to Aspfiy reserve endpoints
                $callAspfiy = function($endpoint, $payload) use ($aspKey) {
                    $url = rtrim('https://api-v1.aspfiy.com', '/') . '/' . ltrim($endpoint, '/');
                    $ch = curl_init($url);
                    $body = json_encode($payload);
                    curl_setopt($ch, CURLOPT_RETURNTRANSFER, true);
                    curl_setopt($ch, CURLOPT_HTTPHEADER, [
                        'Content-Type: application/json',
                        'Authorization: Bearer ' . $aspKey,
                        'Content-Length: ' . strlen($body)
                    ]);
                curl_setopt($ch, CURLOPT_POST, true);
                curl_setopt($ch, CURLOPT_POSTFIELDS, $body);
                curl_setopt($ch, CURLOPT_TIMEOUT, 20);
                $resp = curl_exec($ch);
                $err = curl_error($ch);
                $code = curl_getinfo($ch, CURLINFO_HTTP_CODE);
                curl_close($ch);

                if ($err) {
                    throw new Exception('HTTP request error: ' . $err);
                }

                $decoded = json_decode($resp, true);
                if (json_last_error() !== JSON_ERROR_NONE) {
                    throw new Exception('Invalid JSON from Aspfiy: ' . json_last_error_msg());
                }

                return ['code' => $code, 'body' => $decoded];
            };

            $referenceBase = 'PAGA-' . $data->user_id . '-' . time();
            $webhookUrl = !empty($webhookUrl) ? $webhookUrl : null;

            $firstName = $user['sFname'] ?? '';
            $lastName = $user['sLname'] ?? '';
            $phone = $user['sPhone'] ?? '';

            // Reserve Paga
            $pagaPayload = [
                'reference' => $referenceBase . '-PAGA',
                'firstName' => $firstName,
                'lastName' => $lastName,
                'phone' => $phone,
                'email' => $user['sEmail'] ?? '',
            ];
            if (!empty($webhookUrl)) $pagaPayload['webhookUrl'] = $webhookUrl;

            error_log('Calling Aspfiy reserve-paga with payload: ' . json_encode($pagaPayload));
            $pagaResp = $callAspfiy('reserve-paga/', $pagaPayload);

            $pagaAcct = '';
            $pagaAcctName = '';
            $pagaBankName = '';

            if ($pagaResp['code'] >= 200 && $pagaResp['code'] < 300) {
                $body = $pagaResp['body'];
                $pagaOk = (!empty($body['data'])) || (!empty($body['status']) && (strtolower((string)$body['status']) === 'success' || $body['status'] === true || $body['status'] === 'true'));
                if ($pagaOk && !empty($body['data']) && is_array($body['data'])) {
                    $d = $body['data'];
                    // Aspfiy may return account_number/account_name/bank_name
                    $pagaAcct = $d['account_number'] ?? $d['account'] ?? $d['accountNo'] ?? $d['reference'] ?? '';
                    $pagaAcctName = $d['account_name'] ?? $d['name'] ?? '';
                    $pagaBankName = $d['bank_name'] ?? $d['bank'] ?? '';
                    // If the extracted value is itself an array/object, try to normalize
                    if (is_array($pagaAcct) || is_object($pagaAcct)) {
                        $cand = (array)$pagaAcct;
                        $pagaAcct = $cand['account_number'] ?? $cand['accountNo'] ?? $cand['account'] ?? $cand['reference'] ?? '';
                        // Also try to pull name/bank from nested structure if empty
                        if (empty($pagaAcctName)) $pagaAcctName = $cand['account_name'] ?? $cand['name'] ?? '';
                        if (empty($pagaBankName)) $pagaBankName = $cand['bank_name'] ?? $cand['bank'] ?? '';
                    }
                    if (!empty($pagaAcct)) {
                        error_log('Aspfiy reserve-paga created account: ' . $pagaAcct);
                    } else {
                        error_log('Aspfiy reserve-paga response (no account number): ' . print_r($pagaResp, true));
                    }
                } else {
                    // Not a success or no account returned
                    error_log('Aspfiy reserve-paga response (no account): ' . print_r($pagaResp, true));
                }
            } else {
                error_log('Aspfiy reserve-paga failed (http): ' . print_r($pagaResp, true));
            }

            // Update subscribers table when we have values
            // Normalize account values as plain strings
            $pagaAcct = is_null($pagaAcct) ? '' : trim((string)$pagaAcct);

            if (!empty($pagaAcct)) {
                $updateQuery = 'UPDATE subscribers SET sAsfiyBank = ?, sBankName = ? WHERE sId = ?';
                $db->query($updateQuery, [$pagaAcct, 'application', $data->user_id]);

                $response['status'] = 'success';
                $response['message'] = 'Paga account generated/updated';
                $response['data'] = [
                    'paga_account' => $pagaAcct,
                    'paga_account_name' => $pagaAcctName,
                    'paga_bank_name' => $pagaBankName,
                ];
                http_response_code(200);
            } else {
                $response['status'] = 'error';
                $response['message'] = 'Failed to reserve Paga account. See server logs.';
                http_response_code(502);
            }
        } catch (PDOException $e) {
            error_log('Database error in generate-paga-only: ' . $e->getMessage());
            http_response_code(503);
            $response['status'] = 'error';
            $response['message'] = 'Database service is currently unavailable.';
        } catch (Exception $e) {
            error_log('Error in generate-paga-only: ' . $e->getMessage());
            http_response_code(500);
            $response['status'] = 'error';
            $response['message'] = $e->getMessage();
        }
        break;

        case 'update-pin':
            if ($requestMethod !== 'POST') {
                throw new Exception('Method not allowed');
            }

            // Get authenticated user ID from session
            $authenticatedUserId = requireAuth();

            $data = json_decode(file_get_contents("php://input"));
            if (json_last_error() !== JSON_ERROR_NONE) {
                throw new Exception('Invalid JSON: ' . json_last_error_msg());
            }

            if (!isset($data->pin)) {
                throw new Exception('Missing required parameter: pin');
            }

            try {
                $userService = new UserService();
                // Use session user ID, not client-supplied user_id
                $updated = $userService->updatePin($authenticatedUserId, $data->pin);
                if ($updated) {
                    $response['status'] = 'success';
                    $response['message'] = 'PIN updated successfully';
                    $response['data'] = null;
                    http_response_code(200);

                    // Send PIN change notification
                    try {
                        sendTransactionNotification(
                            userId: (string)$authenticatedUserId,
                            transactionType: 'pin_changed',
                            transactionData: []
                        );
                    } catch (Exception $notifError) {
                        error_log('Warning: Failed to send pin_changed notification: ' . $notifError->getMessage());
                        // Don't fail the PIN update if notification fails
                    }
                } else {
                    throw new Exception('Failed to update PIN');
                }
            } catch (PDOException $e) {
                error_log("Database error in update-pin: " . $e->getMessage());
                http_response_code(503);
                throw new Exception("Database service is currently unavailable. Please try again later.");
            } catch (Exception $e) {
                error_log("Error in update-pin: " . $e->getMessage());
                throw $e;
            }
            break;

        case 'transactions':
            // Get authenticated user ID from session
            $authenticatedUserId = requireAuth();

        // Select fields that actually exist in the `transactions` table and include oldbal/newbal
        $query = "SELECT tId, sId, transref, servicename, servicedesc, amount, status, 
                  COALESCE(oldbal, NULL) as oldbal, COALESCE(newbal, NULL) as newbal,
                  profit, date, api_response, api_response_log
              FROM transactions
              WHERE sId = ?
              ORDER BY date DESC";
            $db = new Database();
            $transactions = $db->query($query, [$authenticatedUserId]);

            // Map oldbal/newbal to string values to send to client (keep null if not present)
            // Also extract token from api_response for display
            foreach ($transactions as &$tx) {
                if (isset($tx['oldbal']) && $tx['oldbal'] !== null) {
                    $tx['oldbal'] = (string)$tx['oldbal'];
                } else {
                    $tx['oldbal'] = null;
                }
                if (isset($tx['newbal']) && $tx['newbal'] !== null) {
                    $tx['newbal'] = (string)$tx['newbal'];
                } else {
                    $tx['newbal'] = null;
                }
                // Keep response keys consistent and present for the client
                if (!isset($tx['transref'])) $tx['transref'] = '';
                if (!isset($tx['servicename'])) $tx['servicename'] = '';
                if (!isset($tx['servicedesc'])) $tx['servicedesc'] = '';
                
                // Extract token from api_response or api_response_log if available (search recursively)
                $tx['token'] = '';
                $candidates = [];
                if (!empty($tx['api_response'])) $candidates[] = $tx['api_response'];
                if (!empty($tx['api_response_log'])) $candidates[] = $tx['api_response_log'];

                $findToken = function ($node) use (&$findToken) {
                    if (is_array($node)) {
                        // direct keys
                        foreach (['token','Token','purchased_code','purchasedCode','purchasedCode','receipt'] as $k) {
                            if (isset($node[$k]) && !empty($node[$k])) return (string)$node[$k];
                        }
                        // recurse
                        foreach ($node as $v) {
                            $res = $findToken($v);
                            if ($res) return $res;
                        }
                        return null;
                    } elseif (is_string($node)) {
                        // look for patterns like 'Token : 12345' or 'Token:12345'
                        if (preg_match('/Token\s*[:\-]\s*([0-9A-Za-z\-\s]+)/i', $node, $m)) {
                            return trim($m[1]);
                        }
                        if (preg_match('/\btoken\b\s*[:\-]\s*([0-9A-Za-z\-\s]+)/i', $node, $m)) {
                            return trim($m[1]);
                        }
                        return null;
                    }
                    return null;
                };

                foreach ($candidates as $raw) {
                    try {
                        $apiResp = json_decode($raw, true);
                    } catch (Exception $e) {
                        $apiResp = null;
                    }
                    if ($apiResp === null) continue;
                    $tok = $findToken($apiResp);
                    if ($tok) {
                        // Clean token: remove 'Token :' prefix and extract first alphanumeric/hyphen group
                        $clean = trim((string)$tok);
                        if (preg_match('/Token\s*[:\-]?\s*(.+)/i', $clean, $mclean)) {
                            $clean = $mclean[1];
                        }
                        if (preg_match('/([0-9A-Za-z\-]+)/', $clean, $m2)) {
                            $clean = $m2[1];
                        }
                        $tx['token'] = $clean;
                        break;
                    }
                }
            }

            $response['data'] = $transactions;
            $response['status'] = 'success';
            $response['message'] = 'Transactions fetched successfully';
            break;

        case 'beneficiaries':
            // GET beneficiaries for authenticated user
            // Get authenticated user ID from session
            $authenticatedUserId = requireAuth();

            try {
                $svc = new BeneficiaryService();
                $rows = $svc->listByUser($authenticatedUserId);
                $response['data'] = $rows;
                $response['status'] = 'success';
                $response['message'] = 'Beneficiaries fetched successfully';
            } catch (PDOException $e) {
                http_response_code(503);
                throw new Exception('Database service is unavailable');
            }
            break;

        case 'beneficiary':
            // POST to create, PUT to update, DELETE to remove
            if ($requestMethod === 'POST') {
                // Get authenticated user ID from session
                $authenticatedUserId = requireAuth();

                $data = json_decode(file_get_contents('php://input'));
                if (!isset($data->name) || !isset($data->phone)) {
                    throw new Exception('Missing required parameters');
                }
                $svc = new BeneficiaryService();
                // Use authenticated user ID, not client-supplied user_id
                $insertId = $svc->create($authenticatedUserId, $data->name, $data->phone);
                $response['status'] = 'success';
                $response['message'] = 'Beneficiary added';
                $response['data'] = ['id' => $insertId];
            } else if ($requestMethod === 'PUT') {
                // Get authenticated user ID from session
                $authenticatedUserId = requireAuth();

                $data = json_decode(file_get_contents('php://input'));
                if (!isset($data->id) || !isset($data->name) || !isset($data->phone)) {
                    throw new Exception('Missing required parameters');
                }
                $svc = new BeneficiaryService();
                // Use authenticated user ID, not client-supplied user_id
                $ok = $svc->update($data->id, $authenticatedUserId, $data->name, $data->phone);
                $response['status'] = $ok ? 'success' : 'failed';
                $response['message'] = $ok ? 'Beneficiary updated' : 'Update failed';
            } else if ($requestMethod === 'DELETE') {
                // Get authenticated user ID from session
                $authenticatedUserId = requireAuth();

                // Expect JSON body { id: ... }
                $data = json_decode(file_get_contents('php://input'));
                if (!isset($data->id)) {
                    throw new Exception('Missing required parameter: id');
                }
                $svc = new BeneficiaryService();
                // Use authenticated user ID, not client-supplied user_id
                $ok = $svc->delete($data->id, $authenticatedUserId);
                $response['status'] = $ok ? 'success' : 'failed';
                $response['message'] = $ok ? 'Beneficiary deleted' : 'Delete failed';
            } else {
                throw new Exception('Method not allowed');
            }
            break;

        case 'manual-payments':
            // Fetch manual payment records for authenticated user
            if ($requestMethod !== 'GET') {
                http_response_code(405);
                throw new Exception('Method not allowed');
            }

            // Get authenticated user ID from session
            $authenticatedUserId = requireAuth();

            require_once __DIR__ . '/../config/database.php';

            try {
                $db = new Database();

                $query = "SELECT * FROM manualfunds WHERE sId = ? ORDER BY dPosted DESC";
                $payments = $db->query($query, [$authenticatedUserId]);

                $response['data'] = $payments;
                $response['status'] = 'success';
                $response['message'] = 'Manual payments fetched successfully';
            } catch (PDOException $e) {
                error_log("Database error in manual-payments: " . $e->getMessage());
                http_response_code(503);
                $response['status'] = 'error';
                $response['message'] = 'Database service is currently unavailable. Please try again later.';
            } catch (Exception $e) {
                error_log("Error in manual-payments: " . $e->getMessage());
                http_response_code(500);
                $response['status'] = 'error';
                $response['message'] = $e->getMessage();
            }
            break;

        case 'manual-payment':
            // Fetch a single manual payment destination (preferred: status=1), optional ?bank filter
            if ($requestMethod !== 'GET') {
                http_response_code(405);
                throw new Exception('Method not allowed');
            }
            // Return account details stored in sitesettings table (single row)
            require_once __DIR__ . '/../config/database.php';

            try {
                $db = new Database();
                // sitesettings usually has one row (sId=1). Fetch latest just in case.
                $query = "SELECT accountname, accountno, bankname FROM sitesettings ORDER BY sId DESC LIMIT 1";
                $rows = $db->query($query);

                if (!empty($rows)) {
                    $settings = $rows[0];
                    $response['data'] = [
                        'account_name' => $settings['accountname'] ?? '',
                        'account_number' => $settings['accountno'] ?? '',
                        'bank_name' => $settings['bankname'] ?? '',
                    ];
                    $response['status'] = 'success';
                    $response['message'] = 'Manual payment settings fetched successfully';
                } else {
                    $response['data'] = null;
                    $response['status'] = 'error';
                    $response['message'] = 'Site settings not found';
                }
            } catch (PDOException $e) {
                error_log("Database error in manual-payment (sitesettings): " . $e->getMessage());
                http_response_code(503);
                $response['status'] = 'error';
                $response['message'] = 'Database service is currently unavailable. Please try again later.';
            } catch (Exception $e) {
                error_log("Error in manual-payment (sitesettings): " . $e->getMessage());
                http_response_code(500);
                $response['status'] = 'error';
                $response['message'] = $e->getMessage();
            }
            break;

        case 'send-manual-proof':
            // Accepts POST with JSON body: amount, bank, sender, optional account_number, account_name, bank_name, user_id
            if ($requestMethod !== 'POST') {
                http_response_code(405);
                $response['message'] = 'Method not allowed';
                break;
            }

            $rawInput = file_get_contents("php://input");
            error_log("send-manual-proof raw input: " . $rawInput);

            $data = json_decode($rawInput);
            if (json_last_error() !== JSON_ERROR_NONE) {
                http_response_code(400);
                $response['message'] = 'Invalid JSON';
                break;
            }

            if (!isset($data->amount) || !isset($data->bank) || !isset($data->sender)) {
                http_response_code(400);
                $response['message'] = 'Missing required parameters: amount, bank, sender';
                break;
            }

            $amount = $data->amount;
            $bank = $data->bank;
            $sender = $data->sender;
            $accountNumber = isset($data->account_number) ? $data->account_number : '';
            $accountName = isset($data->account_name) ? $data->account_name : '';
            $bankName = isset($data->bank_name) ? $data->bank_name : '';

            // Load PHPMailer
            require_once __DIR__ . '/../vendor/autoload.php';
            

            try {
                $mail = new \PHPMailer\PHPMailer\PHPMailer(true);

                // SMTP settings from environment
                $mail->isSMTP();
                $mail->Host = getenv('MAIL_HOST') ?: 'mail.mkdata.com';
                $mail->SMTPAuth = true;
                $mail->Username = getenv('MAIL_USERNAME') ?: 'no-reply@mkdata.com';
                $mail->Password = getenv('MAIL_PASSWORD');
                
                // Verify password is set
                if (!$mail->Password) {
                    throw new Exception('MAIL_PASSWORD not configured in environment');
                }

                // Use STARTTLS for port 587
                $mail->SMTPSecure = PHPMailer::ENCRYPTION_STARTTLS;
                $mail->Port = 587;

                $mail->setFrom(getenv('MAIL_USERNAME') ?: 'no-reply@mkdata.com', getenv('MAIL_FROM_NAME') ?: 'MK Data');
                $mail->addAddress('Muhammadbinali1234@gmail.com');

                $mail->isHTML(true);
                $mail->Subject = 'Manual Payment Proof Submission';

                $body = "<h3>Manual Payment Proof</h3>";
                $body .= "<p><strong>Amount:</strong> ₦" . htmlspecialchars($amount) . "</p>";
                $body .= "<p><strong>Bank Provided:</strong> " . htmlspecialchars($bank) . "</p>";
                if (!empty($bankName)) $body .= "<p><strong>Bank Name:</strong> " . htmlspecialchars($bankName) . "</p>";
                if (!empty($accountNumber)) $body .= "<p><strong>Account Number:</strong> " . htmlspecialchars($accountNumber) . "</p>";
                if (!empty($accountName)) $body .= "<p><strong>Account Name:</strong> " . htmlspecialchars($accountName) . "</p>";
                $body .= "<p><strong>Sender:</strong> " . htmlspecialchars($sender) . "</p>";
                // prefer subscriber id sent by client (sId) but accept user_id for backwards compatibility
                $submittedSid = isset($data->sId) ? $data->sId : (isset($data->user_id) ? $data->user_id : '');
                if (!empty($submittedSid)) $body .= "<p><strong>Subscriber ID:</strong> " . htmlspecialchars($submittedSid) . "</p>";
                $body .= "<p>Posted at: " . date('Y-m-d H:i:s') . "</p>";

                $mail->Body = $body;
                $mail->AltBody = strip_tags(str_replace(['<br>', '<br/>', '<p>', '</p>'], "\n", $body));

                $mail->send();

                // Also insert the proof record into the manualfunds table
                try {
                    require_once __DIR__ . '/../config/database.php';
                    $db = new Database();
                    $conn = $db->getConnection();

                    // Build account field using what the user submitted. If the user sent
                    // account_name and account_number, prefer those. Fallback to sender
                    // name only when the user did not provide account info.
                    $accountField = trim((!empty($accountName) ? $accountName . ' ' : '') . (!empty($accountNumber) ? $accountNumber : ''));
                    if (empty($accountField)) {
                        $accountField = $sender;
                    }

                    // Prefer the explicit bank name provided by the user (bank_name),
                    // otherwise use the provided 'bank' value.
                    $methodField = !empty($bankName) ? $bankName : $bank;

                    // Prefer 'sId' (subscriber id) if provided by the client, else accept user_id.
                    $sId = isset($data->sId) ? $data->sId : (isset($data->user_id) ? $data->user_id : '');
                    $statusVal = 0; // default pending
                    $postedAt = date('Y-m-d H:i:s');

                    $insertStmt = $conn->prepare("INSERT INTO manualfunds (sId, amount, account, method, status, dPosted) VALUES (?, ?, ?, ?, ?, ?)");
                    $insertStmt->execute([$sId, $amount, $accountField, $methodField, $statusVal, $postedAt]);
                    $insertId = $conn->lastInsertId();

                    $response['status'] = 'success';
                    $response['message'] = 'Proof email sent and record saved successfully';
                    $response['data'] = ['insert_id' => $insertId];
                } catch (Exception $e) {
                    error_log('Error inserting manual proof into DB: ' . $e->getMessage());
                    http_response_code(500);
                    $response['status'] = 'error';
                    $response['message'] = 'Email sent but failed to save record: ' . $e->getMessage();
                    $response['data'] = null;
                }
            } catch (Exception $e) {
                error_log('Error sending manual proof email: ' . $e->getMessage());
                http_response_code(500);
                $response['status'] = 'error';
                $response['message'] = 'Unable to send email: ' . $e->getMessage();
            }

            break;

        case 'account-details':
            // Get authenticated user ID from session (ignore any client-supplied id)
            $subscriberId = requireAuth();

            $query = "SELECT sId, sFname, sLname, sEmail, sPhone, sType, sWallet, sRefWallet,
                sBankNo, sSterlingBank, sBankName, sRolexBank, sFidelityBank, sAsfiyBank,
                s9PSBBank, sPayvesselBank, sPaga, sPagaBank, sPalmpayBank, sRegStatus, sLastActivity,
                sAccountLimit
                FROM subscribers WHERE sId = ?";

            $db = new Database();
            $result = $db->query($query, [$subscriberId]);

            if (empty($result)) {
                throw new Exception('Account details not found');
            }

            $account = $result[0];
            error_log("Raw account data from database: " . print_r($account, true));

            $response['data'] = [
                'sId' => $account['sId'],
                'sFname' => $account['sFname'],
                'sLname' => $account['sLname'],
                'sEmail' => $account['sEmail'],
                'sPhone' => $account['sPhone'],
                'sType' => (int)$account['sType'],
                'sWallet' => (float)$account['sWallet'],
                'sRefWallet' => (float)$account['sRefWallet'],
                'sBankNo' => $account['sBankNo'],
                'sSterlingBank' => $account['sSterlingBank'],
                'sBankName' => $account['sBankName'],
                'sRolexBank' => $account['sRolexBank'],
                'sFidelityBank' => $account['sFidelityBank'],
                'sAsfiyBank' => $account['sAsfiyBank'],
                's9PSBBank' => $account['s9PSBBank'],
                'sPayvesselBank' => $account['sPayvesselBank'],
                'sPagaBank' => $account['sPagaBank'],
                'sPaga' => $account['sPaga'],
                'sPalmpayBank' => $account['sPalmpayBank'],
                'sAccountLimit' => $account['sAccountLimit']
            ];
            error_log("Formatted response data: " . json_encode($response['data'], JSON_PRETTY_PRINT));
            $response['status'] = 'success';
            $response['message'] = 'Account details fetched successfully';
            break;

        case 'subscriber':
            $subscriberId = isset($_GET['id']) ? $_GET['id'] : null;
            if (!$subscriberId) {
                throw new Exception('Subscriber ID is required');
            }

            $query = "SELECT sId, sFname, sLname, sEmail, sPhone, sType, sWallet, sRefWallet, 
                sBankNo, sSterlingBank, sBankName, sRegStatus, sLastActivity,
                sRolexBank, sFidelityBank, sPaga ,sAsfiyBank, s9PSBBank, sPayvesselBank, 
                sPagaBank, sPalmpayBank 
                FROM subscribers WHERE sId = ?";

            $db = new Database();
            $result = $db->query($query, [$subscriberId]);

            if (empty($result)) {
                throw new Exception('Subscriber not found');
            }

            $subscriber = $result[0];
            // Format the response
            $response['data'] = [
                'sId' => $subscriber['sId'],
                'sFname' => $subscriber['sFname'],
                'sLname' => $subscriber['sLname'],
                'sEmail' => $subscriber['sEmail'],
                'sPhone' => $subscriber['sPhone'],
                'sType' => (int)$subscriber['sType'],
                'sWallet' => (float)$subscriber['sWallet'],
                'sRefWallet' => (float)$subscriber['sRefWallet'],
                'sBankNo' => $subscriber['sBankNo'],
                'sSterlingBank' => $subscriber['sSterlingBank'],
                'sBankName' => $subscriber['sBankName'],
                'sRolexBank' => $subscriber['sRolexBank'],
                'sFidelityBank' => $subscriber['sFidelityBank'],
                'sAsfiyBank' => $subscriber['sAsfiyBank'],
                's9PSBBank' => $subscriber['s9PSBBank'],
                'sPayvesselBank' => $subscriber['sPayvesselBank'],
                'sPagaBank' => $subscriber['sPagaBank'],
                'sPaga' => $subscriber['sPaga'],
                'sPalmpayBank' => $subscriber['sPalmpayBank'],
                'sRegStatus' => (int)$subscriber['sRegStatus'],
                'lastActivity' => $subscriber['sLastActivity']
            ];
            $response['status'] = 'success';
            $response['message'] = 'Subscriber details fetched successfully';
            break;

        case 'update-profile':
            if ($requestMethod !== 'POST') {
                throw new Exception('Method not allowed');
            }

            // Get authenticated user ID from session
            $authenticatedUserId = requireAuth();

            $data = json_decode(file_get_contents("php://input"));
            
            // Validate required fields
            if (!isset($data->fname) && !isset($data->lname) && !isset($data->new_password)) {
                throw new Exception('At least one field (fname, lname, or new_password) must be provided');
            }

            try {
                $user_service = new UserService();
                
                // Prepare update data
                $updates = [];
                $params = [];

                // Update first name if provided
                if (isset($data->fname) && !empty($data->fname)) {
                    $updates[] = 'sFname = ?';
                    $params[] = trim($data->fname);
                }

                // Update last name if provided
                if (isset($data->lname) && !empty($data->lname)) {
                    $updates[] = 'sLname = ?';
                    $params[] = trim($data->lname);
                }

                // Update password if provided
                if (isset($data->new_password) && !empty($data->new_password)) {
                    // Verify current password first
                    if (!isset($data->current_password) || empty($data->current_password)) {
                        throw new Exception('Current password is required to change password');
                    }

                    // Get current password hash from database
                    $db = new Database();
                    $result = $db->query('SELECT sPass FROM subscribers WHERE sId = ? LIMIT 1', [$authenticatedUserId]);
                    
                    if (empty($result)) {
                        throw new Exception('User not found');
                    }

                    // Verify current password using website-compatible hash
                    $currentHashedPassword = $result[0]['sPass'];
                    $providedHash = substr(sha1(md5($data->current_password)), 3, 10);
                    if ($currentHashedPassword !== $providedHash) {
                        throw new Exception('Current password is incorrect');
                    }

                    // Hash new password using website-compatible hash
                    $newPasswordHash = substr(sha1(md5($data->new_password)), 3, 10);
                    $updates[] = 'sPass = ?';
                    $params[] = $newPasswordHash;
                }

                if (empty($updates)) {
                    throw new Exception('No valid updates provided');
                }

                // Add user_id to params for WHERE clause
                $params[] = $authenticatedUserId;

                // Build and execute update query
                $updateQuery = 'UPDATE subscribers SET ' . implode(', ', $updates) . ' WHERE sId = ?';
                $db = new Database();
                $stmt = $db->getConnection()->prepare($updateQuery);
                $stmt->execute($params);

                if ($stmt->rowCount() > 0) {
                    // Fetch updated user data
                    $result = $db->query('SELECT sId, sFname, sLname, sEmail, sPhone FROM subscribers WHERE sId = ? LIMIT 1', [$authenticatedUserId]);
                    
                    if (!empty($result)) {
                        $response['status'] = 'success';
                        $response['message'] = 'Profile updated successfully';
                        $response['data'] = [
                            'user_id' => $result[0]['sId'],
                            'fname' => $result[0]['sFname'],
                            'lname' => $result[0]['sLname'],
                            'email' => $result[0]['sEmail'],
                            'phone' => $result[0]['sPhone']
                        ];

                        // Send profile_updated notification
                        try {
                            sendTransactionNotification(
                                userId: (string)$authenticatedUserId,
                                transactionType: 'profile_updated',
                                transactionData: []
                            );
                        } catch (Exception $notifError) {
                            error_log('Warning: Failed to send profile_updated notification: ' . $notifError->getMessage());
                            // Don't fail the profile update if notification fails
                        }
                    } else {
                        throw new Exception('Failed to fetch updated profile');
                    }
                } else {
                    throw new Exception('Failed to update profile');
                }

            } catch (PDOException $e) {
                error_log("Database error in update-profile: " . $e->getMessage());
                http_response_code(503);
                throw new Exception("Database service is currently unavailable. Please try again later.");
            } catch (Exception $e) {
                error_log("Error in update-profile: " . $e->getMessage());
                throw $e;
            }
            break;

        case 'past-questions':
            if ($requestMethod !== 'GET') {
                throw new Exception('Method not allowed. Use GET');
            }

            try {
                $db = new Database();
                
                // Optional filters
                $exam = $_GET['exam'] ?? null;
                $subject = $_GET['subject'] ?? null;
                $year = $_GET['year'] ?? null;

                // Build query
                $query = "SELECT id, name, exam, subject, file, year, created_at FROM past_questions WHERE 1=1";
                $params = [];

                if ($exam) {
                    $query .= " AND exam = ?";
                    $params[] = $exam;
                }

                if ($subject) {
                    $query .= " AND subject = ?";
                    $params[] = $subject;
                }

                if ($year) {
                    $query .= " AND year = ?";
                    $params[] = (int)$year;
                }

                $query .= " ORDER BY year DESC, created_at DESC";

                $results = $db->query($query, $params);

                if ($results === false) {
                    throw new Exception('Failed to fetch past questions');
                }

                $response = [
                    'status' => 'success',
                    'message' => 'Past questions retrieved successfully',
                    'data' => $results
                ];
            } catch (Exception $e) {
                error_log("Error in past-questions: " . $e->getMessage());
                http_response_code(500);
                throw $e;
            }
            break;

        case 'purchase-daily-data':
            if ($requestMethod !== 'POST') {
                throw new Exception('Method not allowed. Use POST');
            }

            // Initialize response variable
            $response = [
                'status' => 'error',
                'message' => 'Unknown error',
                'data' => null
            ];

            try {
                // Read raw input once and log for debugging (helps detect empty body issues)
                $rawInput = file_get_contents("php://input");
                error_log("purchase-daily-data raw input: " . var_export($rawInput, true));
                $input = json_decode($rawInput, true);

                // Validate required fields
                $userId = $input['user_id'] ?? null;
                $planId = $input['plan_id'] ?? null;
                $networkName = $input['network'] ?? null;
                $phoneNumber = $input['phone_number'] ?? null;
                $userType = $input['user_type'] ?? null;
                $pricePerDay = floatval($input['price_per_day'] ?? 0);
                $totalDays = intval($input['total_days'] ?? 0);
                $pin = $input['pin'] ?? null;

                // Validation
                if (!$userId || !$planId || !$networkName || !$phoneNumber || !$userType || $pricePerDay <= 0 || $totalDays <= 0) {
                    throw new Exception('Missing or invalid required fields');
                }

                if (strlen($pin) !== 4 || !is_numeric($pin)) {
                    throw new Exception('Invalid PIN format');
                }

                $db = new Database();

                // Verify user exists and get wallet balance
                $userQuery = "SELECT sId, sWallet, sPass FROM subscribers WHERE sId = ? LIMIT 1";
                $userResult = $db->query($userQuery, [$userId]);
                if (empty($userResult)) {
                    throw new Exception('User not found');
                }

                $userWallet = floatval($userResult[0]['sWallet']);
                $totalAmount = $pricePerDay * $totalDays;

                // Check wallet balance
                if ($userWallet < $totalAmount) {
                    throw new Exception('Insufficient wallet balance');
                }

                // Verify PIN
                $storedPin = $userResult[0]['sPass']; // Note: This should be compared with website hash
                // For now, we're assuming PIN verification happens on client side with stored login_pin
                // The app should verify the PIN before sending it

                // Generate transaction reference
                $transactionRef = 'DD' . time() . bin2hex(random_bytes(4));

                // Calculate next delivery date (first delivery at current time)
                $nextDeliveryDate = new DateTime('now');
                
                // Try first delivery but don't fail the whole purchase if it fails
                error_log("purchase-daily-data: attempting first data delivery. Phone: " . $phoneNumber . ", Network: " . $networkName . ", Plan: " . $planId . ", User: " . $userId);
                
                $firstDeliverySuccess = false;
                $deliveryResult = null;
                $deliveryError = null;
                
                try {
                    $service = new DataService();
                    $deliveryResult = $service->purchaseData(
                        resolveNetworkIdFromInput($networkName) ?? $networkName,
                        $phoneNumber,
                        $planId,
                        $userId
                    );
                    
                    if ($deliveryResult && ($deliveryResult['status'] === 'success' || $deliveryResult['status'] === 'processing')) {
                        error_log("purchase-daily-data: first delivery successful. Result: " . json_encode($deliveryResult));
                        $firstDeliverySuccess = true;
                    } else {
                        error_log("purchase-daily-data: first delivery failed. Result: " . json_encode($deliveryResult));
                        $deliveryError = $deliveryResult['message'] ?? 'Unknown error';
                    }
                } catch (Exception $deliveryEx) {
                    error_log("purchase-daily-data: first delivery exception: " . $deliveryEx->getMessage());
                    $deliveryError = $deliveryEx->getMessage();
                    // Don't rethrow - continue with plan setup even if delivery fails
                }

                // Remaining days calculation: if first delivery succeeded, decrement by 1; otherwise keep full total
                $remainingDays = $firstDeliverySuccess ? ($totalDays - 1) : $totalDays;

                // Insert into daily_data_plans table
                $insertQuery = "INSERT INTO daily_data_plans 
                    (user_id, plan_id, network, phone_number, user_type, price_per_day, total_days, remaining_days, next_delivery_date, transaction_reference, status)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 'active')";

                $params = [
                    $userId,
                    $planId,
                    $networkName,
                    $phoneNumber,
                    $userType,
                    $pricePerDay,
                    $totalDays,
                    $remainingDays,
                    $nextDeliveryDate->format('Y-m-d H:i:s'),
                    $transactionRef
                ];

                // Log insert attempt for debugging
                error_log("purchase-daily-data: executing insert into daily_data_plans. Query: " . $insertQuery . " Params: " . json_encode($params));
                    try {
                    $insertResult = $db->execute($insertQuery, $params);
                    $lastId = null;
                    try {
                        $lastId = $db->lastInsertId();
                    } catch (Exception $e) {
                        error_log("purchase-daily-data: failed to fetch lastInsertId: " . $e->getMessage());
                    }
                    error_log("purchase-daily-data: insert result (affected rows): " . var_export($insertResult, true) . ", lastInsertId: " . var_export($lastId, true));
                    if (!$insertResult || $insertResult === 0) {
                        error_log("purchase-daily-data: insert returned falsy or 0 rows affected. Params: " . json_encode($params));
                        throw new Exception('Failed to save daily data plan');
                    }
                } catch (Exception $dbEx) {
                    error_log("purchase-daily-data: insert error: " . $dbEx->getMessage());
                    // Rethrow to be handled by the outer catch which sends JSON error
                    throw $dbEx;
                }

                // Deduct amount from wallet
                $updateWalletQuery = "UPDATE subscribers SET sWallet = sWallet - ? WHERE sId = ?";
                // Update wallet and log
                error_log("purchase-daily-data: executing wallet update. Query: " . $updateWalletQuery . " Params: " . json_encode([$totalAmount, $userId]));
                try {
                    $walletUpdateResult = $db->execute($updateWalletQuery, [$totalAmount, $userId]);
                    if (!$walletUpdateResult) {
                        error_log("purchase-daily-data: wallet update returned falsy result");
                        throw new Exception('Failed to update wallet');
                    }
                } catch (Exception $dbEx) {
                    error_log("purchase-daily-data: wallet update error: " . $dbEx->getMessage());
                    throw $dbEx;
                }

                // Insert transaction record
                $transactionQuery = "INSERT INTO transactions 
                    (sId, servicename, servicedesc, amount, status, oldbal, newbal, transref, date, api_response_log) 
                    VALUES (?, 'daily_data', ?, ?, 'success', ?, ?, ?, NOW(), ?)";
                
                $newBalance = $userWallet - $totalAmount;
                $transactionDescription = $userType . ' - ' . $planId . ' (' . $totalDays . ' days @ ₦' . $pricePerDay . '/day) to ' . $phoneNumber;
                $apiLog = 'Daily data plan purchase: ' . $transactionRef . ' (First delivery: ' . ($firstDeliverySuccess ? 'success' : ($deliveryError ? 'failed - ' . $deliveryError : 'pending')) . ')';
                
                error_log("purchase-daily-data: inserting transaction record. Query: " . $transactionQuery . " Params: " . json_encode([$userId, $transactionDescription, $totalAmount, $userWallet, $newBalance, $transactionRef, $apiLog]));
                try {
                    $txnResult = $db->execute($transactionQuery, [
                        $userId,
                        $transactionDescription,
                        $totalAmount,
                        $userWallet,
                        $newBalance,
                        $transactionRef,
                        $apiLog
                    ]);
                    if (!$txnResult) {
                        error_log("purchase-daily-data: transaction insert returned falsy result");
                        throw new Exception('Failed to save transaction record');
                    }
                } catch (Exception $dbEx) {
                    error_log("purchase-daily-data: transaction insert error: " . $dbEx->getMessage());
                    throw $dbEx;
                }

                // Prepare response
                $responseMessage = 'Daily data plan purchased successfully.';
                if ($firstDeliverySuccess) {
                    $responseMessage .= ' First delivery sent successfully.';
                } else if ($deliveryError) {
                    $responseMessage .= ' First delivery failed (' . $deliveryError . '), but will retry later. Remaining deliveries will be sent daily.';
                } else {
                    $responseMessage .= ' First delivery pending. Remaining deliveries will be sent daily.';
                }
                
                $response = [
                    'status' => 'success',
                    'message' => $responseMessage,
                    'data' => [
                        'transaction_reference' => $transactionRef,
                        'user_id' => $userId,
                        'phone_number' => $phoneNumber,
                        'network' => $networkName,
                        'user_type' => $userType,
                        'price_per_day' => $pricePerDay,
                        'total_days' => $totalDays,
                        'remaining_days' => $remainingDays,
                        'total_amount' => $totalAmount,
                        'next_delivery_date' => $nextDeliveryDate->format('Y-m-d H:i:s'),
                        'new_wallet_balance' => $newBalance
                    ]
                ];

                // Send push notification
                sendTransactionNotification(
                    userId: $userId,
                    transactionType: 'daily_data',
                    transactionData: [
                        'transaction_id' => $transactionRef,
                        'plan' => $totalDays . ' day' . ($totalDays > 1 ? 's' : '') . ' daily data',
                        'servicename' => 'daily_data',
                        'servicedesc' => $transactionDescription,
                        'amount' => $totalAmount,
                        'network' => $networkName,
                        'phone' => $phoneNumber,
                        'total_days' => $totalDays,
                        'price_per_day' => $pricePerDay
                    ]
                );

            } catch (Exception $e) {
                error_log("Error in purchase-daily-data: " . $e->getMessage());
                http_response_code(400);
                $response['status'] = 'error';
                $response['message'] = $e->getMessage();
            }
            // Ensure we always send a JSON response for this endpoint and stop further routing
            header('Content-Type: application/json; charset=UTF-8');
            // Log the response we are about to send (helps troubleshoot empty body issues)
            error_log("purchase-daily-data response: " . var_export($response, true));
            // Clear output buffers to avoid accidental empty responses from earlier output
            if (function_exists('ob_get_level') && ob_get_level() > 0) {
                while (ob_get_level() > 0) {
                    @ob_end_clean();
                }
            }
            echo json_encode($response);
            exit();
            break;

        case 'spin-rewards':
            // GET /api/spin-rewards - Get all active rewards with weights
            if ($requestMethod !== 'GET') {
                throw new Exception('Method not allowed');
            }

            try {
                $db = new Database();
                $query = "SELECT id, code, name, type, amount, unit, plan_id, weight, active, created_at, updated_at FROM spin_rewards WHERE active = 1 ORDER BY weight DESC";
                $rewards = $db->query($query);

                if (empty($rewards)) {
                    // Log if no rewards found - this helps with debugging
                    error_log("No active spin rewards found in database");
                    // Still return success but with empty data - frontend will handle this
                }

                $response['status'] = 'success';
                $response['message'] = 'Spin rewards fetched successfully';
                $response['data'] = $rewards ?: [];
            } catch (PDOException $e) {
                error_log("Database error in spin-rewards: " . $e->getMessage());
                http_response_code(503);
                throw new Exception("Database service is currently unavailable");
            } catch (Exception $e) {
                error_log("Error in spin-rewards: " . $e->getMessage());
                http_response_code(500);
                throw new Exception("Error fetching spin rewards: " . $e->getMessage());
            }
            break;

        case 'perform-spin':
            // POST /api/perform-spin - Perform a spin, check cooldown, and return reward
            if ($requestMethod !== 'POST') {
                throw new Exception('Method not allowed');
            }

            try {
                $input = json_decode(file_get_contents("php://input"), true);
                $userId = $input['user_id'] ?? null;
                $phoneNumber = $input['phone_number'] ?? null;
                $network = $input['network'] ?? null;

                if (!$userId) {
                    throw new Exception('Missing required parameter: user_id');
                }

                $db = new Database();

                // Check if user exists
                $userQuery = "SELECT sId, sWallet FROM subscribers WHERE sId = ? LIMIT 1";
                $userResult = $db->query($userQuery, [$userId]);
                if (empty($userResult)) {
                    throw new Exception('User not found');
                }

                // Check last spin time (72 hours = 259200 seconds)
                $lastSpinQuery = "SELECT MAX(spin_at) as last_spin FROM spin_wins WHERE user_id = ?";
                $lastSpinResult = $db->query($lastSpinQuery, [$userId]);
                $lastSpinTime = null;

                error_log("Spin query result: " . json_encode($lastSpinResult));

                if (!empty($lastSpinResult) && !empty($lastSpinResult[0]['last_spin'])) {
                    $lastSpinDateStr = $lastSpinResult[0]['last_spin'];
                    $lastSpinTime = strtotime($lastSpinDateStr);
                    error_log("Last spin time for user $userId: '$lastSpinDateStr' (timestamp: $lastSpinTime)");

                    // Validate the strtotime result
                    if ($lastSpinTime === false) {
                        error_log("WARNING: strtotime failed to parse date: '$lastSpinDateStr'");
                        // If strtotime fails, try using DateTime instead
                        try {
                            $dateObj = new DateTime($lastSpinDateStr);
                            $lastSpinTime = $dateObj->getTimestamp();
                            error_log("Recovered using DateTime: $lastSpinTime");
                        } catch (Exception $e) {
                            error_log("Failed to parse date with DateTime: " . $e->getMessage());
                            $lastSpinTime = null;
                        }
                    }
                } else {
                    error_log("No previous spins found for user $userId - first spin allowed");
                }

                $currentTime = time();
                $cooldownPeriod = 259200; // 72 hours in seconds
                $timeUntilNextSpin = null;

                if ($lastSpinTime !== null && $lastSpinTime !== false) {
                    $timeSinceLastSpin = $currentTime - $lastSpinTime;
                    error_log("Current time: $currentTime, Last spin time: $lastSpinTime, Time since last spin: $timeSinceLastSpin seconds (cooldown period: $cooldownPeriod seconds)");

                    if ($timeSinceLastSpin < $cooldownPeriod) {
                        $timeUntilNextSpin = $cooldownPeriod - $timeSinceLastSpin;
                        error_log("Cooldown active. Time until next spin: $timeUntilNextSpin seconds");
                        http_response_code(429);
                        throw new Exception(json_encode([
                            'error' => 'COOLDOWN_ACTIVE',
                            'message' => 'You can spin again in ' . $timeUntilNextSpin . ' seconds',
                            'time_until_next_spin' => $timeUntilNextSpin
                        ]));
                    } else {
                        error_log("Cooldown period has passed. User can spin now.");
                    }
                }

                // Get all active rewards with weights
                $rewardsQuery = "SELECT id, code, name, type, amount, unit, plan_id, weight FROM spin_rewards WHERE active = 1";
                $rewards = $db->query($rewardsQuery);

                if (empty($rewards)) {
                    throw new Exception('No rewards available');
                }

                // Calculate weighted random selection
                $totalWeight = 0;
                foreach ($rewards as $reward) {
                    $totalWeight += floatval($reward['weight']);
                }

                $randomValue = (mt_rand() / mt_getrandmax()) * $totalWeight;
                $cumulativeWeight = 0;
                $selectedReward = null;

                foreach ($rewards as $reward) {
                    $cumulativeWeight += floatval($reward['weight']);
                    if ($randomValue <= $cumulativeWeight) {
                        $selectedReward = $reward;
                        break;
                    }
                }

                if ($selectedReward === null) {
                    $selectedReward = end($rewards);
                }

                // Record the spin in spin_wins table
                $spinAt = date('Y-m-d H:i:s');
                $meta = json_encode([
                    'phone' => $phoneNumber ?? '',
                    'network' => $network ?? ''
                ]);

                $insertQuery = "INSERT INTO spin_wins (user_id, reward_id, reward_type, amount, unit, plan_id, status, meta, spin_at) 
                               VALUES (?, ?, ?, ?, ?, ?, 'pending', ?, ?)";
                
                $params = [
                    $userId,
                    $selectedReward['id'],
                    $selectedReward['type'],
                    $selectedReward['amount'] ?? null,
                    $selectedReward['unit'] ?? null,
                    $selectedReward['plan_id'] ?? null,
                    $meta,
                    $spinAt
                ];

                $insertResult = $db->query($insertQuery, $params, false);

                error_log("Spin record insert result: " . var_export($insertResult, true));

                // Get the newly inserted record ID using PDO directly
                $spinWinId = $db->getConnection()->lastInsertId();
                error_log("New spin win ID: $spinWinId");
                
                // Check if insert was successful by verifying we got an ID
                // Note: Some database drivers return 0 for rowCount() on INSERT, so we check lastInsertId instead
                if (!$spinWinId || $spinWinId == 0) {
                    error_log("Failed to insert spin record. Got no insert ID. Affected rows: " . var_export($insertResult, true));
                    throw new Exception('Failed to record spin');
                }

                error_log("Spin recorded successfully for user $userId with ID: $spinWinId");

                // Fetch the newly inserted record
                $fetchQuery = "SELECT id, user_id, reward_id, reward_type, amount, unit, plan_id, status, meta, spin_at, delivered_at 
                              FROM spin_wins WHERE id = ? LIMIT 1";
                
                $spinWinRecord = null;
                try {
                    error_log("Attempting to fetch spin record with ID: $spinWinId");
                    $spinWinRecord = $db->query($fetchQuery, [$spinWinId]);
                    error_log("Fetch result type: " . gettype($spinWinRecord));
                    error_log("Fetch result count: " . (is_array($spinWinRecord) ? count($spinWinRecord) : 'N/A'));
                    
                    if (is_array($spinWinRecord) && count($spinWinRecord) > 0) {
                        error_log("Fetched spin record data: " . json_encode($spinWinRecord[0]));
                    }
                } catch (Exception $fetchError) {
                    error_log("Error fetching spin record: " . $fetchError->getMessage());
                    error_log("Fetch error stack: " . $fetchError->getTraceAsString());
                    $spinWinRecord = null;
                }

                // Return the complete spin win record
                $response['status'] = 'success';
                $response['message'] = 'Spin completed successfully';
                error_log("Setting response status to success");
                
                if (!empty($spinWinRecord) && is_array($spinWinRecord) && count($spinWinRecord) > 0) {
                    error_log("Using fetched record for response data");
                    $response['data'] = $spinWinRecord[0];
                    // Send push notification about spin win
                    try {
                        sendTransactionNotification($userId, 'spin_win', [
                            'spin_id' => $spinWinRecord[0]['id'],
                            'reward_type' => $spinWinRecord[0]['reward_type'],
                            'amount' => $spinWinRecord[0]['amount'],
                            'unit' => $spinWinRecord[0]['unit'] ?? null,
                        ]);
                    } catch (Exception $e) {
                        error_log('Failed to send spin win notification: ' . $e->getMessage());
                    }
                } else {
                    // Fallback to constructed data if fetch failed
                    error_log("Using fallback constructed record for response data");
                    $response['data'] = [
                        'id' => $spinWinId,
                        'user_id' => $userId,
                        'reward_id' => $selectedReward['id'],
                        'reward_type' => $selectedReward['type'],
                        'amount' => $selectedReward['amount'],
                        'unit' => $selectedReward['unit'],
                        'plan_id' => $selectedReward['plan_id'] ?? null,
                        'status' => 'pending',
                        'meta' => $meta,
                        'spin_at' => $spinAt,
                        'delivered_at' => null
                    ];
                    // Try to send a notification even when fetch fallback used
                    try {
                        sendTransactionNotification($userId, 'spin_win', [
                            'spin_id' => $spinWinId,
                            'reward_type' => $selectedReward['type'],
                            'amount' => $selectedReward['amount'],
                            'unit' => $selectedReward['unit'] ?? null,
                        ]);
                    } catch (Exception $e) {
                        error_log('Failed to send spin win notification (fallback): ' . $e->getMessage());
                    }
                }
                error_log("Response data set successfully: " . json_encode($response));

            } catch (Exception $e) {
                error_log("Error in perform-spin: " . $e->getMessage());
                
                // Check if this is a cooldown error
                $errorMessage = $e->getMessage();
                if (strpos($errorMessage, 'COOLDOWN_ACTIVE') !== false) {
                    http_response_code(429); // Too Many Requests
                    $errorData = json_decode($errorMessage, true);
                    $response['status'] = 'error';
                    $response['message'] = $errorData['message'] ?? 'Cooldown period active';
                    $response['data'] = ['time_until_next_spin' => $errorData['time_until_next_spin'] ?? null];
                } else {
                    http_response_code(400);
                    $response['status'] = 'error';
                    $response['message'] = $e->getMessage();
                }
            }
            break;

        case 'spin-history':
            // GET /api/spin-history?user_id=123 - Get user's spin history
            if ($requestMethod !== 'GET') {
                throw new Exception('Method not allowed');
            }

            try {
                $userId = $_GET['user_id'] ?? null;
                if (!$userId) {
                    throw new Exception('Missing required parameter: user_id');
                }

                $db = new Database();
                $query = "SELECT sw.id, sw.user_id, sw.reward_id, sw.reward_type, sw.amount, sw.unit, sw.plan_id, 
                         sw.status, sw.meta, sw.spin_at, sw.delivered_at
                         FROM spin_wins sw
                         WHERE sw.user_id = ?
                         ORDER BY sw.spin_at DESC
                         LIMIT 50";
                
                $history = $db->query($query, [$userId]);

                $response['status'] = 'success';
                $response['message'] = 'Spin history fetched successfully';
                $response['data'] = $history;
            } catch (PDOException $e) {
                error_log("Database error in spin-history: " . $e->getMessage());
                http_response_code(503);
                throw new Exception("Database service is currently unavailable");
            }
            break;

        case 'last-spin-time':
            // GET /api/last-spin-time?user_id=123 - Check when user can spin next
            if ($requestMethod !== 'GET') {
                throw new Exception('Method not allowed');
            }

            try {
                $userId = $_GET['user_id'] ?? null;
                if (!$userId) {
                    throw new Exception('Missing required parameter: user_id');
                }

                $db = new Database();
                $query = "SELECT MAX(spin_at) as last_spin FROM spin_wins WHERE user_id = ?";
                $result = $db->query($query, [$userId]);

                $lastSpinTime = null;
                $nextSpinTime = null;
                $canSpinNow = true;

                if (!empty($result) && !empty($result[0]['last_spin'])) {
                    $lastSpinTime = $result[0]['last_spin'];
                    $lastSpinTimestamp = strtotime($lastSpinTime);
                    $currentTime = time();
                    $cooldownPeriod = 259200; // 72 hours
                    $timeSinceLastSpin = $currentTime - $lastSpinTimestamp;

                    if ($timeSinceLastSpin < $cooldownPeriod) {
                        $canSpinNow = false;
                        $nextSpinTime = date('Y-m-d H:i:s', $lastSpinTimestamp + $cooldownPeriod);
                    }
                }

                $response['status'] = 'success';
                $response['message'] = 'Last spin time retrieved';
                $response['data'] = [
                    'last_spin_time' => $lastSpinTime,
                    'can_spin_now' => $canSpinNow,
                    'next_spin_available' => $nextSpinTime
                ];
            } catch (PDOException $e) {
                error_log("Database error in last-spin-time: " . $e->getMessage());
                http_response_code(503);
                throw new Exception("Database service is currently unavailable");
            }
            break;

        case 'pending-spin-rewards':
            // GET /api/pending-spin-rewards?user_id=123 - Get user's pending rewards (non-tryagain)
            if ($requestMethod !== 'GET') {
                throw new Exception('Method not allowed');
            }

            try {
                $userId = $_GET['user_id'] ?? null;
                if (!$userId) {
                    throw new Exception('Missing required parameter: user_id');
                }

                $db = new Database();
                $query = "SELECT sw.id, sw.user_id, sw.reward_id, sw.reward_type, sw.amount, sw.unit, sw.plan_id,
                         sw.status, sw.meta, sw.spin_at
                         FROM spin_wins sw
                         WHERE sw.user_id = ? AND sw.status = 'pending' AND sw.reward_type != 'tryagain'
                         ORDER BY sw.spin_at DESC";
                
                $rewards = $db->query($query, [$userId]);

                $response['status'] = 'success';
                $response['message'] = 'Pending rewards fetched successfully';
                $response['data'] = $rewards;
            } catch (PDOException $e) {
                error_log("Database error in pending-spin-rewards: " . $e->getMessage());
                http_response_code(503);
                throw new Exception("Database service is currently unavailable");
            }
            break;

        case 'networks':
            // GET /api/networks - Get all available networks
            if ($requestMethod !== 'GET') {
                throw new Exception('Method not allowed');
            }

            try {
                $db = new Database();
                // Try to fetch networks with active status first, then fallback to all
                $query = "SELECT nId, networkid, network FROM networkid WHERE networkStatus = 1 ORDER BY network ASC";
                $networks = $db->query($query);
                
                if (empty($networks)) {
                    // Fallback: try without status filter for debugging
                    error_log("No networks found with networkStatus=1, trying all networks");
                    $query = "SELECT nId, networkid, network FROM networkid ORDER BY network ASC";
                    $networks = $db->query($query);
                }
                
                if (empty($networks)) {
                    error_log("WARNING: No networks found in networkid table");
                }

                $response['status'] = 'success';
                $response['message'] = 'Networks fetched successfully';
                $response['data'] = $networks;
            } catch (PDOException $e) {
                error_log("Database error in networks: " . $e->getMessage());
                http_response_code(503);
                throw new Exception("Database service is currently unavailable");
            }
            break;

        case 'claim-spin-reward':
            // POST /api/claim-spin-reward - Claim a spin reward (airtime or data)
            if ($requestMethod !== 'POST') {
                throw new Exception('Method not allowed');
            }

            try {
                $input = json_decode(file_get_contents("php://input"), true);
                
                // Accept both 'id' and 'spin_win_id' for flexibility
                $spinWinId = $input['id'] ?? $input['spin_win_id'] ?? null;
                $userId = $input['user_id'] ?? null;

                if (!$spinWinId || !$userId) {
                    throw new Exception('Missing required parameters: id and user_id');
                }

                $db = new Database();

                // Fetch the spin win record to get its details
                $fetchQuery = "SELECT id, user_id, reward_type, amount, unit, meta FROM spin_wins WHERE id = ? AND user_id = ?";
                $spinWinRecord = $db->query($fetchQuery, [$spinWinId, $userId]);

                if (empty($spinWinRecord)) {
                    throw new Exception('Spin win record not found');
                }

                $spinWin = $spinWinRecord[0];
                $rewardType = $spinWin['reward_type'];
                $amount = $spinWin['amount'];

                // If it's a "try again" reward, just mark as claimed and return
                if ($rewardType === 'tryagain') {
                    $updateQuery = "UPDATE spin_wins SET status = 'claimed' WHERE id = ? AND user_id = ?";
                    $db->query($updateQuery, [$spinWinId, $userId], false);

                    $response['status'] = 'success';
                    $response['message'] = 'Try again reward claimed';
                    $response['data'] = [
                        'id' => $spinWinId,
                        'status' => 'claimed'
                    ];
                    // Send a notification for the claim (even though it's a tryagain)
                    try {
                        sendTransactionNotification($userId, 'spin_claim', [
                            'id' => $spinWinId,
                            'status' => 'claimed',
                            'reward_type' => $rewardType,
                            'delivered' => false
                        ]);
                    } catch (Exception $e) {
                        error_log('Failed to send spin claim notification (tryagain): ' . $e->getMessage());
                    }
                    break;
                }

                // For airtime/data rewards, mark as claimed and prepare for delivery
                // Initially set to claimed, but will revert to pending if delivery fails
                $claimedStatus = 'claimed';
                
                // Optional delivery parameters: phone and network (network can be id or name)
                $phone = isset($input['phone']) ? trim($input['phone']) : null;
                $network = isset($input['network']) ? $input['network'] : null;

                $delivered = null;
                $deliveryMessage = null;
                $finalStatus = $claimedStatus;

                if ($phone) {
                    if ($rewardType === 'airtime') {
                        $networkIdForDelivery = resolveNetworkIdFromInput($network) ?? $network;
                        $ok = _deliverAirtime($phone, $networkIdForDelivery, $amount, 'spin-'.$spinWinId, $userId);
                        $delivered = $ok;
                        $deliveryMessage = $ok ? 'Airtime delivered' : 'Airtime delivery failed';
                        // Set final status: 'delivered' if successful, 'pending' if failed
                        $finalStatus = $ok ? 'delivered' : 'pending';
                    } elseif ($rewardType === 'data') {
                        $networkIdForDelivery = resolveNetworkIdFromInput($network) ?? $network;
                        $ok = _deliverData($phone, $networkIdForDelivery, $amount, 'spin-'.$spinWinId, $userId);
                        $delivered = $ok;
                        $deliveryMessage = $ok ? 'Data delivered' : 'Data delivery failed';
                        // Set final status: 'delivered' if successful, 'pending' if failed
                        $finalStatus = $ok ? 'delivered' : 'pending';
                    }
                } else {
                    $deliveryMessage = 'No phone provided; reward marked as claimed and will be delivered later';
                    // If no phone provided, stay as 'claimed' (user can claim again with phone later)
                    $finalStatus = 'claimed';
                }
                
                // Update status based on delivery outcome
                $updateStatusQuery = "UPDATE spin_wins SET status = ? WHERE id = ? AND user_id = ?";
                $db->query($updateStatusQuery, [$finalStatus, $spinWinId, $userId], false);

                // Update meta with delivery details if provided
                try {
                    $metaArr = [];
                    if (!empty($spinWin['meta']) && is_string($spinWin['meta'])) {
                        $decoded = json_decode($spinWin['meta'], true);
                        if (is_array($decoded)) $metaArr = $decoded;
                    } elseif (!empty($spinWin['meta']) && is_array($spinWin['meta'])) {
                        $metaArr = $spinWin['meta'];
                    }
                    if ($phone) $metaArr['phone'] = $phone;
                    if ($network) $metaArr['network'] = $network;
                    if ($delivered === true) {
                        $metaArr['delivery_status'] = 'delivered';
                    } elseif ($phone) {
                        $metaArr['delivery_status'] = 'delivery_failed';
                    } else {
                        $metaArr['delivery_status'] = 'pending';
                    }

                    $updateMetaQuery = "UPDATE spin_wins SET meta = ? WHERE id = ?";
                    $db->query($updateMetaQuery, [json_encode($metaArr), $spinWinId], false);
                } catch (Exception $e) {
                    error_log('Error updating spin_wins meta: ' . $e->getMessage());
                }

                $response['status'] = 'success';
                $response['message'] = 'Reward claimed successfully. ' . ($delivered === true ? ucfirst($rewardType) . ' delivered.' : $deliveryMessage);
                $response['data'] = [
                    'id' => $spinWinId,
                    'status' => $finalStatus,
                    'reward_type' => $rewardType,
                    'amount' => $amount,
                    'delivered' => $delivered
                ];

                // Send notification about claim & (possible) delivery
                try {
                    sendTransactionNotification($userId, 'spin_claim', [
                        'id' => $spinWinId,
                        'status' => $finalStatus,
                        'reward_type' => $rewardType,
                        'amount' => $amount,
                        'delivered' => $delivered
                    ]);
                } catch (Exception $e) {
                    error_log('Failed to send spin claim notification: ' . $e->getMessage());
                }

            } catch (Exception $e) {
                error_log("Error in claim-spin-reward: " . $e->getMessage());
                http_response_code(400);
                $response['status'] = 'error';
                $response['message'] = $e->getMessage();
            }
            break;

        case 'welcome-bonus-settings':
            // GET /api/welcome-bonus-settings - Get welcome bonus amount and status
            if ($requestMethod !== 'GET') {
                throw new Exception('Method not allowed');
            }

            try {
                $db = new Database();
                $query = "SELECT id, amount, is_active, description FROM welcome_bonus_settings WHERE id = 1";
                $result = $db->query($query);

                if (empty($result)) {
                    // Default settings if not configured
                    $response['status'] = 'success';
                    $response['message'] = 'Welcome bonus settings retrieved';
                    $response['data'] = [
                        'id' => 1,
                        'amount' => 100.00,
                        'is_active' => 'On',
                        'description' => 'Welcome bonus for new members'
                    ];
                } else {
                    $settings = $result[0];
                    $response['status'] = 'success';
                    $response['message'] = 'Welcome bonus settings retrieved';
                    $response['data'] = [
                        'id' => $settings['id'],
                        'amount' => floatval($settings['amount']),
                        'is_active' => $settings['is_active'],
                        'description' => $settings['description']
                    ];
                }
            } catch (PDOException $e) {
                error_log("Database error in welcome-bonus-settings: " . $e->getMessage());
                http_response_code(503);
                throw new Exception("Database service is currently unavailable");
            }
            break;

        case 'welcome-bonus-status':
            // GET /api/welcome-bonus-status?user_id=123 - Check if user already claimed bonus
            if ($requestMethod !== 'GET') {
                throw new Exception('Method not allowed');
            }

            try {
                $userId = $_GET['user_id'] ?? null;
                if (!$userId) {
                    throw new Exception('Missing required parameter: user_id');
                }

                $db = new Database();

                // Check if user has already claimed the bonus
                $claimQuery = "SELECT id, bonus_amount, status, claimed_at, credited_at FROM welcome_bonus_claims WHERE user_id = ?";
                $claimResult = $db->query($claimQuery, [$userId]);

                if (!empty($claimResult)) {
                    // User has already claimed
                    $claim = $claimResult[0];
                    $response['status'] = 'success';
                    $response['message'] = 'User already claimed welcome bonus';
                    $response['data'] = [
                        'has_claimed' => true,
                        'claim_id' => $claim['id'],
                        'bonus_amount' => floatval($claim['bonus_amount']),
                        'claim_status' => $claim['status'],
                        'claimed_at' => $claim['claimed_at'],
                        'credited_at' => $claim['credited_at']
                    ];
                } else {
                    // User hasn't claimed yet
                    $response['status'] = 'success';
                    $response['message'] = 'User is eligible for welcome bonus';
                    $response['data'] = [
                        'has_claimed' => false,
                        'is_eligible' => true
                    ];
                }
            } catch (PDOException $e) {
                error_log("Database error in welcome-bonus-status: " . $e->getMessage());
                http_response_code(503);
                throw new Exception("Database service is currently unavailable");
            }
            break;

        case 'claim-welcome-bonus':
            // POST /api/claim-welcome-bonus - Claim the welcome bonus
            if ($requestMethod !== 'POST') {
                throw new Exception('Method not allowed');
            }

            try {
                $input = json_decode(file_get_contents("php://input"), true);
                $userId = $input['user_id'] ?? null;

                if (!$userId) {
                    throw new Exception('Missing required parameter: user_id');
                }

                $db = new Database();

                // Check if user already claimed
                $existingQuery = "SELECT id FROM welcome_bonus_claims WHERE user_id = ?";
                $existingResult = $db->query($existingQuery, [$userId]);

                if (!empty($existingResult)) {
                    http_response_code(400);
                    throw new Exception('Welcome bonus already claimed');
                }

                // Get bonus amount from settings
                $settingsQuery = "SELECT amount, is_active FROM welcome_bonus_settings WHERE id = 1";
                $settingsResult = $db->query($settingsQuery);
                
                $bonusAmount = 100.00;
                $isActive = 'On';

                if (!empty($settingsResult)) {
                    $bonusAmount = floatval($settingsResult[0]['amount']);
                    $isActive = $settingsResult[0]['is_active'];
                }

                if ($isActive !== 'On') {
                    http_response_code(400);
                    throw new Exception('Welcome bonus is currently inactive');
                }

                // Verify user exists
                $userQuery = "SELECT sId, sWallet FROM subscribers WHERE sId = ? LIMIT 1";
                $userResult = $db->query($userQuery, [$userId]);

                if (empty($userResult)) {
                    throw new Exception('User not found');
                }

                $currentWallet = floatval($userResult[0]['sWallet']);

                // Insert claim record with pending status
                $claimAt = date('Y-m-d H:i:s');
                $insertQuery = "INSERT INTO welcome_bonus_claims (user_id, bonus_amount, status, claimed_at, notes) 
                               VALUES (?, ?, 'pending', ?, ?)";
                
                $insertResult = $db->query($insertQuery, [
                    $userId,
                    $bonusAmount,
                    $claimAt,
                    'Bonus claimed via app'
                ], false);

                // For INSERT, rowCount() should return 1 for successful insert
                // The database class will throw an exception if there's a database error (like constraint violation)
                error_log("Welcome bonus claim inserted successfully for user: $userId, affected rows: $insertResult");

                // Credit the bonus to wallet
                $updateQuery = "UPDATE subscribers SET sWallet = sWallet + ? WHERE sId = ?";
                $updateResult = $db->query($updateQuery, [$bonusAmount, $userId], false);

                error_log("Wallet updated for user: $userId, affected rows: $updateResult");

                // Update claim status to credited
                $creditQuery = "UPDATE welcome_bonus_claims SET status = 'credited', credited_at = ? WHERE user_id = ?";
                $creditResult = $db->query($creditQuery, [date('Y-m-d H:i:s'), $userId], false);

                error_log("Claim status updated for user: $userId, affected rows: $creditResult");

                // Fetch updated wallet to confirm
                $updatedUserQuery = "SELECT sWallet FROM subscribers WHERE sId = ? LIMIT 1";
                $updatedUserResult = $db->query($updatedUserQuery, [$userId]);
                $newWallet = !empty($updatedUserResult) ? floatval($updatedUserResult[0]['sWallet']) : $currentWallet + $bonusAmount;

                $response['status'] = 'success';
                $response['message'] = 'Welcome bonus claimed successfully';
                $response['data'] = [
                    'bonus_amount' => $bonusAmount,
                    'new_wallet_balance' => $newWallet,
                    'credited_at' => date('Y-m-d H:i:s'),
                    'status' => 'credited'
                ];

            } catch (Exception $e) {
                error_log("Error in claim-welcome-bonus: " . $e->getMessage());
                error_log("Stack trace: " . $e->getTraceAsString());
                if (http_response_code() === 200) {
                    http_response_code(400);
                }
                $response['status'] = 'error';
                $response['message'] = $e->getMessage();
            }
            break;

        case 'welcome-bonus-history':
            // GET /api/welcome-bonus-history?user_id=123 - Get user's welcome bonus claim history
            if ($requestMethod !== 'GET') {
                throw new Exception('Method not allowed');
            }

            try {
                $userId = $_GET['user_id'] ?? null;
                if (!$userId) {
                    throw new Exception('Missing required parameter: user_id');
                }

                $db = new Database();
                $query = "SELECT id, user_id, bonus_amount, status, claimed_at, credited_at, notes FROM welcome_bonus_claims WHERE user_id = ?";
                $result = $db->query($query, [$userId]);

                $response['status'] = 'success';
                $response['message'] = 'Welcome bonus history retrieved';
                $response['data'] = !empty($result) ? $result[0] : null;
            } catch (PDOException $e) {
                error_log("Database error in welcome-bonus-history: " . $e->getMessage());
                http_response_code(503);
                throw new Exception("Database service is currently unavailable");
            }
            break;

        case 'a2c-settings':
            // Get A2C settings for all networks
            try {
                $db = new Database();
                $settings = $db->query("SELECT network, phone_number, whatsapp_number, contact_phone, rate, min_amount, max_amount FROM a2c_settings WHERE is_active = 1");
                
                if (!$settings) {
                    throw new Exception('Failed to load A2C settings');
                }

                // Format response
                $formatted = [];
                foreach ($settings as $setting) {
                    $formatted[$setting['network']] = [
                        'phone_number' => $setting['phone_number'],
                        'whatsapp_number' => $setting['whatsapp_number'],
                        'contact_phone' => $setting['contact_phone'],
                        'rate' => (float)$setting['rate'],
                        'min_amount' => (float)$setting['min_amount'],
                        'max_amount' => (float)$setting['max_amount'],
                    ];
                }

                $response['status'] = 'success';
                $response['message'] = 'A2C settings retrieved';
                $response['data'] = $formatted;
            } catch (Exception $e) {
                error_log("Error in a2c-settings: " . $e->getMessage());
                http_response_code(500);
                $response['status'] = 'error';
                $response['message'] = $e->getMessage();
            }
            break;

        case 'a2c-submit':
            // Submit airtime2cash request
            if ($requestMethod !== 'POST') {
                throw new Exception('Method not allowed');
            }

            // Get authenticated user ID from session
            $authenticatedUserId = requireAuth();

            $data = json_decode(file_get_contents("php://input"), true);
            
            $required = ['network', 'sender_phone', 'airtime_amount', 'cash_amount'];
            foreach ($required as $field) {
                if (!isset($data[$field])) {
                    throw new Exception("Missing required field: $field");
                }
            }

            try {
                $db = new Database();

                // Validate network exists in settings
                $networkCheck = $db->query(
                    "SELECT id FROM a2c_settings WHERE network = ? AND is_active = 1",
                    [$data['network']]
                );

                if (!$networkCheck) {
                    throw new Exception('Invalid network selected');
                }

                // Validate amount
                $setting = $db->query(
                    "SELECT min_amount, max_amount FROM a2c_settings WHERE network = ?",
                    [$data['network']]
                );

                if ($data['airtime_amount'] < $setting[0]['min_amount'] || 
                    $data['airtime_amount'] > $setting[0]['max_amount']) {
                    throw new Exception('Amount is outside allowed range');
                }

                // Generate reference
                $reference = 'A2C-' . time() . '-' . $authenticatedUserId;

                // Insert request
                $db->query(
                    "INSERT INTO a2c_requests (user_id, network, sender_phone, airtime_amount, cash_amount, reference, status) 
                     VALUES (?, ?, ?, ?, ?, ?, 'pending')",
                    [
                        $authenticatedUserId,
                        $data['network'],
                        $data['sender_phone'],
                        $data['airtime_amount'],
                        $data['cash_amount'],
                        $reference
                    ]
                );

                $response['status'] = 'success';
                $response['message'] = 'Request submitted successfully';
                $response['data'] = [
                    'reference' => $reference,
                    'airtime_amount' => $data['airtime_amount'],
                    'cash_amount' => $data['cash_amount'],
                    'status' => 'pending'
                ];
            } catch (Exception $e) {
                error_log("Error in a2c-submit: " . $e->getMessage());
                http_response_code(400);
                $response['status'] = 'error';
                $response['message'] = $e->getMessage();
            }
            break;

        case 'a2c-requests':
            // Get pending requests for current user
            try {
                // Get authenticated user ID from session
                $authenticatedUserId = requireAuth();

                $db = new Database();
                $requests = $db->query(
                    "SELECT id, network, sender_phone, airtime_amount, cash_amount, status, reference, created_at 
                     FROM a2c_requests WHERE user_id = ? ORDER BY created_at DESC",
                    [$authenticatedUserId]
                );

                $response['status'] = 'success';
                $response['message'] = 'Requests retrieved';
                $response['data'] = $requests ?? [];
            } catch (Exception $e) {
                error_log("Error in a2c-requests: " . $e->getMessage());
                http_response_code(400);
                $response['status'] = 'error';
                $response['message'] = $e->getMessage();
            }
            break;

        case 'a2c-approve':
            // Admin endpoint to approve pending request and credit user
            if ($requestMethod !== 'POST') {
                throw new Exception('Method not allowed');
            }

            // Verify admin access
            $adminId = requireAdmin();

            $data = json_decode(file_get_contents("php://input"), true);
            
            $required = ['request_id', 'approval_status'];
            foreach ($required as $field) {
                if (!isset($data[$field])) {
                    throw new Exception("Missing required field: $field");
                }
            }

            if (!in_array($data['approval_status'], ['approved', 'rejected'])) {
                throw new Exception('Invalid approval_status. Must be "approved" or "rejected"');
            }

            try {
                $db = new Database();
                $db->beginTransaction();

                // Get request details
                $request = $db->query(
                    "SELECT user_id, cash_amount, status FROM a2c_requests WHERE id = ?",
                    [$data['request_id']]
                );

                if (!$request) {
                    throw new Exception('Request not found');
                }

                if ($request[0]['status'] !== 'pending') {
                    throw new Exception('Request is not pending');
                }

                // Update request status
                $notes = $data['admin_notes'] ?? '';
                $db->query(
                    "UPDATE a2c_requests SET status = ?, admin_notes = ?, updated_at = NOW() WHERE id = ?",
                    [$data['approval_status'], $notes, $data['request_id']]
                );

                // If approved, credit user wallet
                if ($data['approval_status'] === 'approved') {
                    // Add to wallet
                    $db->query(
                        "UPDATE subscribers SET sWallet = sWallet + ? WHERE sId = ?",
                        [$request[0]['cash_amount'], $request[0]['user_id']]
                    );

                    // Log transaction
                    $db->query(
                        "INSERT INTO transactions (sId, transref, servicename, servicedesc, amount, status) 
                         VALUES (?, ?, ?, ?, ?, ?)",
                        [
                            $request[0]['user_id'],
                            'A2C-APPROVED-' . $data['request_id'] . '-' . time(),
                            'Airtime2Cash',
                            'Airtime to Cash - Admin Approved',
                            $request[0]['cash_amount'],
                            'success'
                        ]
                    );
                }

                $db->commit();

                $response['status'] = 'success';
                $response['message'] = 'Request ' . $data['approval_status'] . ' successfully';
                $response['data'] = [
                    'request_id' => $data['request_id'],
                    'approval_status' => $data['approval_status'],
                    'cash_amount' => $request[0]['cash_amount']
                ];
            } catch (Exception $e) {
                error_log("Error in a2c-approve: " . $e->getMessage());
                try {
                    $db->rollBack();
                } catch (Exception $rollbackError) {
                    error_log("Rollback failed: " . $rollbackError->getMessage());
                }
                http_response_code(400);
                $response['status'] = 'error';
                $response['message'] = $e->getMessage();
            }
            break;

        case 'airtime2cash':
            if ($subEndpoint === 'verify') {
                if ($requestMethod !== 'POST') {
                    throw new Exception('Method not allowed');
                }

                $data = json_decode(file_get_contents("php://input"), true);
                if (!isset($data['user_id']) || !isset($data['network'])) {
                    throw new Exception('Missing required parameters: user_id, network');
                }

                // Validate network
                $valid_networks = ['mtn', 'airtel', 'glo', '9mobile'];
                if (!in_array(strtolower($data['network']), $valid_networks)) {
                    throw new Exception('Invalid network: ' . $data['network']);
                }

                // Initialize database helper (guarded)
                try {
                    $db = new Database();
                } catch (Exception $e) {
                    // Log full DB error for debugging but return a generic message to clients
                    error_log("Database connection failed in airtime2cash/verify: " . $e->getMessage());
                    http_response_code(503);
                    $response['status'] = 'error';
                    $response['message'] = 'Service temporarily unavailable';
                    break;
                }

                try {
                    // Get API configurations
                    $configs = [];
                    $configResult = $db->query("SELECT name, value FROM apiconfigs WHERE name IN ('a2cHost', 'a2cApikey')");
                    
                    if (!$configResult) {
                        throw new Exception('Failed to load API configurations from database');
                    }

                    foreach ($configResult as $config) {
                        $configs[$config['name']] = $config['value'];
                    }

                    // Check required configurations
                    if (!isset($configs['a2cHost']) || !isset($configs['a2cApikey'])) {
                        throw new Exception('Missing VTU Africa API configuration (a2cHost or a2cApikey)');
                    }

                    $a2c_host = $configs['a2cHost'];
                    $a2c_api_key = $configs['a2cApikey'];

                    // Build verification request URL
                    $verify_url = rtrim($a2c_host, '/') . '/portal/api/merchant-verify/';
                    
                    // Prepare query parameters
                    $verify_params = [
                        'apikey' => $a2c_api_key,
                        'serviceName' => 'Airtime2Cash',
                        'network' => $data['network'],
                    ];

                    // Build full URL with query string
                    $verify_url_with_params = $verify_url . '?' . http_build_query($verify_params);

                    // Make verification request to VTU Africa
                    $curl = curl_init();
                    curl_setopt_array($curl, [
                        CURLOPT_URL => $verify_url_with_params,
                        CURLOPT_RETURNTRANSFER => true,
                        CURLOPT_TIMEOUT => 15,
                        CURLOPT_HTTP_VERSION => CURL_HTTP_VERSION_1_1,
                        CURLOPT_CUSTOMREQUEST => 'GET',
                        CURLOPT_HTTPHEADER => [
                            'Content-Type: application/json',
                        ],
                    ]);

                    $vtu_response = curl_exec($curl);
                    $http_code = curl_getinfo($curl, CURLINFO_HTTP_CODE);
                    $curl_error = curl_error($curl);
                    curl_close($curl);

                    if ($curl_error) {
                        throw new Exception('Verification request failed: ' . $curl_error);
                    }

                    if ($http_code !== 200) {
                        error_log("VTU Africa verification failed with HTTP {$http_code}: {$vtu_response}");
                        throw new Exception('VTU Africa verification service returned error: HTTP ' . $http_code);
                    }

                    $vtu_parsed = json_decode($vtu_response, true);

                    if (!$vtu_parsed) {
                        throw new Exception('Invalid response from VTU Africa verification service');
                    }

                    // Check VTU Africa response code
                    if (($vtu_parsed['code'] ?? null) !== 101) {
                        throw new Exception($vtu_parsed['description']['Status'] ?? 'Verification failed');
                    }

                    // Validate response structure
                    $description = $vtu_parsed['description'] ?? [];
                    $status = $description['Status'] ?? null;
                    $phone_number = $description['Phone_Number'] ?? null;

                    if ($status !== 'Completed' || !$phone_number) {
                        throw new Exception('Service not available for ' . $data['network']);
                    }

                    // Success response
                    $response['status'] = 'success';
                    $response['data'] = [
                        'status' => $status,
                        'phone_number' => $phone_number,
                        'network' => $data['network'],
                    ];
                    http_response_code(200);

                } catch (Exception $e) {
                    error_log("Error in airtime2cash/verify: " . $e->getMessage());
                    http_response_code(400);
                    $response['status'] = 'error';
                    $response['message'] = $e->getMessage();
                }

            } elseif ($subEndpoint === 'convert') {
            if ($requestMethod !== 'POST') {
                throw new Exception('Method not allowed');
            }

            $data = json_decode(file_get_contents("php://input"), true);
            
            $user_id = $data['user_id'] ?? null;
            $user_phone = $data['user_phone'] ?? null;
            $network = $data['network'] ?? null;
            $amount = $data['amount'] ?? null;
            $reference = $data['reference'] ?? null;
            $site_phone = $data['site_phone'] ?? null;

            // Validate inputs
            $required = ['user_id', 'user_phone', 'network', 'amount', 'reference', 'site_phone'];
            foreach ($required as $field) {
                if (!$$field) {
                    throw new Exception("Missing required parameter: {$field}");
                }
            }

            // Validate amount is numeric and positive
            if (!is_numeric($amount) || $amount <= 0) {
                throw new Exception('Amount must be a positive number');
            }

            $amount = floatval($amount);

            // Validate network
            $valid_networks = ['mtn', 'airtel', 'glo', '9mobile'];
            if (!in_array(strtolower($network), $valid_networks)) {
                throw new Exception('Invalid network: ' . $network);
            }

                // Initialize database helper (guarded)
                try {
                    $db = new Database();
                } catch (Exception $e) {
                    // Log full DB error for debugging but return a generic message to clients
                    error_log("Database connection failed in airtime2cash/convert: " . $e->getMessage());
                    http_response_code(503);
                    $response['status'] = 'error';
                    $response['message'] = 'Service temporarily unavailable';
                    break;
                }

                try {
                    // Get API configurations
                    $configs = [];
                $configResult = $db->query("SELECT name, value FROM apiconfigs WHERE name IN ('a2cHost', 'a2cApikey')");
                
                if (!$configResult) {
                    throw new Exception('Failed to load API configurations');
                }

                foreach ($configResult as $config) {
                    $configs[$config['name']] = $config['value'];
                }

                if (!isset($configs['a2cHost']) || !isset($configs['a2cApikey'])) {
                    throw new Exception('Missing VTU Africa API configuration');
                }

                $a2c_host = $configs['a2cHost'];
                $a2c_api_key = $configs['a2cApikey'];

                // Begin transaction
                $db->beginTransaction();

                // Store transaction BEFORE calling VTU Africa
                $transactionData = [
                    'user_id' => $user_id,
                    'reference' => $reference,
                    'service' => 'Airtime2Cash',
                    'network' => $network,
                    'amount' => $amount,
                    'status' => 'processing',
                    'raw_request' => json_encode($data),
                ];

                // Get current balance
                $userResult = $db->query("SELECT sWallet FROM subscribers WHERE sId = ?", [$user_id]);
                if (!$userResult) {
                    throw new Exception('User not found');
                }

                $oldBalance = floatval($userResult[0]['sWallet'] ?? 0);
                $newBalance = $oldBalance;
                $profit = 0;

                // Insert transaction record
                $insertQuery = "
                    INSERT INTO transactions (sId, transref, servicename, servicedesc, amount, status, oldbal, newbal, profit, date, api_response)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, NOW(), ?)
                ";

                $db->execute($insertQuery, [
                    $user_id,
                    $reference,
                    'Airtime 2 Cash',
                    'Airtime conversion - Pending',
                    $amount,
                    0, // status: 0 = processing/initiated
                    $oldBalance,
                    $newBalance,
                    $profit,
                    json_encode($transactionData),
                ]);

                // Commit transaction to ensure data is saved before making external request
                $db->commit();

                // Now make the conversion request to VTU Africa
                $convert_url = rtrim($a2c_host, '/') . '/portal/api/airtime-cash/';

                // Prepare parameters for conversion
                $convert_params = [
                    'apikey' => $a2c_api_key,
                    'network' => $network,
                    'sender' => $user_id,
                    'sendernumber' => $user_phone,
                    'amount' => intval($amount),
                    'ref' => $reference,
                    'sitephone' => $site_phone,
                    'webhookURL' => 'https://api.mkdata.com.ng/api/webhooks/a2c',
                ];

                // Build full URL with query string
                $convert_url_with_params = $convert_url . '?' . http_build_query($convert_params);

                $curl = curl_init();
                curl_setopt_array($curl, [
                    CURLOPT_URL => $convert_url_with_params,
                    CURLOPT_RETURNTRANSFER => true,
                    CURLOPT_TIMEOUT => 15,
                    CURLOPT_HTTP_VERSION => CURL_HTTP_VERSION_1_1,
                    CURLOPT_CUSTOMREQUEST => 'GET',
                    CURLOPT_HTTPHEADER => [
                        'Content-Type: application/json',
                    ],
                ]);

                $vtu_response = curl_exec($curl);
                $http_code = curl_getinfo($curl, CURLINFO_HTTP_CODE);
                $curl_error = curl_error($curl);
                curl_close($curl);

                if ($curl_error) {
                    throw new Exception('Conversion request failed: ' . $curl_error);
                }

                $vtu_parsed = json_decode($vtu_response, true);

                // Store the response for debugging
                $db->execute(
                    "UPDATE transactions SET api_response = ? WHERE transref = ?",
                    [json_encode($vtu_parsed), $reference]
                );

                if ($http_code !== 200) {
                    error_log("VTU Africa conversion failed with HTTP {$http_code}: {$vtu_response}");
                    throw new Exception('VTU Africa conversion service returned error');
                }

                if (!$vtu_parsed) {
                    throw new Exception('Invalid response from VTU Africa');
                }

                // Return success
                $response['status'] = 'success';
                $response['message'] = 'Airtime conversion request submitted successfully';
                $response['data'] = [
                    'reference' => $reference,
                    'amount' => $amount,
                    'network' => $network,
                ];
                http_response_code(200);

            } catch (Exception $e) {
                error_log("Error in airtime2cash/convert: " . $e->getMessage());
                try {
                    $db->rollBack();
                } catch (Exception $rollbackError) {
                    error_log("Rollback failed: " . $rollbackError->getMessage());
                }
                http_response_code(400);
                $response['status'] = 'error';
                $response['message'] = $e->getMessage();
            }
            } else {
                http_response_code(404);
                $response['status'] = 'error';
                $response['message'] = 'Unknown airtime2cash endpoint: ' . ($subEndpoint ?? 'none');
            }
            break;

        default:
            error_log("No matching endpoint found for: " . $endpoint);
            http_response_code(404);
            $response['message'] = "Endpoint '/$endpoint' not found";
            break;
    }
} catch (Exception $e) {
    error_log("CRITICAL: Unhandled exception in API: " . $e->getMessage());
    error_log("Stack trace: " . $e->getTraceAsString());
    $response['status'] = 'error';
    $response['message'] = $e->getMessage();
    http_response_code(500);
}

// Ensure we always output valid JSON
if (!isset($response) || !is_array($response)) {
    error_log("CRITICAL: Response not set or invalid type");
    $response = ['status' => 'error', 'message' => 'Internal server error'];
}

// Add helpful debug info to response for quick diagnostics (temporary)
$sessionId = function_exists('session_id') ? session_id() : null;
$sessionSavePath = ini_get('session.save_path') ?: sys_get_temp_dir();
$sessionFilePath = $sessionId ? rtrim($sessionSavePath, DIRECTORY_SEPARATOR) . DIRECTORY_SEPARATOR . 'sess_' . $sessionId : null;
$sessionFileExists = $sessionFilePath ? file_exists($sessionFilePath) : false;
$sessionFileExcerpt = null;
if ($sessionFileExists) {
    $content = @file_get_contents($sessionFilePath);
    if ($content !== false) {
        $sessionFileExcerpt = substr($content, 0, 200);
    }
}

$response['__debug'] = [
    'uri' => $uri ?? null,
    'endpoint' => $endpoint ?? null,
    'subEndpoint' => $subEndpoint ?? null,
    'method' => $requestMethod ?? null,
    // Include incoming cookie and session data for debugging authentication issues
    // 'incoming_cookies' => isset($_COOKIE) ? $_COOKIE : null,
    // 'session_id' => $sessionId,
    // 'session' => isset($_SESSION) ? $_SESSION : null,
    // 'session_save_path' => $sessionSavePath,
    // 'session_file' => $sessionFilePath,
    // 'session_file_exists' => $sessionFileExists,
    // 'session_file_excerpt' => $sessionFileExcerpt,
];

error_log("Final response: " . json_encode($response));
echo json_encode($response);
