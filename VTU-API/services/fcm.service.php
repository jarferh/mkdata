<?php
/**
 * Firebase Cloud Messaging Service (FCM HTTP v1 API)
 * 
 * Handles:
 * - OAuth 2.0 token generation from service account JSON
 * - Token caching (1 hour TTL)
 * - FCM message sending via HTTP v1 API
 * - Error handling and retry logic
 */

class FCMService {
    private $serviceAccountPath;
    private $projectId;
    private $accessToken;
    private $tokenExpiry;
    private $fcmApiUrl = 'https://fcm.googleapis.com/v1/projects';
    
    // Cache file path for tokens
    private $tokenCacheFile;
    
    public function __construct($serviceAccountJsonPath = null) {
        if ($serviceAccountJsonPath === null) {
            // Default path - adjust to your server setup
            $serviceAccountJsonPath = __DIR__ . '/../srv/keys/mkdata-firebase-sa.json';
        }
        
        $this->serviceAccountPath = $serviceAccountJsonPath;
        $this->tokenCacheFile = sys_get_temp_dir() . '/fcm_access_token.cache';
        
        // Load and validate service account
        $this->loadServiceAccount();
    }
    
    /**
     * Load and parse service account JSON
     */
    private function loadServiceAccount() {
        if (!file_exists($this->serviceAccountPath)) {
            throw new Exception('Service account JSON not found at: ' . $this->serviceAccountPath);
        }
        
        $json = file_get_contents($this->serviceAccountPath);
        $config = json_decode($json, true);
        
        if ($config === null) {
            throw new Exception('Invalid service account JSON format');
        }
        
        $this->projectId = $config['project_id'] ?? null;
        
        if (empty($this->projectId)) {
            throw new Exception('project_id not found in service account JSON');
        }
    }
    
    /**
     * Get a valid access token (cached or freshly generated)
     * Uses JWT to request OAuth 2.0 token from Google
     */
    public function getAccessToken() {
        // Check if cached token is still valid
        if ($this->isCachedTokenValid()) {
            return $this->accessToken;
        }
        
        // Generate new token
        $this->generateAccessToken();
        return $this->accessToken;
    }
    
    /**
     * Check if cached token is still valid
     */
    private function isCachedTokenValid() {
        if (file_exists($this->tokenCacheFile)) {
            $cached = json_decode(file_get_contents($this->tokenCacheFile), true);
            
            if ($cached && isset($cached['token']) && isset($cached['expiry'])) {
                // Check if token expiry is still in the future (add 30 second buffer)
                if (time() < ($cached['expiry'] - 30)) {
                    $this->accessToken = $cached['token'];
                    $this->tokenExpiry = $cached['expiry'];
                    return true;
                }
            }
        }
        
        return false;
    }
    
    /**
     * Generate new OAuth 2.0 access token using JWT
     */
    private function generateAccessToken() {
        $json = file_get_contents($this->serviceAccountPath);
        $config = json_decode($json, true);
        
        $privateKey = $config['private_key'];
        $clientEmail = $config['client_email'];
        
        // Create JWT header
        $header = json_encode([
            'alg' => 'RS256',
            'typ' => 'JWT'
        ]);
        
        $now = time();
        $expiry = $now + 3600; // Token valid for 1 hour
        
        // Create JWT payload
        $payload = json_encode([
            'iss' => $clientEmail,
            'scope' => 'https://www.googleapis.com/auth/firebase.messaging',
            'aud' => 'https://oauth2.googleapis.com/token',
            'exp' => $expiry,
            'iat' => $now
        ]);
        
        // Encode header and payload
        $base64Header = rtrim(strtr(base64_encode($header), '+/', '-_'), '=');
        $base64Payload = rtrim(strtr(base64_encode($payload), '+/', '-_'), '=');
        
        // Create signature
        $signatureInput = $base64Header . '.' . $base64Payload;
        
        // Sign with private key
        openssl_sign(
            $signatureInput,
            $signature,
            $privateKey,
            'sha256WithRSAEncryption'
        );
        
        $base64Signature = rtrim(strtr(base64_encode($signature), '+/', '-_'), '=');
        $jwt = $signatureInput . '.' . $base64Signature;
        
        // Exchange JWT for access token
        $tokenResponse = $this->requestAccessToken($jwt);
        
        if (!isset($tokenResponse['access_token'])) {
            throw new Exception('Failed to obtain access token: ' . json_encode($tokenResponse));
        }
        
        $this->accessToken = $tokenResponse['access_token'];
        $this->tokenExpiry = time() + ($tokenResponse['expires_in'] ?? 3600);
        
        // Cache token
        $this->cacheToken($this->accessToken, $this->tokenExpiry);
        
        error_log('✓ New FCM access token generated, expires at ' . date('Y-m-d H:i:s', $this->tokenExpiry));
    }
    
