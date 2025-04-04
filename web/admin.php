<?php
// FACINUS Admin Panel
// This file allows viewing logs and connection information from deployed clients

// Session and authentication
session_start();
$admin_password = "ADMIN_PASSWORD_PLACEHOLDER"; // Will be replaced during installation

// Handle login
if (isset($_POST['password'])) {
    if ($_POST['password'] === $admin_password) {
        $_SESSION['authenticated'] = true;
    } else {
        $login_error = "Invalid password";
    }
}

// Handle logout
if (isset($_GET['logout'])) {
    session_destroy();
    header("Location: " . $_SERVER['PHP_SELF']);
    exit;
}

// Check authentication
$authenticated = isset($_SESSION['authenticated']) && $_SESSION['authenticated'] === true;

// Directories
$logs_dir = __DIR__ . "/logs";
$secrets_dir = __DIR__ . "/secrets";

// Get list of hosts (each subdirectory in logs_dir is a host)
$hosts = [];
if ($authenticated && is_dir($logs_dir)) {
    $dir_content = scandir($logs_dir);
    foreach ($dir_content as $item) {
        if ($item != "." && $item != ".." && is_dir($logs_dir . "/" . $item)) {
            $hosts[] = $item;
        }
    }
}

// View specific log if requested
$current_log = null;
$log_content = "";
if ($authenticated && isset($_GET['log'])) {
    $log_path = $logs_dir . "/" . $_GET['host'] . "/" . $_GET['log'];
    if (file_exists($log_path) && is_file($log_path)) {
        $current_log = $_GET['log'];
        $log_content = file_get_contents($log_path);
    }
}

// View system info if requested
$system_info = null;
if ($authenticated && isset($_GET['info']) && $_GET['info'] === 'system') {
    $info_path = $logs_dir . "/" . $_GET['host'] . "/system_info.json";
    if (file_exists($info_path) && is_file($info_path)) {
        $system_info = json_decode(file_get_contents($info_path), true);
    }
}

// View secrets if requested
$secrets = [];
if ($authenticated && isset($_GET['secrets']) && $_GET['host']) {
    $host_secrets_dir = $secrets_dir . "/" . $_GET['host'];
    if (is_dir($host_secrets_dir)) {
        $secret_files = scandir($host_secrets_dir);
        foreach ($secret_files as $file) {
            if ($file != "." && $file != ".." && is_file($host_secrets_dir . "/" . $file)) {
                $type = pathinfo($file, PATHINFO_FILENAME);
                $value = file_get_contents($host_secrets_dir . "/" . $file);
                $secrets[$type] = $value;
            }
        }
    }
}

