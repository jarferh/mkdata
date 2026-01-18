<?php
require_once __DIR__ . '/../config/database.php';

use Binali\Config\Database;

class ElectricityService {
    private $db;

    public function __construct() {
        $this->db = new Database();
    }

    public function getElectricityProviders() {
        try {
            $query = "SELECT eId, provider, abbreviation FROM electricityid WHERE providerStatus = 'On' ORDER BY provider ASC";
            return $this->db->query($query);
        } catch (Exception $e) {
            throw new Exception("Error fetching electricity providers: " . $e->getMessage());
        }
    }

    public function getProviderDetails() {
        try {
            // Get all required API configurations in a single query
            $query = "SELECT 
                        (SELECT value FROM apiconfigs WHERE name = 'meterProvider') as provider,
                        (SELECT value FROM apiconfigs WHERE name = 'meterApi') as apiKey,
                        (SELECT value FROM apiconfigs WHERE name = 'meterVerificationProvider') as verificationProvider,
                        (SELECT value FROM apiconfigs WHERE name = 'meterVerificationApi') as verificationKey,
                        (SELECT value FROM apiconfigs WHERE name = 'meterProvider') as purchaseProvider,
                        (SELECT value FROM apiconfigs WHERE name = 'meterApi') as purchaseKey";
            
            $result = $this->db->query($query);
            
            if (empty($result)) {
                throw new Exception("No API configuration found");
            }
            
            return $result;
        } catch (Exception $e) {
            throw new Exception("Error fetching provider details: " . $e->getMessage());
        }
    }

    public function purchaseElectricity($meterNumber, $providerId, $amount, $meterType = 'prepaid', $phone = '') {
        // MOCK FUNCTION FOR TESTING - Always returns success
        // Comment this out and uncomment the real implementation below to use the actual provider
        try {
            error_log("\n=== ELECTRICITY PURCHASE (MOCK) INIT START ===");
            error_log("Meter Number: " . $meterNumber);
            error_log("Provider ID: " . $providerId);
            error_log("Amount: " . $amount);
            error_log("Meter Type: " . $meterType);
            error_log("Phone: " . $phone);
            error_log("=== ELECTRICITY PURCHASE (MOCK) INIT END ===\n");
            
            // Get the provider information
            $query = "SELECT provider, abbreviation FROM electricityid WHERE eId = ?";
            $provider = $this->db->query($query, [$providerId]);
            
            if (empty($provider)) {
                throw new Exception("Invalid provider ID");
            }

            $provider = $provider[0];

            // Mock success response with sample data
            $mockResponse = [
                "success" => true,
                "message" => "Transaction Successfully.And your token is Token : 1473800000838 and purchased units are ",
                "response" => [
                    "code" => "000",
                    "content" => [
                        "transactions" => [
                            "status" => "delivered",
                            "product_name" => "Abuja Electricity Distribution Company- AEDC",
                            "unique_element" => "12345678900",
                            "unit_price" => 500,
                            "quantity" => 1,
                            "service_verification" => null,
                            "channel" => "api",
                            "commission" => 6,
                            "total_amount" => 494,
                            "discount" => null,
                            "type" => "Electricity Bill",
                            "email" => "null",
                            "phone" => "null",
                            "name" => null,
                            "convinience_fee" => 0,
                            "amount" => (int)$amount,
                            "platform" => "api",
                            "method" => "api",
                            "transactionId" => "17176739153935832537"
                        ]
                    ],
                    "response_description" => "TRANSACTION SUCCESSFUL",
                    "requestId" => "202406061257122",
                    "amount" => $amount,
                    "transaction_date" => date('Y-m-d\TH:i:s.000000\Z'),
                    "purchased_code" => "Token : 147380000005838",
                    "CustomerName" => "MOCK CUSTOMER",
                    "CustomerAddress" => "123 MOCK STREET, CITY",
                    "Units" => 7.3,
                    "Token" => "147385800001985838",
                    "Receipt" => "240606594285"
                ]
            ];

            error_log("=== ELECTRICITY PURCHASE (MOCK) RESPONSE ===");
            error_log("Mock Response: " . json_encode($mockResponse));
            error_log("=== END MOCK RESPONSE ===");

            // Extract token from various possible locations in provider response
            $token = null;
            if (!empty($mockResponse['Token'])) {
                $token = $mockResponse['Token'];
            } elseif (!empty($mockResponse['token'])) {
                $token = $mockResponse['token'];
            } elseif (!empty($mockResponse['purchased_code'])) {
                $token = $mockResponse['purchased_code'];
            } elseif (!empty($mockResponse['response']['purchased_code'])) {
                $token = $mockResponse['response']['purchased_code'];
            } elseif (!empty($mockResponse['response']['Token'])) {
                $token = $mockResponse['response']['Token'];
            } elseif (!empty($mockResponse['response']['content']['purchased_code'])) {
                $token = $mockResponse['response']['content']['purchased_code'];
            } elseif (!empty($mockResponse['response']['content']['Token'])) {
                $token = $mockResponse['response']['content']['Token'];
            }
            error_log("Token extracted: " . ($token ?? 'NOT FOUND'));
            
            return array(
                'status' => 'success',
                'data' => array(
                    'token' => $token,
                    'units' => $mockResponse['Units'] ?? $mockResponse['units'] ?? null,
                    'amount' => $mockResponse['amount'] ?? $amount,
                    'meter_number' => $meterNumber,
                    'provider' => $provider['provider'],
                    'reference' => $mockResponse['Receipt'] ?? null,
                    'message' => $mockResponse['message'] ?? 'Purchase successful',
                    'full_response' => $mockResponse
                )
            );

        } catch (Exception $e) {
            error_log("=== ELECTRICITY PURCHASE (MOCK) EXCEPTION ===");
            error_log("Exception: " . $e->getMessage());
            error_log("=== END EXCEPTION ===");
            throw new Exception("Error purchasing electricity: " . $e->getMessage());
        }
    }

