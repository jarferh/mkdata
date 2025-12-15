<?php
header("Access-Control-Allow-Origin: *");
header("Content-Type: application/json; charset=UTF-8");
header("Access-Control-Allow-Methods: GET, POST, OPTIONS");
header("Access-Control-Max-Age: 3600");
header("Access-Control-Allow-Headers: Content-Type, Access-Control-Allow-Headers, Authorization, X-Requested-With");

if ($_SERVER['REQUEST_METHOD'] == 'OPTIONS') {
    http_response_code(200);
    exit();
}

include_once '../config/database.php';

$database = new \Binali\Config\Database();
$db = $database->getConnection();

// Get user ID from authorization header or request body
$userId = null;
$authHeader = isset($_SERVER['HTTP_AUTHORIZATION']) ? $_SERVER['HTTP_AUTHORIZATION'] : '';

// For now, accept user_id from POST data (in production, use JWT tokens)
$data = json_decode(file_get_contents("php://input"));
if(!empty($data->user_id)) {
    $userId = $data->user_id;
}

if(empty($userId)) {
    http_response_code(400);
    echo json_encode(array("message" => "User ID is required."));
    exit();
}

try {
    // Get referral stats
    $statsStmt = $db->prepare('
        SELECT 
            COUNT(*) as total_referrals,
            SUM(CASE WHEN reward_claimed = 1 THEN 1 ELSE 0 END) as claimed_rewards,
            SUM(CASE WHEN reward_claimed = 0 THEN 1 ELSE 0 END) as pending_rewards,
            SUM(CASE WHEN reward_claimed = 1 THEN reward_amount ELSE 0 END) as total_earned
        FROM referrals 
        WHERE referrer_id = :user_id
    ');
    $statsStmt->bindParam(':user_id', $userId);
    $statsStmt->execute();
    $stats = $statsStmt->fetch(PDO::FETCH_ASSOC);

    // Get detailed referrals list
    $refStmt = $db->prepare('
        SELECT 
            r.id,
            r.referee_id,
            r.reward_amount,
            r.reward_claimed,
            r.created_at,
            s.sPhone,
            s.sFname,
            s.sLname,
            s.sEmail,
            s.sRegDate
        FROM referrals r
        LEFT JOIN subscribers s ON r.referee_id = s.sId
        WHERE r.referrer_id = :user_id
        ORDER BY r.created_at DESC
    ');
    $refStmt->bindParam(':user_id', $userId);
    $refStmt->execute();
    
    $referrals = [];
    while($row = $refStmt->fetch(PDO::FETCH_ASSOC)) {
        $referrals[] = [
            'id' => $row['id'],
            'phone' => $row['sPhone'] ?? 'N/A',
            'name' => trim(($row['sFname'] ?? '') . ' ' . ($row['sLname'] ?? '')),
            'email' => $row['sEmail'] ?? 'N/A',
            'reward_amount' => floatval($row['reward_amount']),
            'reward_claimed' => boolval($row['reward_claimed']),
            'claimed_date' => $row['created_at'],
            'referred_date' => $row['created_at']
        ];
    }

    http_response_code(200);
    echo json_encode([
        'success' => true,
        'stats' => [
            'total_referrals' => intval($stats['total_referrals'] ?? 0),
            'claimed_rewards' => intval($stats['claimed_rewards'] ?? 0),
            'pending_rewards' => intval($stats['pending_rewards'] ?? 0),
            'total_earned' => floatval($stats['total_earned'] ?? 0)
        ],
        'referrals' => $referrals
    ]);

} catch(PDOException $e) {
    http_response_code(500);
    echo json_encode(array("message" => "Database error: " . $e->getMessage()));
}
?>
