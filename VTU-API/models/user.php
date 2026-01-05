<?php
namespace Binali\Models;

use Exception;

/**
 * User Class
 * @package Binali\Models
 */
class User
{
    private $conn;
    private $table_name = "subscribers";
    
    private function getConnection() {
        if (!$this->conn) {
            throw new Exception("Database connection not initialized");
        }
        return $this->conn instanceof \PDO ? $this->conn : 
               (method_exists($this->conn, 'getPDO') ? $this->conn->getPDO() : 
               (method_exists($this->conn, 'getConnection') ? $this->conn->getConnection() : 
               $this->conn));
    }
    
    public $sId;
    public $sApiKey;
    public $sFname;
    public $sLname;
    public $sEmail;
    public $sPhone;
    public $sPass;
    public $sReferal;
    public $sRegStatus;
    public $sRegDate;
    public $sWallet;
    public $reset_token;
    public $reset_token_expiry;
    
    public function __construct($db) {
        if ($db instanceof \PDO) {
            $this->conn = $db;
        } elseif (method_exists($db, 'getPDO')) {
            $this->conn = $db->getPDO();
        } elseif (method_exists($db, 'getConnection')) {
            $this->conn = $db->getConnection();
        } else {
            $this->conn = $db;
        }
    }

    /**
     * Compute the website-compatible password hash.
     * This matches the legacy logic used by the website: substr(sha1(md5($password)), 3, 10)
     */
    private function computeWebsiteHash(string $password): string {
        return substr(sha1(md5($password)), 3, 10);
    }
    
    private function callAspfiyApi($endpoint, $payload, $aspfiyApiKey) {
        $create_url = 'https://api-v1.aspfiy.com/' . $endpoint . '/';
        
        error_log("Aspfiy API Payload for $endpoint: " . json_encode($payload));
        
        $curl = curl_init();
        curl_setopt_array($curl, array(
            CURLOPT_URL => $create_url,
            CURLOPT_RETURNTRANSFER => true,
            CURLOPT_ENCODING => "",
            CURLOPT_MAXREDIRS => 10,
            CURLOPT_TIMEOUT => 90,
            CURLOPT_FOLLOWLOCATION => true,
            CURLOPT_HTTP_VERSION => CURL_HTTP_VERSION_1_1,
            CURLOPT_CUSTOMREQUEST => "POST",
            CURLOPT_POSTFIELDS => json_encode($payload),
            CURLOPT_HTTPHEADER => array(
                "Content-Type: application/json",
                "Authorization: Bearer " . $aspfiyApiKey
            ),
        ));
        
        $response = curl_exec($curl);
        $curlError = curl_error($curl);
        $httpCode = curl_getinfo($curl, CURLINFO_HTTP_CODE);
        curl_close($curl);
        
        error_log("Aspfiy API Response Code ($endpoint): " . $httpCode);
        error_log("Aspfiy API Response ($endpoint): " . $response);
        
        if ($curlError) {
            error_log("Curl Error ($endpoint): " . $curlError);
            return null;
        }
        
        $value = json_decode($response, true);
        if (json_last_error() !== JSON_ERROR_NONE) {
            error_log("JSON decode error ($endpoint): " . json_last_error_msg());
            return null;
        }
        
        return $value;
    }
    
    private function extractAccountNumber($value) {
        $accountNumber = null;
        
        // Aspfiy response structure: data.account.account_number
        if (isset($value['data']) && is_array($value['data'])) {
            if (isset($value['data']['account']) && is_array($value['data']['account'])) {
                if (isset($value['data']['account']['account_number'])) {
                    $accountNumber = $value['data']['account']['account_number'];
                }
            }
        }
        
        // Fallback: try other possible locations
        if (empty($accountNumber)) {
            $d = $value['data'] ?? $value;
            if (is_array($d)) {
                if (isset($d['account_number'])) {
                    $accountNumber = $d['account_number'];
                } elseif (isset($d['accountNumber'])) {
                    $accountNumber = $d['accountNumber'];
                } elseif (isset($d['account'])) {
                    $accountNumber = $d['account'];
                }
            }
        }
        
        return (!empty($accountNumber) && !is_array($accountNumber)) ? $accountNumber : null;
    }
    