    /* REAL FUNCTION - COMMENTED OUT FOR TESTING */
    public function purchaseElectricity_REAL($meterNumber, $providerId, $amount, $meterType = 'prepaid', $phone = '') {
        try {
            // Get the provider information
            $query = "SELECT provider, abbreviation FROM electricityid WHERE eId = ?";
            $provider = $this->db->query($query, [$providerId]);
            
            if (empty($provider)) {
                throw new Exception("Invalid provider ID");
            }

            $provider = $provider[0];
            
            // Get API configuration
            $apiDetails = $this->getProviderDetails()[0];
            
            // Get base URL and API key from configuration
            $baseUrl = $apiDetails['provider'];
            if (empty($baseUrl)) {
                throw new Exception("Purchase provider URL not configured");
            }
            
            $apiKey = $apiDetails['apiKey'];
            if (empty($apiKey)) {
                throw new Exception("Purchase API key not configured");
            }

            // Map provider names/abbreviations to formatted service names (slug format)
            $providerMap = [
                'Ikeja Electric' => 'ikeja-electric',
                'Eko Electric' => 'eko-electric',
                'Kano Electric' => 'kano-electric',
                'Port Harcourt Electric' => 'portharcourt-electric',
                'Jos Electric' => 'jos-electric',
                'Ibadan Electric' => 'ibadan-electric',
                'Kaduna Electric' => 'kaduna-electric',
                'Abuja Electric' => 'abuja-electric',
                'Enugu Electric' => 'enugu-electric',
                'Benin Electric' => 'benin-electric',
                'Aba Electric' => 'aba-electric',
                'Yola Electric' => 'yola-electric',
                // also map common DB abbreviations if used
                'IE' => 'ikeja-electric',
                'EKEDC' => 'eko-electric',
                'KEDCO' => 'kano-electric',
                'PHEDC' => 'portharcourt-electric',
                'JED' => 'jos-electric',
                'IBEDC' => 'ibadan-electric',
                'KEDC' => 'kaduna-electric',
                'AEDC' => 'abuja-electric',
                'ENUGU' => 'enugu-electric',
                'BENIN' => 'benin-electric',
                'YOLA' => 'yola-electric',
            ];

            $dbProviderKey = $provider['provider'] ?? $provider['abbreviation'] ?? '';
            $formattedServiceName = $providerMap[$dbProviderKey] ?? null;
            if (empty($formattedServiceName)) {
                // fallback: sanitize provider string to a slug-like format
                $formattedServiceName = strtolower(preg_replace('/[^a-zA-Z0-9\s-]/', '', ($provider['provider'] ?? $provider['abbreviation'])));
                $formattedServiceName = str_replace([' ', '_'], '-', $formattedServiceName);
            }

            // Build the request payload as JSON
            // Ensure numeric types where provider expects numeric values
            $payload = json_encode([
                'meternumber' => $meterNumber,
                'disconame' => $provider['abbreviation'],
                'mtype' => strtolower($meterType),
                'amount' => (int)$amount,
                'phone' => $phone,
                // Provider expects disco_name as a primary key (numeric)
                'disco_name' => (int)$providerId,
                'meter_number' => $meterNumber,
                // Provider expects a single numeric MeterType: PREPAID=1, POSTPAID=2
                'MeterType' => ($meterType === 'prepaid') ? 1 : 2,
                'public_key' => $apiDetails['apiKey'],
                'service_name' => $formattedServiceName,
                'meter_type' => strtolower($meterType)
            ]);

            // Log the request details
            error_log("=== ELECTRICITY PURCHASE REQUEST START ===");
            error_log("URL: " . $baseUrl);
            error_log("API Key: " . substr($apiKey, 0, 10) . "...");
            error_log("Request Payload: " . $payload);
            error_log("=== ELECTRICITY PURCHASE REQUEST END ===");

            $curl = curl_init();
            curl_setopt_array($curl, array(
                CURLOPT_URL => $baseUrl,
                CURLOPT_RETURNTRANSFER => true,
                CURLOPT_ENCODING => '',
                CURLOPT_MAXREDIRS => 10,
                CURLOPT_TIMEOUT => 30,
                CURLOPT_FOLLOWLOCATION => true,
                CURLOPT_HTTP_VERSION => CURL_HTTP_VERSION_1_1,
                CURLOPT_CUSTOMREQUEST => 'POST',
                CURLOPT_POSTFIELDS => $payload,
                CURLOPT_HTTPHEADER => array(
                    'Authorization: Token ' . $apiKey,
                    'Content-Type: application/json'
                ),
            ));

            $response = curl_exec($curl);
            $err = curl_error($curl);
            curl_close($curl);

            // Log the provider response
            error_log("=== ELECTRICITY PURCHASE RESPONSE START ===");
            error_log("Raw Response: " . $response);
            if ($err) {
                error_log("cURL Error: " . $err);
            }
            error_log("=== ELECTRICITY PURCHASE RESPONSE END ===");

            if ($err) {
                throw new Exception("cURL Error: " . $err);
            }

            $result = json_decode($response, true);

            // Log parsed result
            error_log("=== ELECTRICITY PURCHASE PARSED RESULT START ===");
            error_log("Parsed Result: " . json_encode($result));
            error_log("=== ELECTRICITY PURCHASE PARSED RESULT END ===");

            // If we didn't get a JSON response, consider it an error
            if (!$result || !is_array($result)) {
                error_log("=== ELECTRICITY PURCHASE ERROR ===");
                error_log("Invalid JSON response from provider");
                error_log("=== END ERROR ===");
                return array(
                    'status' => 'error',
                    'message' => 'Failed to process electricity purchase: invalid response from provider',
                    'raw' => $response
                );
            }

            // Detect common provider-side validation errors or explicit failure flags
            $hasProviderError = false;
            $errorMessages = [];

            error_log("=== ELECTRICITY PURCHASE ERROR DETECTION ===");

            // Check for detail field (some APIs use this for error messages)
            if (isset($result['detail'])) {
                $hasProviderError = true;
                $errorMessages[] = (string)$result['detail'];
                error_log("Found 'detail' field: " . $result['detail']);
            }

            if (isset($result['status']) && !empty($result['status']) && !in_array(strtolower((string)$result['status']), ['success', 'ok', 'true'], true)) {
                $hasProviderError = true;
                $errorMessages[] = is_string($result['message'] ?? '') ? $result['message'] : '';
                error_log("Found invalid 'status' field: " . $result['status']);
            }

            // Some providers return a boolean/string `success` flag. Treat explicit false as an error.
            if (isset($result['success'])) {
                $s = $result['success'];
                if ($s === false || (is_string($s) && strtolower($s) === 'false')) {
                    $hasProviderError = true;
                    $errorMessages[] = is_string($result['message'] ?? '') ? $result['message'] : 'Provider reported failure';
                    error_log("Found 'success' => false in provider response");
                }
            }

            if (isset($result['error'])) {
                $hasProviderError = true;
                if (is_array($result['error'])) {
                    $errorMessages = array_merge($errorMessages, $result['error']);
                    error_log("Found 'error' array with count: " . count($result['error']));
                } else {
                    $errorMessages[] = (string)$result['error'];
                    error_log("Found 'error' field: " . $result['error']);
                }
            }

            if (isset($result['errors']) && is_array($result['errors'])) {
                $hasProviderError = true;
                error_log("Found 'errors' array with count: " . count($result['errors']));
                // flatten nested error arrays
                foreach ($result['errors'] as $k => $v) {
                    if (is_array($v)) {
                        $errorMessages = array_merge($errorMessages, $v);
                    } else {
                        $errorMessages[] = (string)$v;
                    }
                }
            }

            // Some providers return validation messages keyed by field (e.g., amount => ["This field is required."])
            if (!empty($result['amount']) && is_array($result['amount'])) {
                $hasProviderError = true;
                error_log("Found 'amount' error array");
                foreach ($result['amount'] as $m) {
                    $errorMessages[] = (string)$m;
                }
            }

            // Generic detection: recursively scan the response for any array-valued
            // validation messages and flatten them. Treat presence of such arrays
            // as provider-side validation errors.
            $flattened = [];
            $scanForArrays = function ($node) use (&$scanForArrays, &$hasProviderError, &$flattened, &$errorMessages) {
                if (is_array($node)) {
                    // If this node is an associative array mapping fields to arrays/messages
                    foreach ($node as $k => $v) {
                        if (is_array($v)) {
                            if (!empty($v)) {
                                $hasProviderError = true;
                                error_log("Found field error array for '{$k}' with count: " . count($v));
                                foreach ($v as $item) {
                                    if (is_array($item)) {
                                        // flatten nested arrays
                                        $flattened = array_merge($flattened, $item);
                                    } else {
                                        $flattened[] = (string)$item;
                                    }
                                }
                            }
                            // Recurse into array values in case of deeper nesting
                            $scanForArrays($v);
                        }
                    }
                }
            };

            // Scan both top-level and data container
            $scanForArrays($result);
            if (isset($result['data']) && is_array($result['data'])) {
                $scanForArrays($result['data']);
            }

            if (!empty($flattened)) {
                $errorMessages = array_merge($errorMessages, $flattened);
            }

            error_log("Error Detection Complete. Has Error: " . ($hasProviderError ? 'YES' : 'NO'));
            error_log("=== END ERROR DETECTION ===");

            if ($hasProviderError) {
                error_log("=== ELECTRICITY PURCHASE ERROR ===");
                error_log("Provider Error Message: " . implode('; ', array_filter($errorMessages)));
                error_log("=== END ERROR ===");
                // Return an error with provider details so router can set proper HTTP code
                return array(
                    'status' => 'error',
                    'message' => implode('; ', array_filter($errorMessages)) ?: ($result['message'] ?? 'Provider reported an error'),
                    'data' => $result
                );
            }

            // Otherwise treat as success and return normalized data
            error_log("=== ELECTRICITY PURCHASE SUCCESS ===");
            error_log("Transaction successful for meter: " . $meterNumber);
            
            // Extract token from various possible locations in provider response
            $token = $result['Token'] ?? $result['token'] ?? $result['purchased_code'] ?? null;
            error_log("Token extracted: " . ($token ?? 'NOT FOUND'));
            error_log("=== END SUCCESS ===");
            
            return array(
                'status' => 'success',
                'data' => array(
                    'token' => $token,
                    'units' => $result['Units'] ?? $result['units'] ?? null,
                    'amount' => $result['Amount'] ?? $result['amount'] ?? $amount,
                    'meter_number' => $meterNumber,
                    'provider' => $provider['provider'],
                    'reference' => $result['reference'] ?? null,
                    'message' => $result['message'] ?? 'Purchase successful',
                    'full_response' => $result
                )
            );

        } catch (Exception $e) {
            error_log("=== ELECTRICITY PURCHASE EXCEPTION ===");
            error_log("Exception: " . $e->getMessage());
            error_log("=== END EXCEPTION ===");
            throw new Exception("Error purchasing electricity: " . $e->getMessage());
        }
    }
    // END OF COMMENTED REAL FUNCTION

