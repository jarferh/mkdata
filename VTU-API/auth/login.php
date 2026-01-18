<?php
// Allow credentials with specific origins or same-origin requests
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
    // For all other origins, still allow but without credentials
    header("Access-Control-Allow-Origin: *");
}

header("Content-Type: application/json; charset=UTF-8");
header("Access-Control-Allow-Methods: POST");
header("Access-Control-Max-Age: 3600");
header("Access-Control-Allow-Headers: Content-Type, Access-Control-Allow-Headers, Authorization, X-Requested-With");

// Load environment variables from .env file
require_once '../auth/session-helper.php';
loadEnvFile(__DIR__ . '/../.env');

// Initialize session to enable session-based authentication
initializeSession();

include_once '../config/database.php';
include_once '../models/user.php';
use Binali\Config\Database;
use Binali\Models\User;

$database = new Database();
$db = $database->getConnection();

$user = new User($db);

$data = json_decode(file_get_contents("php://input"));

if(!empty($data->email) && !empty($data->password)){
    $user->sEmail = $data->email;
    $user->sPass = $data->password;
    
    if($user->emailExists()){
        // Check if account is deleted
        if((int)$user->sRegStatus === 3) {
            http_response_code(401);
            echo json_encode(array("message" => "This account has been deleted. Please contact support if you wish to reactivate it."));
            exit();
        }
        
        if($user->validatePassword($data->password)){
            // Save user ID to session (THIS is the authenticated user)
            setAuthenticatedUser($user->sId, $user->sEmail, 'user');
            
            // Log session diagnostics to error log for debugging
            error_log('Login BEFORE write_close: session_id=' . session_id());
            error_log('Login BEFORE write_close: $_SESSION=' . json_encode($_SESSION));
            
            // Note: Do NOT call session_write_close() here as it closes the session
            // The session will be automatically written when the PHP script ends
            
            error_log('Login AFTER (implicit) write: session_id=' . session_id());
            
            http_response_code(200);
            echo json_encode(array(
                "message" => "Login successful.",
                "id" => (string)$user->sId,
                "fullname" => $user->sFname . ' ' . $user->sLname,
                "email" => $user->sEmail,
                "phone" => $user->sPhone,
                "wallet" => $user->sWallet
            ));
            // If client included an fcm_token during login, insert into device_tokens
            if (!empty($data->fcm_token)) {
                try {
                    // Upsert token and update platform & last_seen when token already exists for the user
                    $stmt = $db->prepare('INSERT INTO device_tokens (user_id, token, platform, last_seen) VALUES (:uid, :token, :platform, NOW()) ON DUPLICATE KEY UPDATE last_seen = NOW(), platform = VALUES(platform)');
                    $platform = isset($data->platform) ? $data->platform : null;
                    $token = $data->fcm_token;
                    $stmt->bindParam(':uid', $user->sId);
                    $stmt->bindParam(':token', $token);
                    $stmt->bindParam(':platform', $platform);
                    $stmt->execute();
                } catch (Exception $e) {
                    error_log('Failed to save device token on login for user ' . $user->sId . ': ' . $e->getMessage());
                }
            }
            
            // Send login notification
            try {
                $notificationFile = __DIR__ . '/../api/send-transaction-notification.php';
                if (file_exists($notificationFile)) {
                    require_once $notificationFile;
                    sendTransactionNotification($user->sId, 'login', [
                        'time' => date('H:i')
                    ]);
                } else {
                    error_log('Notification file not found: ' . $notificationFile);
                }
            } catch (Exception $e) {
                error_log('Failed to send login notification for user ' . $user->sId . ': ' . $e->getMessage());
            }
        }
        else{
            http_response_code(401);
            echo json_encode(array("message" => "Invalid password."));
        }
    }
    else{
        http_response_code(404);
        echo json_encode(array("message" => "Email not found."));
    }
}
else{
    http_response_code(400);
    echo json_encode(array("message" => "Unable to login. Data is incomplete."));
}
?>
