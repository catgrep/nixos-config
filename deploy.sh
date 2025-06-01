#!/usr/bin/env bash
# Helper script for NixOS homelab deployment

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Helper functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check if host is reachable
check_host() {
    local host=$1
    if ping -c 1 "$host.local" >/dev/null 2>&1; then
        log_success "$host is reachable"
        return 0
    else
        log_error "$host is not reachable"
        return 1
    fi
}

# Generate hardware configuration for a host
generate_hardware_config() {
    local host=$1
    log_info "Generating hardware configuration for $host..."

    if ! check_host "$host"; then
        log_error "Cannot reach $host, skipping hardware config generation"
        return 1
    fi

    ssh "root@$host.local" "nixos-generate-config --show-hardware-config" > "hosts/$host/hardware-configuration.nix"
    log_success "Hardware configuration saved to hosts/$host/hardware-configuration.nix"
}

# Backup existing configuration
backup_config() {
    local backup_dir="backups/$(date +%Y%m%d_%H%M%S)"
    mkdir -p "$backup_dir"
    cp -r hosts/ "$backup_dir/"
    cp flake.nix flake.lock "$backup_dir/" 2>/dev/null || true
    log_success "Configuration backed up to $backup_dir"
}

# Deploy to a specific host
deploy_host() {
    local host=$1
    local dry_run=${2:-false}

    log_info "Deploying to $host..."

    if ! check_host "$host"; then
        log_error "Cannot reach $host, aborting deployment"
        return 1
    fi

    # Build configuration first
    log_info "Building configuration for $host..."
    if ! nix build ".#nixosConfigurations.$host.config.system.build.toplevel" --no-link; then
        log_error "Failed to build configuration for $host"
        return 1
    fi

    # Deploy or dry-run
    if [ "$dry_run" = "true" ]; then
        log_info "Performing dry-run deployment to $host..."
        nixos-rebuild dry-run --flake ".#$host" --target-host "$host.local" --use-remote-sudo
    else
        log_info "Deploying to $host..."
        nixos-rebuild switch --flake ".#$host" --target-host "$host.local" --use-remote-sudo --build-host localhost
        log_success "Successfully deployed to $host"
    fi
}

# Pre-deployment checks
pre_deployment_checks() {
    log_info "Running pre-deployment checks..."

    # Check if flake is valid
    if ! nix flake check --no-build; then
        log_error "Flake check failed"
        return 1
    fi
    log_success "Flake check passed"

    # Check if SSH keys exist
    if [ ! -f ~/.ssh/id_ed25519.pub ] && [ ! -f ~/.ssh/id_rsa.pub ]; then
        log_warning "No SSH public key found. Generate one with: ssh-keygen -t ed25519"
    fi

    # Check Git status
    if [ -d .git ]; then
        if ! git diff --quiet; then
            log_warning "You have uncommitted changes. Consider committing them first."
        fi
    fi

    log_success "Pre-deployment checks completed"
}

# Show disk information for ZFS setup
show_disks() {
    local host=$1
    log_info "Showing disk information for $host..."

    if ! check_host "$host"; then
        return 1
    fi

    echo "Available disks on $host:"
    ssh "root@$host.local" "lsblk -d -o NAME,SIZE,MODEL,SERIAL | grep -E '^(sd|nvme)'"
    echo ""
    echo "Disk IDs on $host:"
    ssh "root@$host.local" "ls -la /dev/disk/by-id/ | grep -E '(ata|nvme)'"
}

# Initialize a new host
init_host() {
    local host=$1
    log_info "Initializing host: $host"

    # Create host directory structure
    mkdir -p "hosts/$host/services"

    # Generate basic configuration if it doesn't exist
    if [ ! -f "hosts/$host/configuration.nix" ]; then
        log_info "Creating basic configuration for $host..."
        # This would copy from a template or create a basic config
        log_warning "Please create hosts/$host/configuration.nix manually"
    fi

    # Generate hardware configuration
    if check_host "$host"; then
        generate_hardware_config "$host"
    else
        log_warning "Host not reachable, skipping hardware config generation"
    fi

    log_success "Host $host initialized"
}

# Main menu
show_menu() {
    echo ""
    echo "===== NixOS Homelab Deployment Helper ====="
    echo "1. Pre-deployment checks"
    echo "2. Initialize new host"
    echo "3. Generate hardware config"
    echo "4. Show disk info (for ZFS setup)"
    echo "5. Test deployment (dry-run)"
    echo "6. Deploy to host"
    echo "7. Deploy to all hosts"
    echo "8. Backup configuration"
    echo "9. Check host connectivity"
    echo "0. Exit"
    echo "============================================="
}

# Main script logic
main() {
    if [ $# -eq 0 ]; then
        # Interactive mode
        while true; do
            show_menu
            read -p "Choose an option: " choice

            case $choice in
                1)
                    pre_deployment_checks
                    ;;
                2)
                    read -p "Enter host name (beelink/firebat/pi4): " host
                    init_host "$host"
                    ;;
                3)
                    read -p "Enter host name: " host
                    generate_hardware_config "$host"
                    ;;
                4)
                    read -p "Enter host name: " host
                    show_disks "$host"
                    ;;
                5)
                    read -p "Enter host name: " host
                    deploy_host "$host" true
                    ;;
                6)
                    read -p "Enter host name: " host
                    backup_config
                    deploy_host "$host"
                    ;;
                7)
                    log_warning "This will deploy to ALL hosts. Are you sure? (y/N)"
                    read -p "Continue? " confirm
                    if [ "$confirm" = "y" ] || [ "$confirm" = "Y" ]; then
                        backup_config
                        for host in pi4 firebat beelink; do
                            deploy_host "$host"
                        done
                    fi
                    ;;
                8)
                    backup_config
                    ;;
                9)
                    for host in beelink firebat pi4; do
                        check_host "$host"
                    done
                    ;;
                0)
                    log_info "Goodbye!"
                    exit 0
                    ;;
                *)
                    log_error "Invalid option"
                    ;;
            esac
            echo ""
            read -p "Press Enter to continue..."
        done
    else
        # Command line mode
        case $1 in
            "check")
                pre_deployment_checks
                ;;
            "init")
                if [ $# -ne 2 ]; then
                    log_error "Usage: $0 init <hostname>"
                    exit 1
                fi
                init_host "$2"
                ;;
            "deploy")
                if [ $# -ne 2 ]; then
                    log_error "Usage: $0 deploy <hostname>"
                    exit 1
                fi
                backup_config
                deploy_host "$2"
                ;;
            "dry-run")
                if [ $# -ne 2 ]; then
                    log_error "Usage: $0 dry-run <hostname>"
                    exit 1
                fi
                deploy_host "$2" true
                ;;
            "hardware")
                if [ $# -ne 2 ]; then
                    log_error "Usage: $0 hardware <hostname>"
                    exit 1
                fi
                generate_hardware_config "$2"
                ;;
            "disks")
                if [ $# -ne 2 ]; then
                    log_error "Usage: $0 disks <hostname>"
                    exit 1
                fi
                show_disks "$2"
                ;;
            "backup")
                backup_config
                ;;
            *)
                echo "Usage: $0 [check|init|deploy|dry-run|hardware|disks|backup] [hostname]"
                echo "Or run without arguments for interactive mode"
                exit 1
                ;;
        esac
    fi
}

# Run main function
main "$@"
