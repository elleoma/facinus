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
    
    # Copy web files
    copy_web_files
    
    # Configure web server
    configure_webserver
}

copy_web_files() {
    # Copy PHP files from the web directory to the server root
    sudo cp -r "$WEB_DIR/"* "$SERVER_ROOT/"
    
    # Add the theme CSS
    create_theme_files
    
    # Update configurations in files
    sudo sed -i "s/TOKEN_PLACEHOLDER/$SECRET_TOKEN/g" "$SERVER_ROOT/log_receiver.php"
    sudo sed -i "s/ADMIN_PASSWORD_PLACEHOLDER/$ADMIN_PASSWORD/g" "$SERVER_ROOT/admin.php"

    # Update Server IP in the HTML files
    sudo sed -i "s/SERVER_IP/$SERVER_IP/g" "$SERVER_ROOT/index.html"
    sudo sed -i "s/SERVER_IP/$SERVER_IP/g" "$SERVER_ROOT/admin.php"
    
    # Set proper permissions
    sudo chmod 640 "$SERVER_ROOT/admin.php"
    sudo chmod 640 "$SERVER_ROOT/log_receiver.php"
}

create_theme_files() {
    # Create dark theme CSS file
    cat > "$TEMP_DIR/dark-theme.css" << 'EOF'
:root {
    --bg-color: #1e1e1e;
    --text-color: #e0e0e0;
    --border-color: #444;
    --header-bg: #252525;
    --card-bg: #2d2d2d;
    --link-color: #58a6ff;
    --button-bg: #0d6efd;
    --button-color: white;
    --input-bg: #333;
    --input-color: #e0e0e0;
    --table-header-bg: #333;
    --table-row-hover: #3a3a3a;
    --code-bg: #2d2d2d;
    --code-color: #e0e0e0;
}

body {
    background-color: var(--bg-color);
    color: var(--text-color);
}

.container, .card, .login {
    background-color: var(--card-bg);
    border-color: var(--border-color);
}

a {
    color: var(--link-color);
}

input, select, textarea {
    background-color: var(--input-bg);
    color: var(--input-color);
    border-color: var(--border-color);
}

button, .button {
    background-color: var(--button-bg);
    color: var(--button-color);
}

table {
    border-color: var(--border-color);
}

th {
    background-color: var(--table-header-bg);
}

tr:hover {
    background-color: var(--table-row-hover);
}

.logs, pre, code, .command {
    background-color: var(--code-bg);
    color: var(--code-color);
}

.secret {
    background-color: #332;
    border-color: #554;
}
EOF

    # Create light theme CSS file
    cat > "$TEMP_DIR/light-theme.css" << 'EOF'
:root {
    --bg-color: #f2f2f2;
    --text-color: #333;
    --border-color: #ddd;
    --header-bg: #f8f8f8;
    --card-bg: #fff;
    --link-color: #0066cc;
    --button-bg: #0d6efd;
    --button-color: white;
    --input-bg: #fff;
    --input-color: #333;
    --table-header-bg: #f2f2f2;
    --table-row-hover: #f8f8f8;
    --code-bg: #f8f8f8;
    --code-color: #333;
}

body {
    background-color: var(--bg-color);
    color: var(--text-color);
}

.container, .card, .login {
    background-color: var(--card-bg);
    border-color: var(--border-color);
}

a {
    color: var(--link-color);
}

input, select, textarea {
    background-color: var(--input-bg);
    color: var(--input-color);
    border-color: var(--border-color);
}

button, .button {
    background-color: var(--button-bg);
    color: var(--button-color);
}

table {
    border-color: var(--border-color);
}

th {
    background-color: var(--table-header-bg);
}

tr:hover {
    background-color: var(--table-row-hover);
}

.logs, pre, code, .command {
    background-color: var(--code-bg);
    color: var(--code-color);
}

.secret {
    background-color: #ffe;
    border-color: #ddc;
}
EOF

    sudo cp "$TEMP_DIR/dark-theme.css" "$SERVER_ROOT/css/dark-theme.css"
    sudo cp "$TEMP_DIR/light-theme.css" "$SERVER_ROOT/css/light-theme.css"
    
    # Create theme switcher JS
    cat > "$TEMP_DIR/theme-switcher.js" << 'EOF'
document.addEventListener('DOMContentLoaded', function() {
    // Check for saved theme preference or use preferred color scheme
    const savedTheme = localStorage.getItem('theme') || 
                      (window.matchMedia('(prefers-color-scheme: dark)').matches ? 'dark' : 'light');
    
    // Apply the theme
    document.documentElement.setAttribute('data-theme', savedTheme);
    
    // Create theme toggle button
    const themeToggle = document.createElement('button');
    themeToggle.id = 'theme-toggle';
    themeToggle.innerHTML = savedTheme === 'dark' ? '☀️' : '🌙';
    themeToggle.style.position = 'fixed';
    themeToggle.style.bottom = '20px';
    themeToggle.style.right = '20px';
    themeToggle.style.borderRadius = '50%';
    themeToggle.style.width = '50px';
    themeToggle.style.height = '50px';
    themeToggle.style.fontSize = '24px';
    themeToggle.style.cursor = 'pointer';
    themeToggle.style.border = 'none';
    themeToggle.style.boxShadow = '0 2px 5px rgba(0,0,0,0.2)';
    themeToggle.style.zIndex = '1000';
    
    document.body.appendChild(themeToggle);
    
    // Update link element
    const themeLink = document.getElementById('theme-stylesheet');
    themeLink.href = `css/${savedTheme}-theme.css`;
    
    // Theme toggle functionality
    themeToggle.addEventListener('click', function() {
        const currentTheme = document.documentElement.getAttribute('data-theme');
        const newTheme = currentTheme === 'dark' ? 'light' : 'dark';
        
        document.documentElement.setAttribute('data-theme', newTheme);
        themeLink.href = `css/${newTheme}-theme.css`;
        themeToggle.innerHTML = newTheme === 'dark' ? '☀️' : '🌙';
        
        // Save preference
        localStorage.setItem('theme', newTheme);
    });
});
EOF

    sudo cp "$TEMP_DIR/theme-switcher.js" "$SERVER_ROOT/assets/theme-switcher.js"
    
    # Update HTML files to include theme
    sudo sed -i '/<\/head>/i \    <link id="theme-stylesheet" rel="stylesheet" href="css/light-theme.css">\n    <script src="assets/theme-switcher.js"></script>' "$SERVER_ROOT/index.html"
    sudo sed -i '/<\/head>/i \    <link id="theme-stylesheet" rel="stylesheet" href="css/light-theme.css">\n    <script src="../assets/theme-switcher.js"></script>' "$SERVER_ROOT/admin.php"
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
