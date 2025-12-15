<?php
/**
 * Spin & Win Feature Setup Script
 * 
 * This script sets up the necessary tables for the Spin & Win feature:
 * - Creates spin_rewards table if it doesn't exist
 * - Creates spin_wins table if it doesn't exist
 * - Inserts sample rewards data if the table is empty
 * 
 * To run this script, use:
 * curl https://api.mkdata.com.ng/setup-spin.php
 * 
 * OR navigate to it in your browser:
 * https://api.mkdata.com.ng/setup-spin.php
 */

error_reporting(E_ALL);
ini_set('display_errors', 0);
ini_set('log_errors', 1);

// Include database class
require_once __DIR__ . '/db/database.php';

header('Content-Type: application/json');

$response = [
    'status' => 'success',
    'message' => 'Spin & Win tables setup completed',
    'data' => []
];

try {
    $db = new Database();

    // Create spin_rewards table
    $createRewardsTable = "
    CREATE TABLE IF NOT EXISTS `spin_rewards` (
      `id` int(10) UNSIGNED NOT NULL AUTO_INCREMENT,
      `code` varchar(64) NOT NULL UNIQUE,
      `name` varchar(128) NOT NULL,
      `type` enum('airtime','data','tryagain') NOT NULL DEFAULT 'airtime',
      `amount` decimal(12,2) DEFAULT NULL,
      `unit` varchar(16) DEFAULT NULL,
      `plan_id` varchar(50) DEFAULT NULL,
      `weight` decimal(5,2) NOT NULL DEFAULT 0.00,
      `active` tinyint(1) NOT NULL DEFAULT 1,
      `created_at` datetime NOT NULL DEFAULT current_timestamp(),
      `updated_at` datetime NOT NULL DEFAULT current_timestamp() ON UPDATE current_timestamp(),
      PRIMARY KEY (`id`),
      UNIQUE KEY `uq_spin_rewards_code` (`code`)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
    ";

    // Create spin_wins table
    $createWinsTable = "
    CREATE TABLE IF NOT EXISTS `spin_wins` (
      `id` bigint(20) UNSIGNED NOT NULL AUTO_INCREMENT,
      `user_id` int(10) UNSIGNED NOT NULL,
      `reward_id` int(10) UNSIGNED DEFAULT NULL,
      `reward_type` enum('airtime','data','tryagain') NOT NULL,
      `amount` decimal(12,2) DEFAULT NULL,
      `unit` varchar(16) DEFAULT NULL,
      `plan_id` varchar(50) DEFAULT NULL,
      `status` enum('pending','delivered','claimed') NOT NULL DEFAULT 'pending',
      `meta` longtext CHARACTER SET utf8mb4 COLLATE utf8mb4_bin DEFAULT NULL,
      `spin_at` datetime NOT NULL DEFAULT current_timestamp(),
      `delivered_at` datetime DEFAULT NULL,
      PRIMARY KEY (`id`),
      KEY `idx_user_spin_at` (`user_id`,`spin_at`),
      KEY `idx_reward_id` (`reward_id`),
      FOREIGN KEY (`reward_id`) REFERENCES `spin_rewards` (`id`) ON DELETE SET NULL
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
    ";

    // Execute table creation (using PDO directly to avoid routing through query method)
    $connection = $db->getConnection();
    
    // Create rewards table
    $connection->exec($createRewardsTable);
    $response['data']['rewards_table'] = 'Created/Verified';

    // Create wins table
    $connection->exec($createWinsTable);
    $response['data']['wins_table'] = 'Created/Verified';

    // Check if spin_rewards table is empty
    $checkQuery = "SELECT COUNT(*) as count FROM spin_rewards";
    $stmt = $connection->prepare($checkQuery);
    $stmt->execute();
    $result = $stmt->fetch(PDO::FETCH_ASSOC);
    
    if ($result['count'] == 0) {
        // Insert sample rewards
        $insertQuery = "
        INSERT INTO `spin_rewards` 
        (`code`, `name`, `type`, `amount`, `unit`, `weight`, `active`) 
        VALUES
        ('NGN_500', '₦500 Airtime', 'airtime', 500.00, 'NGN', 0.50, 1),
        ('DATA_1GB', '1GB Data', 'data', 1.00, 'GB', 0.30, 1),
        ('NGN_1000', '₦1000 Airtime', 'airtime', 1000.00, 'NGN', 0.20, 1),
        ('NGN_200', '₦200 Airtime', 'airtime', 200.00, 'NGN', 98.00, 1),
        ('DATA_2GB', '2GB Data', 'data', 2.00, 'GB', 0.50, 1),
        ('NGN_750', '₦750 Airtime', 'airtime', 750.00, 'NGN', 0.50, 1),
        ('TRY_AGAIN', 'Try Again', 'tryagain', NULL, NULL, 1.00, 1)
        ";
        
        $connection->exec($insertQuery);
        $response['data']['sample_rewards'] = 'Inserted (7 rewards)';
    } else {
        $response['data']['sample_rewards'] = 'Already exists (' . $result['count'] . ' rewards)';
    }

    error_log("Spin & Win setup completed successfully");

} catch (Exception $e) {
    error_log("Error setting up Spin & Win tables: " . $e->getMessage());
    http_response_code(500);
    $response['status'] = 'error';
    $response['message'] = 'Failed to setup tables: ' . $e->getMessage();
}

echo json_encode($response, JSON_PRETTY_PRINT | JSON_UNESCAPED_SLASHES);
