-- Device Tokens Table for FCM Push Notifications
-- Stores FCM device tokens per user for push notification delivery

CREATE TABLE IF NOT EXISTS `user_devices` (
  `id` int NOT NULL AUTO_INCREMENT,
  `user_id` int NOT NULL,
  `fcm_token` varchar(500) COLLATE utf8mb4_unicode_ci NOT NULL COMMENT 'FCM device token',
  `device_type` enum('android','ios','web') COLLATE utf8mb4_unicode_ci DEFAULT 'android' COMMENT 'Device platform',
  `device_name` varchar(255) COLLATE utf8mb4_unicode_ci DEFAULT NULL COMMENT 'Device model/name',
  `is_active` tinyint(1) DEFAULT '1' COMMENT 'Whether token is still valid',
  `last_used` timestamp DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT 'Last time this device was used',
  `created_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  UNIQUE KEY `unique_token` (`fcm_token`),
  KEY `idx_user_id` (`user_id`),
  KEY `idx_is_active` (`is_active`),
  KEY `idx_device_type` (`device_type`),
  CONSTRAINT `fk_user_devices_user_id` FOREIGN KEY (`user_id`) 
    REFERENCES `subscribers` (`sId`) ON DELETE CASCADE ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci COMMENT='Stores FCM device tokens for push notifications';

-- Example: Insert a device token
-- INSERT INTO user_devices (user_id, fcm_token, device_type, device_name)
-- VALUES (1, 'token_value_here', 'android', 'Samsung Galaxy S21');