// Get logs for a specific host if requested
$host_logs = [];
if ($authenticated && isset($_GET['host'])) {
    $host_logs_dir = $logs_dir . "/" . $_GET['host'];
    if (is_dir($host_logs_dir)) {
        $log_files = scandir($host_logs_dir);
        foreach ($log_files as $file) {
            if ($file != "." && $file != ".." && is_file($host_logs_dir . "/" . $file)) {
                $host_logs[] = $file;
            }
        }
    }
    // Sort logs by most recent first
    usort($host_logs, function($a, $b) {
        return filemtime($logs_dir . "/" . $_GET['host'] . "/" . $b) - 
               filemtime($logs_dir . "/" . $_GET['host'] . "/" . $a);
    });
}
?>
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>FACINUS - Admin Panel</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 0; padding: 0; }
        .container { max-width: 1200px; margin: 0 auto; padding: 20px; }
        .header { background: #333; color: white; padding: 10px; }
        .header h1 { margin: 0; }
        .logout { float: right; color: white; text-decoration: none; }
        .sidebar { width: 250px; float: left; }
        .content { margin-left: 270px; }
        .card { border: 1px solid #ddd; border-radius: 5px; padding: 15px; margin-bottom: 20px; }
        .login { max-width: 400px; margin: 50px auto; border: 1px solid #ddd; padding: 20px; border-radius: 5px; }
        .form-group { margin-bottom: 15px; }
        input[type="password"] { width: 100%; padding: 8px; box-sizing: border-box; }
        button { background: #0275d8; color: white; border: none; padding: 10px 15px; cursor: pointer; }
        .host-list { list-style: none; padding: 0; }
        .host-list li { padding: 8px; border-bottom: 1px solid #eee; }
        .host-list li:hover { background: #f5f5f5; }
        .host-list a { text-decoration: none; color: #333; display: block; }
        .log-list { list-style: none; padding: 0; }
        .log-list li { padding: 8px; border-bottom: 1px solid #eee; }
        .log-list a { text-decoration: none; color: #333; }
        .tabs { margin-bottom: 20px; }
        .tab { display: inline-block; padding: 10px 15px; cursor: pointer; border: 1px solid #ddd; }
        .tab.active { background: #007bff; color: white; }
        .logs { background: #f8f8f8; padding: 15px; border: 1px solid #ddd; overflow: auto; max-height: 600px; font-family: monospace; white-space: pre-wrap; }
        .secret { background: #ffffd8; padding: 15px; border: 1px solid #e6e6a3; margin-bottom: 10px; font-family: monospace; }
        .secret-title { font-weight: bold; margin-bottom: 5px; }
        .alert { padding: 15px; margin-bottom: 20px; border: 1px solid transparent; border-radius: 4px; }
        .alert-danger { color: #721c24; background-color: #f8d7da; border-color: #f5c6cb; }
        .command { background: #f8f8f8; padding: 10px; border: 1px solid #ddd; font-family: monospace; margin: 10px 0; }
    </style>
</head>
<body>
    <div class="header">
        <div class="container">
            <h1>FACINUS Admin Panel</h1>
            <?php if ($authenticated): ?>
                <a href="?logout=1" class="logout">Logout</a>
            <?php endif; ?>
        </div>
    </div>

    <div class="container">
        <?php if (!$authenticated): ?>
        <div class="login">
            <h2>Login</h2>
            <?php if (isset($login_error)): ?>
                <div class="alert alert-danger"><?php echo $login_error; ?></div>
            <?php endif; ?>
            <form method="post">
                <div class="form-group">
                    <label for="password">Admin Password</label>
                    <input type="password" id="password" name="password" required>
                </div>
                <button type="submit">Login</button>
            </form>
        </div>
        <?php else: ?>
        
        <div class="sidebar">
            <div class="card">
                <h3>Hosts</h3>
                <?php if (empty($hosts)): ?>
                    <p>No hosts found.</p>
                <?php else: ?>
                    <ul class="host-list">
                        <?php foreach ($hosts as $host): ?>
                            <li><a href="?host=<?php echo urlencode($host); ?>"><?php echo htmlspecialchars($host); ?></a></li>
                        <?php endforeach; ?>
                    </ul>
                <?php endif; ?>
            </div>
        </div>
        
        <div class="content">
            <?php if (isset($_GET['host'])): ?>
                <div class="card">
                    <h2>Host: <?php echo htmlspecialchars($_GET['host']); ?></h2>
                    
                    <div class="tabs">
                        <a href="?host=<?php echo urlencode($_GET['host']); ?>" class="tab <?php echo (!isset($_GET['secrets']) && !isset($_GET['info'])) ? 'active' : ''; ?>">Logs</a>
                        <a href="?host=<?php echo urlencode($_GET['host']); ?>&secrets=1" class="tab <?php echo isset($_GET['secrets']) ? 'active' : ''; ?>">Access Info</a>
                        <a href="?host=<?php echo urlencode($_GET['host']); ?>&info=system" class="tab <?php echo isset($_GET['info']) ? 'active' : ''; ?>">System Info</a>
                    </div>
                    
                    <?php if (isset($_GET['secrets'])): ?>
                        <h3>Connection Information</h3>
                        <?php if (empty($secrets)): ?>
                            <p>No connection information available.</p>
                        <?php else: ?>
                            <?php foreach ($secrets as $type => $value): ?>
                                <div class="secret">
                                    <div class="secret-title"><?php echo ucfirst(htmlspecialchars($type)); ?>:</div>
                                    <?php if ($type === "gsocket_secret"): ?>
                                        <p>Secret: <code><?php echo htmlspecialchars($value); ?></code></p>
                                        <p>Connect using: <div class="command">gs-netcat -s <?php echo htmlspecialchars($value); ?></div></p>
                                    <?php elseif ($type === "ssh_config"): ?>
                                        <?php $ssh_config = json_decode($value, true); ?>
                                        <p>SSH Port: <code><?php echo $ssh_config['port']; ?></code></p>
                                        <p>Connect using: <div class="command">ssh user@<?php echo $_GET['host']; ?> -p <?php echo $ssh_config['port']; ?></div></p>
                                    <?php elseif ($type === "ssh_key"): ?>
                                        <p>SSH Public Key:</p>
                                        <pre><?php echo htmlspecialchars($value); ?></pre>
                                    <?php elseif ($type === "wol_config"): ?>
                                        <?php $wol_config = json_decode($value, true); ?>
                                        <p>Interface: <code><?php echo $wol_config['interface']; ?></code></p>
                                        <p>MAC Address: <code><?php echo $wol_config['mac']; ?></code></p>
                                        <p>Wake using: <div class="command">wakeonlan <?php echo $wol_config['mac']; ?></div></p>
                                    <?php else: ?>
                                        <pre><?php echo htmlspecialchars($value); ?></pre>
                                    <?php endif; ?>
                                </div>
                            <?php endforeach; ?>
                        <?php endif; ?>
                    <?php elseif (isset($_GET['info']) && $_GET['info'] === 'system'): ?>
                        <h3>System Information</h3>
                        <?php if ($system_info): ?>
                            <div class="logs">
                                <?php foreach ($system_info as $key => $value): ?>
                                    <?php if (is_array($value)): ?>
                                        <strong><?php echo ucfirst(htmlspecialchars($key)); ?>:</strong>
                                        <ul>
                                            <?php foreach ($value as $item): ?>
                                                <li>
                                                    <?php 
                                                    if (is_array($item)) {
                                                        foreach ($item as $k => $v) {
                                                            echo htmlspecialchars($k) . ": " . htmlspecialchars($v) . " ";
                                                        }
                                                    } else {
                                                        echo htmlspecialchars($item);
                                                    }
                                                    ?>
                                                </li>
                                            <?php endforeach; ?>
                                        </ul>
                                    <?php else: ?>
                                        <strong><?php echo ucfirst(htmlspecialchars($key)); ?>:</strong> <?php echo htmlspecialchars($value); ?><br>
                                    <?php endif; ?>
                                <?php endforeach; ?>
                            </div>
                        <?php else: ?>
                            <p>No system information available.</p>
                        <?php endif; ?>
                    <?php else: ?>
                        <h3>Available Logs</h3>
                        <?php if (empty($host_logs)): ?>
                            <p>No logs available.</p>
                        <?php else: ?>
                            <ul class="log-list">
                                <?php foreach ($host_logs as $log): ?>
                                    <li><a href="?host=<?php echo urlencode($_GET['host']); ?>&log=<?php echo urlencode($log); ?>"><?php echo htmlspecialchars($log); ?></a></li>
                                <?php endforeach; ?>
                            </ul>
                            
                            <?php if ($current_log): ?>
                                <h3>Log: <?php echo htmlspecialchars($current_log); ?></h3>
                                <div class="logs"><?php echo htmlspecialchars($log_content); ?></div>
                            <?php endif; ?>
                        <?php endif; ?>
                    <?php endif; ?>
                </div>
            <?php else: ?>
                <div class="card">
                    <h2>Welcome to FACINUS Admin Panel</h2>
                    <p>Select a host from the sidebar to view logs and connection information.</p>
                </div>
            <?php endif; ?>
        </div>
        <?php endif; ?>
    </div>
</body>
</html>