    // public function validateMeterNumber($meterNumber, $providerId, $meterType = 'prepaid') {
    //     try {
    //         // Log incoming parameters
    //         error_log("\n=== METER VALIDATION INIT START ===");
    //         error_log("Meter Number: " . $meterNumber);
    //         error_log("Provider ID: " . $providerId);
    //         error_log("Meter Type: " . $meterType);
    //         error_log("=== METER VALIDATION INIT END ===\n");
            
    //         // Get the provider information
    //         $query = "SELECT provider, abbreviation, electricityid FROM electricityid WHERE eId = ?";
    //         $provider = $this->db->query($query, [$providerId]);
            
    //         if (empty($provider)) {
    //             throw new Exception("Invalid provider ID");
    //         }

    //         $provider = $provider[0];
            
    //         // Get API configuration
    //         $apiDetails = $this->getProviderDetails()[0];
            
    //         // Convert meter type to lowercase for consistency
    //         $meterType = strtolower($meterType);
            
    //         // Prepare the API request using Strowallet verify-merchant endpoint
    //         $curl = curl_init();

    //         // Strowallet verification endpoint is always at this URL
    //         $baseUrl = 'https://strowallet.com';

    //         // Use hardcoded public key for Strowallet verification
    //         $publicKey = 'pub_c7Y8ufejLZon3gDMNMnBQxQXyIwNVWhXshmA1JCh';

