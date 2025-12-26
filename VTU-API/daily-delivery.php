<?php
/**
 * Daily Data Plan Delivery Cron Script
 * 
 * This script runs daily to deliver data to active recurring plans.
 * It should be scheduled to run via cron job at regular intervals (e.g., every hour or daily).
 * 
 * Cron command example:
 * 0 * * * * /usr/bin/php /opt/lampp/htdocs/cron/daily-delivery.php
 */

// Set timezone
date_default_timezone_set('Africa/Lagos');

// Include notification service
require_once __DIR__ . '/api/notifications/send.php';

// Configuration
$siteurl = "https://mkdata.com.ng";
$db_host = '127.0.0.1';
$db_user = 'root';
$db_password = '';
$db_name = 'binalion_site';

// Log directory and file (use cron folder inside this project)
$log_dir = __DIR__ . '/logs';
if (!is_dir($log_dir)) {
    @mkdir($log_dir, 0755, true);
}
$log_file = $log_dir . '/daily-delivery-' . date('Y-m-d') . '.log';

// Lockfile to prevent concurrent runs
$lock_file = __DIR__ . '/daily-delivery.lock';
$lock_fp = fopen($lock_file, 'c');
if ($lock_fp === false) {
    error_log("Could not open lock file: $lock_file\n", 3, $log_file);
    exit(1);
}
if (!flock($lock_fp, LOCK_EX | LOCK_NB)) {
    // Another instance is running
    error_log('['.date('Y-m-d H:i:s')."] Another instance is running\n", 3, $log_file);
    fclose($lock_fp);
    exit(0);
}

/**
 * Log function
 */
function logMessage($message, $type = 'INFO') {
    global $log_file;
    $timestamp = date('Y-m-d H:i:s');
    $log_message = "[$timestamp] [$type] $message\n";
    error_log($log_message, 3, $log_file);
    echo $log_message;
}

/**
 * Database connection
 */
$mysqli = new mysqli($db_host, $db_user, $db_password, $db_name);
if ($mysqli->connect_error) {
    logMessage("Database connection failed: " . $mysqli->connect_error, 'ERROR');
    // release lock
    flock($lock_fp, LOCK_UN);
    fclose($lock_fp);
    exit(1);
}
logMessage('Database connection established', 'INFO');

/**
 * Fetch all active daily data plans where next delivery date is today or earlier
 */
$query = "SELECT * FROM daily_data_plans 
          WHERE status = 'active' 
          AND remaining_days > 0 
          AND next_delivery_date <= NOW()
          ORDER BY next_delivery_date ASC";

$result = $mysqli->query($query);

if (!$result) {
    logMessage("Query failed: " . $mysqli->error, 'ERROR');
    exit(1);
}

$plans_count = $result->num_rows;
logMessage("Found $plans_count active plans ready for delivery", 'INFO');

if ($plans_count == 0) {
    logMessage("No plans to deliver at this time", 'INFO');
    exit(0);
}

/**
 * Process each plan
 */
while ($plan = $result->fetch_assoc()) {
    $plan_id = $plan['id'];
    $user_id = $plan['user_id'];
    $phone = $plan['phone_number'];
    $network = $plan['network'];
    $plan_code = $plan['plan_id'];
    $user_type = $plan['user_type'];
    $remaining_days = $plan['remaining_days'];
    $transaction_ref = $plan['transaction_reference'];
    
    logMessage("Processing plan ID: $plan_id | User: $user_id | Phone: $phone | Remaining: $remaining_days days", 'INFO');
    
    // Attempt to deliver data
    $delivery_success = attemptDataDelivery($phone, $network, $plan_code, $transaction_ref . '_day' . ($plan['total_days'] - $remaining_days + 1));
    
    if ($delivery_success) {
        logMessage("Data delivery successful for plan $plan_id", 'SUCCESS');
        
        // Send delivery notification to user
        sendDeliveryNotification($user_id, $phone, $network, $plan_code, $transaction_ref);
        
        // Update plan in database
        $new_remaining_days = $remaining_days - 1;
        $new_delivery_date = date('Y-m-d H:i:s', strtotime('+1 day', strtotime($plan['next_delivery_date'])));
        $new_status = ($new_remaining_days <= 0) ? 'finished' : 'active';
        
        $update_query = "UPDATE daily_data_plans 
                        SET remaining_days = $new_remaining_days,
                            next_delivery_date = '$new_delivery_date',
                            status = '$new_status',
                            updated_at = NOW()
                        WHERE id = $plan_id";
        
        if ($mysqli->query($update_query)) {
            logMessage("Plan $plan_id updated: $new_remaining_days days remaining, status: $new_status", 'INFO');
        } else {
            logMessage("Failed to update plan $plan_id: " . $mysqli->error, 'ERROR');
        }
    } else {
        logMessage("Data delivery failed for plan $plan_id - will retry next cycle", 'WARNING');
    }
}

logMessage("Daily delivery cycle completed", 'INFO');
$mysqli->close();

