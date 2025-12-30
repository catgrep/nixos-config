#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later

. ./scripts/lib/all.sh

set -euo pipefail

title "$0"

# NIXBUILD_USER can be used to override the default user in './deploy.yaml'
NIXBUILD_USER="${NIXBUILD_USER:-}"

usage() {
    title "Usage: $0 <action> <host>"
    echo ""
    echo "Simple wrapper around 'nixos-rebuild' for building and deploying on"
    echo "pre-configured / pre-provisioned NixOS hosts."
    echo ""
    echo "Assumes that '${DEPLOY_YAML}' contains host deployment metadata."
    echo ""
    title "Arguments:"
    echo "  action      One of 'dry-build', 'build', 'dry-activate', 'test', 'switch', or 'reboot'"
    echo "  host        Host defined in the top-level '${DEPLOY_YAML}'"
    echo ""
    title "Examples:"
    echo "$0 dry-build firebat"
    echo "$0 test pi4"
    echo ""
    title "Package Operations:"
    echo "  pkg-list       List available packages (categories: overlays, system, services, all)"
    echo "  pkg-build      Build a specific package"
    echo "  pkg-version    Show package version"
    echo "  pkg-eval       Evaluate config expression"
    echo ""
    title "Package Examples:"
    echo "  $0 pkg-list ser8                        # List all package categories"
    echo "  $0 pkg-list ser8 overlays               # List only overlay packages"
    echo "  $0 pkg-build ser8 jellyfin-ffmpeg       # Build single package"
    echo "  $0 pkg-version ser8 lcevcdec            # Check package version"
    echo "  $0 pkg-eval ser8 'config.services.jellyfin.enable'"
    echo ""
}

raspberrypi_warning_banner() {
    echo
    echo -e "$(fmt_bold "📝 NOTE on Raspberry Pi's")"
    echo -e "$(fmt_blue "||") For bootstrapping from the installer, you may need to generate"
    echo -e "$(fmt_blue "||") the hardware config first with:"
    echo -e "$(fmt_blue "||")"
    echo -e "$(fmt_blue "||") > $(fmt_yellow "$0 update-hardware piX")"
    echo -e "$(fmt_blue "||")"
    echo -e "$(fmt_blue "||") This will replace the existing config with the generated one."
    echo -e "$(fmt_blue "||")"
    echo -e "$(fmt_blue "||") For rebuilds, if '$(fmt_blue test)' or '$(fmt_blue switch)' fails due to:"
    echo -e "$(fmt_blue "||")"
    echo -e "$(fmt_blue "||") $(fmt_red "Error: Failed to open unit file /nix/store/.../etc/systemd/system/boot-firmware.mount")"
    echo -e "$(fmt_blue "||")"
    echo -e "$(fmt_blue "||") You may need to mount '$(fmt_blue /boot/firmware)' first with:"
    echo -e "$(fmt_blue "||")"
    echo -e "$(fmt_blue "||") > $(fmt_yellow "sudo mount /dev/disk/by-label/FIRMWARE /boot/firmware")"
    echo -e "$(fmt_blue "||")"
    echo -e "$(fmt_blue "||") See: https://gist.github.com/mti/f6572f34aefbcb1aba1d33c888a5b298"
    echo -e "$(fmt_bold "📝 END NOTE")"
    echo
}

# confirm to not accidentally bork your system :'D
nixos_confirm() {
    echo ""
    warn "This could result in a boot failure upon reboot and require console access!"
    confirm
}

