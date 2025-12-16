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
            $dsn = "mysql:host=" . $this->host . ";dbname=" . $this->db_name . ";charset=utf8mb4";
            $options = [
                PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION,
                PDO::ATTR_EMULATE_PREPARES => false,
                PDO::ATTR_AUTOCOMMIT => true,
                PDO::ATTR_DEFAULT_FETCH_MODE => PDO::FETCH_ASSOC,
            ];

            // If PDO MySQL init command constant exists, set NAMES to utf8mb4 with a unicode collation
            if (defined('PDO::MYSQL_ATTR_INIT_COMMAND')) {
                $options[PDO::MYSQL_ATTR_INIT_COMMAND] = "SET NAMES utf8mb4 COLLATE utf8mb4_unicode_ci";
            }

            $this->pdo = new PDO($dsn, $this->username, $this->password, $options);
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
            $affected = $stmt->rowCount();
            if ($affected === 0) {
                $err = $stmt->errorInfo();
                error_log("Database query affected 0 rows. SQL: " . $query . " Params: " . json_encode($params) . " SQLSTATE: " . ($err[0] ?? '') . " ErrorCode: " . ($err[1] ?? '') . " Message: " . ($err[2] ?? ''));
            } else {
                error_log("Database query affected rows: " . $affected . ". SQL: " . $query . " Params: " . json_encode($params));
            }

            return $affected;
        } catch(PDOException $e) {
            // If this looks like a collation/charset conversion error, attempt to sanitize parameters and retry once.
            $msg = $e->getMessage();
            error_log("Database Error in query: " . $query . " with params: " . json_encode($params));
            error_log("Error message: " . $msg);

            if (stripos($msg, 'Conversion from collation') !== false || stripos($msg, 'cannot be converted') !== false || strpos($msg, '3988') !== false) {
                try {
                    $sanitized = $this->sanitizeParamsForLatin1($params);
                    $stmt = $this->pdo->prepare($query);
                    $stmt->execute($sanitized);

                    if ($fetchResults && stripos(trim($query), 'SELECT') === 0) {
                        return $stmt->fetchAll(PDO::FETCH_ASSOC);
                    }
                    $affected = $stmt->rowCount();
                    error_log("Database query succeeded after sanitizing params. Rows: " . $affected . ". SQL: " . $query . " Params: " . json_encode($sanitized));
                    return $affected;
                } catch (PDOException $e2) {
                    error_log("Retry after sanitize failed: " . $e2->getMessage());
                    throw new Exception("Database Error: " . $e2->getMessage());
                }
            }

            throw new Exception("Database Error: " . $msg);
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

    /**
     * Attempt to convert string parameters to a Latin-1 compatible representation.
     * First tries transliteration via iconv to ISO-8859-1, then falls back to removing
     * non-ASCII characters if iconv isn't available or fails.
     */
    private function sanitizeParamsForLatin1($params) {
        $out = [];
        foreach ($params as $k => $v) {
            if (is_string($v)) {
                // Try transliteration to ISO-8859-1
                $converted = false;
                if (function_exists('iconv')) {
                    $converted = @iconv('UTF-8', 'ISO-8859-1//TRANSLIT', $v);
                }
                if ($converted === false || $converted === null) {
                    // Fallback: strip non-ASCII characters
                    $converted = preg_replace('/[^\x00-\x7F]/', '', $v);
                }
                $out[$k] = $converted;
            } else {
                $out[$k] = $v;
            }
        }
        return $out;
    }
}
?>