/**
 * Attempt to deliver data to user's phone
 * 
 * @param string $phone Phone number
 * @param string $network Network ID
 * @param string $plan_code Data plan code
 * @param string $reference Transaction reference
 * @return bool Success or failure
 */
function attemptDataDelivery($phone, $network, $plan_code, $reference) {
    global $siteurl, $mysqli;
    
    try {
        // Get the API key and provider URL from database
        $api_key = null;
        $provider_url = null;
        
        // Try to get provider-specific configuration for this network
        $network_prefixes = [
            1 => 'mtn',
            2 => 'glo',
            3 => '9mobile',
            4 => 'airtel'
        ];
        
        $network_prefix = $network_prefixes[$network] ?? 'data';
        $provider_config_name = $network_prefix . 'GiftingProvider';
        $api_key_config_name = $network_prefix . 'GiftingApi';
        
        // Try to get provider details using the same logic as the data purchase flow
        $planType = null;
        $planRes = $mysqli->query("SELECT type FROM dataplans WHERE planid = '" . $mysqli->real_escape_string($plan_code) . "' LIMIT 1");
        if ($planRes && $prow = $planRes->fetch_assoc()) {
            $planType = $prow['type'];
            logMessage("Plan $plan_code resolved type: $planType", 'DEBUG');
        } else {
            logMessage("Could not resolve plan type for planid $plan_code", 'DEBUG');
        }

        // Prefer using DataService's provider resolution to keep behavior consistent
        $providerConfig = null;
        if ($planType) {
            require_once __DIR__ . '/services/data.service.php';
            try {
                // Normalize network to numeric id expected by DataService
                $networkIdForDS = is_numeric($network) ? intval($network) : null;
                if ($networkIdForDS === null) {
                    $nlow = strtolower($network);
                    if (strpos($nlow, 'mtn') !== false) $networkIdForDS = 1;
                    elseif (strpos($nlow, 'airtel') !== false) $networkIdForDS = 4;
                    elseif (strpos($nlow, 'glo') !== false) $networkIdForDS = 2;
                    elseif (strpos($nlow, '9mobile') !== false || strpos($nlow, '9mobile') !== false) $networkIdForDS = 3;
                    else $networkIdForDS = 0;
                }

                $ds = new DataService();
                $details = $ds->getDataProviderDetails($networkIdForDS, $planType);
                if (!empty($details) && isset($details[0])) {
                    $providerConfig = $details[0];
                    $provider_url = $providerConfig['provider'] ?? $provider_url;
                    $api_key = $providerConfig['apiKey'] ?? $api_key;
                    logMessage("Provider resolved via DataService: " . json_encode($providerConfig), 'DEBUG');
                }
            } catch (Exception $e) {
                logMessage("DataService provider resolution failed: " . $e->getMessage(), 'WARNING');
            }
        }

        // Fallback: read apiconfigs table directly if DataService didn't yield a provider
        if (empty($providerConfig)) {
            $config_res = $mysqli->query("SELECT name, value FROM apiconfigs WHERE name IN ('$provider_config_name', '$api_key_config_name')");
            logMessage("Fallback provider config query returned: " . json_encode($config_res), 'DEBUG');
            if (!empty($config_res)) {
                while ($row = $config_res->fetch_assoc()) {
                    if (strtolower($row['name']) === strtolower($provider_config_name)) {
                        $provider_url = $row['value'];
                    } elseif (strtolower($row['name']) === strtolower($api_key_config_name)) {
                        $api_key = $row['value'];
                    }
                }
            }
        }
        
        // Fallback to generic dataApiKey if provider-specific key not found
        if (empty($api_key)) {
            $api_res = $mysqli->query("SELECT value FROM apiconfigs WHERE name = 'dataApiKey' LIMIT 1");
            logMessage("Fallback dataApiKey query returned: " . json_encode($api_res), 'DEBUG');
            if ($api_res && $row = $api_res->fetch_assoc()) {
                $api_key = $row['value'] ?? null;
            }
        }
        
        if (empty($api_key)) {
            logMessage("Could not retrieve API key for delivery", 'ERROR');
            return false;
        }
        
        // Use the provider URL directly for delivery (avoid posting to internal API)
        if (empty($provider_url)) {
            logMessage("No provider URL configured for network $network", 'ERROR');
            return false;
        }

        $api_url = $provider_url;
        logMessage("Attempting delivery to $phone with plan $plan_code (provider endpoint)", 'INFO');
        logMessage("Using provider URL: $provider_url", 'DEBUG');

        // Prepare provider request body to match what providers expect
        $payloadBody = [
            'network' => intval($network),
            'network_id' => intval($network),
            'mobile_number' => $phone,
            'plan' => is_numeric($plan_code) ? intval($plan_code) : $plan_code,
            'plan_id' => is_numeric($plan_code) ? intval($plan_code) : $plan_code,
            'Ported_number' => true,
            'ref' => (string)(time() . mt_rand(1000, 9999)),
            'phone' => $phone
        ];

        $payload = json_encode($payloadBody);

        // Determine authentication method based on provider URL
        $auth_headers = [];
        if (strpos($provider_url, 'smeplug.ng') !== false) {
            $auth_headers[] = 'Authorization: Token ' . $api_key;
        } else {
            $auth_headers[] = 'Authorization: Bearer ' . $api_key;
        }

        $http_headers = array_merge([
            'Content-Type: application/json',
            'Accept: application/json'
        ], $auth_headers);

        $ch = curl_init();
        curl_setopt_array($ch, [
            CURLOPT_URL => $api_url,
            CURLOPT_RETURNTRANSFER => true,
            CURLOPT_ENCODING => '',
            CURLOPT_MAXREDIRS => 10,
            CURLOPT_TIMEOUT => 60,
            CURLOPT_FOLLOWLOCATION => true,
            CURLOPT_HTTP_VERSION => CURL_HTTP_VERSION_1_1,
            CURLOPT_CUSTOMREQUEST => 'POST',
            CURLOPT_POSTFIELDS => $payload,
            CURLOPT_HTTPHEADER => $http_headers,
            CURLOPT_SSL_VERIFYPEER => false,
            CURLOPT_SSL_VERIFYHOST => false
        ]);

        $response = curl_exec($ch);
        $curlErr = curl_error($ch);
        $http_code = curl_getinfo($ch, CURLINFO_HTTP_CODE);
        curl_close($ch);

        if ($response === false) {
            logMessage("cURL error during provider delivery attempt: " . $curlErr, 'ERROR');
            return false;
        }

        logMessage("Provider Response (HTTP $http_code): " . $response, 'DEBUG');

        $result = json_decode($response, true);
        if (json_last_error() !== JSON_ERROR_NONE) {
            logMessage("Non-JSON response from provider (HTTP $http_code): $response", 'ERROR');
            return false;
        }

        // Robust provider status detection (similar to data.service.php)
        $providerStatus = null;
        if (isset($result['current_status'])) {
            $providerStatus = strtolower((string)$result['current_status']);
        } elseif (isset($result['status']) && is_string($result['status'])) {
            $providerStatus = strtolower((string)$result['status']);
        } elseif (isset($result['Status'])) {
            $providerStatus = strtolower((string)$result['Status']);
        } elseif (isset($result['data']['status'])) {
            $providerStatus = strtolower((string)$result['data']['status']);
        } elseif (isset($result['data']['Status'])) {
            $providerStatus = strtolower((string)$result['data']['Status']);
        }

        // Fall back to boolean status fields
        if ($providerStatus === null && isset($result['status']) && is_bool($result['status'])) {
            $providerStatus = $result['status'] ? 'success' : 'failed';
        }

        $isSuccess = false;
        if ($providerStatus !== null) {
            if (in_array($providerStatus, ['success', 'successful', 'ok', 'completed', 'true'], true)) {
                $isSuccess = true;
            }
        }

        // Some providers return success message in 'api_response' or 'message'
        if (!$isSuccess) {
            $msg = $result['api_response'] ?? $result['message'] ?? $result['msg'] ?? null;
            if ($msg && preg_match('/success/i', $msg)) {
                $isSuccess = true;
            }
        }

        if ($isSuccess) {
            logMessage("Data delivery successful | Provider status: " . ($providerStatus ?? 'unknown') . " | Reference: $reference", 'SUCCESS');
            return true;
        }

        logMessage("Data delivery failed | HTTP $http_code | Provider status: " . ($providerStatus ?? 'unknown') . " | Response: " . json_encode($result), 'WARNING');
        return false;
        
    } catch (Exception $e) {
        logMessage("Exception during delivery attempt: " . $e->getMessage(), 'ERROR');
        return false;
    }
}

