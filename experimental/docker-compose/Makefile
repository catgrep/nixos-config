# SPDX-License-Identifier: GPL-3.0-or-later

# Docker remote builder management
start-builders:
	@./scripts/docker-compose.sh up

stop-builders:
	@./scripts/docker-compose.sh down

builder-status:
	@./scripts/docker-compose.sh status

restart-builders:
	@./scripts/docker-compose.sh down
	@./scripts/docker-compose.sh up

# Auto-managed cross-platform builds
pi5-installer:
	@./scripts/docker-compose.sh up
	@NIX_SSHOPTS="-F etc/nix/sshd_config" nix build .#packages.aarch64-linux.pi5-usb-installer --max-jobs 0 --builders @etc/nix/machines

export NIX_SSHOPTS = -p 3022 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null
pi4-installer:
	@./scripts/docker-compose.sh up
	nix build .#installerConfigurations.pi4 \
	--max-jobs 0 \
	--debug \
	--builders "ssh://docknix@127.0.0.1 aarch64-linux /Users/bobby/.ssh/id_rsa 4 1 big-parallel,kvm"

build-aarch64-linux-%:
	@./scripts/docker-compose.sh up
	@nix build .#packages.aarch64-linux."$*" \
	--max-jobs 0 \
	--debug \
	--builders "ssh://docknix@127.0.0.1 aarch64-linux /Users/bobby/.ssh/id_rsa 4 1 big-parallel,kvm"

build-x86_64-linux-%:
	@./scripts/docker-compose.sh up
	@nix build .#packages.x86_64-linux.$* --max-jobs 0 --builders @etc/nix/machines
