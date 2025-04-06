#!/bin/bash
# Install required dependencies based on detected distro

install_dependencies() {
    echo "Installing dependencies for $DISTRO..."
    
    case "$DISTRO" in
        arch)
            install_arch_dependencies
            ;;
        debian|ubuntu)
            install_debian_dependencies
            ;;
        redhat|fedora|centos)
            install_redhat_dependencies
            ;;
        *)
            echo "Warning: Unsupported distribution detected. You may need to install dependencies manually."
            echo "Required packages: webserver (Apache/Nginx), PHP, Git, Build tools, curl, ethtool"
            read -p "Continue anyway? [y/N] " -n 1 -r
            echo
            if [[ ! $REPLY =~ ^[Yy]$ ]]; then
                exit 1
            fi
            ;;
    esac
}

install_arch_dependencies() {
    # Check and install required packages
    PACKAGES=("apache" "php" "php-apache" "git" "base-devel" "curl" "ethtool")
    
    for pkg in "${PACKAGES[@]}"; do
        if ! pacman -Q "$pkg" &>/dev/null; then
            echo "Installing $pkg..."
            sudo pacman -S --noconfirm "$pkg"
        fi
    done
    
    # Configure PHP with Apache if not already done
    if ! grep -q "LoadModule php_module" /etc/httpd/conf/httpd.conf; then
        sudo bash -c 'echo "LoadModule php_module modules/libphp.so" >> /etc/httpd/conf/httpd.conf'
        sudo bash -c 'echo "AddHandler php-script .php" >> /etc/httpd/conf/httpd.conf'
        sudo bash -c 'echo "Include conf/extra/php_module.conf" >> /etc/httpd/conf/httpd.conf'
    fi
    
    # Set correct MPM module
    if grep -q "#LoadModule mpm_prefork_module" /etc/httpd/conf/httpd.conf; then
        sudo sed -i 's/^\(LoadModule mpm_event_module modules\/mod_mpm_event\.so\)/#\1/' /etc/httpd/conf/httpd.conf
        sudo sed -i 's/^#\(LoadModule mpm_prefork_module modules\/mod_mpm_prefork\.so\)/\1/' /etc/httpd/conf/httpd.conf
    fi
}

install_debian_dependencies() {
    sudo apt update -q
    PACKAGES=("apache2" "php" "libapache2-mod-php" "git" "build-essential" "curl" "ethtool")
    sudo DEBIAN_FRONTEND=noninteractive apt install -y "${PACKAGES[@]}"
    
    # Enable PHP module
    sudo a2enmod php
    
    # Enable Apache modules
    sudo a2enmod rewrite
}

install_redhat_dependencies() {
    # Install required packages
    PACKAGES=("httpd" "php" "php-cli" "git" "make" "gcc" "gcc-c++" "curl" "ethtool")
    
    # Use dnf if available, otherwise fallback to yum
    if command -v dnf &>/dev/null; then
        sudo dnf install -y "${PACKAGES[@]}"
    else
        sudo yum install -y "${PACKAGES[@]}"
    fi
    
    # Enable and start Apache
    sudo systemctl enable httpd
    sudo systemctl start httpd
    
    # Configure SELinux if present
    if command -v sestatus &>/dev/null; then
        if sestatus | grep -q "SELinux status: *enabled"; then
            sudo setsebool -P httpd_can_network_connect 1
        fi
    fi
}