    //         // Map DB provider names/abbreviations to Strowallet service_name slugs
    //         $providerMap = [
    //             'Ikeja Electric' => 'ikeja-electric',
    //             'Eko Electric' => 'eko-electric',
    //             'Kano Electric' => 'kano-electric',
    //             'Port Harcourt Electric' => 'portharcourt-electric',
    //             'Jos Electric' => 'jos-electric',
    //             'Ibadan Electric' => 'ibadan-electric',
    //             'Kaduna Electric' => 'kaduna-electric',
    //             'Abuja Electric' => 'abuja-electric',
    //             'Enugu Electric' => 'enugu-electric',
    //             'Benin Electric' => 'benin-electric',
    //             'Aba Electric' => 'aba-electric',
    //             'Yola Electric' => 'yola-electric',
    //             // also map common DB abbreviations if used
    //             'IE' => 'ikeja-electric',
    //             'EKEDC' => 'eko-electric',
    //             'KEDCO' => 'kano-electric',
    //             'PHEDC' => 'portharcourt-electric',
    //             'JED' => 'jos-electric',
    //             'IBEDC' => 'ibadan-electric',
    //             'KEDC' => 'kaduna-electric',
    //             'AEDC' => 'abuja-electric',
    //             'ENUGU' => 'enugu-electric',
    //             'BENIN' => 'benin-electric',
    //             'YOLA' => 'yola-electric',
    //         ];