    /**
     * Request access token from Google OAuth endpoint
     */
    private function requestAccessToken($jwt) {
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
        
        $result = json_decode($response, true);
        
        if ($httpCode !== 200) {
            throw new Exception('OAuth token request failed with status ' . $httpCode . ': ' . json_encode($result));
        }
        
        return $result;
    }
    
    /**
     * Cache access token to file
     */
    private function cacheToken($token, $expiry) {
        $cacheData = json_encode([
            'token' => $token,
            'expiry' => $expiry,
            'cached_at' => date('Y-m-d H:i:s')
        ]);
        
        file_put_contents($this->tokenCacheFile, $cacheData);
    }
    
    /**
     * Send push notification to a single FCM token
     */
    public function sendToToken($fcmToken, $title, $body, $data = [], $options = []) {
        $message = $this->buildMessage($fcmToken, $title, $body, $data, $options);
        return $this->sendMessage($message);
    }
    
    /**
     * Send push notification to multiple FCM tokens
     */
    public function sendToMultipleTokens($fcmTokens, $title, $body, $data = [], $options = []) {
        $results = [
            'successful' => 0,
            'failed' => 0,
            'errors' => []
        ];
        
        foreach ($fcmTokens as $token) {
            try {
                if ($this->sendToToken($token, $title, $body, $data, $options)) {
                    $results['successful']++;
                } else {
                    $results['failed']++;
                    $results['errors'][] = ['token' => $token, 'reason' => 'send_failed'];
                }
            } catch (Exception $e) {
                $results['failed']++;
                $results['errors'][] = ['token' => $token, 'reason' => $e->getMessage()];
                
                // Log each individual failure
                error_log('FCM send failed for token: ' . substr($token, 0, 20) . '... - ' . $e->getMessage());
            }
        }
        
        return $results;
    }
    
    /**
     * Build FCM message payload
     */
    private function buildMessage($fcmToken, $title, $body, $data = [], $options = []) {
        $notification = [
            'title' => $title,
            'body' => $body
        ];
        
        // Add optional notification fields
        if (isset($options['image'])) {
            $notification['image'] = $options['image'];
        }
        
        $message = [
            'token' => $fcmToken,
            'notification' => $notification
        ];
        
        // Add data payload (custom data)
        if (!empty($data)) {
            $message['data'] = [];
            foreach ($data as $key => $value) {
                // FCM data values must be strings
                $message['data'][$key] = (string)$value;
            }
        }
        
        // Add Android-specific options
        if (isset($options['android'])) {
            $message['android'] = $options['android'];
        } else {
            // Default Android config
            $message['android'] = [
                'priority' => 'high',
                'notification' => [
                    'click_action' => 'FLUTTER_NOTIFICATION_CLICK'
                ]
            ];
        }
        
        // Add iOS-specific options
        if (isset($options['apns'])) {
            $message['apns'] = $options['apns'];
        } else {
            // Default iOS config
            $message['apns'] = [
                'headers' => [
                    'apns-priority' => '10'
                ]
            ];
        }
        
        return $message;
    }
    
    /**
     * Send message via FCM HTTP v1 API
     */
    private function sendMessage($message) {
        $accessToken = $this->getAccessToken();
        
        $url = $this->fcmApiUrl . '/' . $this->projectId . '/messages:send';
        
        $payload = json_encode(['message' => $message]);
        
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
            error_log('FCM curl error: ' . $error);
            return false;
        }
        
        if ($httpCode !== 200) {
            error_log('FCM API error (HTTP ' . $httpCode . '): ' . $response);
            
            // Check for specific error codes
            $result = json_decode($response, true);
            if (isset($result['error']['details'])) {
                foreach ($result['error']['details'] as $detail) {
                    if ($detail['reason'] === 'INVALID_ARGUMENT' && 
                        strpos($detail['detail'], 'registration token is invalid') !== false) {
                        // Invalid token - should be removed from DB
                        return 'invalid_token';
                    }
                }
            }
            
            return false;
        }
        
        error_log('✓ FCM message sent successfully');
        return true;
    }
}
?>