    public function createVirtualAccount($id, $fname, $lname, $phone, $email) {
        try {
            if (!$this->conn) {
                error_log("Database connection not initialized");
                return false;
            }
            
            // Fetch Aspfiy API credentials from apiconfigs table
            $debugQuery = "DESCRIBE apiconfigs";
            $debugStmt = $this->conn->prepare($debugQuery);
            $debugStmt->execute();
            $columns = $debugStmt->fetchAll(\PDO::FETCH_COLUMN, 0);
            error_log("Apiconfigs table columns: " . json_encode($columns));
            
            // Try to fetch API key - try multiple column name variations
            $possibleValueColumns = ['sValue', 'value', 'sVal', 'config_value', 'data'];
            $valueColumn = null;
            
            foreach ($possibleValueColumns as $col) {
                if (in_array($col, $columns)) {
                    $valueColumn = $col;
                    break;
                }
            }
            
            if (!$valueColumn) {
                error_log("Could not find value column in apiconfigs table. Available columns: " . implode(', ', $columns));
                return false;
            }
            
            error_log("Using column: " . $valueColumn . " for apiconfigs values");
            
            // Get API key
            $configQuery = "SELECT `" . $valueColumn . "` FROM apiconfigs WHERE name = :name LIMIT 1";
            $stmt = $this->conn->prepare($configQuery);
            $apiKeyName = 'asfiyApi';
            $stmt->bindParam(':name', $apiKeyName, \PDO::PARAM_STR);
            $stmt->execute();
            
            if ($stmt->rowCount() === 0) {
                error_log("Aspfiy API key not found in apiconfigs");
                return false;
            }
            
            $apiKeyRow = $stmt->fetch(\PDO::FETCH_ASSOC);
            $aspfiyApiKey = $apiKeyRow[$valueColumn];
            error_log("Retrieved API key: " . substr($aspfiyApiKey, 0, 10) . "...");
            
            // Get webhook URL
            $stmt = $this->conn->prepare($configQuery);
            $webhookName = 'asfiyWebhook';
            $stmt->bindParam(':name', $webhookName, \PDO::PARAM_STR);
            $stmt->execute();
            
            if ($stmt->rowCount() === 0) {
                error_log("Aspfiy webhook URL not found in apiconfigs");
                return false;
            }
            
            $webhookRow = $stmt->fetch(\PDO::FETCH_ASSOC);
            $aspfiyWebhook = $webhookRow[$valueColumn];
            error_log("Retrieved webhook: " . $aspfiyWebhook);
            
            // Generate unique references for both accounts
            $timestamp = time();
            $randomStr = bin2hex(random_bytes(4));
            $palmpayRef = "MK" . $id . $timestamp . $randomStr;
            $pagaRef = "MK" . $id . ($timestamp + 1) . bin2hex(random_bytes(4));
            error_log("Generated references - Palmpay: " . $palmpayRef . ", Paga: " . $pagaRef);
            
            // Create Palmpay account
            $palmpayPayload = [
                'reference' => $palmpayRef,
                'firstName' => $fname,
                'lastName' => $lname,
                'phone' => $phone,
                'email' => $email,
                'webhookUrl' => $aspfiyWebhook
            ];
            
            $palmpayResponse = $this->callAspfiyApi('reserve-palmpay', $palmpayPayload, $aspfiyApiKey);
            if (!$palmpayResponse) {
                error_log("Failed to create Palmpay account");
                return false;
            }
            
            $palmpayAccountNumber = $this->extractAccountNumber($palmpayResponse);
            if (empty($palmpayAccountNumber)) {
                error_log("Could not extract Palmpay account number");
                error_log("Full Palmpay response: " . json_encode($palmpayResponse));
                return false;
            }
            error_log("Successfully extracted Palmpay account number: " . $palmpayAccountNumber);
            
            // Create Paga account
            $pagaPayload = [
                'reference' => $pagaRef,
                'firstName' => $fname,
                'lastName' => $lname,
                'phone' => $phone,
                'email' => $email,
                'webhookUrl' => $aspfiyWebhook
            ];
            
            $pagaResponse = $this->callAspfiyApi('reserve-paga', $pagaPayload, $aspfiyApiKey);
            if (!$pagaResponse) {
                error_log("Failed to create Paga account");
                // Continue - Paga is not critical if Palmpay succeeded
            } else {
                $pagaAccountNumber = $this->extractAccountNumber($pagaResponse);
                if (empty($pagaAccountNumber)) {
                    error_log("Could not extract Paga account number");
                    error_log("Full Paga response: " . json_encode($pagaResponse));
                    // Continue - Paga is not critical
                } else {
                    error_log("Successfully extracted Paga account number: " . $pagaAccountNumber);
                }
            }
            
            // Persist both accounts to database
            // NOTE: Palmpay is saved to sPaga, Paga is saved to sAsfiyBank
            try {
                $pagaNumber = $pagaAccountNumber ?? '';
                $query = "UPDATE " . $this->table_name . " 
                         SET sPaga = :palmpay, sAsfiyBank = :paga, 
                             accountReference = :palmpayRef, sBankName = :bankName
                         WHERE sId = :id";
                $stmt = $this->conn->prepare($query);
                $bankName = 'application';
                $stmt->bindParam(':palmpay', $palmpayAccountNumber, \PDO::PARAM_STR);
                $stmt->bindParam(':paga', $pagaNumber, \PDO::PARAM_STR);
                $stmt->bindParam(':palmpayRef', $palmpayRef, \PDO::PARAM_STR);
                $stmt->bindParam(':bankName', $bankName, \PDO::PARAM_STR);
                $stmt->bindParam(':id', $id, \PDO::PARAM_INT);
                return $stmt->execute();
            } catch (\PDOException $e) {
                error_log("Database error: " . $e->getMessage());
                return false;
            }
        } catch (\Throwable $e) {
            error_log("Error in createVirtualAccount: " . $e->getMessage());
            return false;
        }
    }
    
