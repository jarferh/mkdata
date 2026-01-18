<!DOCTYPE html>
<html lang="en">

<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Reset Password - MK DATA</title>
    <link href="https://fonts.googleapis.com/css2?family=Inter:wght@400;500;600;700&display=swap" rel="stylesheet">
    <link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.0.0/css/all.min.css">
    <style>
        * {
            margin: 0;
            padding: 0;
            box-sizing: border-box;
        }

        body {
            font-family: 'Inter', -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif;
            background: linear-gradient(135deg, #f5f7fa 0%, #c3cfe2 100%);
            min-height: 100vh;
            color: #333;
            display: flex;
            flex-direction: column;
        }

        .header {
            background: linear-gradient(135deg, #ce4323 0%, #a73b1f 100%);
            padding: 2rem 1rem;
            text-align: center;
            color: white;
            box-shadow: 0 4px 15px rgba(206, 67, 35, 0.2);
            position: relative;
            overflow: hidden;
        }

        .header::after {
            content: '';
            position: absolute;
            bottom: -1px;
            left: 0;
            width: 100%;
            height: 30px;
            background: white;
            clip-path: polygon(0 50%, 2% 40%, 4% 35%, 6% 42%, 8% 38%, 10% 45%, 12% 40%, 14% 38%, 16% 44%, 18% 42%, 20% 45%, 22% 38%, 24% 40%, 26% 44%, 28% 42%, 30% 40%, 32% 45%, 34% 38%, 36% 42%, 38% 44%, 40% 40%, 42% 38%, 44% 45%, 46% 42%, 48% 40%, 50% 44%, 52% 42%, 54% 38%, 56% 45%, 58% 40%, 60% 44%, 62% 42%, 64% 38%, 66% 45%, 68% 40%, 70% 44%, 72% 42%, 74% 40%, 76% 45%, 78% 38%, 80% 42%, 82% 44%, 84% 40%, 86% 38%, 88% 45%, 90% 42%, 92% 40%, 94% 44%, 96% 42%, 98% 38%, 100% 45%, 100% 100%, 0 100%);
        }

        .logo {
            max-height: 50px;
            margin-bottom: 0.5rem;
        }

        .header h2 {
            font-size: 24px;
            font-weight: 600;
            margin-bottom: 0.25rem;
            z-index: 1;
            position: relative;
        }

        .header p {
            font-size: 14px;
            opacity: 0.95;
            z-index: 1;
            position: relative;
        }

        .main-content {
            flex: 1;
            display: flex;
            align-items: center;
            justify-content: center;
            padding: 2rem 1rem;
        }

        .container {
            width: 100%;
            max-width: 450px;
            background: white;
            border-radius: 16px;
            box-shadow: 0 10px 40px rgba(0, 0, 0, 0.1);
            overflow: hidden;
            animation: slideUp 0.3s ease-out;
        }

        @keyframes slideUp {
            from {
                opacity: 0;
                transform: translateY(20px);
            }
            to {
                opacity: 1;
                transform: translateY(0);
            }
        }

        .form-header {
            padding: 2rem 2rem 1rem;
            text-align: center;
        }

        .icon-box {
            width: 60px;
            height: 60px;
            margin: 0 auto 1.5rem;
            background: linear-gradient(135deg, #ce4323 0%, #a73b1f 100%);
            border-radius: 50%;
            display: flex;
            align-items: center;
            justify-content: center;
            box-shadow: 0 4px 15px rgba(206, 67, 35, 0.2);
        }

        .icon-box i {
            color: white;
            font-size: 28px;
        }

        .form-header h1 {
            color: #333;
            font-size: 22px;
            margin-bottom: 0.5rem;
            font-weight: 700;
        }

        .form-header p {
            color: #666;
            font-size: 14px;
            line-height: 1.5;
        }

        .form-content {
            padding: 2rem;
        }

        .form-group {
            margin-bottom: 1.5rem;
        }

        label {
            display: block;
            margin-bottom: 0.75rem;
            color: #333;
            font-weight: 500;
            font-size: 14px;
        }

        input {
            width: 100%;
            padding: 0.875rem 1rem;
            border: 1.5px solid #e0e0e0;
            border-radius: 10px;
            font-size: 15px;
            font-family: 'Inter', sans-serif;
            transition: all 0.3s ease;
            background-color: #fafafa;
        }

        input:focus {
            background-color: white;
            border-color: #ce4323;
            outline: none;
            box-shadow: 0 0 0 3px rgba(206, 67, 35, 0.1);
        }

        input::placeholder {
            color: #aaa;
        }

        .password-requirements {
            font-size: 12px;
            color: #666;
            margin-top: 0.5rem;
            line-height: 1.6;
            background: #f9f9f9;
            padding: 0.75rem;
            border-radius: 6px;
            border-left: 3px solid #ce4323;
        }

        .password-requirements ul {
            list-style: none;
            padding: 0;
            margin: 0.5rem 0 0 0;
        }

        .password-requirements li {
            margin-bottom: 0.3rem;
            padding-left: 1.5rem;
            position: relative;
        }

        .password-requirements li:before {
            content: '✓';
            position: absolute;
            left: 0;
            color: #ce4323;
            font-weight: bold;
        }

        .error {
            color: #d32f2f;
            font-size: 13px;
            margin-top: 0.5rem;
            display: none;
            padding: 0.75rem;
            background-color: #ffebee;
            border-radius: 6px;
            border-left: 3px solid #d32f2f;
        }

        .error.show {
            display: block;
            animation: shake 0.3s ease;
        }

        @keyframes shake {
            0%, 100% { transform: translateX(0); }
            25% { transform: translateX(-5px); }
            75% { transform: translateX(5px); }
        }

        button {
            width: 100%;
            padding: 0.875rem;
            background: linear-gradient(135deg, #ce4323 0%, #a73b1f 100%);
            color: white;
            border: none;
            border-radius: 10px;
            font-size: 15px;
            font-weight: 600;
            cursor: pointer;
            transition: all 0.3s ease;
            box-shadow: 0 4px 15px rgba(206, 67, 35, 0.2);
            margin-top: 1rem;
        }

        button:hover {
            transform: translateY(-2px);
            box-shadow: 0 6px 20px rgba(206, 67, 35, 0.3);
        }

        button:active {
            transform: translateY(0);
            box-shadow: 0 2px 10px rgba(206, 67, 35, 0.2);
        }

        .error-container {
            background-color: #ffebee;
            border-left: 4px solid #d32f2f;
            padding: 1rem;
            margin-bottom: 1.5rem;
            border-radius: 8px;
            display: flex;
            align-items: flex-start;
            gap: 0.75rem;
            animation: slideUp 0.3s ease-out;
        }

        .error-container i {
            color: #d32f2f;
            font-size: 18px;
            flex-shrink: 0;
            margin-top: 2px;
        }

        .error-container p {
            color: #c62828;
            font-size: 14px;
            margin: 0;
            line-height: 1.5;
        }

        .success-container {
            background-color: #e8f5e9;
            border-left: 4px solid #2e7d32;
            padding: 1rem;
            margin-bottom: 1.5rem;
            border-radius: 8px;
            display: flex;
            align-items: flex-start;
            gap: 0.75rem;
            animation: slideUp 0.3s ease-out;
        }

        .success-container i {
            color: #2e7d32;
            font-size: 18px;
            flex-shrink: 0;
            margin-top: 2px;
        }

        .success-container p {
            color: #1b5e20;
            font-size: 14px;
            margin: 0;
            line-height: 1.5;
        }

        .footer-link {
            text-align: center;
            padding: 1.5rem 2rem 2rem;
            border-top: 1px solid #f0f0f0;
        }

        .footer-link a {
            color: #ce4323;
            text-decoration: none;
            font-size: 14px;
            font-weight: 500;
            transition: all 0.2s ease;
        }

        .footer-link a:hover {
            text-decoration: underline;
        }

        @media (max-width: 480px) {
            .main-content {
                padding: 1rem;
            }

            .container {
                max-width: 100%;
            }

            .form-content {
                padding: 1.5rem;
            }

            .form-header {
                padding: 1.5rem 1.5rem 1rem;
            }

            .form-header h1 {
                font-size: 20px;
            }

            .footer-link {
                padding: 1rem 1.5rem 1.5rem;
            }
        }
    </style>
</head>

<body>
    <div class="header">
        <h2>Reset Password</h2>
        <p>Create a new password for your account</p>
        <div style="position: absolute; top: 0; left: 0; width: 100%; height: 100%; background: rgba(0,0,0,0.05);"></div>
    </div>

    <div class="main-content">
        <div class="container">
            <?php
            require_once __DIR__ . '/config/database.php';

            use Binali\Config\Database;
            use PDO;
            use PDOException;

            $token = $_GET['token'] ?? '';
            $error = '';
            $success = '';

            if (empty($token)) {
                $error = 'Invalid reset link';
            } else {
                try {
                    $database = new Database();
                    $db = $database->getConnection();

                    if (!$db) {
                        throw new Exception("Database connection failed");
                    }

                    $query = "SELECT * FROM password_resets WHERE token = ? AND expires_at > NOW() LIMIT 1";
                    $stmt = $db->prepare($query);
                    $stmt->execute([$token]);

                    if ($stmt->rowCount() == 0) {
                        $error = 'This reset link has expired or is invalid';
                    }
                } catch (Exception $e) {
                    error_log("Reset page error: " . $e->getMessage());
                    $error = 'An error occurred. Please try again later.';
                }
            }

            if ($error): ?>
                <div class="form-header">
                    <div class="icon-box" style="background: linear-gradient(135deg, #d32f2f 0%, #b71c1c 100%);">
                        <i class="fas fa-exclamation-circle"></i>
                    </div>
                    <h1>Unable to Reset Password</h1>
                    <p>Please request a new password reset link</p>
                </div>
                <div class="form-content">
                    <div class="error-container">
                        <i class="fas fa-alert-circle"></i>
                        <p><?php echo htmlspecialchars($error); ?></p>
                    </div>
                    <div class="footer-link">
                        <a href="/login"><i class="fas fa-arrow-left"></i> Return to Login</a>
                    </div>
                </div>
            <?php else: ?>
                <div class="form-header">
                    <div class="icon-box">
                        <i class="fas fa-lock"></i>
                    </div>
                    <h1>Create New Password</h1>
                    <p>Enter a strong password to secure your account</p>
                </div>

                <form id="resetForm" action="auth/reset_password.php" method="POST" class="form-content">
                    <input type="hidden" name="token" value="<?php echo htmlspecialchars($token); ?>">

                    <div class="form-group">
                        <label for="password">
                            <i class="fas fa-key"></i> New Password
                        </label>
                        <input type="password" id="password" name="password" required minlength="8" 
                            pattern="(?=.*\d)(?=.*[a-z])(?=.*[A-Z]).{8,}" placeholder="Enter your new password">
                        <div class="password-requirements">
                            <strong>Password Requirements:</strong>
                            <ul>
                                <li>At least 8 characters long</li>
                                <li>One uppercase letter (A-Z)</li>
                                <li>One lowercase letter (a-z)</li>
                                <li>One number (0-9)</li>
                            </ul>
                        </div>
                    </div>

                    <div class="form-group">
                        <label for="confirm_password">
                            <i class="fas fa-check-circle"></i> Confirm Password
                        </label>
                        <input type="password" id="confirm_password" name="confirm_password" required 
                            placeholder="Re-enter your password">
                        <div id="password-match-error" class="error">
                            <i class="fas fa-exclamation-circle"></i> Passwords do not match
                        </div>
                    </div>

                    <button type="submit">
                        <i class="fas fa-check-circle"></i> Reset Password
                    </button>
                </form>

                <div class="footer-link">
                    <a href="/login"><i class="fas fa-sign-in-alt"></i> Back to Login</a>
                </div>
            <?php endif; ?>
        </div>
    </div>

    <script>
        document.getElementById('resetForm')?.addEventListener('submit', function(e) {
            var password = document.getElementById('password').value;
            var confirm = document.getElementById('confirm_password').value;
            var error = document.getElementById('password-match-error');

            if (password !== confirm) {
                error.classList.add('show');
                e.preventDefault();
                return false;
            }

            error.classList.remove('show');
            return true;
        });

        // Real-time password match check
        document.getElementById('confirm_password')?.addEventListener('input', function() {
            var password = document.getElementById('password').value;
            var confirm = this.value;
            var error = document.getElementById('password-match-error');

            if (confirm && password && password !== confirm) {
                error.classList.add('show');
            } else {
                error.classList.remove('show');
            }
        });
    </script>
</body>

</html>