nixos_rebuild() {
    local action="$1"
    local host="$2"
    local user
    local ip
    user="$(get_user "$host")"
    ip="$(get_ip "$host")"

    if [ -n "$NIXBUILD_USER" ]; then
        info "Build user will be '$NIXBUILD_USER' instead of '$user'"
        user="$NIXBUILD_USER"
    fi

    info "Running 'nixos-rebuild ${action}' on '${user}@${ip}'..."

    # base args
    local args=(
        "$action"
        --flake ".#${host}"
        --build-host "${user}@${ip}"
        --target-host "${user}@${ip}"
        --use-remote-sudo
        --verbose
        # add '--fast' to bypass 'Exec format error'
        # See https://discourse.nixos.org/t/deploy-nixos-configurations-on-other-machines/22940/32
        --fast
    )

    # add extra args if there are more than required
    if [ "$#" -ge 3 ]; then
        args=("${args[@]}" "${@:3}")
        info "with extra args: '${args[*]}'"
    fi

    # LFG m8
    mkdir -p ./logs
    local build_logs
    build_logs="./logs/nixos-rebuild.log-$(date +%Y%m%d-%H%M%S)"
    info "build logs will be at: '$build_logs'"

    nixos-rebuild "${args[@]}" | tee -a "$build_logs"
}

nixos_generate_config() {
    local host="$1"
    local user
    local ip

    user="$(get_user "$host")"
    ip="$(get_ip "$host")"

    if [ -n "$NIXBUILD_USER" ]; then
        info "Build user will be '$NIXBUILD_USER' instead of '$user'"
        user="$NIXBUILD_USER"
    fi

    info "updating './hosts/${host}/hardware-configuration.nix' using 'nixos-generate-config'..."
    ssh "${user}@${ip}" "nixos-generate-config --show-hardware-config" >"./hosts/${host}/hardware-configuration.nix"
}

nixos_reboot() {
    local host="$1"
    local user
    local ip

    user="$(get_user "$host")"
    ip="$(get_ip "$host")"

    info "Rebooting '${user}@${ip}'..."
    ssh -o StrictHostKeyChecking=no "${user}@${ip}" -- sudo reboot
    info "Waiting for host '${ip}' to come back online..."

    sleep 1
    # Retry SSH up to 10 times with 1 second delay
    for i in {1..10}; do
        if ssh -o ConnectTimeout=3 -o StrictHostKeyChecking=no "${user}@${ip}" "echo 'online'" &>/dev/null; then
            info "Host '${ip}' is back online (after $i attempt(s))"
            return 0
        fi
        info "Retrying..."
        sleep 5
    done

    fail "Host '${ip}' did not come back online after 10 attempts"
    return 1
}

# Fetch all package info in a single nix eval call
pkg_list_all() {
    local host="$1"
    local category="$2"

    info "Fetching package info..."

    local pkg_info
    pkg_info=$(nix eval ".#packageInfo.${host}" --json 2>/dev/null) || {
        fail "Unable to evaluate packageInfo for host '$host'"
        return 1
    }

    # Display overlays
    if [ "$category" = "overlays" ] || [ "$category" = "all" ]; then
        echo ""
        info "$(fmt_bold "Overlay packages") (custom/overridden):"
        local overlay_count
        overlay_count=$(echo "$pkg_info" | jq '.overlays | length')
        if [ "$overlay_count" = "0" ]; then
            echo "  (none)"
        else
            echo "$pkg_info" | jq -r '.overlays | to_entries | .[] | "\(.key)\t\(.value // "?")"' |
                while IFS=$'\t' read -r pkg version; do
                    printf "  %-30s (%s)\n" "$pkg" "$version"
                done
        fi
    fi

    # Display system packages
    if [ "$category" = "system" ] || [ "$category" = "all" ]; then
        echo ""
        info "$(fmt_bold "System packages") (environment.systemPackages):"
        echo "  (showing first 50 unique packages)"
        echo "$pkg_info" | jq -r '.systemPackages[] | "\(.name)\t\(.version // "?")"' |
            while IFS=$'\t' read -r pkg version; do
                printf "  %-30s (%s)\n" "$pkg" "$version"
            done
    fi

    # Display service packages
    if [ "$category" = "services" ] || [ "$category" = "all" ]; then
        echo ""
        info "$(fmt_bold "Service packages") (enabled services with packages):"
        local svc_count
        svc_count=$(echo "$pkg_info" | jq '.services | length')
        if [ "$svc_count" = "0" ]; then
            echo "  (no services with packages found)"
        else
            echo "$pkg_info" | jq -r '.services | to_entries | .[] | "\(.key)\t\(.value.package)\t\(.value.version // "?")"' |
                while IFS=$'\t' read -r svc pkg version; do
                    printf "  %-25s -> %-20s (%s)\n" "$svc" "$pkg" "$version"
                done
        fi
    fi
}

