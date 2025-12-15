<?php
header("Access-Control-Allow-Origin: *");
header("Content-Type: application/json; charset=UTF-8");
header("Access-Control-Allow-Methods: POST");
header("Access-Control-Max-Age: 3600");
header("Access-Control-Allow-Headers: Content-Type, Access-Control-Allow-Headers, Authorization, X-Requested-With");

include_once '../config/database.php';
include_once '../models/user.php';
include_once '../api/notifications/send.php';
use Binali\Models\User;
use Binali\Config\Database;

$database = new Database();
$db = $database->getConnection();

$user = new User($db);

$data = json_decode(file_get_contents("php://input"));

if(
    !empty($data->fullname) &&
    !empty($data->email) &&
    !empty($data->mobile) &&
    !empty($data->password)
){
    // Split the fullname into first and last name
    $names = explode(' ', $data->fullname, 2);
    $user->sFname = $names[0];
    $user->sLname = isset($names[1]) ? $names[1] : '';
    $user->sEmail = $data->email;
    $user->sPhone = $data->mobile;
    $user->sPass = $data->password;
    $user->sReferal = $data->referral_code ?? '';
    
    // Check for duplicate email
    if($user->emailExists()){
        http_response_code(400);
        echo json_encode(array("message" => "Email already exists."));
        exit();
    }

    // Check for duplicate phone number via direct DB lookup
    try{
        $conn = $db;
        $stmt = $conn->prepare('SELECT sId FROM subscribers WHERE sPhone = :phone LIMIT 1');
        $stmt->bindParam(':phone', $data->mobile);
        $stmt->execute();
        if($stmt->rowCount() > 0){
            http_response_code(400);
            echo json_encode(array("message" => "Phone number already exists."));
            exit();
        }
    } catch(PDOException $ex) {
        // ignore DB check error, continue to create (model will handle uniqueness if enforced)
    }
    
    if($user->create()){
        // Get the newly created user's ID
        $newUserId = $user->sId;
        
        // Send welcome bonus notification
        try {
            $notificationData = [
                'type' => 'welcome_bonus',
                'bonus_type' => 'welcome',
                'timestamp' => time()
            ];
            
            sendTransactionNotification($newUserId, 'welcome_bonus', $notificationData);
        } catch(Exception $e) {
            // Log the error but don't fail the registration
            error_log("Welcome bonus notification error: " . $e->getMessage());
        }
        
        // Handle referral linking if referral code provided
        if(!empty($data->referral_code)){
            try {
                $conn = $db;
                
                // Get referral settings
                $settingsStmt = $conn->prepare('SELECT reward_amount FROM referral_settings WHERE status = "active" LIMIT 1');
                $settingsStmt->execute();
                $rewardAmount = 0.00;
                if($settingsStmt->rowCount() > 0) {
                    $settings = $settingsStmt->fetch();
                    $rewardAmount = $settings['reward_amount'];
                }
                
                // Find referrer by phone number (sReferal stores phone number)
                $referrerStmt = $conn->prepare('SELECT sId FROM subscribers WHERE sPhone = :phone LIMIT 1');
                $referrerStmt->bindParam(':phone', $data->referral_code);
                $referrerStmt->execute();
                
                if($referrerStmt->rowCount() > 0) {
                    $referrer = $referrerStmt->fetch();
                    $referrerId = $referrer['sId'];
                    
                    // Create referral entry
                    $refStmt = $conn->prepare(
                        'INSERT INTO referrals (referrer_id, referee_id, reward_amount, reward_claimed, created_at) 
                         VALUES (:referrer_id, :referee_id, :reward_amount, 0, NOW())'
                    );
                    $refStmt->bindParam(':referrer_id', $referrerId);
                    $refStmt->bindParam(':referee_id', $newUserId);
                    $refStmt->bindParam(':reward_amount', $rewardAmount);
                    $refStmt->execute();
                }
            } catch(Exception $e) {
                // Log the error but don't fail the registration
                error_log("Referral linking error: " . $e->getMessage());
            }
        }
        
        http_response_code(201);
        echo json_encode(array(
            "message" => "User was created.",
            "fullname" => $user->sFname . ' ' . $user->sLname,
            "email" => $user->sEmail
        ));
    }
    else{
        http_response_code(503);
        echo json_encode(array("message" => "Unable to create user."));
    }
}
else{
    http_response_code(400);
    echo json_encode(array("message" => "Unable to create user. Data is incomplete."));
}
?>
