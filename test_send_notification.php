<?php
/**
 * Test Push Notification Script
 * 
 * This script tests the FCM HTTP v1 push notification system
 * by sending a test message to a device token.
 * 
 * Usage:
 *   php test_send_notification.php
 * 
 * Or with custom parameters:
 *   php test_send_notification.php --user-id=1 --title="Test" --body="Message"
 */

// Include database configuration
require_once __DIR__ . '/VTU-API/config/database.php';
require_once __DIR__ . '/VTU-API/services/fcm.service.php';

use Binali\Config\Database;
use Binali\Services\FCMService;

// Configuration
$config = [
    'firebase_project_id' => 'mkdata-39b0f',
    'service_account_path' => __DIR__ . '/VTU-API/srv/keys/mkdata-firebase-sa.json'
];

// Parse command line arguments
$userId = $argc > 1 ? trim($argv[1]) : 1;
$title = 'Test Notification';
$body = 'This is a test push notification from mkdata VTU platform!';

// Parse options if provided
for ($i = 1; $i < $argc; $i++) {
    if (strpos($argv[$i], '--user-id=') === 0) {
        $userId = str_replace('--user-id=', '', $argv[$i]);
    } elseif (strpos($argv[$i], '--title=') === 0) {
        $title = str_replace('--title=', '', $argv[$i]);
    } elseif (strpos($argv[$i], '--body=') === 0) {
        $body = str_replace('--body=', '', $argv[$i]);
    }
}

echo "\n╔════════════════════════════════════════════════════════════╗\n";
echo "║         FCM Push Notification Test Script                 ║\n";
echo "╚════════════════════════════════════════════════════════════╝\n\n";

echo "📋 Test Configuration:\n";
echo "   User ID: $userId\n";
echo "   Title: $title\n";
echo "   Body: $body\n\n";

// Step 1: Connect to database
echo "Step 1: Connecting to database...\n";
try {
    $database = new Database();
    $pdo = $database->getConnection();
    echo "✅ Database connected\n\n";
} catch (Exception $e) {
    echo "❌ Database connection failed: " . $e->getMessage() . "\n";
    exit(1);
}

// Step 2: Fetch device tokens for user
echo "Step 2: Fetching device tokens for user $userId...\n";
try {
    // Try new schema first (user_devices)
    $query = "SELECT id, fcm_token, device_type FROM user_devices WHERE user_id = ? AND is_active = 1";
    $stmt = $pdo->prepare($query);
    $stmt->execute([$userId]);
    $devices = $stmt->fetchAll(PDO::FETCH_ASSOC);
    
    // If no results, try old schema (device_tokens)
    if (empty($devices)) {
        echo "   ℹ user_devices table not found or no active devices, trying device_tokens...\n";
        $query = "SELECT id, token as fcm_token, platform as device_type FROM device_tokens WHERE user_id = ?";
        $stmt = $pdo->prepare($query);
        $stmt->execute([$userId]);
        $devices = $stmt->fetchAll(PDO::FETCH_ASSOC);
    }
    
    if (empty($devices)) {
        echo "❌ No devices found for user $userId\n";
        exit(1);
    }
    
    echo "✅ Found " . count($devices) . " device(s):\n";
    foreach ($devices as $device) {
        $tokenPreview = substr($device['fcm_token'], 0, 20) . '...';
        echo "   • {$device['device_type']}: $tokenPreview\n";
    }
    echo "\n";
} catch (Exception $e) {
    echo "❌ Error fetching devices: " . $e->getMessage() . "\n";
    exit(1);
}

// Step 3: Load and verify service account
echo "Step 3: Loading Firebase service account...\n";
if (!file_exists($config['service_account_path'])) {
    echo "❌ Service account not found at: {$config['service_account_path']}\n";
    exit(1);
}

$serviceAccount = json_decode(file_get_contents($config['service_account_path']), true);
if (!$serviceAccount) {
    echo "❌ Invalid service account JSON\n";
    exit(1);
}

echo "✅ Service account loaded\n";
echo "   Project ID: {$serviceAccount['project_id']}\n";
echo "   Client Email: {$serviceAccount['client_email']}\n\n";

// Step 4: Generate OAuth 2.0 token
echo "Step 4: Generating OAuth 2.0 access token...\n";
try {
    $token = generateAccessToken($serviceAccount);
    if (!$token) {
        echo "❌ Failed to generate access token\n";
        exit(1);
    }
    echo "✅ Access token generated\n";
    echo "   Token (preview): " . substr($token, 0, 30) . "...\n\n";
} catch (Exception $e) {
    echo "❌ Token generation error: " . $e->getMessage() . "\n";
    exit(1);
}

// Step 5: Send notification to each device
echo "Step 5: Sending notifications...\n";
$successCount = 0;
$failureCount = 0;

foreach ($devices as $device) {
    $deviceType = $device['device_type'] ?? 'unknown';
    $fcmToken = $device['fcm_token'];
    
    try {
        $result = sendFCMNotification(
            $token,
            $config['firebase_project_id'],
            $fcmToken,
            $title,
            $body,
            ['type' => 'test', 'user_id' => $userId]
        );
        
        if ($result) {
            echo "   ✅ {$deviceType}: Message sent\n";
            $successCount++;
        } else {
            echo "   ❌ {$deviceType}: Send failed\n";
            $failureCount++;
        }
    } catch (Exception $e) {
        echo "   ❌ {$deviceType}: " . $e->getMessage() . "\n";
        $failureCount++;
    }
}

