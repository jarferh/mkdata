<?php
namespace Binali\Models;

use Exception;
use PDO;

/**
 * SiteSettings Class
 * Handles retrieval of site configuration and contact details from database
 * @package Binali\Models
 */
class SiteSettings
{
    private $conn;
    private $table_name = "sitesettings";
    
    public function __construct($db) {
        if ($db instanceof PDO) {
            $this->conn = $db;
        } elseif (method_exists($db, 'getPDO')) {
            $this->conn = $db->getPDO();
        } elseif (method_exists($db, 'getConnection')) {
            $this->conn = $db->getConnection();
        } else {
            $this->conn = $db;
        }
    }

    /**
     * Get all site settings
     */
    public function getAll() {
        try {
            $query = "SELECT * FROM " . $this->table_name . " LIMIT 1";
            $stmt = $this->conn->prepare($query);
            $stmt->execute();
            
            $result = $stmt->fetch(PDO::FETCH_ASSOC);
            
            if (!$result) {
                throw new Exception("No site settings found");
            }
            
            return $result;
        } catch (Exception $e) {
            error_log("SiteSettings Error: " . $e->getMessage());
            throw $e;
        }
    }

    /**
     * Get contact information only
     */
    public function getContactInfo() {
        try {
            $query = "SELECT 
                        phone, 
                        email, 
                        whatsapp, 
                        whatsappgroup, 
                        facebook, 
                        twitter, 
                        instagram, 
                        telegram,
                        sitename,
                        siteurl
                      FROM " . $this->table_name . " 
                      LIMIT 1";
            
            $stmt = $this->conn->prepare($query);
            $stmt->execute();
            
            $result = $stmt->fetch(PDO::FETCH_ASSOC);
            
            if (!$result) {
                throw new Exception("No site settings found");
            }
            
            return $result;
        } catch (Exception $e) {
            error_log("SiteSettings Contact Info Error: " . $e->getMessage());
            throw $e;
        }
    }

    /**
     * Get FAQ content
     */
    public function getFAQ() {
        // This returns static FAQ data. 
        // If you want to store FAQ in database later, modify this method
        return [
            [
                'question' => 'What Are The Codes For Checking Data Balance?',
                'answer' => 'Dial *123# to check your data balance or use the mobile app.'
            ],
            [
                'question' => 'How Do I Fund My Wallet?',
                'answer' => 'Use your bank transfer, PoS, or card to fund your wallet.'
            ]
        ];
    }
}
