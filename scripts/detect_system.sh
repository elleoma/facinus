#!/bin/bash

detect_system() {
    ARCH=$(uname -m)
    
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        DISTRO_NAME=${ID,,}  # Convert to lowercase
        
        for arch_distro in "${ARCH_DISTROS[@]}"; do
            if [[ "$DISTRO_NAME" == *"$arch_distro"* ]]; then
                DISTRO="arch"
                return
            fi
        done
        
        for deb_distro in "${DEB_DISTROS[@]}"; do
            if [[ "$DISTRO_NAME" == *"$deb_distro"* ]]; then
                DISTRO="debian"
                return
            fi
        done
        
        for rpm_distro in "${RPM_DISTROS[@]}"; do
            if [[ "$DISTRO_NAME" == *"$rpm_distro"* ]]; then
                DISTRO="redhat"
                return
            fi
        done
        
        DISTRO="$DISTRO_NAME"
    elif [ -f /etc/arch-release ]; then
        DISTRO="arch"
    elif [ -f /etc/debian_version ]; then
        DISTRO="debian"
    elif [ -f /etc/redhat-release ]; then
        DISTRO="redhat"
    else
        echo "Unable to determine distribution. Defaulting to generic."
        DISTRO="generic"
    fi
}