    /**
     * Generate specific virtual accounts
     * @param int $id User ID
     * @param string $fname First name
     * @param string $lname Last name
     * @param string $phone Phone number
     * @param string $email Email address
     * @param string $type Account type: 'palmpay', 'paga', or 'all' (default: 'all')
     * @return bool
     */
    public function createSelectiveVirtualAccount($id, $fname, $lname, $phone, $email, $type = 'all') {
        try {
            if (!$this->conn) {
                error_log("Database connection not initialized");
                return false;
            }
            
            // Validate type parameter
            $validTypes = ['palmpay', 'paga', 'all'];
            if (!in_array($type, $validTypes)) {
                error_log("Invalid type parameter: $type. Must be one of: " . implode(', ', $validTypes));
                return false;
            }
            
            // Fetch Aspfiy API credentials from apiconfigs table
            $debugQuery = "DESCRIBE apiconfigs";
            $debugStmt = $this->conn->prepare($debugQuery);
            $debugStmt->execute();
            $columns = $debugStmt->fetchAll(\PDO::FETCH_COLUMN, 0);
            error_log("Apiconfigs table columns: " . json_encode($columns));
            
            // Try to fetch API key
            $possibleValueColumns = ['sValue', 'value', 'sVal', 'config_value', 'data'];
            $valueColumn = null;
            
            foreach ($possibleValueColumns as $col) {
                if (in_array($col, $columns)) {
                    $valueColumn = $col;
                    break;
                }
            }
            
            if (!$valueColumn) {
                error_log("Could not find value column in apiconfigs table. Available columns: " . implode(', ', $columns));
                return false;
            }
            
            error_log("Using column: " . $valueColumn . " for apiconfigs values");
            
            // Get API key
            $configQuery = "SELECT `" . $valueColumn . "` FROM apiconfigs WHERE name = :name LIMIT 1";
            $stmt = $this->conn->prepare($configQuery);
            $apiKeyName = 'asfiyApi';
            $stmt->bindParam(':name', $apiKeyName, \PDO::PARAM_STR);
            $stmt->execute();
            
            if ($stmt->rowCount() === 0) {
                error_log("Aspfiy API key not found in apiconfigs");
                return false;
            }
            
            $apiKeyRow = $stmt->fetch(\PDO::FETCH_ASSOC);
            $aspfiyApiKey = $apiKeyRow[$valueColumn];
            error_log("Retrieved API key: " . substr($aspfiyApiKey, 0, 10) . "...");
            
            // Get webhook URL
            $stmt = $this->conn->prepare($configQuery);
            $webhookName = 'asfiyWebhook';
            $stmt->bindParam(':name', $webhookName, \PDO::PARAM_STR);
            $stmt->execute();
            
            if ($stmt->rowCount() === 0) {
                error_log("Aspfiy webhook URL not found in apiconfigs");
                return false;
            }
            
            $webhookRow = $stmt->fetch(\PDO::FETCH_ASSOC);
            $aspfiyWebhook = $webhookRow[$valueColumn];
            error_log("Retrieved webhook: " . $aspfiyWebhook);
            
            // Generate unique references for both accounts
            $timestamp = time();
            $randomStr = bin2hex(random_bytes(4));
            $palmpayRef = "MK" . $id . $timestamp . $randomStr;
            $pagaRef = "MK" . $id . ($timestamp + 1) . bin2hex(random_bytes(4));
            error_log("Generated references - Palmpay: " . $palmpayRef . ", Paga: " . $pagaRef);
            
            $palmpayAccountNumber = null;
            $pagaAccountNumber = null;
            
            // Create Palmpay account if requested
            if ($type === 'palmpay' || $type === 'all') {
                $palmpayPayload = [
                    'reference' => $palmpayRef,
                    'firstName' => $fname,
                    'lastName' => $lname,
                    'phone' => $phone,
                    'email' => $email,
                    'webhookUrl' => $aspfiyWebhook
                ];
                
                $palmpayResponse = $this->callAspfiyApi('reserve-palmpay', $palmpayPayload, $aspfiyApiKey);
                if (!$palmpayResponse) {
                    error_log("Failed to create Palmpay account");
                    if ($type === 'palmpay') {
                        return false; // Fail only if Palmpay was specifically requested
                    }
                    // Continue if type is 'all'
                } else {
                    $palmpayAccountNumber = $this->extractAccountNumber($palmpayResponse);
                    if (empty($palmpayAccountNumber)) {
                        error_log("Could not extract Palmpay account number");
                        error_log("Full Palmpay response: " . json_encode($palmpayResponse));
                        if ($type === 'palmpay') {
                            return false;
                        }
                    } else {
                        error_log("Successfully extracted Palmpay account number: " . $palmpayAccountNumber);
                    }
                }
            }
            
            // Create Paga account if requested
            if ($type === 'paga' || $type === 'all') {
                $pagaPayload = [
                    'reference' => $pagaRef,
                    'firstName' => $fname,
                    'lastName' => $lname,
                    'phone' => $phone,
                    'email' => $email,
                    'webhookUrl' => $aspfiyWebhook
                ];
                
                $pagaResponse = $this->callAspfiyApi('reserve-paga', $pagaPayload, $aspfiyApiKey);
                if (!$pagaResponse) {
                    error_log("Failed to create Paga account");
                    if ($type === 'paga') {
                        return false; // Fail only if Paga was specifically requested
                    }
                    // Continue if type is 'all'
                } else {
                    $pagaAccountNumber = $this->extractAccountNumber($pagaResponse);
                    if (empty($pagaAccountNumber)) {
                        error_log("Could not extract Paga account number");
                        error_log("Full Paga response: " . json_encode($pagaResponse));
                        if ($type === 'paga') {
                            return false;
                        }
                    } else {
                        error_log("Successfully extracted Paga account number: " . $pagaAccountNumber);
                    }
                }
            }
            
            // Update database with generated accounts
            try {
                $updates = [];
                $params = [];
                
                if ($palmpayAccountNumber) {
                    $updates[] = "sPaga = :palmpay";
                    $params[':palmpay'] = $palmpayAccountNumber;
                }
                
                if ($pagaAccountNumber) {
                    $updates[] = "sAsfiyBank = :paga";
                    $params[':paga'] = $pagaAccountNumber;
                }
                
                if (empty($updates)) {
                    error_log("No accounts were successfully generated");
                    return false;
                }
                
                // Always set bankName and reference
                $updates[] = "sBankName = :bankName";
                $params[':bankName'] = 'application';
                
                if ($palmpayAccountNumber) {
                    $updates[] = "accountReference = :palmpayRef";
                    $params[':palmpayRef'] = $palmpayRef;
                }
                
                $params[':id'] = $id;
                
                $query = "UPDATE " . $this->table_name . " 
                         SET " . implode(', ', $updates) . "
                         WHERE sId = :id";
                
                $stmt = $this->conn->prepare($query);
                return $stmt->execute($params);
            } catch (\PDOException $e) {
                error_log("Database error: " . $e->getMessage());
                return false;
            }
        } catch (\Throwable $e) {
            error_log("Error in createSelectiveVirtualAccount: " . $e->getMessage());
            return false;
        }
    }

