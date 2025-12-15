<?php
namespace Binali\Config;

use PDO;
use PDOException;
use Exception;

if (!class_exists('Binali\Config\Database')) {
    class Database {    
        private string $host = "localhost";
        private string $db_name = "entafhdn_mkdata";
        private string $username = "entafhdn_mkdata";
        private string $password = "entafhdn_mkdata";
        private ?PDO $conn = null;

    public function __construct() {
        try {
            error_log("Attempting to establish database connection...");
            $dsn = "mysql:host=" . $this->host . ";dbname=" . $this->db_name;
            $this->conn = new PDO($dsn, $this->username, $this->password);
            $this->conn->setAttribute(PDO::ATTR_ERRMODE, PDO::ERRMODE_EXCEPTION);
            error_log("Database connection established successfully");
        } catch(PDOException $e) {
            error_log("Connection Error: " . $e->getMessage());
            throw new Exception("Database connection failed: " . $e->getMessage());
        }
    }

    public function query($query, $params = []) {
        try {
            $stmt = $this->conn->prepare($query);
            $stmt->execute($params);
            return $stmt->fetchAll(PDO::FETCH_ASSOC);
        } catch(PDOException $e) {
            error_log("Query Error: " . $e->getMessage());
            throw new Exception("Database query failed");
        }
    }

    public function getConnection(): PDO {
        if (!$this->conn || !($this->conn instanceof PDO)) {
            error_log("Connection is not valid, attempting to reconnect...");
            $this->__construct();
        }
        if (!$this->conn) {
            throw new Exception("Unable to establish database connection");
        }
        return $this->conn;
    }

    public function isConnected() {
        try {
            if ($this->conn instanceof PDO) {
                $this->conn->query("SELECT 1");
                return true;
            }
            return false;
        } catch (PDOException $e) {
            error_log("Connection test failed: " . $e->getMessage());
            return false;
        }
    }

    public function execute($query, $params = []) {
        try {
            $stmt = $this->conn->prepare($query);
            $result = $stmt->execute($params);
            return $result ? $stmt->rowCount() : 0;
        } catch(PDOException $e) {
            error_log("Execute Error: " . $e->getMessage());
            throw new Exception("Database execute failed: " . $e->getMessage());
        }
    }

    public function lastInsertId() {
        try {
            return $this->conn->lastInsertId();
        } catch(PDOException $e) {
            error_log("LastInsertId Error: " . $e->getMessage());
            throw new Exception("Failed to get last insert ID");
        }
    }
}
}