/**
 * Send delivery notification to user using the unified notification system
 * 
 * @param int $user_id User ID
 * @param string $phone Phone number
 * @param int $network Network ID
 * @param string $plan_code Plan code
 * @param string $reference Transaction reference
 * @return void
 */
function sendDeliveryNotification($user_id, $phone, $network, $plan_code, $reference) {
    try {
        // Get network name
        $network_names = [
            1 => 'MTN',
            2 => 'Glo',
            3 => '9mobile',
            4 => 'Airtel'
        ];
        $network_name = $network_names[$network] ?? 'Data';
        
        // Get plan details from database
        global $mysqli;
        $plan_res = $mysqli->query("SELECT name, type FROM dataplans WHERE planid = ? LIMIT 1", [$plan_code]);
        $plan_name = 'Data';
        if ($plan_res && $row = $plan_res->fetch_assoc()) {
            $plan_name = $row['name'] ?? 'Data';
        }
        
        // Use the unified notification system from send.php
        $notificationData = [
            'type' => 'daily_data',
            'network' => $network,
            'phone' => $phone,
            'plan_code' => $plan_code,
            'reference' => $reference,
            'plan' => $plan_name
        ];
        
        // Send via unified system (uses FCMService, not direct API)
        $result = sendTransactionNotification($user_id, 'daily_data', $notificationData);
        
        logMessage("Delivery notification sent to user $user_id | Result: " . json_encode($result), 'INFO');
        
    } catch (Exception $e) {
        logMessage("Error sending delivery notification: " . $e->getMessage(), 'WARNING');
    }
}
