-- Migration: Create Referral System Tables
-- Description: Create tables for tracking referrals, referrers, and referral settings

-- Ensure subscribers table has sReferal column
ALTER TABLE subscribers 
ADD COLUMN sReferal VARCHAR(255) NULL DEFAULT NULL 
AFTER sPass;

-- Create referrals table to track referrer-referee relationships
CREATE TABLE IF NOT EXISTS referrals (
    id INT PRIMARY KEY AUTO_INCREMENT,
    referrer_id INT NOT NULL,
    referee_id INT NOT NULL,
    reward_amount DECIMAL(10, 2) NOT NULL DEFAULT 0.00,
    reward_claimed BOOLEAN DEFAULT FALSE,
    claimed_at TIMESTAMP NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    
    -- Foreign keys
    CONSTRAINT fk_referrer FOREIGN KEY (referrer_id) REFERENCES subscribers(sId) ON DELETE CASCADE,
    CONSTRAINT fk_referee FOREIGN KEY (referee_id) REFERENCES subscribers(sId) ON DELETE CASCADE,
    
    -- Indexes for performance
    INDEX idx_referrer (referrer_id),
    INDEX idx_referee (referee_id),
    INDEX idx_claimed (reward_claimed),
    INDEX idx_created (created_at),
    
    -- Unique constraint: a user can only be referred once
    UNIQUE KEY unique_referee (referee_id)
);

-- Create referral_settings table for global configuration
CREATE TABLE IF NOT EXISTS referral_settings (
    id INT PRIMARY KEY AUTO_INCREMENT,
    status ENUM('active', 'inactive') DEFAULT 'active',
    reward_amount DECIMAL(10, 2) NOT NULL DEFAULT 100.00,
    referrer_reward DECIMAL(10, 2) NOT NULL DEFAULT 100.00,
    referee_reward DECIMAL(10, 2) NOT NULL DEFAULT 0.00,
    min_referrals_to_claim INT NOT NULL DEFAULT 1,
    max_claims_per_user INT NOT NULL DEFAULT 0,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
);

-- Insert default referral settings if table is empty
INSERT INTO referral_settings (status, reward_amount, referrer_reward, referee_reward, min_referrals_to_claim, max_claims_per_user) 
VALUES ('active', 100.00, 100.00, 0.00, 1, 0)
ON DUPLICATE KEY UPDATE id=id;