    //         $dbProviderKey = $provider['provider'] ?? $provider['abbreviation'] ?? '';
    //         $serviceName = $providerMap[$dbProviderKey] ?? null;
    //         if (empty($serviceName)) {
    //             // fallback: sanitize provider string to a slug-like format
    //             $serviceName = strtolower(preg_replace('/[^a-zA-Z0-9\s-]/', '', ($provider['provider'] ?? $provider['abbreviation'])));
    //             $serviceName = str_replace([' ', '_'], '-', $serviceName);
    //         }

    //         $url = $baseUrl . '/api/electricity/verify-merchant/';

    //         $payload = json_encode([
    //             'meter_type' => $meterType,
    //             'meter_number' => $meterNumber,
    //             'service_name' => $serviceName,
    //             'public_key' => $publicKey,
    //         ]);

    //         // Log the request details
    //         error_log("=== METER VALIDATION REQUEST START ===");
    //         error_log("URL: " . $url);
    //         error_log("API Key (partial): " . substr($publicKey, 0, 10) . "...");
    //         error_log("Service Name: " . $serviceName);
    //         error_log("Meter Type: " . $meterType);
    //         error_log("Meter Number: " . $meterNumber);
    //         error_log("Payload: " . $payload);
    //         error_log("=== METER VALIDATION REQUEST END ===");

