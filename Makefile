SHELL := /bin/zsh
.PHONY: help build switch deploy-% update check format clean colmena-% test-build-%
COLMENA := colmena
HOSTS := beelink firebat pi4 pi5

# Default target
help:
	@echo "Available targets:"
	@echo "= Nix Development"
	@echo "  devshell          - Enter devshell"
	@echo "  update            - Update flake inputs"
	@echo "  update-nix-conf   - Update '/etc/nix' with './etc/nix'"
	@echo "  check             - Check flake and run basic tests"
	@echo "  format            - Format Nix files"
	@echo "  home-switch       - Switch to the new home-manager config locally"
	@echo "  flake-info        - Show flake info"
	@echo "  dry-store-gc      - Nix store garbage collection (dry run)"
	@echo "  store-gc          - Nix store garbage collection"
	@echo ""
	@echo "= Host Access"
	@echo "  status            - Ping hosts to check if they are up"
	@echo "  deploy-info       - Show colmena deploy info"
	@echo "  ssh-HOST          - SSH into host"
	@echo ""
	@echo "= Deployment (use 'all' for all hosts)"
	@echo "  setup-HOST        - Initial setup for a new host"
	@echo "  diff-HOST         - Show configuration diff for host"
	@echo "  build-HOST        - Build HOST configuration on HOST"
	@echo "  dry-apply-HOST    - Deploy to specific HOST using Colmena (dry run)"
	@echo "  apply-HOST        - Deploy to specific HOST using Colmena"
	@echo ""
	@echo "= Raspberry Pi"
	@echo "  build-image-HOST  - Build Arm64 image for Raspberry Pi"
	@echo "  wsd-HOST DEVICE   - Write Arm64 image for Raspberry Pi to SD card"

# Home-manager dev shell
devshell:
	nix develop

# Update flake inputs
update:
	nix flake update
	nix flake update --flake ./home-manager
	@echo "Flake inputs updated. Consider running 'make deploy-all' to apply updates."

update-nix-conf:
	@echo "Backing up '/etc/nix/machines'"; \
	cp -v /etc/nix/machines /etc/nix/machines.old; \
	echo "Updating '/etc/nix/machines'"; \
	cp -v ./etc/nix/machines /etc/nix/machines; \
	echo "Backing up '/etc/nix/nix.custom.conf'"; \
	cp -v /etc/nix/nix.custom.conf /etc/nix/nix.custom.conf.old; \
	echo "Updating '/etc/nix/nix.custom.conf'"; \
	cp -v ./etc/nix/nix.custom.conf /etc/nix/nix.custom.conf
	launchctl kickstart -k system/systems.determinate.nix-daemon

# Check flake and run basic tests
check:
	nix flake check
	@echo "✓ Flake check passed"
	@echo "Testing host configurations..."; \
	for host in $(HOSTS); do \
	    nix build .#nixosConfigurations."$$host".config.system.build.toplevel --dry-run; \
    done; \
	echo "✓ All host configurations are valid"

# Format Nix files
format:
	find . -name "*.nix" -exec nixfmt {} \;
	@echo "✓ All Nix files formatted"

# Home manager switch
home-switch:
	nix run home-manager -- switch --flake ./home-manager

# Show flake info
flake-info:
	nix flake show

dry-store-gc:
	nix store gc -v --dry-run
	@echo "✓ Garbage collection completed (dry run)"

store-gc:
	nix store gc --debug
	@echo "✓ Garbage collection completed"

# Quick status check
status:
	@echo "Checking host connectivity..."; \
	for host in $(HOSTS); do \
	    ping -c 1 "$$host.local" >/dev/null 2>&1 && echo "✓ $$host: Online" || echo "✗ $$host: Offline"; \
    done

# Show deployment info
deploy-info:
	$(COLMENA) eval -E 'nodes: builtins.attrNames nodes'

# SSH into hosts for debugging
ssh-%:
	ssh bdhill@$*.local

