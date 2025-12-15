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

if(empty($data->user_id) || empty($data->amount)) {
    http_response_code(400);
    echo json_encode(array("message" => "User ID and amount are required."));
    exit();
}

try {
    $userId = $data->user_id;
    $withdrawAmount = floatval($data->amount);

    if($withdrawAmount <= 0) {
        http_response_code(400);
        echo json_encode(array("message" => "Amount must be greater than zero."));
        exit();
    }

    // Check user exists and has sufficient referral balance
    $checkStmt = $db->prepare('
        SELECT sId, sRefWallet, sWallet FROM subscribers 
        WHERE sId = :user_id
    ');
    $checkStmt->bindParam(':user_id', $userId);
    $checkStmt->execute();

    if($checkStmt->rowCount() == 0) {
        http_response_code(404);
        echo json_encode(array("message" => "User not found."));
        exit();
    }

    $user = $checkStmt->fetch(PDO::FETCH_ASSOC);
    $refWallet = floatval($user['sRefWallet'] ?? 0);
    $mainWallet = floatval($user['sWallet'] ?? 0);

    if($refWallet < $withdrawAmount) {
        http_response_code(400);
        echo json_encode(array(
            "message" => "Insufficient referral balance.",
            "available" => $refWallet,
            "requested" => $withdrawAmount
        ));
        exit();
    }

    // Start transaction
    $db->beginTransaction();

    try {
        // Deduct from referral wallet (sRefWallet)
        $deductStmt = $db->prepare('
            UPDATE subscribers 
            SET sRefWallet = sRefWallet - :amount 
            WHERE sId = :user_id
        ');
        $deductStmt->bindParam(':amount', $withdrawAmount);
        $deductStmt->bindParam(':user_id', $userId);
        $deductStmt->execute();

        // Add to main wallet (sWallet)
        $addStmt = $db->prepare('
            UPDATE subscribers 
            SET sWallet = sWallet + :amount 
            WHERE sId = :user_id
        ');
        $addStmt->bindParam(':amount', $withdrawAmount);
        $addStmt->bindParam(':user_id', $userId);
        $addStmt->execute();

        // Commit transaction
        $db->commit();

        // Fetch updated balance
        $updatedStmt = $db->prepare('
            SELECT sRefWallet, sWallet FROM subscribers 
            WHERE sId = :user_id
        ');
        $updatedStmt->bindParam(':user_id', $userId);
        $updatedStmt->execute();
        $updatedUser = $updatedStmt->fetch(PDO::FETCH_ASSOC);

        // Send notification
        require_once __DIR__ . '/notifications/send.php';
        try {
            sendTransactionNotification(
                $userId,
                'referral_withdrawal',
                [
                    'amount' => $withdrawAmount,
                    'new_wallet_balance' => floatval($updatedUser['sWallet'] ?? 0)
                ]
            );
        } catch (Exception $e) {
            error_log("Non-fatal: Referral withdrawal notification failed: " . $e->getMessage());
        }

        http_response_code(200);
        echo json_encode([
            'success' => true,
            'message' => 'Withdrawal successful.',
            'withdrawn_amount' => $withdrawAmount,
            'new_ref_wallet' => floatval($updatedUser['sRefWallet'] ?? 0),
            'new_main_wallet' => floatval($updatedUser['sWallet'] ?? 0)
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