    /**
     * Create a new user account in the subscribers table
     * @return bool
     */
    public function create() {
        try {
            // Generate API key
            $this->sApiKey = bin2hex(random_bytes(32));

            $query = "INSERT INTO {$this->table_name} 
            (sApiKey, sFname, sLname, sEmail, sPhone, sPass, sReferal, sWallet, sRegStatus, sRegDate)
            VALUES
            (:sApiKey, :sFname, :sLname, :sEmail, :sPhone, :sPass, :sReferal, 0, 0, NOW())";

            $stmt = $this->conn->prepare($query);

            // Sanitize input
            $this->sFname = htmlspecialchars(strip_tags($this->sFname));
            $this->sLname = htmlspecialchars(strip_tags($this->sLname));
            $this->sEmail = htmlspecialchars(strip_tags($this->sEmail));
            $this->sPhone = htmlspecialchars(strip_tags($this->sPhone));
            $this->sReferal = htmlspecialchars(strip_tags($this->sReferal));

            // Hash the password using website-compatible hash
            $password_hash = $this->computeWebsiteHash($this->sPass);

            // Bind values
            $stmt->bindParam(":sApiKey", $this->sApiKey);
            $stmt->bindParam(":sFname", $this->sFname);
            $stmt->bindParam(":sLname", $this->sLname);
            $stmt->bindParam(":sEmail", $this->sEmail);
            $stmt->bindParam(":sPhone", $this->sPhone);
            $stmt->bindParam(":sPass", $password_hash);
            $stmt->bindParam(":sReferal", $this->sReferal);

            if($stmt->execute()) {
                // Get the last inserted ID
                $lastId = $this->conn->lastInsertId();
                $this->sId = $lastId;

                // Attempt to create virtual account but do not fail registration if it fails.
                try {
                    $this->createVirtualAccount(
                        $lastId,
                        $this->sFname,
                        $this->sLname,
                        $this->sPhone,
                        $this->sEmail
                    );
                } catch (\Throwable $e) {
                    // Log the error but continue; account can be generated later.
                    error_log("Non-fatal: createVirtualAccount failed for sId={$lastId}: " . $e->getMessage());
                }

                // Registration succeeded regardless of virtual account creation outcome
                return true;
            }

            return false;
        } catch (\Throwable $e) {
            error_log("Error in create: " . $e->getMessage());
            return false;
        }
    }

