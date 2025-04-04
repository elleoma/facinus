#!/bin/bash
# Module for installing precompiled binaries without root access

# Define a list of common tools and their download URLs
BINARIES=(
    "nmap:https://github.com/nmap/nmap/releases/download/7.94/nmap-7.94-x86_64.AppImage"
    "nc:https://github.com/andrew-d/static-binaries/raw/master/binaries/linux/x86_64/ncat"
    "socat:https://github.com/andrew-d/static-binaries/raw/master/binaries/linux/x86_64/socat"
    "bash:https://github.com/robxu9/bash-static/releases/download/5.1.016-1.2.3/bash-linux-x86_64"
    "python3:https://github.com/indygreg/python-build-standalone/releases/download/20211017/cpython-3.9.7-x86_64-unknown-linux-gnu-install_only.tar.gz"
)

# Directory to store binaries
BIN_DIR="$HOME/.config/.hidden/bin"

install_binary() {
    local name=$1
    local url=$2
    local target_dir=$3
    local log_file=$4
    
    echo "[*] Installing $name..."
    
    mkdir -p "$target_dir"
    
    # Check file extension to determine how to handle
    if [[ "$url" == *.tar.gz ]] || [[ "$url" == *.tgz ]]; then
        # For archives, download and extract
        local temp_archive="$TEMP_DIR/$name.tar.gz"
        log_cmd "curl -sSL -o '$temp_archive' '$url'" "Downloading $name archive" "$log_file"
        
        mkdir -p "$target_dir/$name"
        log_cmd "tar -xzf '$temp_archive' -C '$target_dir/$name'" "Extracting $name" "$log_file"
        
        # For Python specifically
        if [[ "$name" == "python3" ]]; then
            # Create a symlink in the bin directory
            ln -sf "$target_dir/$name/python/bin/python3" "$target_dir/python3"
            ln -sf "$target_dir/$name/python/bin/pip3" "$target_dir/pip3"
        fi
    elif [[ "$url" == *.zip ]]; then
        # For zip archives
        local temp_archive="$TEMP_DIR/$name.zip"
        log_cmd "curl -sSL -o '$temp_archive' '$url'" "Downloading $name archive" "$log_file"
        
        mkdir -p "$target_dir/$name"
        log_cmd "unzip -q '$temp_archive' -d '$target_dir/$name'" "Extracting $name" "$log_file"
    else
        # For direct binaries
        log_cmd "curl -sSL -o '$target_dir/$name' '$url'" "Downloading $name binary" "$log_file"
        log_cmd "chmod +x '$target_dir/$name'" "Setting execute permissions" "$log_file"
    fi
}

install_precompiled_binaries() {
    local log_file="$TEMP_DIR/binary_install.log"
    touch "$log_file"
    
    echo "[*] Installing precompiled binaries..."
    
    # Create directory for binaries
    mkdir -p "$BIN_DIR"
    
    # Install each binary
    for binary in "${BINARIES[@]}"; do
        name=$(echo "$binary" | cut -d':' -f1
