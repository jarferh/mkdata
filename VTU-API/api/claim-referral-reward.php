<?php
header("Access-Control-Allow-Origin: *");
header("Content-Type: application/json; charset=UTF-8");
header("Access-Control-Allow-Methods: POST, OPTIONS");
header("Access-Control-Max-Age: 3600");
header("Access-Control-Allow-Headers: Content-Type, Access-Control-Allow-Headers, Authorization, X-Requested-With");

if ($_SERVER['REQUEST_METHOD'] == 'OPTIONS') {
    http_response_code(200);
    exit();
}

include_once '../config/database.php';

$database = new \Binali\Config\Database();
$db = $database->getConnection();

$data = json_decode(file_get_contents("php://input"));

if(empty($data->user_id) || empty($data->referral_id)) {
    http_response_code(400);
    echo json_encode(array("message" => "User ID and Referral ID are required."));
    exit();
}

try {
    $userId = $data->user_id;
    $referralId = $data->referral_id;

    // Check if referral exists and belongs to the user
    $checkStmt = $db->prepare('
        SELECT id, reward_amount, reward_claimed FROM referrals 
        WHERE id = :referral_id AND referrer_id = :user_id
    ');
    $checkStmt->bindParam(':referral_id', $referralId);
    $checkStmt->bindParam(':user_id', $userId);
    $checkStmt->execute();

    if($checkStmt->rowCount() == 0) {
        http_response_code(404);
        echo json_encode(array("message" => "Referral not found or you don't have permission to claim it."));
        exit();
    }

    $referral = $checkStmt->fetch(PDO::FETCH_ASSOC);

    if($referral['reward_claimed']) {
        http_response_code(400);
        echo json_encode(array("message" => "Reward has already been claimed."));
        exit();
    }

    // Start transaction
    $db->beginTransaction();

    try {
        // Update referral as claimed
        $updateStmt = $db->prepare('
            UPDATE referrals 
            SET reward_claimed = 1, claimed_at = NOW() 
            WHERE id = :referral_id
        ');
        $updateStmt->bindParam(':referral_id', $referralId);
        $updateStmt->execute();

        // Add reward amount to user's referral wallet (sRefWallet)
        $rewardAmount = floatval($referral['reward_amount']);
        $walletStmt = $db->prepare('
            UPDATE subscribers 
            SET sRefWallet = sRefWallet + :amount 
            WHERE sId = :user_id
        ');
        $walletStmt->bindParam(':amount', $rewardAmount);
        $walletStmt->bindParam(':user_id', $userId);
        $walletStmt->execute();

        // Commit transaction
        $db->commit();

        // Send notification
        require_once __DIR__ . '/notifications/send.php';
        try {
            sendTransactionNotification(
                $userId,
                'referral_claimed',
                [
                    'amount' => $rewardAmount,
                    'referral_id' => $referralId
                ]
            );
        } catch (Exception $e) {
            error_log("Non-fatal: Referral claim notification failed: " . $e->getMessage());
        }

        http_response_code(200);
        echo json_encode([
            'success' => true,
            'message' => 'Reward claimed successfully.',
            'reward_amount' => $rewardAmount
        ]);

    } catch(Exception $e) {
        $db->rollBack();
        throw $e;
    }

} catch(PDOException $e) {
    http_response_code(500);
    echo json_encode(array("message" => "Database error: " . $e->getMessage()));
} catch(Exception $e) {
    http_response_code(500);
    echo json_encode(array("message" => "Error: " . $e->getMessage()));
}
?>
