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
        try {
            // Debug: Log incoming parameters
            error_log("purchaseElectricity() called with: meter={$meterNumber}, provider={$providerId}, amount={$amount}, type={$meterType}, phone={$phone}");
            
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

            // Build the request payload as JSON
            $payload = json_encode([
                'meternumber' => $meterNumber,
                'disconame' => $provider['abbreviation'],
                'mtype' => strtolower($meterType),
                'amount' => $amount,
                'phone' => $phone
            ]);

            // Debug: Log the URL being sent
            error_log("Sending purchase request to provider: {$baseUrl}");
            error_log("Payload: {$payload}");

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

            // Debug: Log the provider response
            error_log("Provider response (raw): {$response}");

            if ($err) {
                throw new Exception("cURL Error: " . $err);
            }

            $result = json_decode($response, true);

            // If we didn't get a JSON response, consider it an error
            if (!$result || !is_array($result)) {
                return array(
                    'status' => 'error',
                    'message' => 'Failed to process electricity purchase: invalid response from provider',
                    'raw' => $response
                );
            }

            // Detect common provider-side validation errors or explicit failure flags
            $hasProviderError = false;
            $errorMessages = [];

            if (isset($result['status']) && !empty($result['status']) && !in_array(strtolower((string)$result['status']), ['success', 'ok', 'true'], true)) {
                $hasProviderError = true;
                $errorMessages[] = is_string($result['message'] ?? '') ? $result['message'] : '';
            }

            if (isset($result['error'])) {
                $hasProviderError = true;
                if (is_array($result['error'])) {
                    $errorMessages = array_merge($errorMessages, $result['error']);
                } else {
                    $errorMessages[] = (string)$result['error'];
                }
            }

            if (isset($result['errors']) && is_array($result['errors'])) {
                $hasProviderError = true;
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
                foreach ($result['amount'] as $m) {
                    $errorMessages[] = (string)$m;
                }
            }

            if ($hasProviderError) {
                // Return an error with provider details so router can set proper HTTP code
                return array(
                    'status' => 'error',
                    'message' => implode('; ', array_filter($errorMessages)) ?: ($result['message'] ?? 'Provider reported an error'),
                    'data' => $result
                );
            }

            // Otherwise treat as success and return normalized data
            return array(
                'status' => 'success',
                'data' => array(
                    'token' => $result['token'] ?? null,
                    'units' => $result['units'] ?? null,
                    'amount' => $result['amount'] ?? $amount,
                    'meter_number' => $meterNumber,
                    'provider' => $provider['provider'],
                    'reference' => $result['reference'] ?? null,
                    'message' => $result['message'] ?? 'Purchase successful'
                )
            );

        } catch (Exception $e) {
            throw new Exception("Error purchasing electricity: " . $e->getMessage());
        }
    }

    public function validateMeterNumber($meterNumber, $providerId, $meterType = 'prepaid') {
        try {
            // Get the provider information
            $query = "SELECT provider, abbreviation, electricityid FROM electricityid WHERE eId = ?";
            $provider = $this->db->query($query, [$providerId]);
            
            if (empty($provider)) {
                throw new Exception("Invalid provider ID");
            }

            $provider = $provider[0];
            
            // Get API configuration
            $apiDetails = $this->getProviderDetails()[0];
            
            // Convert meter type to lowercase for consistency
            $meterType = strtolower($meterType);
            
            // Prepare the API request using Strowallet verify-merchant endpoint
            $curl = curl_init();

            // Get base URL and API key from configuration
            $baseUrl = rtrim($apiDetails['verificationProvider'], '/') ?: null;
            if (empty($baseUrl)) {
                throw new Exception("Verification provider URL not configured");
            }

            // The verification key is used as the public_key in the JSON payload
            $publicKey = $apiDetails['verificationKey'] ?? '';
            if (empty($publicKey)) {
                throw new Exception("Verification public key not configured");
            }

            // Map DB provider names/abbreviations to Strowallet service_name slugs
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
            $serviceName = $providerMap[$dbProviderKey] ?? null;
            if (empty($serviceName)) {
                // fallback: sanitize provider string to a slug-like format
                $serviceName = strtolower(preg_replace('/[^a-zA-Z0-9\s-]/', '', ($provider['provider'] ?? $provider['abbreviation'])));
                $serviceName = str_replace([' ', '_'], '-', $serviceName);
            }

            $url = $baseUrl . '/api/electricity/verify-merchant/';

            $payload = json_encode([
                'meter_type' => $meterType,
                'meter_number' => $meterNumber,
                'service_name' => $serviceName,
                'public_key' => $publicKey,
            ]);

            // Log the request details (avoid logging full key)
            error_log("Meter Validation Request (Strowallet): URL={$url}");
            error_log("Service: {$serviceName}, MeterType: {$meterType}, Meter: {$meterNumber}");

            curl_setopt_array($curl, array(
                CURLOPT_URL => $url,
                CURLOPT_RETURNTRANSFER => true,
                CURLOPT_ENCODING => '',
                CURLOPT_MAXREDIRS => 10,
                CURLOPT_TIMEOUT => 30,
                CURLOPT_FOLLOWLOCATION => true,
                CURLOPT_HTTP_VERSION => CURL_HTTP_VERSION_1_1,
                CURLOPT_CUSTOMREQUEST => 'POST',
                CURLOPT_POSTFIELDS => $payload,
                CURLOPT_HTTPHEADER => array(
                    'Accept: application/json',
                    'Content-Type: application/json'
                ),
            ));

            $response = curl_exec($curl);
            $err = curl_error($curl);
            $httpCode = curl_getinfo($curl, CURLINFO_HTTP_CODE);
            curl_close($curl);

            error_log("Meter Validation Response (Strowallet): HTTP {$httpCode}");
            error_log("Raw Response: {$response}");

            if ($err) {
                error_log("cURL Error: " . $err);
                throw new Exception("cURL Error: " . $err);
            }

            $result = json_decode($response, true);
            error_log("Decoded Response: " . print_r($result, true));

            if (!$result || !is_array($result)) {
                error_log("Meter validation: invalid or empty response from provider: " . var_export($response, true));
                return array(
                    'status' => 'error',
                    'message' => 'fail to validate meter'
                );
            }

            // Normalise response container
            $d = [];
            if (isset($result['data']) && is_array($result['data'])) {
                $d = $result['data'];
            } else {
                $d = $result;
            }

            // Try several possible field names for customer name/address
            $name = $d['name'] ?? $d['customer_name'] ?? ($d['customer']['name'] ?? null);
            $address = $d['address'] ?? $d['customer_address'] ?? ($d['customer']['address'] ?? null);

            $isInvalid = isset($d['invalid']) && $d['invalid'] === true;
            $hasRequiredData = !empty($name);

            if ($isInvalid || !$hasRequiredData) {
                error_log("Meter validation: provider reported invalid or incomplete data: " . var_export($d, true));
                return array(
                    'status' => 'error',
                    'message' => 'fail to validate meter'
                );
            }

            return array(
                'status' => 'success',
                'data' => array(
                    'invalid' => false,
                    'name' => $name,
                    'address' => $address,
                    'meter_number' => $meterNumber,
                    'provider' => $provider['provider']
                )
            );

        } catch (Exception $e) {
            // Log detailed exception server-side but return a generic message to the client
            error_log("Exception in validateMeterNumber: " . $e->getMessage());
            return array(
                'status' => 'error',
                'message' => 'fail to validate meter'
            );
        }
    }
}
?>
