#!/bin/bash
# Process command line arguments

process_args() {
    # Process command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --no-root)
                NO_ROOT=true
                shift
                ;;
            --no-services)
                NO_SERVICES=true
                shift
                ;;
            --no-wol)
                INSTALL_WOL=false
                shift
                ;;
            --no-fake-poweroff)
                INSTALL_FAKE_POWEROFF=false
                shift
                ;;
            --no-gsocket)
                INSTALL_GSOCKET=false
                shift
                ;;
            --no-stealth)
                STEALTH_MODE=false
                shift
                ;;
            --light-theme)
                DARK_THEME=false
                shift
                ;;
            --server-ip)
                SERVER_IP="$2"
                shift 2
                ;;
            --server-port)
                SERVER_PORT="$2"
                shift 2
                ;;
            --server-root)
                SERVER_ROOT="$2"
                shift 2
                ;;
            --verbose)
                VERBOSE=true
                shift
                ;;
            --help)
                echo "FACINUS Installation Script"
                echo "Usage: $0 [options]"
                echo
                echo "Options:"
                echo "  --no-root            Install without root privileges (limited functionality)"
                echo "  --no-services        Don't install system services"
                echo "  --no-wol             Don't configure Wake-on-LAN"
                echo "  --no-fake-poweroff   Don't install fake poweroff feature"
                echo "  --no-gsocket         Don't install gsocket for remote access"
                echo "  --no-stealth         Don't apply stealth techniques"
                echo "  --light-theme        Use light theme for web interface"
                echo "  --server-ip IP       Specify server IP address"
                echo "  --server-port PORT   Specify server port (default: 80)"
                echo "  --server-root PATH   Specify server root directory"
                echo "  --verbose            Show verbose output"
                echo "  --help               Show this help message"
                exit 0
                ;;
            *)
                echo "Unknown option: $1"
                echo "Run with --help for usage information."
                exit 1
                ;;
        esac
    done
}

# Process provided arguments
process_args "$@"
