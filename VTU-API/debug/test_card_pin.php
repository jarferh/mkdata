<?php
error_reporting(E_ALL);
ini_set('display_errors', 1);

require_once __DIR__ . '/../config/database.php';

use Binali\Config\Database;

try {
    $db = new Database();
    echo "✓ Database connected\n";
    
    // Test 1: Check users table structure
    echo "\n--- Testing Users Table ---\n";
    $userResult = $db->query("SELECT * FROM users LIMIT 1");
    if ($userResult) {
        echo "✓ Users table exists\n";
        echo "Columns: " . json_encode(array_keys($userResult[0])) . "\n";
        echo "Sample user: " . json_encode($userResult[0]) . "\n";
    } else {
        echo "✗ Users table empty or error\n";
    }
    
    // Test 2: Check transactions table structure
    echo "\n--- Testing Transactions Table ---\n";
    $txResult = $db->query("SELECT * FROM transactions LIMIT 1");
    if ($txResult) {
        echo "✓ Transactions table exists\n";
        echo "Columns: " . json_encode(array_keys($txResult[0])) . "\n";
    } else {
        echo "✓ Transactions table exists but is empty\n";
        // Try to get column info
        $cols = $db->query("SHOW COLUMNS FROM transactions");
        echo "Columns: " . json_encode(array_map(fn($c) => $c['Field'], $cols)) . "\n";
    }
    
    // Test 3: Try a simple balance lookup
    echo "\n--- Testing Balance Lookup for User 1 ---\n";
    $balanceResult = $db->query("SELECT sWallet FROM users WHERE sId = ?", [1]);
    if ($balanceResult) {
        echo "✓ Balance lookup succeeded\n";
        echo "Result: " . json_encode($balanceResult[0]) . "\n";
    } else {
        echo "✗ No user found with ID 1\n";
    }
    
} catch (Exception $e) {
    echo "✗ Error: " . $e->getMessage() . "\n";
    echo "Trace: " . $e->getTraceAsString() . "\n";
}
?>