    //         curl_setopt_array($curl, array(
    //             CURLOPT_URL => $url,
    //             CURLOPT_RETURNTRANSFER => true,
    //             CURLOPT_ENCODING => '',
    //             CURLOPT_MAXREDIRS => 10,
    //             CURLOPT_TIMEOUT => 30,
    //             CURLOPT_FOLLOWLOCATION => true,
    //             CURLOPT_HTTP_VERSION => CURL_HTTP_VERSION_1_1,
    //             CURLOPT_CUSTOMREQUEST => 'POST',
    //             CURLOPT_POSTFIELDS => $payload,
    //             CURLOPT_HTTPHEADER => array(
    //                 'Accept: application/json',
    //                 'Content-Type: application/json'
    //             ),
    //         ));

    //         $response = curl_exec($curl);
    //         $err = curl_error($curl);
    //         $httpCode = curl_getinfo($curl, CURLINFO_HTTP_CODE);
    //         curl_close($curl);

    //         // Log the response
    //         error_log("=== METER VALIDATION RESPONSE START ===");
    //         error_log("HTTP Code: " . $httpCode);
    //         error_log("Raw Response: " . $response);
    //         if ($err) {
    //             error_log("cURL Error: " . $err);
    //         }
    //         error_log("=== METER VALIDATION RESPONSE END ===");

    //         if ($err) {
    //             error_log("cURL Error: " . $err);
    //             throw new Exception("cURL Error: " . $err);
    //         }

    //         $result = json_decode($response, true);
            
    //         // Log parsed result
    //         error_log("=== METER VALIDATION PARSED RESULT START ===");
    //         error_log("Parsed Result: " . json_encode($result));
    //         error_log("=== METER VALIDATION PARSED RESULT END ===");

    //         if (!$result || !is_array($result)) {
    //             error_log("=== METER VALIDATION ERROR ===");
    //             error_log("Invalid or empty response from provider");
    //             error_log("=== END ERROR ===");
    //             return array(
    //                 'status' => 'error',
    //                 'message' => 'fail to validate meter'
    //             );
    //         }

    //         // Normalise response container
    //         $d = [];
    //         if (isset($result['data']) && is_array($result['data'])) {
    //             $d = $result['data'];
    //         } else {
    //             $d = $result;
    //         }

    //         // Try several possible field names for customer name/address
    //         $name = $d['name'] ?? $d['customer_name'] ?? ($d['customer']['name'] ?? null);
    //         $address = $d['address'] ?? $d['customer_address'] ?? ($d['customer']['address'] ?? null);

    //         $isInvalid = isset($d['invalid']) && $d['invalid'] === true;
    //         $hasRequiredData = !empty($name);

    //         // Log validation result
    //         error_log("=== METER VALIDATION CHECK START ===");
    //         error_log("Is Invalid: " . ($isInvalid ? 'YES' : 'NO'));
    //         error_log("Has Required Data: " . ($hasRequiredData ? 'YES' : 'NO'));
    //         error_log("Customer Name: " . ($name ?? 'NULL'));
    //         error_log("Customer Address: " . ($address ?? 'NULL'));
    //         error_log("=== METER VALIDATION CHECK END ===");

    //         if ($isInvalid || !$hasRequiredData) {
    //             error_log("=== METER VALIDATION ERROR ===");
    //             error_log("Provider reported invalid or incomplete data");
    //             error_log("=== END ERROR ===");
    //             return array(
    //                 'status' => 'error',
    //                 'message' => 'fail to validate meter'
    //             );
    //         }

    //         error_log("=== METER VALIDATION SUCCESS ===");
    //         error_log("Meter validation successful for: " . $meterNumber);
    //         error_log("Customer: " . $name);
    //         error_log("=== END SUCCESS ===");

    //         return array(
    //             'status' => 'success',
    //             'data' => array(
    //                 'invalid' => false,
    //                 'name' => $name,
    //                 'address' => $address,
    //                 'meter_number' => $meterNumber,
    //                 'provider' => $provider['provider']
    //             )
    //         );

    //     } catch (Exception $e) {
    //         // Log detailed exception server-side but return a generic message to the client
    //         error_log("=== METER VALIDATION EXCEPTION ===");
    //         error_log("Exception: " . $e->getMessage());
    //         error_log("=== END EXCEPTION ===");
    //         return array(
    //             'status' => 'error',
    //             'message' => 'fail to validate meter'
    //         );
    //     }
    // }
}
?>