# Initial setup for a new host
setup-%:
	@echo "Setting up $*..."
	@echo "1. Ensure the host is accessible via SSH at $*.local"
	@echo "2. Installing Nix on the target if needed..."
	@# ssh root@$*.local "curl -L https://nixos.org/nix/install | sh -s -- --daemon" || true
	@echo "3. Deploying NixOS configuration..."
	nixos-rebuild switch --flake .#$* --target-host $*.local --use-remote-sudo --build-host localhost
	@echo "✓ $* setup completed!"

# Show configuration diff for a host
diff-%:
	nixos-rebuild dry-run --flake .#$* --target-host $(HOST).local

# Test builds without deploying
build-%:
	@echo "Test building configuration for $*..."
	$(COLMENA) build --on $*

build-all:
	@echo "Test building all configurations..."
	$(COLMENA) build

# Build specific host configuration
build-host: host-arg
	@if [ -z "$(HOST)" ]; then \
		echo "Usage: make build-host HOST=<hostname>"; \
		echo "Available hosts: beelink, firebat, pi4"; \
		exit 1; \
	fi
	nix build .#nixosConfigurations.$(HOST).config.system.build.toplevel

dry-apply-%:
	@echo "[DRYRUN] Deploying to $* using Colmena..."
	$(COLMENA) apply dry-activate --on $* --verbose

dry-apply-all:
	@echo "Deploying to all hosts using Colmena..."
	$(COLMENA) apply dry-activate --verbose

# Colmena deployment commands
apply-%:
	@echo "Deploying to $* using Colmena..."
	$(COLMENA) apply --reboot --on $* --verbose

apply-all:
	@echo "Deploying to all hosts using Colmena..."
	$(COLMENA) apply --reboot --verbose

# Test deploy (dry run)
test-deploy-%:
	nixos-rebuild dry-run --flake .#$* --target-host $*.local

# Build SD card image for Pi5
NIX_DOCKER_VOLUME ?= nix-store-cache

build-image-%:
	@local pihost="$*"; \
	local tag="nixos-$${pihost}-image"; \
	\
	echo "Building Raspberry Pi $$tag image..."; \
	DOCKER_BUILDKIT=1 docker build \
		--build-arg PI_HOST="$$pihost" \
		--output=result \
		-t "$$tag" .; \
	echo "Image build complete. Output in ./result/pi$$version-installer"

# Write image to SD card
write-sd-%:
	@if [ -z "$(DEVICE)" ]; then \
		echo "Usage: make write-sd-$* DEVICE=/dev/rdiskX"; \
		exit 1; \
	fi
	@if [ ! -d "./result" ]; then \
		echo "No image found. Run 'make build-image-$*' first"; \
		exit 1; \
	fi
	@echo "Writing $* image to $(DEVICE)..."
	@sudo fdisk $(DEVICE)
	@echo "WARNING: This will erase all data on $(DEVICE)!"
	@bash -c 'read -p "Continue? (y/N) " -n 1 -r; \
	echo; \
	if [[ $$REPLY =~ ^[Yy]$$ ]]; then \
		if [ ! -f './result/$*-image.img' ]; then \
	        zstd -d ./result/nixos-sd-image-r$*-uboot.img.zst -o ./result/$*-image.img; \
		fi; \
	    sudo dd if=./result/$*-image.img of=$(DEVICE) bs=1M status=progress; \
		echo "Done! The Pi will boot with SSH enabled."; \
		echo "Default user: nixos"; \
		echo "Your SSH key is already installed"; \
	fi'

# provision-new-host
provision-new-host:
	@if [ -z "$(HOST)" ]; then \
		echo "Usage: make TARGET HOST=<hostname>"; \
		echo "Available hosts: beelink, firebat, pi5"; \
		exit 1; \
	fi
	@echo "Provisioning new host '$*'..."
	@./provision/nixos-anywhere-bootstrap.sh $* --generate-hardware

# clean-reboot
clean-reboot/%:
	@echo TODO
