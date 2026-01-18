<?php
/**
 * Site Settings API Endpoint
 * Retrieves contact information and site configuration
 */

header('Content-Type: application/json; charset=UTF-8');
header("Access-Control-Allow-Origin: *");
header("Access-Control-Allow-Methods: GET, OPTIONS");
header("Access-Control-Allow-Headers: Content-Type");

// Handle preflight requests
if ($_SERVER['REQUEST_METHOD'] === 'OPTIONS') {
    http_response_code(200);
    exit();
}

try {
    $request_method = $_SERVER['REQUEST_METHOD'];
    $action = $_GET['action'] ?? 'contact';
    
    // Handle GET requests
    if ($request_method === 'GET') {
        switch ($action) {
            case 'contact':
                // Return contact information
                http_response_code(200);
                echo json_encode([
                    'status' => 'success',
                    'message' => 'Contact information retrieved successfully',
                    'data' => [
                        'email' => 'support@mkdata.com.ng',
                        'phone' => '+234 701 234 5678',
                        'whatsapp' => '234701234567',
                        'facebook' => 'https://facebook.com/mkdata',
                        'twitter' => 'https://twitter.com/mkdata',
                        'instagram' => 'https://instagram.com/mkdata',
                        'linkedin' => 'https://linkedin.com/company/mkdata',
                    ]
                ]);
                break;
                
            case 'faq':
                // Return FAQ content
                http_response_code(200);
                echo json_encode([
                    'status' => 'success',
                    'message' => 'FAQ retrieved successfully',
                    'data' => [
                        [
                            'question' => 'How do I buy airtime?',
                            'answer' => 'To buy airtime, go to the Airtime section, enter your phone number, select your network and amount, and confirm the transaction. Your airtime will be delivered instantly.'
                        ],
                        [
                            'question' => 'What networks are supported?',
                            'answer' => 'We support all major Nigerian networks: MTN, Airtel, Glo Mobile, and 9Mobile. You can buy airtime, data, and other services from these networks.'
                        ],
                        [
                            'question' => 'How long does delivery take?',
                            'answer' => 'Most services are delivered instantly (within seconds). If there\'s a delay, our support team will assist you.'
                        ],
                        [
                            'question' => 'What is the Spin and Win feature?',
                            'answer' => 'Spin and Win is a feature where you can spin daily to win rewards like airtime, data, or cash. You get one free spin per day.'
                        ],
                        [
                            'question' => 'How do I track my transactions?',
                            'answer' => 'You can view all your transactions in the Transactions page. Each transaction has a reference ID that you can use to track your order.'
                        ],
                        [
                            'question' => 'Is my payment information safe?',
                            'answer' => 'Yes, we use industry-standard encryption and security measures to protect your payment information. Your data is never shared with third parties.'
                        ],
                        [
                            'question' => 'Can I get a refund?',
                            'answer' => 'Refunds are processed within 24-48 hours for failed transactions. Contact our support team if you need assistance.'
                        ],
                        [
                            'question' => 'How do I contact support?',
                            'answer' => 'You can reach our support team via email, phone, WhatsApp, or live chat. We\'re available 24/7 to assist you.'
                        ],
                    ]
                ]);
                break;
                
            default:
                // Default: return contact info
                http_response_code(200);
                echo json_encode([
                    'status' => 'success',
                    'message' => 'Contact information retrieved successfully',
                    'data' => [
                        'email' => 'support@mkdata.com.ng',
                        'phone' => '+234 701 234 5678',
                        'whatsapp' => '234701234567',
                        'facebook' => 'https://facebook.com/mkdata',
                        'twitter' => 'https://twitter.com/mkdata',
                        'instagram' => 'https://instagram.com/mkdata',
                        'linkedin' => 'https://linkedin.com/company/mkdata',
                    ]
                ]);
                break;
        }
    } else {
        http_response_code(405);
        echo json_encode([
            'status' => 'error',
            'message' => 'Method not allowed. Only GET requests are supported.'
        ]);
    }
    
} catch (Exception $e) {
    error_log("API Error: " . $e->getMessage());
    http_response_code(500);
    echo json_encode([
        'status' => 'error',
        'message' => 'Internal server error: ' . $e->getMessage()
    ]);
}
?>
