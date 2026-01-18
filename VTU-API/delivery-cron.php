<?php
/**
 * Optimized Daily Data Plan Delivery Cron Script
 * 
 * Delivers data to active recurring plans without creating transactions.
 * Reuses provider logic from data.service.php.
 * 
 * Cron command (run every day at 2 AM):
 * 0 2 * * * /usr/bin/php /path/to/delivery-cron.php >> /var/log/mkdata-delivery.log 2>&1
 */

date_default_timezone_set('Africa/Lagos');
define('BASEDIR', __DIR__);

require_once BASEDIR . '/services/data.service.php';
require_once BASEDIR . '/services/delivery_log.service.php';
require_once BASEDIR . '/config/database.php';

use Binali\Config\Database;
use Binali\Services\DeliveryLogService;

// Prevent concurrent executions
$lockFile = BASEDIR . '/delivery-cron.lock';
$lock = fopen($lockFile, 'c');
if (!flock($lock, LOCK_EX | LOCK_NB)) {
    exit(0); // Another instance running
}

// Configuration
$db = new Database();
$ds = new DataService();
$logService = new DeliveryLogService();
$logDir = BASEDIR . '/logs';
@mkdir($logDir, 0755, true);
$logFile = $logDir . '/delivery-' . date('Y-m-d') . '.log';

// Network mapping
$networks = [1 => 'MTN', 2 => 'Airtel', 3 => 'Glo', 4 => '9mobile'];

/**
 * Log message to file and console
 */
function log_msg($message, $level = 'INFO') {
    global $logFile;
    $timestamp = date('Y-m-d H:i:s');
    $line = "[$timestamp] [$level] $message\n";
    error_log($line, 3, $logFile);
    echo $line;
}

/**
 * Deliver data for a single plan
 */
function deliver_plan($plan) {
    global $db, $ds, $logService, $networks;
    
    $planId = $plan['id'];
    $userId = $plan['user_id'];
    $phone = $plan['phone_number'];
    // Normalize network: accept numeric id or network name/code
    $rawNetwork = isset($plan['network']) ? $plan['network'] : (isset($plan['network_id']) ? $plan['network_id'] : null);
    $network = 0;
    if ($rawNetwork === null || $rawNetwork === '') {
        // no network provided
        $network = 0;
    } elseif (is_numeric($rawNetwork)) {
        $network = intval($rawNetwork);
    } else {
        // try map by name/code (case-insensitive)
        $rk = strtolower(trim($rawNetwork));
        foreach ($networks as $nid => $nname) {
            if (strpos(strtolower($nname), $rk) !== false || strpos($rk, strtolower($nname)) !== false || $rk === strtolower($nname)) {
                $network = $nid;
                break;
            }
        }
        // if still zero, attempt common aliases
        if ($network === 0) {
            $aliases = [
                'mtn' => 1, 'airtel' => 2, 'glo' => 3, '9mobile' => 4, 'etisalat' => 4, '9mobile' => 4
            ];
            $ak = preg_replace('/[^a-z0-9]/', '', $rk);
            if (isset($aliases[$ak])) {
                $network = $aliases[$ak];
            }
        }
    }
    $planCode = $plan['plan_id'];
    $planType = $plan['user_type']; // SME, Corporate, Gifting
    $transRef = $plan['transaction_reference'];
    
    try {
        // Get plan details from dataplans
        $planData = $db->query(
            "SELECT pId, name, price, type FROM dataplans WHERE planid = ?",
            [$planCode]
        );
        
        if (empty($planData)) {
            log_msg("Plan code $planCode not found in dataplans", 'ERROR');
            $logService->logDelivery([
                'plan_id' => $planId,
                'user_id' => $userId,
                'phone_number' => $phone,
                'network_id' => $network,
                'plan_code' => $planCode,
                'transaction_ref' => $transRef,
                'status' => 'failed',
                'error_message' => "Plan code $planCode not found"
            ]);
            return false;
        }
        
        // Get provider details
        // Validate network id before provider lookup
        if (empty($network) || $network === 0) {
            throw new Exception("Error fetching provider details: Invalid network ID: " . ($rawNetwork ?? 'NULL'));
        }
        $provider = $ds->getDataProviderDetails($network, $planType);
        if (empty($provider)) {
            log_msg("No provider config for network $network, type $planType", 'ERROR');
            $logService->logDelivery([
                'plan_id' => $planId,
                'user_id' => $userId,
                'phone_number' => $phone,
                'network_id' => $network,
                'plan_code' => $planCode,
                'transaction_ref' => $transRef,
                'status' => 'failed',
                'error_message' => "No provider config for network $network"
            ]);
            return false;
        }
        
        $provider = $provider[0];
        $apiKey = $provider['apiKey'];
        $providerUrl = $provider['provider'];
        
        log_msg("Delivering to $phone | Plan: $planCode | Network: " . ($networks[$network] ?? $network), 'INFO');
        
        // Build request payload (same as data.service.php)
        $payload = json_encode([
            'network' => $network,
            'network_id' => $network,
            'mobile_number' => $phone,
            'plan' => is_numeric($planCode) ? intval($planCode) : $planCode,
            'plan_id' => is_numeric($planCode) ? intval($planCode) : $planCode,
            'Ported_number' => true,
            'ref' => $transRef . '_' . date('YmdHis'),
            'phone' => $phone
        ]);
        
        // Determine auth header
        $authHeader = strpos($providerUrl, 'smeplug.ng') !== false 
            ? "Authorization: Bearer $apiKey"
            : "Authorization: Token $apiKey";
        
        // Send request
        $ch = curl_init();
        curl_setopt_array($ch, [
            CURLOPT_URL => $providerUrl,
            CURLOPT_RETURNTRANSFER => true,
            CURLOPT_TIMEOUT => 30,
            CURLOPT_CUSTOMREQUEST => 'POST',
            CURLOPT_POSTFIELDS => $payload,
            CURLOPT_HTTPHEADER => [
                'Content-Type: application/json',
                'Accept: application/json',
                $authHeader
            ],
            CURLOPT_SSL_VERIFYPEER => false
        ]);
        
        $response = curl_exec($ch);
        $httpCode = curl_getinfo($ch, CURLINFO_HTTP_CODE);
        curl_close($ch);
        
        // Parse response
        $result = json_decode($response, true);
        if (json_last_error() !== JSON_ERROR_NONE) {
            log_msg("Invalid JSON response (HTTP $httpCode): $response", 'ERROR');
            $logService->logDelivery([
                'plan_id' => $planId,
                'user_id' => $userId,
                'phone_number' => $phone,
                'network_id' => $network,
                'plan_code' => $planCode,
                'transaction_ref' => $transRef,
                'status' => 'failed',
                'http_code' => $httpCode,
                'provider_response' => $response,
                'error_message' => 'Invalid JSON response'
            ]);
            return false;
        }
        
        // Check status (same robust parsing as data.service.php)
        $status = null;
        if (isset($result['current_status'])) {
            $status = strtolower((string)$result['current_status']);
        } elseif (isset($result['status']) && is_string($result['status'])) {
            $status = strtolower((string)$result['status']);
        } elseif (isset($result['Status'])) {
            $status = strtolower((string)$result['Status']);
        } elseif (isset($result['data']['status'])) {
            $status = strtolower((string)$result['data']['status']);
        } elseif (isset($result['data']['Status'])) {
            $status = strtolower((string)$result['data']['Status']);
        }
        
        // Boolean status fields
        if ($status === null && isset($result['status']) && is_bool($result['status'])) {
            $status = $result['status'] ? 'success' : 'failed';
        }
        
        $isSuccess = $status !== null && in_array($status, 
            ['success', 'successful', 'ok', 'completed', 'true', '1'], true);
        
        // Check message for success indicator if status unclear
        if (!$isSuccess) {
            $msg = $result['api_response'] ?? $result['message'] ?? $result['msg'] ?? null;
            if ($msg && preg_match('/success|completed/i', (string)$msg)) {
                $isSuccess = true;
            }
        }
        
        if (!$isSuccess) {
            log_msg("Provider rejected: HTTP $httpCode | " . json_encode($result), 'WARNING');
            $logService->logDelivery([
                'plan_id' => $planId,
                'user_id' => $userId,
                'phone_number' => $phone,
                'network_id' => $network,
                'plan_code' => $planCode,
                'transaction_ref' => $transRef,
                'status' => 'failed',
                'http_code' => $httpCode,
                'provider_response' => json_encode($result)
            ]);
            return false;
        }
        
        log_msg("✓ Delivered successfully to $phone", 'SUCCESS');
        $logService->logDelivery([
            'plan_id' => $planId,
            'user_id' => $userId,
            'phone_number' => $phone,
            'network_id' => $network,
            'plan_code' => $planCode,
            'transaction_ref' => $transRef,
            'status' => 'success',
            'http_code' => $httpCode,
            'provider_response' => json_encode($result)
        ]);
        return true;
        
    } catch (Exception $e) {
        log_msg("Exception: " . $e->getMessage(), 'ERROR');
        $logService->logDelivery([
            'plan_id' => $planId,
            'user_id' => $userId,
            'phone_number' => $phone,
            'network_id' => $network,
            'plan_code' => $planCode,
            'transaction_ref' => $transRef,
            'status' => 'failed',
            'error_message' => $e->getMessage()
        ]);
        return false;
    }
}

