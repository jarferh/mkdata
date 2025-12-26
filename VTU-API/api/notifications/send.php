<?php
/**
 * Send push notification to a user
 * 
 * This function is called internally from transaction handlers (purchase-daily-data, airtime, etc.)
 * to send notifications to all user devices.
 * 
 * Usage:
 *   sendPushToUser(
 *       userId: 123,
 *       title: 'Transaction Successful',
 *       body: 'Your airtime purchase was successful',
 *       data: [
 *           'type' => 'transaction',
 *           'transaction_id' => 456,
 *           'amount' => '1000',
 *           'network' => 'MTN'
 *       ]
 *   );
 */

require_once __DIR__ . '/../../db/database.php';
require_once __DIR__ . '/../../services/fcm.service.php';

function sendPushToUser($userId, $title, $body, $data = [], $options = []) {
    try {
        // Validate input
        if (empty($userId) || empty($title) || empty($body)) {
            error_log('Invalid push notification parameters: userId=' . $userId . ', title=' . $title . ', body=' . $body);
            return [
                'success' => false,
                'message' => 'Invalid parameters'
            ];
        }
        
        
        // Get a database instance and fetch active devices for this user
        // Check both user_devices (new) and device_tokens (legacy) tables for compatibility
        $db = new Database();
        
        $selectQuery = "SELECT id, fcm_token, device_type, device_name 
                        FROM user_devices 
                        WHERE user_id = ? AND is_active = 1";
        
        $devices = $db->query($selectQuery, [$userId], true);
        
        // If no devices in user_devices, check legacy device_tokens table
        if (empty($devices)) {
            error_log('ℹ No devices in user_devices table, checking legacy device_tokens table for user ' . $userId);
            $legacyQuery = "SELECT id, token as fcm_token, platform as device_type, NULL as device_name 
                           FROM device_tokens 
                           WHERE user_id = ?";
            $legacyDevices = $db->query($legacyQuery, [$userId], true);
            
            if (!empty($legacyDevices)) {
                error_log('✓ Found ' . count($legacyDevices) . ' device(s) in legacy device_tokens table for user ' . $userId);
                $devices = $legacyDevices;
            }
        }
        
        if (empty($devices)) {
            // No devices registered in either table
            error_log('⚠️ No active devices found for user ' . $userId . '. User needs to register their device token via /api/device/register');
            return [
                'success' => true,
                'message' => 'No devices registered for this user. Device registration required.',
                'devices_sent' => 0,
                'note' => 'User should call /api/device/register to enable push notifications'
            ];
        }
        
        // Initialize FCM service
        $fcm = new FCMService();
        
        // Extract tokens and prepare for sending
        $tokens = array_column($devices, 'fcm_token');
        $deviceMap = [];
        foreach ($devices as $device) {
            $deviceMap[$device['fcm_token']] = $device;
        }
        
        error_log('Sending push notification to ' . count($tokens) . ' device(s) for user ' . $userId);
        
        // Send to all tokens
        $results = $fcm->sendToMultipleTokens($tokens, $title, $body, $data, $options);
        
        // Handle invalid tokens - deactivate them in database
        if (!empty($results['errors'])) {
            foreach ($results['errors'] as $error) {
                if ($error['reason'] === 'send_failed' || strpos($error['reason'], 'invalid') !== false) {
                    // Deactivate this device
                    $updateQuery = "UPDATE user_devices SET is_active = 0 WHERE fcm_token = ?";
                    $db->query($updateQuery, [$error['token']], false);
                    
                    error_log('Device deactivated due to invalid token: ' . substr($error['token'], 0, 20) . '...');
                }
            }
        }        // Log results
        error_log('Push notification results: ' . $results['successful'] . ' successful, ' . 
                  $results['failed'] . ' failed for user ' . $userId);
        
        return [
            'success' => $results['successful'] > 0,
            'message' => 'Notification sent to ' . $results['successful'] . ' device(s)',
            'devices_sent' => $results['successful'],
            'devices_failed' => $results['failed'],
            'details' => $results['errors']
        ];
        
    } catch (Throwable $e) {
        // Catch any throwable (Error or Exception) to prevent push notification
        // failures from causing fatal errors in calling code.
        error_log('Error sending push notification: ' . $e->getMessage());

        return [
            'success' => false,
            'message' => 'Failed to send notification: ' . $e->getMessage()
        ];
    }
}

