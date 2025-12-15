<?php
require_once __DIR__ . '/../config/database.php';
require_once __DIR__ . '/../config/config.php';
use Binali\Models;

use PDO;
use PDOException;
use Binali\Config\Database;
use Binali\Config\Config;

class ExamPinService {
    private $db;
    private $config;
    private $examApiKey;
    private $examProvider;

    public function __construct() {
        $this->db = new Database();
        $this->config = new Config($this->db);
        
        // Get API configuration
        $query = "SELECT name, value FROM apiconfigs WHERE name IN ('examApi', 'examProvider')";
        $configs = $this->db->query($query);
        foreach ($configs as $config) {
            if ($config['name'] === 'examApi') {
                $this->examApiKey = $config['value'];
            } elseif ($config['name'] === 'examProvider') {
                $this->examProvider = $config['value'];
            }
        }
        
        if (!$this->examApiKey || !$this->examProvider) {
            throw new Exception("API configuration not found");
        }
    }

    public function getExamProviders() {
        try {
            $query = "SELECT 
                        eId as id, 
                        provider as name, 
                        price, 
                        providerStatus as status 
                     FROM examid 
                     WHERE providerStatus = 'On' 
                     ORDER BY provider";
            $result = $this->db->query($query);
            
            foreach ($result as &$exam) {
                if (isset($exam['price'])) {
                    $exam['price'] = (float)$exam['price'];
                }
                if (isset($exam['id'])) {
                    $exam['id'] = (int)$exam['id'];
                }
            }
            
            if (empty($result)) {
                $result = [];
            }
            
            return [
                'status' => 'success',
                'message' => 'Exam providers fetched successfully',
                'data' => array_values($result)
            ];
        } catch (Exception $e) {
            return [
                'status' => 'error',
                'message' => "Error fetching exam providers: " . $e->getMessage(),
                'data' => []
            ];
        }
    }

