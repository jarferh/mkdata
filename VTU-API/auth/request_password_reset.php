<?php
error_reporting(E_ALL);
ini_set('display_errors', 1);
date_default_timezone_set('Africa/Lagos'); // Set timezone for Nigeria
header("Access-Control-Allow-Origin: *");
header("Content-Type: application/json; charset=UTF-8");
header("Access-Control-Allow-Methods: POST");
header("Access-Control-Max-Age: 3600");
header("Access-Control-Allow-Headers: Content-Type, Access-Control-Allow-Headers, Authorization, X-Requested-With");

require_once __DIR__ . '/../config/database.php';
require_once __DIR__ . '/../vendor/autoload.php'; // For PHPMailer
require_once __DIR__ . '/../auth/session-helper.php';

use Binali\Config\Database;
use PHPMailer\PHPMailer\PHPMailer;
use PHPMailer\PHPMailer\SMTP;
use PHPMailer\PHPMailer\Exception;

// Load environment variables
loadEnvFile(__DIR__ . '/../.env');

// Rate limiting using sessions
session_start();
$current_time = time();
$timeout = 300; // 5 minutes timeout
$max_attempts = 3;

if (isset($_SESSION['reset_attempts'])) {
    // Clear old attempts
    foreach ($_SESSION['reset_attempts'] as $time => $count) {
        if ($current_time - $time > $timeout) {
            unset($_SESSION['reset_attempts'][$time]);
        }
    }
}

// Count recent attempts
$recent_attempts = 0;
if (isset($_SESSION['reset_attempts'])) {
    foreach ($_SESSION['reset_attempts'] as $count) {
        $recent_attempts += $count;
    }
}

if ($recent_attempts >= $max_attempts) {
    http_response_code(429);
    echo json_encode([
        "status" => "error",
        "message" => "Too many reset attempts. Please try again later."
    ]);
    exit();
}

// Get posted data
$data = json_decode(file_get_contents("php://input"));

if (!isset($data->email)) {
    http_response_code(400);
    echo json_encode([
        "status" => "error",
        "message" => "Email is required"
    ]);
    exit();
}

$email = filter_var($data->email, FILTER_SANITIZE_EMAIL);

if (!filter_var($email, FILTER_VALIDATE_EMAIL)) {
    http_response_code(400);
    echo json_encode([
        "status" => "error",
        "message" => "Invalid email format"
    ]);
    exit();
}