main() {
    if [ $# -lt 2 ]; then
        usage
        return 1
    fi

    local action="$1"
    local host="$2"
    shift 2

    # raspberrypi_warning_banner

    case $action in
    dry-build)
        # Show what store paths would be built or downloaded by any of the operations
        # above, but otherwise do nothing.
        nixos_rebuild dry-build "${host}"
        ;;
    build)
        # Build the new configuration, but neither activate it nor add it to the
        # GRUB boot menu.
        nixos_rebuild build "${host}"
        ;;
    dry-activate)
        # Build the new configuration, but instead of activating it, show what
        # changes would be performed by the activation. The list of changes is not
        # guaranteed to be complete.
        nixos_rebuild dry-activate "${host}"
        ;;
    test)
        # Build and activate the new configuration, but do not add it to the GRUB
        # boot menu. Thus, if you reboot the system (or if it crashes), you will
        # automatically revert to the default configuration.
        nixos_rebuild test "${host}"
        ;;
    switch)
        # Build and activate the new configuration, and make it the boot default.
        # That is, the configuration is added to the GRUB boot menu as the default menu
        # entry, so that subsequent reboots will boot the system into the new
        # configuration.
        #
        # Previous configurations activated with nixos-rebuild switch or nixos-rebuild
        # boot remain available in the GRUB menu.
        nixos_confirm
        nixos_rebuild switch "${host}"
        ;;
    reboot)
        # Reboot is a special case where we want to reboot the host after a 'switch'.
        nixos_confirm
        nixos_reboot "${host}"
        ;;
    update-hardware)
        # Updates the host 'hardware-configuration.nix' with one generated by
        # 'nixos-generate-config'.
        nixos_generate_config "${host}"
        ;;
    pkg-build)
        local pkg="${1:-}"
        if [ -z "$pkg" ]; then
            fail "Usage: $0 pkg-build <host> <package>"
            fail "Example: $0 pkg-build ser8 jellyfin-ffmpeg"
            exit 1
        fi
        info "Building package '$pkg' for host '$host'..."
        nix build ".#nixosConfigurations.${host}.pkgs.${pkg}" -v --no-link --print-out-paths
        pass "Package '$pkg' built successfully"
        ;;
    pkg-version)
        local pkg="${1:-}"
        if [ -z "$pkg" ]; then
            fail "Usage: $0 pkg-version <host> <package>"
            fail "Example: $0 pkg-version ser8 lcevcdec"
            exit 1
        fi
        local version
        version=$(nix eval --raw ".#nixosConfigurations.${host}.pkgs.${pkg}.version" 2>/dev/null) || {
            fail "Package '$pkg' not found or has no version attribute"
            exit 1
        }
        info "Package '$pkg' version for host '$host': $(fmt_bold "$version")"
        ;;
    pkg-eval)
        local expr="${1:-}"
        if [ -z "$expr" ]; then
            fail "Usage: $0 pkg-eval <host> <expression>"
            fail "Examples:"
            fail "  $0 pkg-eval ser8 'config.services.jellyfin.enable'"
            fail "  $0 pkg-eval ser8 'pkgs.jellyfin.version'"
            exit 1
        fi
        info "Evaluating '.#nixosConfigurations.${host}.${expr}':"
        nix eval ".#nixosConfigurations.${host}.${expr}"
        ;;
    pkg-list)
        local category="${1:-all}"
        title "Package listing for host '$host' (category: $category)"

        case "$category" in
        overlays | system | services | all)
            pkg_list_all "$host" "$category"
            ;;
        *)
            fail "Unknown category '$category'"
            fail "Valid categories: overlays, system, services, all"
            exit 1
            ;;
        esac
        ;;
    *)
        fail "invalid option '${action}'"
        exit 1
        ;;
    esac

    pass "$(fmt_blue "$0") completed"
}

main "$@"