    public function emailExists() {
        $query = "SELECT sId, sFname, sLname, sPass, sPhone, sWallet, sEmail, sRegStatus 
                FROM " . $this->table_name . "
                WHERE sEmail = ?
                LIMIT 0,1";
    
        $stmt = $this->conn->prepare($query);
        $this->sEmail = htmlspecialchars(strip_tags($this->sEmail));
        $stmt->bindParam(1, $this->sEmail);
        $stmt->execute();
        
        $num = $stmt->rowCount();
        
        if($num > 0) {
            $row = $stmt->fetch(\PDO::FETCH_ASSOC);
            $this->sId = $row['sId'];
            $this->sFname = $row['sFname'];
            $this->sLname = $row['sLname'];
            $this->sPass = $row['sPass'];
            $this->sPhone = $row['sPhone'];
            $this->sWallet = $row['sWallet'];
            $this->sEmail = $row['sEmail'];
            $this->sRegStatus = $row['sRegStatus'];
            // Debug log
            error_log("Retrieved hash from DB: " . $row['sPass']);
            return true;
        }
        return false;
    }
    
    public function validatePassword($plainPassword) {
        // Debug log to check values
        error_log("Plain password: " . $plainPassword);
        error_log("Stored hash: " . $this->sPass);
    // Compare using website's hash function
    $computed = $this->computeWebsiteHash($plainPassword);
    error_log("Computed hash: " . $computed);
    return hash_equals($this->sPass, $computed);
    }
    
