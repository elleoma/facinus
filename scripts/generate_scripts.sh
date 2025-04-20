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
    cp "$DEPLOY_DIR/y" "$SERVER_ROOT"

    # Replace placeholders in the script
    sed -i "s|SERVER_PLACEHOLDER|$SERVER_IP|g" "$SERVER_ROOT/y"
    sed -i "s|TOKEN_PLACEHOLDER|$SECRET_TOKEN|g" "$SERVER_ROOT/y"
    
    chmod 644 "$SERVER_ROOT/y"
}

generate_obfuscated_script() {
    echo "Creating obfuscated version of the client script..."
    
    base64 -w0 < "$DEPLOY_DIR/y" > "$DEPLOY_DIR/y.b64"
    
    cp "$DEPLOY_DIR/x" "$SERVER_ROOT/"
    sed -i "s|y.b64|$(cat $SERVER_ROOT/y.b64)|g" "$SERVER_ROOT/x"
    chmod 644 "$SERVER_ROOT/x"
    
    echo "Obfuscated script created."
}

generate_presets() {
    echo "Creating installation presets..."

    for preset in "$DEPLOY_DIR/minimal" "$DEPLOY_DIR/full" "$DEPLOY_DIR/quiet"; do
        sed -i "s|SERVER_PLACEHOLDER|$SERVER_IP|g" "$preset"
        cp "$preset" "$SERVER_ROOT/"
        chmod 644 "$SERVER_ROOT/$(basename "$preset")"
    done
    
    echo "Installation presets created."
}
