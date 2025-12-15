-- Create spin_rewards table for storing available rewards
CREATE TABLE IF NOT EXISTS `spin_rewards` (
  `id` int(10) UNSIGNED NOT NULL AUTO_INCREMENT,
  `code` varchar(64) NOT NULL UNIQUE,
  `name` varchar(128) NOT NULL,
  `type` enum('airtime','data','tryagain') NOT NULL DEFAULT 'airtime',
  `amount` decimal(12,2) DEFAULT NULL,
  `unit` varchar(16) DEFAULT NULL,
  `plan_id` varchar(50) DEFAULT NULL,
  `weight` decimal(5,2) NOT NULL DEFAULT 0.00,
  `active` tinyint(1) NOT NULL DEFAULT 1,
  `created_at` datetime NOT NULL DEFAULT current_timestamp(),
  `updated_at` datetime NOT NULL DEFAULT current_timestamp() ON UPDATE current_timestamp(),
  PRIMARY KEY (`id`),
  UNIQUE KEY `uq_spin_rewards_code` (`code`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Create spin_wins table for recording user spin results
CREATE TABLE IF NOT EXISTS `spin_wins` (
  `id` bigint(20) UNSIGNED NOT NULL AUTO_INCREMENT,
  `user_id` int(10) UNSIGNED NOT NULL,
  `reward_id` int(10) UNSIGNED DEFAULT NULL,
  `reward_type` enum('airtime','data','tryagain') NOT NULL,
  `amount` decimal(12,2) DEFAULT NULL,
  `unit` varchar(16) DEFAULT NULL,
  `plan_id` varchar(50) DEFAULT NULL,
  `status` enum('pending','delivered','claimed') NOT NULL DEFAULT 'pending',
  `meta` longtext CHARACTER SET utf8mb4 COLLATE utf8mb4_bin DEFAULT NULL,
  `spin_at` datetime NOT NULL DEFAULT current_timestamp(),
  `delivered_at` datetime DEFAULT NULL,
  PRIMARY KEY (`id`),
  KEY `idx_user_spin_at` (`user_id`,`spin_at`),
  KEY `idx_reward_id` (`reward_id`),
  FOREIGN KEY (`reward_id`) REFERENCES `spin_rewards` (`id`) ON DELETE SET NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Insert sample rewards data (if table is empty)
-- Using ON DUPLICATE KEY IGNORE to avoid conflicts
INSERT IGNORE INTO `spin_rewards` 
(`code`, `name`, `type`, `amount`, `unit`, `weight`, `active`) 
VALUES
('NGN_500', '₦500 Airtime', 'airtime', 500.00, 'NGN', 0.50, 1),
('DATA_1GB', '1GB Data', 'data', 1.00, 'GB', 0.30, 1),
('NGN_1000', '₦1000 Airtime', 'airtime', 1000.00, 'NGN', 0.20, 1),
('NGN_200', '₦200 Airtime', 'airtime', 200.00, 'NGN', 98.00, 1),
('DATA_2GB', '2GB Data', 'data', 2.00, 'GB', 0.50, 1),
('NGN_750', '₦750 Airtime', 'airtime', 750.00, 'NGN', 0.50, 1),
('TRY_AGAIN', 'Try Again', 'tryagain', NULL, NULL, 1.00, 1);
