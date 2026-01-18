-- Create delivery logs table for tracking daily data plan deliveries
CREATE TABLE IF NOT EXISTS delivery_logs (
    id INT AUTO_INCREMENT PRIMARY KEY,
    plan_id INT NOT NULL,
    user_id INT NOT NULL,
    phone_number VARCHAR(20) NOT NULL,
    network_id INT NOT NULL,
    plan_code VARCHAR(50) NOT NULL,
    transaction_ref VARCHAR(100),
    status ENUM('success', 'failed', 'pending', 'retry') DEFAULT 'pending',
    provider_response LONGTEXT,
    error_message TEXT,
    http_code INT,
    delivery_date DATETIME DEFAULT CURRENT_TIMESTAMP,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    
    INDEX idx_user_id (user_id),
    INDEX idx_plan_id (plan_id),
    INDEX idx_status (status),
    INDEX idx_delivery_date (delivery_date),
    INDEX idx_phone (phone_number),
    FOREIGN KEY (plan_id) REFERENCES daily_data_plans(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Create summary statistics view
CREATE OR REPLACE VIEW delivery_log_stats AS
SELECT
    DATE(delivery_date) as delivery_day,
    COUNT(*) as total_deliveries,
    SUM(CASE WHEN status = 'success' THEN 1 ELSE 0 END) as successful,
    SUM(CASE WHEN status = 'failed' THEN 1 ELSE 0 END) as failed,
    SUM(CASE WHEN status = 'pending' THEN 1 ELSE 0 END) as pending,
    SUM(CASE WHEN status = 'retry' THEN 1 ELSE 0 END) as retry,
    ROUND(SUM(CASE WHEN status = 'success' THEN 1 ELSE 0 END) * 100 / COUNT(*), 2) as success_rate
FROM delivery_logs
GROUP BY DATE(delivery_date)
ORDER BY delivery_date DESC;
