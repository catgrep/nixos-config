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

pi4-installer:
	@./scripts/docker-compose.sh up; \
	export NIX_SSHOPTS="-F etc/nix/sshd_config"; \
	echo "Target Platform: $(shell nix eval --raw ../..#installerConfigurations.pi4.system)"; \
	nix store info --store ssh-ng://docknix@nix-builder-aarch64; \
	OUTPUT=$$(nix build \
	--eval-store auto \
	--store "ssh-ng://docknix@nix-builder-aarch64" \
	--substituters "ssh-ng://docknix@nix-builder-aarch64" \
	--print-out-paths \
	--builders-use-substitutes \
	 ../..#installerConfigurations.pi4); \
	echo "Built: $$OUTPUT"; \
	nix copy --no-check-sigs --from "ssh-ng://docknix@nix-builder-aarch64" --out-link ./builds/$@ "$$OUTPUT"; \
	echo "Copied: $(PWD)/builds/$@"

nix-pi4-installer:
	./scripts/docker-compose.sh up; \
#	@export NIX_SSHOPTS="-p 3022 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -i /Users/bobby/.ssh/id_rsa"; \
	export NIX_SSHOPTS="-F etc/nix/sshd_config"; \
	nix store info --store ssh-ng://nix-builder-aarch64; \
	NIX_SSHOPTS="-p 3022 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -i /Users/bobby/.ssh/id_rsa"; \
	nix build ../..#installerConfigurations.pi4 \
	--max-jobs 0 \
	--debug \
	--builders "ssh://docknix@127.0.0.1 aarch64-linux - 4 1 big-parallel,kvm"

check-store:
	./scripts/docker-compose.sh up; \
	NIX_SSHOPTS="-F etc/nix/sshd_config" \
	nix store info --store "ssh-ng://docknix@nix-builder-aarch64?trusted=true" \

build-aarch64-linux-%:
	@./scripts/docker-compose.sh up
	@nix build .#packages.aarch64-linux."$*" \
	--max-jobs 0 \
	--debug \
	--builders "ssh://docknix@127.0.0.1 aarch64-linux /Users/bobby/.ssh/id_rsa 4 1 big-parallel,kvm"

build-x86_64-linux-%:
	@./scripts/docker-compose.sh up
	@nix build .#packages.x86_64-linux.$* --max-jobs 0 --builders @etc/nix/machines
