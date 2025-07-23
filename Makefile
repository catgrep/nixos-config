SHELL := /bin/zsh
MAKEFLAGS += --no-print-directory
.PHONY: help build switch deploy-% update check format clean colmena-% test-build-% provision
COLMENA := colmena
HOSTS := $(shell ls ./hosts)

BOLD  = \033[1m
RED = \033[0;31m
GREEN = \033[0;32m
YELLOW = \033[0;33m
BLUE = \033[0;34m
BOLD = \033[1m
RESET = \033[0m
help_width = 30
help_option = @printf "$(BOLD)$(GREEN)%-$(help_width)s$(RESET)%s\n" $(1) $(2)
# Default target
help:
	@echo "🖥️  $(BUILD)$(YELLOW)HOSTS = $(HOSTS)$(RESET)"
	@echo ""
	@echo "🧪 $(BOLD)$(BLUE)Nix Development$(RESET)"
	$(call help_option,"devshell","Enter devshell")
	$(call help_option,"update","Update flake inputs")
	$(call help_option,"update-nix-conf","Update '/etc/nix' with './etc/nix'")
	$(call help_option,"check","Check flake and run basic tests")
	$(call help_option,"format","Format Nix files")
	$(call help_option,"home-switch","Switch to the new home-manager config locally")
	$(call help_option,"flake-info","Show flake info")
	$(call help_option,"dry-store-gc","Nix store garbage collection (dry run)")
	$(call help_option,"store-gc","Nix store garbage collection")
	@echo ""
	@echo "🖥️  $(BOLD)$(BLUE)Host Access$(RESET)"
	$(call help_option,"status","Ping hosts to check if they are up")
	$(call help_option,"deploy-info","Show colmena deploy info")
	$(call help_option,"ssh-HOST","SSH into host")
	@echo ""
	@echo "🔄 $(BOLD)$(BLUE)Deployment (use 'all' for all hosts)$(RESET)"
	$(call help_option,"provision","Provision host using nixos-anywhere")
	$(call help_option,"setup-HOST","Initial setup for a new host")
	$(call help_option,"diff-HOST","Show configuration diff for host")
	$(call help_option,"build-HOST","Build HOST configuration on HOST")
	$(call help_option,"dry-apply-HOST","Deploy to specific HOST using Colmena (dry run)")
	$(call help_option,"apply-HOST","Deploy to specific HOST using Colmena")
	@echo ""
	@echo "🍓 $(BOLD)$(BLUE)Raspberry Pi Builds$(RESET)"
	$(call help_option,"linux-arm64-img-HOST","Build Arm64 image for Raspberry Pi using Docker")
	$(call help_option,"write-arm64-sd-HOST DEVICE","Write Arm64 image for Raspberry Pi to SD card")

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
NIX_DOCKER_IMAGE ?= nixos/nix:2.30.1-arm64
linux-arm64-img-%:
	@echo "Ensuring Docker volume exists: $(NIX_DOCKER_VOLUME)"; \
	docker volume create $(NIX_DOCKER_VOLUME) || true; \
	\
	local pihost="$*"; \
	local tag="nixos-$${pihost}-image"; \
	\
	echo "Building Raspberry Pi $$tag image..."; \
	docker run --rm \
		-v $(NIX_DOCKER_VOLUME):/nix \
		-v $(PWD):/build:ro \
		-v $(PWD)/result:/output:rw \
		-w /build \
		$(NIX_DOCKER_IMAGE) \
		sh -c "nix build .#installerConfigurations.$* \
			--extra-experimental-features 'nix-command flakes' \
			--accept-flake-config \
			--out-link /tmp/result && \
			cp -L /tmp/result/sd-image/*.img.zst /output/$*-installer.img.zst"
	echo "Image build complete. Output in /result/$*-installer.img.zst"

# Write image to SD card
write-arm64-sd-%:
	@if [ -z "$(DEVICE)" ]; then \
		echo "Usage: make write-sd-$* DEVICE=/dev/rdiskX"; \
		exit 1; \
	fi
	@if [ ! -d "./result" ]; then \
		echo "No image found. Run 'make build-image-$*' first"; \
		exit 1; \
	fi
	@sudo fdisk $(DEVICE)
	@echo "$(BOLD)$(YELLOW)WARNING: This will erase all data on $(DEVICE)!$(RESET)"
	@bash -c 'read -p "Continue? (y/N) " -n 1 -r; \
	echo; \
	if [[ $$REPLY =~ ^[Yy]$$ ]]; then \
	    pi_img="./result/$*-installer.img"; \
		echo "Uncompressing $$pi_img.zst..."; \
		if [ ! -f "$${pi_img}" ]; then \
	        zstd -d "$${pi_img}.zst" -o "$${pi_img}"; \
		fi; \
		echo "Begin writing $$pi_img to $(DEVICE)..."; \
	    sudo dd if="$${pi_img}" of=$(DEVICE) bs=1M status=progress; \
		echo "$(BOLD)$(GREEN)Done! The Pi will boot with SSH enabled.$(RESET)"; \
		echo "$(BOLD)$(GREEN)Default user: nixos$(RESET)"; \
		echo "$(BOLD)$(GREEN)Your SSH key is already installed$(RESET)"; \
	fi'

provision:
	@echo "🖥️  $(BUILD)$(YELLOW)HOSTS = $(HOSTS)$(RESET)"
	@echo "$(BOLD)$(GREEN)Run the './scripts/linux-HOSTARCH.sh' script$(RESET)"

# clean-reboot
clean-reboot/%:
	@echo TODO
