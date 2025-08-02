#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later

. ./scripts/lib/all.sh

set -euo pipefail

title "nixos-rebuild"

cleanup_hook() {
    error "nixos-rebuild failed"
}

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
}

# confirm to not accidentally bork your system :'D
confirm() {
    echo ""
    warning "This could result in a boot failure upon reboot and require console access!"
    echo ""
    read -p "Continue? (y/N) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Aborted."
        exit 1
    fi
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
        --fast # add '--fast' to bypass 'Exec format error'. See https://discourse.nixos.org/t/deploy-nixos-configurations-on-other-machines/22940/32
    )

    # add extra args
    if [ "$#" -ge 3 ]; then
        args+=("${@:3}")
        info "with extra args: '${args[*]}'"
    fi

    # LFG m8
    mkdir -p ./logs
    local build_logs
    build_logs="./logs/nixos-rebuild.log-$(date +%Y%m%d-%H%M%S)"
    info "build logs will be at: '$build_logs'"

    nixos-rebuild "${args[@]}" | tee -a "$build_logs"

    success "Done"
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

    success "Done"
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
            success "Done"
            return 0
        fi
        info "Retrying..."
        sleep 5
    done

    error "Host '${ip}' did not come back online after 10 attempts"
    return 1
}

main() {
    if [ $# -lt 2 ]; then
        usage
        return 1
    fi

    local action="$1"
    local host="$2"
    shift 2

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
        confirm
        nixos_rebuild switch "${host}"
        ;;
    reboot)
        # Reboot is a special case where we want to reboot the host after a 'switch'.
        confirm
        nixos_reboot "${host}"
        ;;
    update-hardware)
        # Updates the host 'hardware-configuration.nix' with one generated by
        # 'nixos-generate-config'.
        nixos_generate_config "${host}"
        ;;
    *)
        error "invalid option '${action}'"
        exit 1
        ;;
    esac
}

main "$@"
