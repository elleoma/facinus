#!/bin/bash
# Generate client deployment scripts
DEPLOY_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/deploy"

generate_client_scripts() {
    echo "Generating client deployment scripts..."
    
    generate_main_client_script
    
    generate_obfuscated_script
    
    generate_presets
}

generate_main_client_script() {
    # Replace placeholders in the script
    sed -i "s|SERVER_PLACEHOLDER|$SERVER_IP|g" "$DEPLOY_DIR/y"
    sed -i "s|TOKEN_PLACEHOLDER|$SECRET_TOKEN|g" "$DEPLOY_DIR/y"

    # Copy the script to the server
    sudo cp "$DEPLOY_DIR/y" "$SERVER_ROOT"
    sudo chmod 644 "$SERVER_ROOT/y"
}

generate_obfuscated_script() {
    echo "Creating obfuscated version of the client script..."
    
    # Base64 encode the script to obfuscate it
    base64 -w0 < "$DEPLOY_DIR/y" > "$DEPLOY_DIR/y.b64"
    
    # Replace the placeholder with the actual base64 content
    sed -i "s|BASE64_PLACEHOLDER|$(cat "$DEPLOY_DIR/y.b64")|g" "$DEPLOY_DIR/x"
    
    # Copy the obfuscated script to the server
    sudo cp "$DEPLOY_DIR/x" "$SERVER_ROOT/"
    sudo chmod 644 "$SERVER_ROOT/x"
    
    echo "Obfuscated script created."
}

generate_presets() {
    echo "Creating installation presets..."

    # Replace placeholders
    for preset in "$DEPLOY_DIR/minimal" "$DEPLOY_DIR/full" "$DEPLOY_DIR/quiet"; do
        sed -i "s|SERVER_PLACEHOLDER|$SERVER_IP|g" "$preset"
        sudo cp "$preset" "$SERVER_ROOT/"
        sudo chmod 644 "$SERVER_ROOT/$(basename "$preset")"
    done
    
    echo "Installation presets created."
}
