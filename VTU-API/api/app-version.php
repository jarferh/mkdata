<?php
header("Access-Control-Allow-Origin: *");
header("Content-Type: application/json; charset=UTF-8");
header("Access-Control-Allow-Methods: GET, OPTIONS");
header("Access-Control-Max-Age: 3600");
header("Access-Control-Allow-Headers: Content-Type, Access-Control-Allow-Headers, Authorization, X-Requested-With");

if ($_SERVER['REQUEST_METHOD'] == 'OPTIONS') {
    http_response_code(200);
    exit();
}

try {
    // Latest version information
    // Update these values when you release a new version on Play Store
    $latestVersion = '1.0.0'; // Latest version on Play Store
    $latestBuild = '6'; // Latest build number on Play Store
    $minVersion = '1.0.0'; // Minimum version that can use the app
    $forceUpdate = false; // Set to true to force immediate update
    $updateUrl = 'https://play.google.com/store/apps/details?id=inc.mk.data'; // Play Store URL
    $releaseNotes = 'New features and Better Perpermance.'; // Release notes for the latest version

    http_response_code(200);
    echo json_encode([
        'success' => true,
        'latest_version' => $latestVersion,
        'latest_build' => intval($latestBuild),
        'min_version' => $minVersion,
        'force_update' => $forceUpdate,
        'update_url' => $updateUrl,
        'release_notes' => $releaseNotes,
        'timestamp' => date('Y-m-d H:i:s')
    ]);

} catch (Exception $e) {
    http_response_code(500);
    echo json_encode([
        'success' => false,
        'message' => 'Error: ' . $e->getMessage()
    ]);
}
?>