    public function purchaseExamPin($examName, $quantity, $userId) {
        $transactionId = uniqid('EXM');
        $transactionStatus = 'failed';
        $errorMessage = null;
        $exam = null;
        $pins = [];

        try {
            // First validate the exam exists and is active
            if (is_numeric($examName)) {
                $query = "SELECT * FROM examid WHERE eId = ? AND providerStatus = 'On'";
            } else {
                $query = "SELECT * FROM examid WHERE UPPER(provider) = UPPER(?) AND providerStatus = 'On'";
            }
            $exam = $this->db->query($query, [$examName]);
            
            if (empty($exam)) {
                throw new Exception("Invalid or inactive exam type");
            }
            
            if ($quantity <= 0 || $quantity > 5) {
                throw new Exception("Invalid quantity. Must be between 1 and 5");
            }

            $totalAmount = $exam[0]['price'] * $quantity;
            
            $balanceQuery = "SELECT sWallet FROM subscribers WHERE sId = ?";
            $userBalance = $this->db->query($balanceQuery, [$userId]);
            
            if (empty($userBalance)) {
                throw new Exception("User not found");
            }
            
            $currentBalance = $userBalance[0]['sWallet'];
            if ($currentBalance < $totalAmount) {
                throw new Exception("Insufficient balance. Required: ₦{$totalAmount}, Available: ₦{$currentBalance}");
            }
            
            // Make API call first before deducting balance
            $curl = curl_init();
            $postData = [
                'exam_name' => strtoupper($exam[0]['provider']),
                'quantity' => $quantity,
                'api_key' => $this->examApiKey
            ];

            curl_setopt_array($curl, [
                CURLOPT_SSL_VERIFYPEER => false,
                CURLOPT_URL => $this->examProvider,
                CURLOPT_RETURNTRANSFER => true,
                CURLOPT_ENCODING => '',
                CURLOPT_MAXREDIRS => 10,
                CURLOPT_TIMEOUT => 30,
                CURLOPT_HTTP_VERSION => CURL_HTTP_VERSION_1_1,
                CURLOPT_CUSTOMREQUEST => 'POST',
                CURLOPT_POSTFIELDS => json_encode($postData),
                CURLOPT_HTTPHEADER => [
                    'Authorization: Token ' . $this->examApiKey,
                    'Content-Type: application/json'
                ],
            ]);
            
            $response = curl_exec($curl);
            $err = curl_error($curl);
            curl_close($curl);
            
            if ($err) {
                throw new Exception("API Error: " . $err);
            }

            $apiResponse = json_decode($response, true);
            
            if (!$apiResponse) {
                throw new Exception("Failed to decode API response: " . $response);
            }

            if (isset($apiResponse['error'])) {
                $error = is_array($apiResponse['error']) 
                    ? implode(', ', $apiResponse['error']) 
                    : $apiResponse['error'];
                throw new Exception($error);
            }

            if (isset($apiResponse['status']) && $apiResponse['status'] === 'error') {
                throw new Exception($apiResponse['message'] ?? 'API returned an error');
            }

            $pins = $apiResponse['pins'] ?? $apiResponse['data']['pins'] ?? null;
            if (!$pins || !is_array($pins)) {
                throw new Exception("No pins returned from API");
            }

            // Start transaction after successful API response
            $this->db->beginTransaction();
            error_log("Database transaction started");

            // Deduct balance only after confirming we have pins
            $updateBalanceQuery = "UPDATE subscribers SET sWallet = sWallet - ? WHERE sId = ?";
            $this->db->query($updateBalanceQuery, [$totalAmount, $userId]);

            // Save pins
            foreach ($pins as $pin) {
                $insertPinQuery = "INSERT INTO exam_pins (pin, exam_id, user_id, status) VALUES (?, ?, ?, 'active')";
                $this->db->query($insertPinQuery, [$pin, $exam[0]['eId'], $userId]);
            }

            $status = 1; // 1 = success
            $description = "{$quantity} {$exam[0]['provider']} exam pin(s) purchase";
            
            // Record transaction
            $insertTxnQuery = "INSERT INTO transactions (
                sId, transref, servicename, servicedesc, amount, status, oldbal, newbal, api_response
            ) VALUES (?, ?, 'exam_pin', ?, ?, ?, ?, ?, ?)";
            
            $result = $this->db->query(
                $insertTxnQuery, 
                [
                    $userId,
                    $transactionId,
                    $description,
                    $totalAmount,
                    $status,
                    $currentBalance,
                    ($currentBalance - $totalAmount),
                    json_encode($apiResponse)
                ]
            );

            if ($result === false) {
                throw new Exception("Failed to insert transaction record");
            }

            $this->db->commit();
            
            return [
                'status' => 'success',
                'message' => "Successfully purchased {$quantity} {$exam[0]['provider']} pin(s)",
                'data' => [
                    'transactionId' => $transactionId,
                    'provider' => $exam[0]['provider'],
                    'quantity' => $quantity,
                    'amount' => $totalAmount,
                    'pins' => $pins
                ]
            ];

        } catch (Exception $e) {
            if (isset($this->db)) {
                $this->db->rollBack();

                // Record failed transaction if we have exam details
                if ($exam) {
                    $description = "{$quantity} {$exam[0]['provider']} exam pin(s) purchase - Error: " . $e->getMessage();
                    $insertTxnQuery = "INSERT INTO transactions (
                        sId, transref, servicename, servicedesc, amount, status, oldbal, newbal, api_response_log
                    ) VALUES (?, ?, 'exam_pin', ?, ?, ?, ?, ?, ?)";
                    
                    try {
                        $this->db->beginTransaction();
                        
                        // Refund the user's balance
                        if (isset($totalAmount) && $totalAmount > 0) {
                            $this->db->query("UPDATE subscribers SET sWallet = sWallet + ? WHERE sId = ?", 
                                [$totalAmount, $userId]);
                        }
                        
                        $this->db->query(
                            $insertTxnQuery, 
                            [
                                $userId,
                                $transactionId,
                                $description,
                                $totalAmount,
                                2, // 2 = failed
                                $currentBalance,
                                $currentBalance, // Balance remains the same after refund
                                $e->getMessage()
                            ]
                        );
                        $this->db->commit();
                    } catch (Exception $e2) {
                        error_log("Failed to record failed transaction: " . $e2->getMessage());
                        if ($this->db->inTransaction()) {
                            $this->db->rollBack();
                        }
                    }
                }
            }

            return [
                'status' => 'error',
                'message' => $e->getMessage(),
                'data' => null
            ];
        }
    }

    public function getExamProviderDetails($examId) {
        try {
            $query = "SELECT eId as id, provider as name, price, providerStatus as status, 
                            buying_price as buyingPrice
                     FROM examid 
                     WHERE eId = ? AND providerStatus = 'On'";
            
            $result = $this->db->query($query, [$examId]);
            
            if (empty($result)) {
                return [
                    'status' => 'error',
                    'message' => 'Exam provider not found or inactive',
                    'data' => null
                ];
            }
            
            return [
                'status' => 'success',
                'message' => 'Provider details fetched successfully',
                'data' => $result[0]
            ];
        } catch (Exception $e) {
            return [
                'status' => 'error',
                'message' => "Error fetching provider details: " . $e->getMessage(),
                'data' => null
            ];
        }
    }

    public function validatePurchaseRequest($examName, $quantity) {
        try {
            $query = "SELECT * FROM examid WHERE provider = ? AND providerStatus = 'On'";
            $exam = $this->db->query($query, [$examName]);
            
            if (empty($exam)) {
                return [
                    'status' => 'error',
                    'message' => 'Invalid or inactive exam type',
                    'data' => null
                ];
            }
            
            if ($quantity <= 0 || $quantity > 5) {
                return [
                    'status' => 'error',
                    'message' => 'Invalid quantity. Must be between 1 and 5',
                    'data' => null
                ];
            }
            
            return [
                'status' => 'success',
                'message' => 'Validation successful',
                'data' => [
                    'exam' => $exam[0],
                    'totalAmount' => $exam[0]['price'] * $quantity
                ]
            ];
        } catch (Exception $e) {
            return [
                'status' => 'error',
                'message' => "Validation error: " . $e->getMessage(),
                'data' => null
            ];
        }
    }
}