/**
 * Send notification for specific transaction types
 * Helper function to construct proper data payloads for different transaction types
 */
function sendTransactionNotification($userId, $transactionType, $transactionData) {
    // Construct data payload based on transaction type
    $data = [
        'type' => 'transaction',
        'transaction_type' => $transactionType,
        'timestamp' => time()
    ];
    
    // Add transaction-specific data
    if (isset($transactionData['transaction_id'])) {
        $data['transaction_id'] = $transactionData['transaction_id'];
    }
    if (isset($transactionData['amount'])) {
        $data['amount'] = $transactionData['amount'];
    }
    if (isset($transactionData['network'])) {
        $data['network'] = $transactionData['network'];
    }
    if (isset($transactionData['reference'])) {
        $data['reference'] = $transactionData['reference'];
    }
    
    // Determine title and body based on type
    $title = '';
    $body = '';
    
    switch ($transactionType) {
        case 'daily_data':
            $title = '📱 Daily Data Activated';
            $plan = $transactionData['plan'] ?? 'Unknown plan';
            $body = 'Your ' . $plan . ' is activated successfully';
            break;
            
        case 'airtime':
            $status = $transactionData['status'] ?? 'success';
            
            if ($status === 'error' || $status === 'failed') {
                $title = 'Airtime Purchase Failed';
                $body = 'Airtime purchase failed. Please try again.';
            } else {
                $title = 'Airtime Purchase Successful';
                $body = 'Your airtime purchase was successful.';
            }
            break;
            
        case 'data':
            $status = $transactionData['status'] ?? 'success';
            
            if ($status === 'error' || $status === 'failed') {
                $title = 'Data Purchase Failed';
                $body = 'Data bundle purchase failed. Please try again.';
            } else {
                $title = 'Data Purchase Successful';
                $body = 'Your data bundle purchase was successful.';
            }
            break;
            
        case 'cable':
            $status = $transactionData['status'] ?? 'success';
            
            if ($status === 'error' || $status === 'failed') {
                $title = 'Cable Subscription Failed';
                $body = 'Cable subscription failed. Please try again.';
            } else {
                $title = 'Cable Subscription Successful';
                $body = 'Your cable subscription was successful.';
            }
            break;
            
        case 'electricity':
            $status = $transactionData['status'] ?? 'success';
            
            if ($status === 'error' || $status === 'failed') {
                $title = 'Electricity Purchase Failed';
                $body = 'Electricity purchase failed. Please try again.';
            } else {
                $title = 'Electricity Purchase Successful';
                $body = 'Your electricity purchase was successful.';
            }
            break;
            
        case 'wallet_credit':
            $title = '💰 Wallet Credited';
            $amount = $transactionData['amount'] ?? '0';
            $body = '₦' . number_format($amount) . ' has been added to your wallet';
            break;
            
        case 'refund':
            $title = '↩️ Refund Processed';
            $amount = $transactionData['amount'] ?? '0';
            $body = '₦' . number_format($amount) . ' refund has been processed';
            break;

        case 'spin_win':
            // Notification for when a spin completes (won something)
            $rewardType = $transactionData['reward_type'] ?? 'reward';
            $amount = $transactionData['amount'] ?? '';
            if ($rewardType === 'airtime') {
                $title = '🎉 Spin Win — Airtime!';
                $body = 'You won ₦' . number_format($amount) . ' airtime';
            } elseif ($rewardType === 'data') {
                $title = '🎉 Spin Win — Data!';
                $body = 'You won ' . ($amount) . ' ' . ($transactionData['unit'] ?? 'MB') . ' of data';
            } else {
                $title = '🎉 Spin Win!';
                $body = 'You won a reward from the Spin & Win';
            }
            break;

        case 'spin_claim':
            // Notification when a user claims a spin reward (and optional delivery)
            $status = $transactionData['status'] ?? 'claimed';
            $rewardType = $transactionData['reward_type'] ?? 'reward';
            if ($status === 'claimed' && !empty($transactionData['delivered']) && $transactionData['delivered'] === true) {
                if ($rewardType === 'airtime') {
                    $title = '☎️ Airtime Delivered';
                    $body = 'Your airtime has been delivered successfully';
                } else {
                    $title = '📡 Data Delivered';
                    $body = 'Your data reward has been delivered successfully';
                }
            } else {
                $title = '✅ Reward Claimed';
                $body = 'Your spin reward has been claimed; delivery is pending';
            }
            break;

        case 'welcome_bonus':
            // Notification when a new user registers and receives welcome bonus
            $title = '🎉 Welcome to mkdata!';
            $body = 'You\'ve received a welcome bonus. Check your account to claim it!';
            break;

        case 'referral_claimed':
            // Notification when user claims a referral reward
            $amount = $transactionData['amount'] ?? '0';
            $title = '💰 Referral Reward Claimed';
            $body = '₦' . number_format($amount) . ' has been added to your referral wallet';
            break;

        case 'referral_withdrawal':
            // Notification when user withdraws from referral wallet
            $amount = $transactionData['amount'] ?? '0';
            $title = '💸 Withdrawal Complete';
            $body = '₦' . number_format($amount) . ' withdrawn to your main wallet';
            break;

        case 'profile_updated':
            // Notification when user updates their profile
            $title = '✅ Profile Updated';
            $body = 'Your profile has been successfully updated';
            break;

        case 'pin_changed':
            // Notification when user changes their transaction PIN
            $title = '🔐 PIN Changed';
            $body = 'Your transaction PIN has been successfully updated';
            break;

        case 'card_pin':
            // Notification for card PIN purchases
            $status = $transactionData['status'] ?? 'error';
            
            if ($status === 'error') {
                $title = 'Card PIN Purchase Failed';
                $body = 'Card PIN purchase failed. Please try again.';
            } else {
                $title = 'Card PIN Purchase Successful';
                $body = 'Your card PIN purchase was successful.';
            }
            break;

        case 'data_pin':
            // Notification for data PIN purchases
            $status = $transactionData['status'] ?? 'error';
            
            if ($status === 'error') {
                $title = 'Data PIN Purchase Failed';
                $body = 'Data PIN purchase failed. Please try again.';
            } else {
                $title = 'Data PIN Purchase Successful';
                $body = 'Your data PIN purchase was successful.';
            }
            break;

        case 'exam_pin':
            // Notification for exam PIN purchases
            $status = $transactionData['status'] ?? 'error';
            
            if ($status === 'error') {
                $title = 'Exam PIN Purchase Failed';
                $body = 'Exam PIN purchase failed. Please try again.';
            } else {
                $title = 'Exam PIN Purchase Successful';
                $body = 'Your exam PIN purchase was successful.';
            }
            break;

        case 'airtime2cash':
            // Notification for airtime to cash conversions
            $status = $transactionData['status'] ?? 'success';
            $amount = $transactionData['amount'] ?? '0';
            $reference = $transactionData['reference'] ?? 'Unknown';
            
            if ($status === 'error' || $status === 'failed') {
                $title = '❌ Airtime Conversion Failed';
                $body = 'Unable to convert ₦' . number_format($amount) . ' airtime to cash. Please try again. Ref: ' . $reference;
            } else {
                $title = '💰 Airtime Conversion Processing';
                $body = '₦' . number_format($amount) . ' airtime conversion initiated. Wallet will be credited shortly. Ref: ' . $reference;
            }
            break;
            
        default:
            $title = '✓ Transaction Complete';
            $body = 'Your transaction has been processed successfully';
    }
    
    return sendPushToUser($userId, $title, $body, $data);
}

/**
 * Send error notification to user
 */
function sendErrorNotification($userId, $errorMessage, $transactionType = null) {
    $data = [
        'type' => 'error',
        'timestamp' => time()
    ];
    
    if ($transactionType) {
        $data['transaction_type'] = $transactionType;
    }
    
    return sendPushToUser(
        $userId,
        '⚠️ Transaction Failed',
        'Error: ' . $errorMessage,
        $data
    );
}

/**
 * Send wallet notification
 */
function sendWalletNotification($userId, $title, $body, $data = []) {
    $data['type'] = 'wallet';
    $data['timestamp'] = time();
    
    return sendPushToUser($userId, $title, $body, $data);
}
?>