try {
    $database = new Database();
    $db = $database->getConnection();

    if (!$db) {
        throw new Exception("Database connection failed");
    }

    // Check if email exists in subscribers table
    $check_query = "SELECT sId, sEmail FROM subscribers WHERE sEmail = ? LIMIT 1";
    $check_stmt = $db->prepare($check_query);
    
    if (!$check_stmt) {
        throw new Exception("Failed to prepare query");
    }
    
    $execute_result = $check_stmt->execute([$email]);
    
    if (!$execute_result) {
        throw new Exception("Failed to execute query");
    }

    if ($check_stmt->rowCount() == 0) {
        // Don't reveal that the email doesn't exist
        http_response_code(200);
        echo json_encode([
            "status" => "success",
            "message" => "If your email is registered, you will receive reset instructions shortly."
        ]);
        exit();
    }

    // Generate secure random token
    $token = bin2hex(random_bytes(32));
    $expires_at = date('Y-m-d H:i:s', strtotime('+1 day'));

    // Delete any existing reset tokens for this email
    $delete_query = "DELETE FROM password_resets WHERE email = ?";
    $delete_stmt = $db->prepare($delete_query);
    
    if ($delete_stmt) {
        $delete_stmt->execute([$email]);
    }

    // Insert new reset token
    $insert_query = "INSERT INTO password_resets (email, token, expires_at) VALUES (?, ?, ?)";
    $insert_stmt = $db->prepare($insert_query);
    
    if (!$insert_stmt) {
        throw new Exception("Failed to prepare insert");
    }
    
    $insert_result = $insert_stmt->execute([$email, $token, $expires_at]);
    
    if (!$insert_result) {
        throw new Exception("Failed to insert reset token");
    }

    // Record this attempt
    $_SESSION['reset_attempts'][$current_time] = 1;

    // Log password reset attempt
    error_log('[PASSWORD_RESET] Processing reset for: ' . $email);

    // Send email using PHPMailer
    $mail = new PHPMailer(true);

    try {
        // Server settings
        $mail->isSMTP();
        $mail->Host = getenv('MAIL_HOST') ?: 'mail.mkdata.com.ng';
        $mail->SMTPAuth = true;
        $mail->Username = getenv('MAIL_USERNAME') ?: 'no-reply@mkdata.com.ng';
        $mail->Password = getenv('MAIL_PASSWORD') ?: ']xG28YL,APm-+xbx';
        
        if (!$mail->Password) {
            error_log('[PASSWORD_RESET_ERROR] MAIL_PASSWORD not configured in environment');
            throw new Exception('MAIL_PASSWORD not configured in environment');
        }

        // Use STARTTLS for port 587, SMTPS for port 465
        $mailPort = (int)(getenv('MAIL_PORT') ?: 587);
        if ($mailPort == 465) {
            $mail->SMTPSecure = PHPMailer::ENCRYPTION_SMTPS;
        } else {
            $mail->SMTPSecure = PHPMailer::ENCRYPTION_STARTTLS;
        }
        $mail->Port = $mailPort;
        
        // Add timeout to prevent hanging
        $mail->Timeout = 10;
        $mail->SMTPKeepAlive = true;
        
        // Disable debugging in production
        $mail->SMTPDebug = 0;
        $mail->Debugoutput = function($str, $level) {
            // Silent - debugging disabled
        };

        error_log('[PASSWORD_RESET] SMTP Config - Host: ' . $mail->Host . ', Port: ' . $mail->Port . ', Encryption: ' . ($mailPort == 465 ? 'SMTPS' : 'STARTTLS'));

        $mail->setFrom(getenv('MAIL_USERNAME') ?: 'no-reply@mkdata.com.ng', 'MK DATA');
        $mail->addAddress($email);
        error_log('[PASSWORD_RESET] Email recipient added: ' . $email);

        // Content
        $mail->isHTML(true);
        $mail->Subject = 'Password Reset Request';

        $reset_link = "http://api.mkdata.com.ng/reset-password.php?token=" . $token;

        $mail->Body = "
            <html>
            <body style='font-family: Arial, sans-serif; background-color: #f5f5f5;'>
                <div style='max-width: 600px; margin: 0 auto; background-color: white; padding: 20px; border-radius: 8px;'>
                    <div style='background-color: #ce4323; padding: 20px; text-align: center; border-radius: 8px 8px 0 0;'>
                        <h1 style='color: white; margin: 0;'>Password Reset Request</h1>
                    </div>
                    <div style='padding: 20px;'>
                        <p style='color: #333; font-size: 16px;'>We received a request to reset your password. Click the button below to set a new password:</p>
                        <p style='text-align: center; margin: 30px 0;'>
                            <a href='{$reset_link}' 
                               style='background-color: #ce4323; 
                                      color: white; 
                                      padding: 12px 30px; 
                                      text-decoration: none; 
                                      border-radius: 5px;
                                      display: inline-block;
                                      font-weight: bold;
                                      font-size: 16px;'>
                                Reset Password
                            </a>
                        </p>
                        <p style='color: #666; font-size: 14px;'><strong>Note:</strong> This link will expire in 24 hours.</p>
                        <p style='color: #666; font-size: 14px;'>If you didn't request this, please ignore this email.</p>
                        <p style='color: #999; font-size: 12px;'><em>For security reasons, please don't share this link with anyone.</em></p>
                    </div>
                    <div style='background-color: #f5f5f5; padding: 15px; text-align: center; border-radius: 0 0 8px 8px; border-top: 1px solid #ddd;'>
                        <p style='color: #999; font-size: 12px; margin: 0;'>© 2024 MK DATA. All rights reserved.</p>
                    </div>
                </div>
            </body>
            </html>
        ";

        $mail->AltBody = "Click this link to reset your password: {$reset_link}";

        error_log('[PASSWORD_RESET] Calling $mail->send()...');
        $sendResult = $mail->send();
        error_log('[PASSWORD_RESET] Email send completed with result: ' . ($sendResult ? 'true' : 'false'));
        error_log('[PASSWORD_RESET] Email sent successfully to: ' . $email);

        http_response_code(200);
        echo json_encode([
            "status" => "success",
            "message" => "If your email is registered, you will receive reset instructions shortly."
        ]);
    } catch (Exception $e) {
        $errorMsg = $e->getMessage();
        error_log('[PASSWORD_RESET_ERROR] ' . $errorMsg);
        http_response_code(500);
        echo json_encode([
            "status" => "error",
            "message" => "Unable to send reset instructions. Please try again later. (Error: " . $errorMsg . ")"
        ]);
    }
} catch (Exception $e) {
    http_response_code(500);
    echo json_encode([
        "status" => "error",
        "message" => "An error occurred. Please try again later."
    ]);
}