    public function update() {
        $query = "UPDATE " . $this->table_name . "
                SET
                    sPass = :sPass
                WHERE sEmail = :sEmail";
    
        $stmt = $this->conn->prepare($query);
        
        $this->sEmail = htmlspecialchars(strip_tags($this->sEmail));
    // Use website-compatible hash
    $password_hash = $this->computeWebsiteHash($this->sPass);
        
        $stmt->bindParam(':sPass', $password_hash);
        $stmt->bindParam(':sEmail', $this->sEmail);
        
        if($stmt->execute()) {
            return true;
        }
        return false;
    }

    public function updateResetToken() {
        $query = "UPDATE " . $this->table_name . "
                SET
                    reset_token = :reset_token,
                    reset_token_expiry = :reset_token_expiry
                WHERE sEmail = :sEmail";
    
        $stmt = $this->conn->prepare($query);
        
        $this->sEmail = htmlspecialchars(strip_tags($this->sEmail));
        $this->reset_token = htmlspecialchars(strip_tags($this->reset_token));
        
        $stmt->bindParam(':reset_token', $this->reset_token);
        $stmt->bindParam(':reset_token_expiry', $this->reset_token_expiry);
        $stmt->bindParam(':sEmail', $this->sEmail);
        
        if($stmt->execute()) {
            return true;
        }
        return false;
    }

    public function validateResetToken($token) {
        $query = "SELECT sId FROM " . $this->table_name . "
                WHERE reset_token = :token
                AND reset_token_expiry > NOW()
                LIMIT 0,1";
    
        $stmt = $this->conn->prepare($query);
        
        $token = htmlspecialchars(strip_tags($token));
        $stmt->bindParam(':token', $token);
        $stmt->execute();
        
        if($stmt->rowCount() > 0) {
            $row = $stmt->fetch(\PDO::FETCH_ASSOC);
            $this->sId = $row['sId'];
            return true;
        }
        return false;
    }

    public function resetPassword() {
        $query = "UPDATE " . $this->table_name . "
                SET
                    sPass = :sPass,
                    reset_token = NULL,
                    reset_token_expiry = NULL
                WHERE sId = :sId";
    
        $stmt = $this->conn->prepare($query);
        
    // Use website-compatible hash for reset as well
    $password_hash = $this->computeWebsiteHash($this->sPass);
        
        $stmt->bindParam(':sPass', $password_hash);
        $stmt->bindParam(':sId', $this->sId);
        
        try {
            if($stmt->execute()) {
                return true;
            }
            return false;
        } catch (\PDOException $e) {
            error_log("Database error: " . $e->getMessage());
            return false;
        }
    }
}
