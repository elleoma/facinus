#!/bin/bash
# Set up the web server components

setup_web_server() {
    echo "Setting up web server..."
    
    # Create necessary directories
    sudo mkdir -p "$SERVER_ROOT/assets"
    sudo mkdir -p "$SERVER_ROOT/logs"
    sudo mkdir -p "$SERVER_ROOT/secrets"
    sudo mkdir -p "$SERVER_ROOT/css"
    
    # Set correct permissions
    case "$DISTRO" in
        arch)
            sudo chown -R http:http "$SERVER_ROOT/logs"
            sudo chown -R http:http "$SERVER_ROOT/secrets"
            ;;
        debian|ubuntu)
            sudo chown -R www-data:www-data "$SERVER_ROOT/logs"
            sudo chown -R www-data:www-data "$SERVER_ROOT/secrets"
            ;;
        redhat|fedora|centos)
            sudo chown -R apache:apache "$SERVER_ROOT/logs"
            sudo chown -R apache:apache "$SERVER_ROOT/secrets"
            ;;
        *)
            # Try to guess the web server user
            if id -u http &>/dev/null; then
                sudo chown -R http:http "$SERVER_ROOT/logs"
                sudo chown -R http:http "$SERVER_ROOT/secrets"
            elif id -u www-data &>/dev/null; then
                sudo chown -R www-data:www-data "$SERVER_ROOT/logs"
                sudo chown -R www-data:www-data "$SERVER_ROOT/secrets"
            elif id -u apache &>/dev/null; then
                sudo chown -R apache:apache "$SERVER_ROOT/logs"
                sudo chown -R apache:apache "$SERVER_ROOT/secrets"
            else
                echo "Warning: Could not determine web server user. Setting default permissions."
            fi
            ;;
    esac
    
    sudo chmod 750 "$SERVER_ROOT/logs"
    sudo chmod 750 "$SERVER_ROOT/secrets"
    
    # Configure web server
    configure_webserver
}

configure_webserver() {
    case "$DISTRO" in
        arch)
            configure_apache_arch
            ;;
        debian|ubuntu)
            configure_apache_debian
            ;;
        redhat|fedora|centos)
            configure_apache_redhat
            ;;
        *)
            echo "Warning: Automatic web server configuration not available for this distribution."
            echo "Please configure your web server manually to serve from $SERVER_ROOT"
            ;;
    esac
}

configure_apache_arch() {
    # Create Apache configuration
    cat > "$TEMP_DIR/deployment.conf" << EOF
<VirtualHost *:$SERVER_PORT>
    ServerName ${SERVER_IP}
    ServerAdmin webmaster@localhost
    DocumentRoot "/srv/http"
    DirectoryIndex index.html
    
    <Directory "$SERVER_ROOT">
        Options -Indexes +FollowSymLinks
        AllowOverride None
        Require all granted
    </Directory>
    
    <Directory "$SERVER_ROOT/logs">
        Require all denied
    </Directory>
    
    <Directory "$SERVER_ROOT/secrets">
        Require all denied
    </Directory>
    
    ErrorLog "/var/log/httpd/deployment-error.log"
    CustomLog "/var/log/httpd/deployment-access.log" combined
</VirtualHost>
EOF

    sudo mv "$TEMP_DIR/deployment.conf" /etc/httpd/conf/extra/deployment.conf
    
    # Include our config in the main httpd.conf
    if ! grep -q "Include conf/extra/deployment.conf" /etc/httpd/conf/httpd.conf; then
        echo "Include conf/extra/deployment.conf" | sudo tee -a /etc/httpd/conf/httpd.conf > /dev/null
    fi
    
    # Start/restart Apache
    sudo systemctl enable httpd
    sudo systemctl restart httpd
}

configure_apache_debian() {
    # Create Apache configuration
    cat > "$TEMP_DIR/deployment.conf" << EOF
<VirtualHost *:$SERVER_PORT>
    ServerName ${SERVER_IP}
    ServerAdmin webmaster@localhost
    DocumentRoot "/var/www/html"
    DirectoryIndex index.html
    
    Alias /deployment $SERVER_ROOT
    
    <Directory "$SERVER_ROOT">
        Options -Indexes +FollowSymLinks
        AllowOverride None
        Require all granted
    </Directory>
    
    <Directory "$SERVER_ROOT/logs">
        Require all denied
    </Directory>
    
    <Directory "$SERVER_ROOT/secrets">
        Require all denied
    </Directory>
    
    ErrorLog \${APACHE_LOG_DIR}/deployment-error.log
    CustomLog \${APACHE_LOG_DIR}/deployment-access.log combined
</VirtualHost>
EOF

    sudo mv "$TEMP_DIR/deployment.conf" /etc/apache2/sites-available/deployment.conf
    sudo a2ensite deployment
    
    # Start/restart Apache
    sudo systemctl enable apache2
    sudo systemctl restart apache2
}

configure_apache_redhat() {
    # Create Apache configuration
    cat > "$TEMP_DIR/deployment.conf" << EOF
<VirtualHost *:$SERVER_PORT>
    ServerName ${SERVER_IP}
    ServerAdmin webmaster@localhost
    DocumentRoot "/var/www/html"
    DirectoryIndex index.html
    
    Alias /deployment $SERVER_ROOT
    
    <Directory "$SERVER_ROOT">
        Options -Indexes +FollowSymLinks
        AllowOverride None
        Require all granted
    </Directory>
    
    <Directory "$SERVER_ROOT/logs">
        Require all denied
    </Directory>
    
    <Directory "$SERVER_ROOT/secrets">
        Require all denied
    </Directory>
    
    ErrorLog /var/log/httpd/deployment-error.log
    CustomLog /var/log/httpd/deployment-access.log combined
</VirtualHost>
EOF

    sudo mv "$TEMP_DIR/deployment.conf" /etc/httpd/conf.d/deployment.conf
    
    # Start/restart Apache
    sudo systemctl enable httpd
    sudo systemctl restart httpd
}
