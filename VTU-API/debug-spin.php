<?php
/**
 * Spin & Win Debug Script
 * 
 * This script helps diagnose issues with the Spin & Win feature
 * 
 * To run this script, visit:
 * https://api.mkdata.com.ng/debug-spin.php
 */

error_reporting(E_ALL);
ini_set('display_errors', 1);
ini_set('log_errors', 1);

// Include database class
require_once __DIR__ . '/db/database.php';

header('Content-Type: application/json');

$debug = [
    'timestamp' => date('Y-m-d H:i:s'),
    'tables' => [],
    'data' => [],
    'errors' => []
];

try {
    $db = new Database();
    $connection = $db->getConnection();

    // Check if spin_rewards table exists
    $checkTableQuery = "SELECT COUNT(*) FROM information_schema.TABLES WHERE TABLE_SCHEMA = 'entafhdn_mkdata' AND TABLE_NAME = 'spin_rewards'";
    $stmt = $connection->prepare($checkTableQuery);
    $stmt->execute();
    $tableExists = $stmt->fetchColumn();
    $debug['tables']['spin_rewards'] = $tableExists ? 'EXISTS' : 'MISSING';

    if ($tableExists) {
        // Check record count
        $countQuery = "SELECT COUNT(*) as total, SUM(CASE WHEN active = 1 THEN 1 ELSE 0 END) as active FROM spin_rewards";
        $stmt = $connection->prepare($countQuery);
        $stmt->execute();
        $counts = $stmt->fetch(PDO::FETCH_ASSOC);
        $debug['data']['record_count'] = $counts['total'] ?? 0;
        $debug['data']['active_count'] = $counts['active'] ?? 0;

        // Get all rewards
        $rewardsQuery = "SELECT id, code, name, type, amount, unit, weight, active FROM spin_rewards ORDER BY id";
        $stmt = $connection->prepare($rewardsQuery);
        $stmt->execute();
        $rewards = $stmt->fetchAll(PDO::FETCH_ASSOC);
        $debug['data']['rewards'] = $rewards;
    }

    // Check if spin_wins table exists
    $checkWinsQuery = "SELECT COUNT(*) FROM information_schema.TABLES WHERE TABLE_SCHEMA = 'entafhdn_mkdata' AND TABLE_NAME = 'spin_wins'";
    $stmt = $connection->prepare($checkWinsQuery);
    $stmt->execute();
    $winsExists = $stmt->fetchColumn();
    $debug['tables']['spin_wins'] = $winsExists ? 'EXISTS' : 'MISSING';

    if ($winsExists) {
        // Check spin_wins record count
        $winsCountQuery = "SELECT COUNT(*) as total FROM spin_wins";
        $stmt = $connection->prepare($winsCountQuery);
        $stmt->execute();
        $winsCounts = $stmt->fetch(PDO::FETCH_ASSOC);
        $debug['data']['spin_wins_count'] = $winsCounts['total'] ?? 0;
    }

    $debug['status'] = 'success';
    $debug['message'] = 'Debug information retrieved successfully';

} catch (Exception $e) {
    $debug['status'] = 'error';
    $debug['message'] = $e->getMessage();
    $debug['errors'][] = $e->getMessage();
    http_response_code(500);
}

echo json_encode($debug, JSON_PRETTY_PRINT | JSON_UNESCAPED_SLASHES);
