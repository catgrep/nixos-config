#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later

# shellcheck source=scripts/lib/all.sh
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
	ip="$(resolve_ssh_host "$host")"

	if [ -n "$NIXBUILD_USER" ]; then
		info "Build user will be '$NIXBUILD_USER' instead of '$user'"
		user="$NIXBUILD_USER"
	fi

	local remote_build_dir="/nix-builds"
	info "Ensuring remote Nix build directory '${remote_build_dir}' exists..."
	ssh "${user}@${ip}" -- "sudo mkdir -p '${remote_build_dir}' && sudo chown root:root '${remote_build_dir}' && sudo chmod 0755 '${remote_build_dir}'"

	info "Running 'nixos-rebuild ${action}' on '${user}@${ip}'..."

	# base args
	local args=(
		"$action"
		--flake ".#${host}"
		--build-host "${user}@${ip}"
		--target-host "${user}@${ip}"
		--sudo
		--option build-dir "${remote_build_dir}"
		# Avoid re-execution to bypass 'Exec format error'.
		# See https://discourse.nixos.org/t/deploy-nixos-configurations-on-other-machines/22940/32
		--no-reexec
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

	# nixos-rebuild-ng places its SSH ControlPath socket under $TMPDIR. macOS
	# caps Unix socket paths at 104 bytes, and the nix dev shell's TMPDIR
	# (/tmp/nix-shell.XXXXXX) pushes the socket path over that limit:
	#   unix_listener: path "..." too long for Unix domain socket
	# Pin TMPDIR to /tmp for this invocation so the socket path stays short.
	TMPDIR=/tmp nixos-rebuild "${args[@]}" | tee -a "$build_logs"
}

nixos_generate_config() {
	local host="$1"
	local user
	local ip

	user="$(get_user "$host")"
	ip="$(resolve_ssh_host "$host")"

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
	ip="$(resolve_ssh_host "$host")"

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

main() {
	if [ $# -lt 2 ]; then
		usage
		return 1
	fi

	local action="$1"
	local host="$2"
	shift 2

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
	*)
		fail "invalid option '${action}'"
		exit 1
		;;
	esac

	pass "$(fmt_blue "$0") completed"
}

if ! command -v nixos-rebuild; then
	fail "nixos-rebuild not found"
	info "Are you running in a nix development shell?"
	exit 1
fi

main "$@"
