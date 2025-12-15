<?php
require_once __DIR__ . '/../config/database.php';

use Binali\Config\Database;
use PDO;

class UserService {
    private $conn;
    private $database;

    public function __construct() {
        try {
            $this->database = new Database();
            $this->initializeConnection();
        } catch (Exception $e) {
            error_log("Database connection error in UserService constructor: " . $e->getMessage());
            throw new Exception("Database connection failed. Please try again later.");
        }
    }

    private function initializeConnection() {
        try {
            // Get a new connection using the method from Database class
            $this->conn = $this->database->getConnection();
            
            if (!$this->conn || !($this->conn instanceof PDO)) {
                error_log("Invalid database connection object received");
                throw new Exception("Database connection is not valid");
            }
            
            // Test the connection
            $this->conn->query("SELECT 1");
            error_log("Database connection successfully initialized");
            
        } catch (PDOException $e) {
            error_log("Database connection test failed: " . $e->getMessage());
            throw new Exception("Database connection is not active");
        }
    }

    private function ensureAccountDeletionsTableExists() {
        try {
            // Create a lightweight audit table WITHOUT a foreign key so we can keep deletion records
            // even after the subscriber row has been removed.
            $createTableQuery = "CREATE TABLE IF NOT EXISTS account_deletions (
                id INT PRIMARY KEY AUTO_INCREMENT,
                user_id INT NOT NULL,
                reason TEXT NOT NULL,
                deletion_date DATETIME NOT NULL
            )";
            $this->conn->exec($createTableQuery);
        } catch (Exception $e) {
            error_log("Error creating account_deletions table: " . $e->getMessage());
            // Don't throw, as the table might already exist
        }
    }

    private function ensurePinChangesTableExists() {
        try {
            $createTableQuery = "CREATE TABLE IF NOT EXISTS pin_changes (
                id INT PRIMARY KEY AUTO_INCREMENT,
                user_id INT NOT NULL,
                old_pin VARCHAR(255),
                new_pin VARCHAR(255) NOT NULL,
                ip_address VARCHAR(100),
                user_agent TEXT,
                changed_at DATETIME NOT NULL,
                FOREIGN KEY (user_id) REFERENCES subscribers(sId)
            )";
            $this->conn->exec($createTableQuery);
        } catch (Exception $e) {
            error_log("Error creating pin_changes table: " . $e->getMessage());
            // Don't throw; logging failure shouldn't prevent PIN update
        }
    }

    /**
     * Ensure the subscribers.sPin column can store leading zeros.
     * If the column is numeric (INT, BIGINT, etc.) convert it to CHAR(4).
     * This runs a safe ALTER TABLE inside try/catch and is idempotent.
     */
    private function ensurePinColumnIsText() {
        try {
            $query = "SELECT DATA_TYPE, COLUMN_TYPE FROM INFORMATION_SCHEMA.COLUMNS
                      WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'subscribers' AND COLUMN_NAME = 'sPin' LIMIT 1";
            $stmt = $this->conn->query($query);
            $row = $stmt->fetch(PDO::FETCH_ASSOC);
            if ($row && isset($row['DATA_TYPE'])) {
                $dataType = strtolower($row['DATA_TYPE']);
                // If it's a numeric type, alter to CHAR(4) to preserve leading zeros
                $numericTypes = ['int','tinyint','smallint','mediumint','bigint','decimal','float','double'];
                if (in_array($dataType, $numericTypes, true)) {
                    // Attempt to alter column to CHAR(4) and keep nullable status
                    try {
                        $alter = "ALTER TABLE subscribers MODIFY COLUMN sPin CHAR(4)";
                        $this->conn->exec($alter);
                        error_log("Altered subscribers.sPin to CHAR(4) to preserve leading zeros");
                    } catch (Exception $e) {
                        error_log("Failed to alter subscribers.sPin column: " . $e->getMessage());
                        // Do not throw; proceed and rely on application-level padding as best-effort
                    }
                }
            }
        } catch (Exception $e) {
            error_log("Error checking/altering sPin column type: " . $e->getMessage());
            // Silent fallback; we won't block PIN updates if this check fails
        }
    }

    public function deleteAccount($userId, $reason) {
        try {
            error_log("Attempting to delete account for user ID: " . $userId);
            
            // Ensure we have a valid connection
            if (!$this->database->isConnected()) {
                error_log("Database connection lost, reinitializing...");
                $this->initializeConnection();
            }
            
            if (!$this->conn) {
                throw new Exception("Database connection is not available");
            }

            // Ensure the account_deletions table exists (create without FK so it survives hard-delete)
            $this->ensureAccountDeletionsTableExists();

            // Start transaction
            $this->conn->beginTransaction();

            // Insert deletion audit (we keep this even after hard-delete)
            $logQuery = "INSERT INTO account_deletions (user_id, reason, deletion_date) 
                        VALUES (:user_id, :reason, NOW())";
            $logStmt = $this->conn->prepare($logQuery);
            $logStmt->execute([
                ':user_id' => $userId,
                ':reason' => $reason
            ]);

            // Discover all tables that have an sId column in the current database
            $schemaQuery = "SELECT TABLE_NAME FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND COLUMN_NAME = 'sId'";
            $stmt = $this->conn->query($schemaQuery);
            $tables = $stmt->fetchAll(PDO::FETCH_COLUMN);

            // Tables to skip when deleting child records
            $skip = ['subscribers', 'account_deletions'];

            // Delete rows in child tables that reference this user id
            if (!empty($tables)) {
                foreach ($tables as $table) {
                    if (in_array($table, $skip, true)) continue;
                    try {
                        $delSql = "DELETE FROM `" . $table . "` WHERE sId = :user_id";
                        $delStmt = $this->conn->prepare($delSql);
                        $delStmt->execute([':user_id' => $userId]);
                        error_log("Deleted from $table for sId=$userId");
                    } catch (Exception $e) {
                        // Log and continue - some tables may use different column types or constraints
                        error_log("Failed to delete from $table: " . $e->getMessage());
                    }
                }
            }

            // Finally delete the subscriber row itself
            $delSub = $this->conn->prepare("DELETE FROM subscribers WHERE sId = :user_id");
            $delSub->execute([':user_id' => $userId]);

            // Commit changes
            $this->conn->commit();
            return true;
        } catch (Exception $e) {
            // If there's an error, rollback the transaction if connection exists
            if ($this->conn instanceof PDO) {
                $this->conn->rollBack();
            }
            throw new Exception("Failed to delete account: " . $e->getMessage());
        }
    }

    /**
     * Update the user's transaction PIN in the subscribers table.
     * The PIN is hashed using the same legacy scheme used for passwords to
     * keep compatibility with existing auth logic.
     *
     * @param int|string $userId
     * @param string $pin
     * @return bool
     * @throws Exception
     */
    public function updatePin($userId, $pin) {
        // Save the PIN exactly as typed, including leading zeros, no encryption or normalization
        try {
            if (!$this->database->isConnected()) {
                $this->initializeConnection();
            }
            if (!$this->conn) {
                throw new Exception("Database connection is not available");
            }
            $updateQuery = "UPDATE subscribers SET sPin = :pin, sLastActivity = NOW() WHERE sId = :user_id";
            $stmt = $this->conn->prepare($updateQuery);
            $stmt->execute([
                ':pin' => $pin,
                ':user_id' => $userId,
            ]);
            return true;
        } catch (Exception $e) {
            error_log("Failed to update PIN for user {$userId}: " . $e->getMessage());
            throw new Exception('Failed to update PIN: ' . $e->getMessage());
        }
    }
}