echo "\n";

// Step 6: Summary
echo "╔════════════════════════════════════════════════════════════╗\n";
echo "║                      Test Results                          ║\n";
echo "╠════════════════════════════════════════════════════════════╣\n";
printf("║ Total Devices: %-47d ║\n", count($devices));
printf("║ Successful: %-51d ║\n", $successCount);
printf("║ Failed: %-56d ║\n", $failureCount);
echo "╠════════════════════════════════════════════════════════════╣\n";

if ($failureCount === 0 && $successCount > 0) {
    echo "║ ✅ SUCCESS - Notification sent to all devices!          ║\n";
} else {
    echo "║ ⚠️  PARTIAL - Some notifications may have failed        ║\n";
}

echo "╚════════════════════════════════════════════════════════════╝\n\n";

// ============================================================================
// HELPER FUNCTIONS
// ============================================================================

/**
 * Generate OAuth 2.0 access token using JWT
 */
function generateAccessToken($serviceAccount) {
    $privateKey = $serviceAccount['private_key'];
    $clientEmail = $serviceAccount['client_email'];
    
    // JWT Header
    $header = json_encode([
        'alg' => 'RS256',
        'typ' => 'JWT'
    ]);
    
    $now = time();
    $expiry = $now + 3600;
    
    // JWT Payload
    $payload = json_encode([
        'iss' => $clientEmail,
        'scope' => 'https://www.googleapis.com/auth/firebase.messaging',
        'aud' => 'https://oauth2.googleapis.com/token',
        'exp' => $expiry,
        'iat' => $now
    ]);
    
    // Encode
    $base64Header = rtrim(strtr(base64_encode($header), '+/', '-_'), '=');
    $base64Payload = rtrim(strtr(base64_encode($payload), '+/', '-_'), '=');
    
    // Sign
    $signatureInput = $base64Header . '.' . $base64Payload;
    
    openssl_sign(
        $signatureInput,
        $signature,
        $privateKey,
        'sha256WithRSAEncryption'
    );
    
    $base64Signature = rtrim(strtr(base64_encode($signature), '+/', '-_'), '=');
    $jwt = $signatureInput . '.' . $base64Signature;
    
    // Exchange JWT for access token
    $ch = curl_init('https://oauth2.googleapis.com/token');
    curl_setopt_array($ch, [
        CURLOPT_RETURNTRANSFER => true,
        CURLOPT_POST => true,
        CURLOPT_HTTPHEADER => ['Content-Type: application/x-www-form-urlencoded'],
        CURLOPT_POSTFIELDS => http_build_query([
            'grant_type' => 'urn:ietf:params:oauth:grant-type:jwt-bearer',
            'assertion' => $jwt
        ]),
        CURLOPT_TIMEOUT => 10,
        CURLOPT_SSL_VERIFYPEER => true
    ]);
    
    $response = curl_exec($ch);
    $httpCode = curl_getinfo($ch, CURLINFO_HTTP_CODE);
    $error = curl_error($ch);
    curl_close($ch);
    
    if ($error) {
        throw new Exception('OAuth request failed: ' . $error);
    }
    
    if ($httpCode !== 200) {
        throw new Exception('OAuth token request failed: ' . $response);
    }
    
    $result = json_decode($response, true);
    return $result['access_token'] ?? null;
}

/**
 * Send notification via FCM HTTP v1 API
 */
function sendFCMNotification($accessToken, $projectId, $fcmToken, $title, $body, $data = []) {
    $url = "https://fcm.googleapis.com/v1/projects/$projectId/messages:send";
    
    // Build message
    $message = [
        'token' => $fcmToken,
        'notification' => [
            'title' => $title,
            'body' => $body
        ],
        'data' => [],
        'android' => [
            'priority' => 'high',
            'notification' => [
                'click_action' => 'FLUTTER_NOTIFICATION_CLICK'
            ]
        ],
        'apns' => [
            'headers' => [
                'apns-priority' => '10'
            ]
        ]
    ];
    
    // Add data (convert to strings)
    foreach ($data as $key => $value) {
        $message['data'][$key] = (string)$value;
    }
    
    $payload = json_encode(['message' => $message]);
    
    // Send via cURL
    $ch = curl_init($url);
    curl_setopt_array($ch, [
        CURLOPT_RETURNTRANSFER => true,
        CURLOPT_POST => true,
        CURLOPT_HTTPHEADER => [
            'Content-Type: application/json',
            'Authorization: Bearer ' . $accessToken
        ],
        CURLOPT_POSTFIELDS => $payload,
        CURLOPT_TIMEOUT => 10,
        CURLOPT_SSL_VERIFYPEER => true
    ]);
    
    $response = curl_exec($ch);
    $httpCode = curl_getinfo($ch, CURLINFO_HTTP_CODE);
    $error = curl_error($ch);
    curl_close($ch);
    
    if ($error) {
        throw new Exception('cURL error: ' . $error);
    }
    
    if ($httpCode !== 200) {
        $result = json_decode($response, true);
        $errorMsg = $result['error']['message'] ?? 'Unknown error';
        throw new Exception("FCM API error (HTTP $httpCode): $errorMsg");
    }
    
    return true;
}

?>