/**
 * Main execution
 */
try {
    log_msg("=== Daily Delivery Cron Started ===", 'INFO');
    
    // Get all active plans due for delivery
    $plans = $db->query(
        "SELECT * FROM daily_data_plans 
         WHERE status = 'active' 
         AND remaining_days > 0 
         AND next_delivery_date <= NOW()
         ORDER BY next_delivery_date ASC",
        []
    );
    
    if (empty($plans)) {
        log_msg("No plans to deliver", 'INFO');
        log_msg("=== Cron Completed ===", 'INFO');
        exit(0);
    }
    
    log_msg("Found " . count($plans) . " plans to process", 'INFO');
    
    $successCount = 0;
    $failureCount = 0;
    
    foreach ($plans as $plan) {
        $success = deliver_plan($plan);
        
        if ($success) {
            $successCount++;
            
            // Update plan: decrease remaining days and set next delivery date
            $newRemaining = intval($plan['remaining_days']) - 1;
            $newNextDate = date('Y-m-d H:i:s', strtotime('+1 day', strtotime($plan['next_delivery_date'])));
            $newStatus = $newRemaining <= 0 ? 'finished' : 'active';
            
            $db->query(
                "UPDATE daily_data_plans 
                 SET remaining_days = ?, 
                     next_delivery_date = ?, 
                     status = ?, 
                     updated_at = NOW() 
                 WHERE id = ?",
                [$newRemaining, $newNextDate, $newStatus, $plan['id']]
            );
            
            log_msg("Updated plan {$plan['id']}: {$newRemaining} days remaining, status: $newStatus", 'INFO');
        } else {
            $failureCount++;
            // Don't update on failure; will retry next cycle
        }
    }
    
    log_msg("=== Cron Completed | Success: $successCount | Failed: $failureCount ===", 'INFO');
    
} catch (Exception $e) {
    log_msg("Fatal error: " . $e->getMessage(), 'ERROR');
} finally {
    flock($lock, LOCK_UN);
    fclose($lock);
}
?>
