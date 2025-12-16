import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class ApiService {
  static const String baseUrl =
      'https://api.mkdata.com.ng'; // Base URL without trailing slash
  static const String _userIdKey = 'user_id';
  static const String _userKey = 'user_data';

  final http.Client _client = http.Client();
  final Future<SharedPreferences> _prefs = SharedPreferences.getInstance();

  // Default timeout for API calls
  static const Duration _defaultTimeout = Duration(seconds: 15);

  // Helper to run a future with a default timeout and convert common network
  // errors to clearer Exceptions.
  Future<T> _withTimeout<T>(Future<T> future) async {
    try {
      return await future.timeout(_defaultTimeout);
    } on SocketException {
      throw Exception('Network error: Please check your internet connection.');
    } on TimeoutException {
      throw Exception('Request timed out. Please try again.');
    }
  }

  void _printRequestDetails(
    String method,
    String endpoint, [
    Map<String, dynamic>? body,
  ]) {
    print('\n=== API Request Details ===');
    print('URL: $baseUrl/$endpoint');
    print('Method: $method');
    if (body != null) {
      print('Body: ${jsonEncode(body)}');
    }
    print('========================\n');
  }

  // Login method
  Future<Map<String, dynamic>> login(String email, String password) async {
    try {
      final url = '$baseUrl/auth/login.php';
      _printRequestDetails('POST', 'auth/login.php', {
        'email': email,
        'password': '[REDACTED]',
      });

      // First login request
      final response = await _client.post(
        Uri.parse(url),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'email': email, 'password': password}),
      );

      var responseData = jsonDecode(response.body);

      // If login successful, immediately fetch full user details
      if (response.statusCode == 200) {
        final userId = responseData['id']?.toString();
        if (userId != null) {
          final userDetailsResponse = await _client.get(
            Uri.parse('$baseUrl/api/subscriber/$userId'),
            headers: {'Content-Type': 'application/json'},
          );

          if (userDetailsResponse.statusCode == 200) {
            final userDetails = jsonDecode(userDetailsResponse.body);
            if (userDetails['status'] == 'success' &&
                userDetails['data'] != null) {
              // Merge login response with detailed user data
              responseData = {
                ...userDetails['data'],
                'message': responseData['message'],
              };
            }
          }
        }
      }

      if (response.statusCode == 200) {
        print('\n=== Login Response Data ===');
        print('Raw response: ${response.body}');

        // Save user data in the new format
        final userData = {
          'sId':
              responseData['sId']?.toString() ??
              responseData['id']?.toString() ??
              '',
          'sFname': responseData['sFname'] ?? '',
          'sLname': responseData['sLname'] ?? '',
          'sEmail': responseData['sEmail'] ?? responseData['email'] ?? '',
          'sPhone': responseData['sPhone'] ?? responseData['phone'] ?? '',
          'sWallet': responseData['sWallet'] ?? responseData['wallet'] ?? 0,
          'sRefWallet': responseData['sRefWallet'] ?? 0,
          'sType': responseData['sType'] ?? responseData['type'] ?? 1,
          'sBankNo': responseData['sBankNo'] ?? responseData['bankNo'],
          'sSterlingBank':
              responseData['sSterlingBank'] ?? responseData['sterlingBank'],
          'sBankName': responseData['sBankName'] ?? responseData['bankName'],
          'sRegStatus':
              responseData['sRegStatus'] ?? responseData['regStatus'] ?? 0,
        };
        print('Formatted user data to save: ${json.encode(userData)}');
        await saveUserData(userData);

        // Save user ID separately for consistent access
        final prefs = await _prefs;
        await prefs.setString(_userIdKey, userData['sId']);
        print('Saved user_id to SharedPreferences: ${userData['sId']}');

        // Verify what was saved
        print('\n=== Verifying Saved Data ===');
        print('Stored user_id: ${prefs.getString(_userIdKey)}');
        print('Stored user_data: ${prefs.getString(_userKey)}');
        print('========================\n');

        return {
          'success': true,
          'message': responseData['message'],
          'user': userData,
        };
      } else {
        return {
          'success': false,
          'message': responseData['message'] ?? 'Login failed',
        };
      }
    } catch (e) {
      return {
        'success': false,
        'message': 'An error occurred during login: ${e.toString()}',
      };
    }
  }

  // Check if user is logged in
  Future<bool> isLoggedIn() async {
    final prefs = await _prefs;
    final userId = prefs.getString(_userIdKey);
    return userId != null;
  }

  // Get the current user ID
  Future<String?> getUserId() async {
    try {
      final prefs = await _prefs;
      // First try to get the direct user ID
      final directUserId = prefs.getString(_userIdKey);
      print(
        'Direct user_id from SharedPreferences: $directUserId',
      ); // Debug log

      // Also check the user data
      final userData = prefs.getString(_userKey);
      print('Raw user_data from SharedPreferences: $userData'); // Debug log

      if (userData != null) {
        final user = json.decode(userData);
        final userId = user['sId']?.toString();
        print('Extracted user ID from user_data: $userId'); // Debug log
        return userId;
      } else if (directUserId != null) {
        print('Using direct user ID: $directUserId'); // Debug log
        return directUserId;
      }
      print('No user ID found in any storage location'); // Debug log
      return null;
    } catch (e) {
      print('Error getting user ID: $e'); // Debug log
      return null;
    }
  }

  // Get network statuses to determine which networks are enabled/disabled
  Future<Map<String, dynamic>> getNetworkStatuses() async {
    try {
      final response = await _withTimeout(
        http.get(Uri.parse('$baseUrl/api/network-status')),
      );

      if (response.statusCode == 200) {
        final responseData = jsonDecode(response.body);
        print('Network statuses raw response: $responseData');

        // Handle both direct array response and wrapped response with data field
        List<dynamic> data = [];
        if (responseData is List) {
          data = responseData;
        } else if (responseData is Map && responseData['data'] is List) {
          data = responseData['data'];
        }

        print('Extracted data list: $data');

        if (data.isNotEmpty) {
          // Convert list to map for easier lookup by network name
          final statusMap = <String, Map<String, dynamic>>{};
          for (final item in data) {
            if (item is Map && item['network'] != null) {
              final networkName = item['network'].toString().toUpperCase();
              statusMap[networkName] = {
                'networkStatus': item['networkStatus'] ?? 'Off',
                'vtuStatus': item['vtuStatus'] ?? 'Off',
                'datapinStatus': item['datapinStatus'] ?? 'Off',
                'airtimepinStatus': item['airtimepinStatus'] ?? 'Off',
                'smeStatus': item['smeStatus'] ?? 'Off',
                'sme2Status': item['sme2Status'] ?? 'Off',
                'giftingStatus': item['giftingStatus'] ?? 'Off',
                'corporateStatus': item['corporateStatus'] ?? 'Off',
                'couponStatus': item['couponStatus'] ?? 'Off',
                'sharesellStatus': item['sharesellStatus'] ?? 'Off',
              };
              print('Network $networkName status: ${statusMap[networkName]}');
            }
          }
          print('Final parsed network statuses map: $statusMap');
          return statusMap;
        }
      }
      return {};
    } catch (e) {
      print('Error fetching network statuses: $e');
      return {}; // Return empty map on error, don't block UI
    }
  }

  // Purchase Airtime
  Future<Map<String, dynamic>> purchaseAirtime({
    required String phone,
    required String amount,
    required String network,
    required String pin,
  }) async {
    try {
      final userId = await getUserId();
      print('Using user ID for purchase: $userId'); // Debug log

      if (userId == null) {
        print('Purchase failed: No user ID available'); // Debug log
        return {'success': false, 'message': 'User not logged in'};
      }

      // Debug log the request we're about to make
      print('Preparing purchase request with data:');
      print('network: $network');
      print('phone: $phone');
      print('amount: $amount');
      print('user_id: $userId');

      // Verify transaction PIN
      final prefs = await _prefs;
      final storedPin = prefs.getString('login_pin');

      if (storedPin == null || storedPin != pin) {
        return {'success': false, 'message': 'Invalid transaction PIN'};
      }

      // The API endpoint might need to include /VTU-API
      final apiUrl = '$baseUrl/api/airtime';
      print('Making API request to: $apiUrl');

      // Debug: Print the exact request being sent
      final requestBody = {
        'network': network,
        'phone': phone,
        'amount': amount,
        'user_id': userId,
      };
      print('Request body: ${jsonEncode(requestBody)}');

      final response = await _withTimeout(
        _client.post(
          Uri.parse(apiUrl),
          headers: {
            'Content-Type': 'application/json',
            'Accept': 'application/json',
          },
          body: jsonEncode(requestBody),
        ),
      );

      // Debug log
      print('Response status code: ${response.statusCode}');
      print('Response body: ${response.body}');

      // Handle empty response
      if (response.body.trim().isEmpty) {
        return {
          'success': false,
          'message': 'No response received from server',
        };
      }

      // Check if response is HTML
      if (response.body.trim().startsWith('<!DOCTYPE html>') ||
          response.body.trim().startsWith('<html>')) {
        return {
          'success': false,
          'message': 'Invalid response format from server',
        };
      }

      Map<String, dynamic> responseData;
      try {
        responseData = jsonDecode(response.body);
      } catch (e) {
        return {
          'success': false,
          'message': 'Invalid JSON response from server',
        };
      }

      if (response.statusCode == 200) {
        if (responseData['status'] == 'success') {
          return {
            'success': true,
            'message': responseData['message'],
            'reference': responseData['reference'],
            'data': responseData['data'],
          };
        } else if (responseData['status'] == 'processing') {
          return {
            'success': true,
            'message': 'Transaction is processing',
            'reference': responseData['reference'],
            'status': 'processing',
            'data': responseData['data'],
          };
        } else {
          return {
            'success': false,
            'message': responseData['message'] ?? 'Transaction failed',
          };
        }
      } else {
        throw Exception(
          responseData['message'] ?? 'Failed to purchase airtime',
        );
      }
    } catch (e) {
      // Ensure we return a message string in known format
      final msg = e is Exception ? e.toString() : '$e';
      return {'success': false, 'message': msg};
    }
  }

  Future<Map<String, dynamic>> get(String endpoint) async {
    try {
      // If the endpoint starts with 'auth/', don't append 'api/'
      final url = endpoint.startsWith('auth/')
          ? '$baseUrl/$endpoint'
          : '$baseUrl/api/$endpoint';
      _printRequestDetails('GET', endpoint);
      final response = await _withTimeout(
        _client.get(
          Uri.parse(url),
          headers: {
            'Content-Type': 'application/json',
            // Add any other headers like authentication tokens here
          },
        ),
      );

      return _handleResponse(response);
    } catch (e) {
      throw Exception('Failed to make GET request: $e');
    }
  }

  /// Fetch manual payment records from the API.
  /// If [userId] is provided it will be passed as a query parameter.
  /// Returns a List of payments on success.
  Future<List<dynamic>> getManualPayments({String? userId}) async {
    try {
      String endpoint = 'manual-payments';
      if (userId != null && userId.isNotEmpty) {
        endpoint = '$endpoint?user_id=$userId';
      }

      final res = await get(endpoint);

      if (res['status'] == 'success') {
        final data = res['data'];
        if (data == null) return [];
        return data is List ? data : [data];
      }

      throw Exception(res['message'] ?? 'Failed to fetch manual payments');
    } catch (e) {
      throw Exception('Error fetching manual payments: $e');
    }
  }

  /// Convenience: fetch manual payments for the currently logged-in user.
  Future<List<dynamic>> getMyManualPayments() async {
    final userId = await getUserId();
    return getManualPayments(userId: userId);
  }

  /// Fetch a single active manual payment destination from the API.
  /// Returns a Map with keys 'account_name', 'account_number', 'bank_name' or null.
  Future<Map<String, dynamic>?> getActiveManualPayment({String? bank}) async {
    try {
      String endpoint = 'manual-payment';
      if (bank != null && bank.isNotEmpty) {
        endpoint += '?bank=${Uri.encodeQueryComponent(bank)}';
      }

      final res = await get(endpoint);

      if (res['status'] == 'success' && res['data'] != null) {
        final data = res['data'];
        return data is Map<String, dynamic>
            ? data
            : Map<String, dynamic>.from(data);
      }

      return null;
    } catch (e) {
      print('Error getting active manual payment: $e');
      return null;
    }
  }

  /// Send manual payment proof via API. Automatically includes logged-in user id when available.
  Future<Map<String, dynamic>> sendManualProof({
    required double amount,
    required String bank,
    required String sender,
    String? accountNumber,
    String? accountName,
    String? bankName,
  }) async {
    try {
      final userId = await getUserId();
      final body = {
        'amount': amount,
        'bank': bank,
        'sender': sender,
        'account_number': accountNumber ?? '',
        'account_name': accountName ?? '',
        'bank_name': bankName ?? '',
      };
      if (userId != null && userId.isNotEmpty) {
        body['user_id'] = userId;
      }

      return await post('send-manual-proof', body);
    } catch (e) {
      throw Exception('Failed to send manual proof: $e');
    }
  }

  // Purchase Data
  Future<Map<String, dynamic>> purchaseData({
    required String phone,
    required String planId,
    required String network,
    required String pin,
  }) async {
    try {
      final userId = await getUserId();
      print('Using user ID for purchase: $userId');

      if (userId == null) {
        throw Exception('User not logged in');
      }

      // Verify transaction PIN
      final prefs = await SharedPreferences.getInstance();
      final storedPin = prefs.getString('login_pin');

      if (storedPin == null || storedPin != pin) {
        throw Exception('Invalid transaction PIN');
      }

      // Debug log the request we're about to make
      print('Preparing data purchase request with data:');
      print('network: $network');
      print('phone: $phone');
      print('planId: $planId');
      print('user_id: $userId');

      final response = await _withTimeout(
        _client.post(
          Uri.parse('$baseUrl/api/purchase-data'),
          headers: {'Content-Type': 'application/json'},
          body: json.encode({
            'network': network,
            'mobile_number': phone,
            'plan': planId,
            'user_id': userId,
            'Ported_number': true,
          }),
        ),
      );

      print('Response status code: ${response.statusCode}');
      print('Response body: ${response.body}');

      if (response.statusCode == 200) {
        final responseData = json.decode(response.body);

        if (responseData['status'] == 'success') {
          return responseData;
        } else {
          throw Exception(responseData['message'] ?? 'Failed to purchase data');
        }
      } else {
        // Try to extract server-provided message from body
        String msg = 'Request failed (status ${response.statusCode})';
        try {
          final errorData = json.decode(response.body);
          if (errorData is Map && errorData['message'] != null) {
            msg = errorData['message'].toString();
          }
        } catch (_) {}
        throw Exception(msg);
      }
    } catch (e) {
      print('Error during data purchase: $e');
      rethrow;
    }
  }

  // Fetch Electricity Providers
  Future<Map<String, dynamic>> getElectricityProviders() async {
    try {
      final response = await _withTimeout(
        _client.get(
          Uri.parse('$baseUrl/api/electricity-providers'),
          headers: {'Content-Type': 'application/json'},
        ),
      );

      return _handleResponse(response);
    } catch (e) {
      throw Exception('Failed to fetch electricity providers: $e');
    }
  }

  Future<Map<String, dynamic>> getCableProviders() async {
    try {
      final response = await _withTimeout(
        _client.get(
          Uri.parse('$baseUrl/api/cable-providers'),
          headers: {'Content-Type': 'application/json'},
        ),
      );

      return _handleResponse(response);
    } catch (e) {
      throw Exception('Failed to fetch cable providers: $e');
    }
  }

  Future<Map<String, dynamic>> getCablePlans({String? providerId}) async {
    try {
      String url = '$baseUrl/api/cable-plans';
      if (providerId != null) {
        url += '?provider=$providerId';
      }

      final response = await _withTimeout(
        _client.get(
          Uri.parse(url),
          headers: {'Content-Type': 'application/json'},
        ),
      );

      return _handleResponse(response);
    } catch (e) {
      throw Exception('Failed to fetch cable plans: $e');
    }
  }

  /// Purchase a cable subscription by calling the backend `cable-subscription` endpoint.
  /// Expects the logged-in user to be present; verifies the stored transaction PIN before sending.
  Future<Map<String, dynamic>> purchaseCable({
    required String providerId,
    required String planId,
    required String iucNumber,
    required String phoneNumber,
    required String amount,
    required String pin,
  }) async {
    try {
      final userId = await getUserId();
      print('Using user ID for cable purchase: $userId');

      if (userId == null) {
        throw Exception('User not logged in');
      }

      // Verify transaction PIN (client stores a copy in prefs)
      final prefs = await _prefs;
      final storedPin = prefs.getString('login_pin');
      if (storedPin == null || storedPin != pin) {
        throw Exception('Invalid transaction PIN');
      }

      final url = '$baseUrl/api/cable-subscription';
      final body = {
        'providerId': providerId,
        'planId': planId,
        'iucNumber': iucNumber,
        'phoneNumber': phoneNumber,
        'amount': amount,
        'pin': pin,
        'userId': userId,
      };

      print(
        'Making cable purchase request to $url with body: ${jsonEncode(body)}',
      );

      final response = await _withTimeout(
        _client.post(
          Uri.parse(url),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode(body),
        ),
      );

      print('Cable purchase response code: ${response.statusCode}');
      print('Cable purchase response body: ${response.body}');

      // If server returned validation details (400) or insufficient balance (402), parse and return them
      if (response.statusCode == 400 || response.statusCode == 402) {
        try {
          final parsed = jsonDecode(response.body);
          if (parsed is Map<String, dynamic>) {
            final Map<String, dynamic> out = Map<String, dynamic>.from(parsed);
            out['code'] = response.statusCode;
            return out;
          }
          return {'status': 'error', 'message': response.body};
        } catch (e) {
          return {'status': 'error', 'message': response.body};
        }
      }

      return _handleResponse(response);
    } catch (e) {
      throw Exception('Failed to purchase cable: $e');
    }
  }

  Future<Map<String, dynamic>> purchaseElectricity({
    required String meterNumber,
    required String providerId,
    required String amount,
    required String pin,
    required String meterType,
    required String phone,
  }) async {
    try {
      final userId = await getUserId();
      if (userId == null) {
        throw Exception('User not logged in');
      }

      // Verify transaction PIN
      final prefs = await SharedPreferences.getInstance();
      final storedPin = prefs.getString('login_pin');

      if (storedPin == null || storedPin != pin) {
        throw Exception('Invalid transaction PIN');
      }

      final response = await _withTimeout(
        _client.post(
          Uri.parse('$baseUrl/api/purchase-electricity'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'meterNumber': meterNumber,
            'providerId': providerId,
            'amount': amount,
            'meterType': meterType,
            'phone': phone,
            'userId': userId,
          }),
        ),
      );

      // If the server returned a 400 with validation details, parse and return
      if (response.statusCode == 400) {
        try {
          final parsed = json.decode(response.body);
          if (parsed is Map<String, dynamic>) {
            // Include the HTTP status code so callers can distinguish validation
            // responses from other error shapes.
            final Map<String, dynamic> out = Map<String, dynamic>.from(parsed);
            out['code'] = response.statusCode;
            return out;
          }
        } catch (_) {
          // fall through to handler
        }
      }

      // If the server returned a 402 (Payment Required / Insufficient balance), parse and return
      if (response.statusCode == 402) {
        try {
          final parsed = json.decode(response.body);
          if (parsed is Map<String, dynamic>) {
            // Attach the HTTP code so UI can treat 402 specially (user wallet insufficient)
            final Map<String, dynamic> out = Map<String, dynamic>.from(parsed);
            out['code'] = response.statusCode;
            return out;
          }
        } catch (_) {
          // fall through to handler
        }
      }

      return _handleResponse(response);
    } catch (e) {
      throw Exception('Failed to purchase electricity: $e');
    }
  }

  Future<Map<String, dynamic>> validateMeterNumber({
    required String meterNumber,
    required String providerId,
    required String meterType,
  }) async {
    try {
      final response = await _client.post(
        Uri.parse('$baseUrl/api/validate-meter'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'meterNumber': meterNumber,
          'providerId': providerId,
          'meterType': meterType,
        }),
      );

      // let the generic handler parse/validate JSON and status codes
      final Map<String, dynamic> parsed = _handleResponse(response);

      // Normalize common response shapes to a consistent contract:
      // Case A: Strowallet-like direct response (passthrough)
      if (parsed.containsKey('success') &&
          (parsed.containsKey('customer_name') ||
              parsed.containsKey('address'))) {
        final bool ok =
            parsed['success'] == true || parsed['success'] == 'true';
        final Map<String, dynamic> data = {
          'name': (parsed['customer_name'] ?? '')?.toString().trim() ?? '',
          'address': (parsed['address'] ?? '')?.toString().trim() ?? '',
          'meter_number':
              (parsed['meter_number'] ?? '')?.toString() ?? meterNumber,
          'provider': '',
        };
        return {
          'status': ok ? 'success' : 'error',
          'message': parsed['message'] ?? '',
          'data': data,
        };
      }

      // Case B: API wrapper returns {'status': 'success', 'data': {...}}
      if (parsed.containsKey('status') &&
          parsed['status'] == 'success' &&
          parsed.containsKey('data')) {
        final dynamic d = parsed['data'];
        if (d is Map<String, dynamic>) {
          final Map<String, dynamic> data = {
            'name':
                (d['name'] ?? d['customer_name'] ?? '')?.toString().trim() ??
                '',
            'address':
                (d['address'] ?? d['customer_address'] ?? '')
                    ?.toString()
                    .trim() ??
                '',
            'meter_number':
                (d['meter_number'] ?? d['meterNumber'] ?? '')?.toString() ??
                meterNumber,
            'provider': d['provider']?.toString() ?? '',
            'invalid': d['invalid'] ?? false,
          };
          return {
            'status': 'success',
            'message': parsed['message'] ?? '',
            'data': data,
          };
        }
      }

      // Fallback: return parsed as-is
      return parsed;
    } catch (e) {
      throw Exception('Failed to validate meter number: $e');
    }
  }

  // Fetch Data Pin Plans
  Future<Map<String, dynamic>> getDataPinPlans({
    String? network,
    String? type,
  }) async {
    try {
      String endpoint = 'data-pin-plans';
      if (network != null || type != null) {
        endpoint += '?';
        if (network != null) endpoint += 'network=$network';
        if (type != null) endpoint += '${network != null ? "&" : ""}type=$type';
      }

      final response = await _client.get(
        Uri.parse('$baseUrl/api/$endpoint'),
        headers: {'Accept': 'application/json'},
      );

      return _handleResponse(response);
    } catch (e) {
      print('Error fetching data pin plans: $e');
      throw Exception('Failed to fetch data pin plans: $e');
    }
  }

  Future<Map<String, dynamic>> purchaseDataPin({
    required String planId,
    required int quantity,
    required String nameOnCard,
    required String pin,
  }) async {
    try {
      final userId = await getUserId();
      if (userId == null) {
        throw Exception('User not logged in');
      }

      // Verify transaction PIN
      final prefs = await SharedPreferences.getInstance();
      final storedPin = prefs.getString('login_pin');

      if (storedPin == null || storedPin != pin) {
        throw Exception('Invalid transaction PIN');
      }

      print('Making data pin purchase request with:');
      print('plan: $planId');
      print('quantity: $quantity');
      print('name_on_card: $nameOnCard');
      print('userId: $userId');

      final response = await _client.post(
        Uri.parse('$baseUrl/api/purchase-data-pin'),
        headers: {
          'Accept': 'application/json',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'plan': planId,
          'quantity': quantity,
          'name_on_card': nameOnCard,
          'userId': userId,
        }),
      );

      return _handleResponse(response);
    } catch (e) {
      print('Error purchasing data pin: $e');
      throw Exception('Failed to purchase data pin: $e');
    }
  }

  Future<Map<String, dynamic>> getTransactionStatus(
    String transactionId,
  ) async {
    try {
      final userId = await getUserId();

      if (userId == null) {
        throw Exception('User not logged in');
      }

      final response = await _client.get(
        Uri.parse(
          '$baseUrl/api/transaction-status?id=$transactionId&user_id=$userId',
        ),
      );

      final responseData = jsonDecode(response.body);

      if (response.statusCode == 200) {
        return responseData;
      } else {
        throw Exception(
          responseData['message'] ?? 'Failed to get transaction status',
        );
      }
    } catch (e) {
      return {'status': 'error', 'message': e.toString()};
    }
  }

  // Fetch exam providers
  Future<Map<String, dynamic>> getExamProviders() async {
    try {
      final response = await _client.get(
        Uri.parse('$baseUrl/api/exam-providers'),
        headers: {
          'Accept': 'application/json',
          'Content-Type': 'application/json',
        },
      );

      print('Exam providers response: ${response.body}');

      if (response.statusCode == 200) {
        final decodedResponse = json.decode(response.body);
        if (decodedResponse['status'] == 'success') {
          // Check if data field exists and is not null
          final data = decodedResponse['data'];
          if (data != null) {
            return {
              'status': 'success',
              'message': decodedResponse['message'],
              'data': data is List
                  ? data
                  : [data], // Ensure data is always a list
            };
          }
        }
        throw Exception(
          decodedResponse['message'] ?? 'Failed to fetch exam providers',
        );
      }
      throw Exception('Failed to fetch exam providers');
    } catch (e) {
      return {
        'status': 'error',
        'message': 'Failed to fetch exam providers: $e',
        'data': [],
      };
    }
  }

  // Purchase exam pin
  Future<Map<String, dynamic>> purchaseExamPin({
    required String examId,
    required int quantity,
    required String pin,
  }) async {
    try {
      final userId = await getUserId();
      if (userId == null) {
        throw Exception('User not logged in');
      }

      // Verify transaction PIN
      final prefs = await SharedPreferences.getInstance();
      final storedPin = prefs.getString('login_pin');

      if (storedPin == null || storedPin != pin) {
        throw Exception('Invalid transaction PIN');
      }

      final response = await _client.post(
        Uri.parse('$baseUrl/api/exam-purchase'),
        headers: {
          'Accept': 'application/json',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'examId': examId,
          'quantity': quantity,
          'userId': userId,
          'pin': pin,
        }),
      );

      print('Exam purchase response: ${response.body}');
      return _handleResponse(response);
    } catch (e) {
      print('Error purchasing exam pin: $e');
      throw Exception('Failed to purchase exam pin: $e');
    }
  }

  Future<Map<String, dynamic>> post(
    String endpoint,
    Map<String, dynamic> body,
  ) async {
    try {
      // If the endpoint starts with 'auth/', don't append 'api/'
      final url = endpoint.startsWith('auth/')
          ? '$baseUrl/$endpoint'
          : '$baseUrl/api/$endpoint';
      _printRequestDetails('POST', endpoint, body);
      final response = await _withTimeout(
        _client.post(
          Uri.parse(url),
          headers: {
            'Content-Type': 'application/json',
            'Accept': 'application/json',
          },
          body: json.encode(body),
        ),
      );

      // Special-case auth endpoints: return parsed JSON even on non-2xx so
      // callers (e.g., AuthService.login) can read the server 'message'
      if (endpoint.startsWith('auth/')) {
        try {
          final parsed = json.decode(response.body);
          return parsed is Map<String, dynamic>
              ? parsed
              : {'message': parsed.toString()};
        } catch (e) {
          // If parsing fails, try to return any plain text body or a generic message
          String msg = 'Request failed (status ${response.statusCode})';
          try {
            if (response.body.trim().isNotEmpty) msg = response.body.trim();
          } catch (_) {}
          return {'message': msg, 'statusCode': response.statusCode};
        }
      }

      return _handleResponse(response);
    } on SocketException {
      // Network-level error
      throw Exception('Network error: Please check your internet connection.');
    } on TimeoutException {
      throw Exception('Request timed out. Please try again.');
    } catch (e) {
      throw Exception('Failed to make POST request: $e');
    }
  }

  Map<String, dynamic> _handleResponse(http.Response response) {
    print('Response status code: ${response.statusCode}'); // Debug log
    print('Response body: ${response.body}'); // Debug log

    try {
      final responseData = json.decode(response.body);
      if (response.statusCode >= 200 && response.statusCode < 300) {
        return responseData;
      } else {
        // Prefer the explicit message field; otherwise fallback to an error key
        final errorMessage = (responseData is Map)
            ? (responseData['message'] ??
                  responseData['error'] ??
                  'An error occurred')
            : 'An error occurred';
        // Throw only the server-provided message so UI shows a concise message
        throw Exception(errorMessage);
      }
    } catch (e) {
      // Failed to parse JSON response
      if (response.statusCode >= 200 && response.statusCode < 300) {
        throw Exception('Failed to parse response from server');
      } else {
        // When parsing fails for an error response, try to extract a plain message
        String msg = 'Request failed (status ${response.statusCode})';
        try {
          if (response.body.trim().isNotEmpty) msg = response.body.trim();
        } catch (_) {}
        throw Exception(msg);
      }
    }
  }

  Future<void> clearAuth() async {
    final prefs = await _prefs;
    await prefs.remove(_userIdKey);
    await prefs.remove(_userKey);
  }

  Future<void> saveUserData(Map<String, dynamic> userData) async {
    try {
      final prefs = await _prefs;

      // Get user ID for making API call
      final userId = userData['sId']?.toString() ?? userData['id']?.toString();
      if (userId != null) {
        // Fetch fresh user data from API
        final response = await _client.get(
          Uri.parse('$baseUrl/api/subscriber/$userId'),
          headers: {'Content-Type': 'application/json'},
        );

        if (response.statusCode == 200) {
          final apiResponse = json.decode(response.body);
          if (apiResponse['status'] == 'success' &&
              apiResponse['data'] != null) {
            // Update userData with API response data, preserving any additional fields
            userData = apiResponse['data'];
          }
        }
      }

      // Save the complete data
      await prefs.setString(_userKey, json.encode(userData));
      print('Saved user data to SharedPreferences: ${json.encode(userData)}');

      // Also save user ID separately for consistency
      if (userId != null) {
        await prefs.setString(_userIdKey, userId);
      }

      // Initialize biometric as enabled
      await prefs.setBool('biometric_enabled', true);
    } catch (e) {
      print('Error saving user data: $e');
      // Still try to save the original data if API call fails
      final prefs = await _prefs;
      await prefs.setString(_userKey, json.encode(userData));
    }
  }

  Future<Map<String, dynamic>?> getUserData() async {
    try {
      final prefs = await _prefs;
      final userJson = prefs.getString(_userKey);

      if (userJson != null) {
        final userData = json.decode(userJson);
        final userId =
            userData['sId']?.toString() ?? userData['id']?.toString();

        if (userId != null) {
          // Fetch fresh data from API
          final response = await _client.get(
            Uri.parse('$baseUrl/api/subscriber/$userId'),
            headers: {'Content-Type': 'application/json'},
          );

          if (response.statusCode == 200) {
            final apiResponse = json.decode(response.body);
            if (apiResponse['status'] == 'success' &&
                apiResponse['data'] != null) {
              // Save and return the fresh data
              final freshData = apiResponse['data'];
              await saveUserData(freshData);
              return freshData;
            }
          }
        }
        // Return cached data if API call fails
        return userData;
      }
    } catch (e) {
      print('Error in getUserData: $e');
      // Return null on error
      return null;
    }
    return null;
  }

  void dispose() {
    _client.close();
  }
}
