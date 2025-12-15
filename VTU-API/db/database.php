<?php
class Database {
    private $host;
    private $db_name;
    private $username;
    private $password;
    private $pdo;

    public function __construct() {
        $this->host = "localhost";
        $this->db_name = "entafhdn_mkdata";
        $this->username = "entafhdn_mkdata";
        $this->password = "entafhdn_mkdata";
        $this->connect(); // Establish connection when object is created
    }

    private function connect() {
        try {
            $this->pdo = new PDO(
                "mysql:host=" . $this->host . ";dbname=" . $this->db_name,
                $this->username,
                $this->password,
                array(
                    PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION,
                    PDO::ATTR_EMULATE_PREPARES => false,
                    PDO::ATTR_AUTOCOMMIT => true
                )
            );
        } catch(PDOException $e) {
            throw new Exception("Connection failed: " . $e->getMessage());
        }
    }

    public function beginTransaction() {
        if (!$this->pdo) {
            $this->connect();
        }
        return $this->pdo->beginTransaction();
    }

    public function commit() {
        if (!$this->pdo) {
            throw new Exception("No active connection");
        }
        return $this->pdo->commit();
    }

    public function rollBack() {
        if (!$this->pdo) {
            throw new Exception("No active connection");
        }
        return $this->pdo->rollBack();
    }

    public function lastInsertId() {
        if (!$this->pdo) {
            throw new Exception("No active connection");
        }
        return $this->pdo->lastInsertId();
    }

    public function inTransaction() {
        if (!$this->pdo) {
            return false;
        }
        return $this->pdo->inTransaction();
    }

    public function query($query, $params = [], $fetchResults = true) {
        if (!$this->pdo) {
            $this->connect();
        }
        
        try {
            $stmt = $this->pdo->prepare($query);
            $stmt->execute($params);
            
            // For SELECT queries, return the results
            if ($fetchResults && stripos(trim($query), 'SELECT') === 0) {
                return $stmt->fetchAll(PDO::FETCH_ASSOC);
            }

            // For INSERT, UPDATE, DELETE queries, return number of affected rows.
            // This provides better visibility to callers (0 means nothing changed).
            $affected = $stmt->rowCount();
            // If nothing was affected, log extended error info to aid debugging
            if ($affected === 0) {
                $err = $stmt->errorInfo();
                error_log("Database query affected 0 rows. SQL: " . $query . " Params: " . json_encode($params) . " SQLSTATE: " . ($err[0] ?? '') . " ErrorCode: " . ($err[1] ?? '') . " Message: " . ($err[2] ?? ''));
            } else {
                error_log("Database query affected rows: " . $affected . ". SQL: " . $query . " Params: " . json_encode($params));
            }

            return $affected;
        } catch(PDOException $e) {
            error_log("Database Error in query: " . $query . " with params: " . json_encode($params));
            error_log("Error message: " . $e->getMessage());
            throw new Exception("Database Error: " . $e->getMessage());
        }
    }

    public function getConnection() {
        if (!$this->pdo) {
            $this->connect();
        }
        return $this->pdo;
    }

    public function execute($query, $params = []) {
        if (!$this->pdo) {
            $this->connect();
        }

        try {
            $stmt = $this->pdo->prepare($query);
            $result = $stmt->execute($params);
            $affected = $stmt->rowCount();
            
            error_log("Database execute affected rows: " . $affected . ". SQL: " . $query . " Params: " . json_encode($params));
            
            return $affected;
        } catch(PDOException $e) {
            error_log("Database Error in execute: " . $query . " with params: " . json_encode($params));
            error_log("Error message: " . $e->getMessage());
            throw new Exception("Database Error: " . $e->getMessage());
        }
    }
}
?>
