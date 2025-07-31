.ONESHELL:
SHELL := /bin/zsh
.SHELLFLAGS := -e -c
MAKEFLAGS += --no-print-directory
.PHONY: help build clean switch deploy-% update check format clean colmena-% test-build-% provision
COLMENA := colmena
HOSTS := $(shell ls ./hosts)

BOLD  = \033[1m
RED = \033[0;31m
GREEN = \033[0;32m
YELLOW = \033[0;33m
BLUE = \033[0;34m
BOLD = \033[1m
RESET = \033[0m
success_msg = echo -e "$(BOLD)$(GREEN)$(1)$(RESET)"
error_msg = echo -e "$(BOLD)$(RED)$(1)$(RESET)"
info_msg = echo -e "$(BOLD)$(YELLOW)$(1)$(RESET)"
title_msg = @echo -e "$(BOLD)$(BLUE)$(1)$(RESET)"

help_width = 30
help_option = @printf "$(BOLD)$(3)%-$(help_width)s$(RESET)%s\n" $(1) $(2)

# Default target
help:
	$(call title_msg,"Nix Development 🧪")
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
	$(call title_msg,"Host Access 🏘️")
	$(call help_option,"HOSTS","$(HOSTS)",$(YELLOW))
	$(call help_option,"status","Ping hosts to check if they are up")
	$(call help_option,"deploy-info","Show colmena deploy info")
	$(call help_option,"ssh-HOST","SSH into host")
	@echo ""
	$(call title_msg,"Deployment \(use \"all\" for all hosts\) 🔄")
	$(call help_option,"provision","Provision host using nixos-anywhere")
	$(call help_option,"setup-HOST","Initial setup for a new host")
	$(call help_option,"diff-HOST","Show configuration diff for host")
	$(call help_option,"build-HOST","Build HOST configuration on HOST")
	$(call help_option,"dry-apply-HOST","Deploy to specific HOST using Colmena (dry run)")
	$(call help_option,"apply-HOST","Deploy to specific HOST using Colmena")
	@echo ""
	$(call title_msg,"Raspberry Pi Builds 🍓")
	$(call help_option,"linux-arm64-img-HOST","Build Arm64 image for Raspberry Pi using Docker")
	$(call help_option,"write-arm64-sd-HOST DEVICE","Write Arm64 image for Raspberry Pi to SD card")
	@echo ""
	$(call title_msg,"SOPS Secrets Management 🤫")
	$(call help_option,"sops-init","Generate barebones '.sops.yaml'")
	$(call help_option,"sops-add-user","Add user to '.sops.yaml'")
	$(call help_option,"sops-add-host-keys","Add host keys to '.sops.yaml'")
	$(call help_option,"sops-update-keys","Update '.sops.yaml' keys if new hosts were added")
	$(call help_option,"sops-edit","Edit secrets in './secrets/secrets.yaml'")
	$(call help_option,"sops-status","Check host age keys and whether './secrets/secrets.yaml' can be decrypted")

# Home-manager dev shell
devshell:
	nix develop

# Update flake inputs
update:
	nix flake update
	nix flake update --flake ./home-manager
	$(call success_msg,"Flake inputs updated. Consider running 'make deploy-all' to apply updates.")

update-nix-conf:
	@$(call info_msg,"Backing up files...")
	@cp -v /etc/nix/machines /etc/nix/machines.old
	@cp -v ./etc/nix/machines /etc/nix/machines
	@cp -v /etc/nix/nix.custom.conf /etc/nix/nix.custom.conf.old
	@cp -v ./etc/nix/nix.custom.conf /etc/nix/nix.custom.conf
	@$(call info_msg,"Restarting nix-daemon...")
	@launchctl kickstart -k system/systems.determinate.nix-daemon
	@$(call success_msg,"Done")

# Check flake and run basic tests
check:
	@nix flake check
	@$(call success_msg,"✓ Flake check passed")
	@$(call info_msg,"Testing host configurations..."); \
	for host in $(HOSTS); do \
	    nix build .#nixosConfigurations."$$host".config.system.build.toplevel --dry-run; \
    done; \
    $(call success_msg,"✓ All host configurations are valid")

# Format Nix files
format:
	find . -name "*.nix" -exec nixfmt {} \;
	@$(call success_msg,"✓ All Nix files formatted")

# Home manager switch
home-switch:
	nix run home-manager -- switch --flake ./home-manager

# Show flake info
flake-info:
	nix flake show

dry-store-gc:
	nix store gc -v --dry-run
	@$(call success_msg,"✓ Garbage collection completed (dry run)")

store-gc:
	nix store gc --debug
	@$(call success_msg,"✓ Garbage collection completed")

# Quick status check
status:
	@$(call info_msg,"Checking host connectivity..."); \
	for host in $(HOSTS); do \
	    if ping -c 1 "$$host.local" >/dev/null 2>&1; then \
			$(call success_msg,"✓ $$host: Online"); \
			continue; \
		fi; \
		$(call error_msg,"✗ $$host: Offline"); \
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
	@$(call info_msg,"Test building configuration for '$*'...")
	$(COLMENA) build --on $*

build-all:
	@$(call info_msg,"Test building all configurations...")
	$(COLMENA) build

# Build specific host configuration
build-host: host-arg
	@if [ -z "$(HOST)" ]; then \
		$(call error_msg,"Usage: make build-host HOST=<hostname>"); \
		$(call info_msg,"Available hosts: $(HOSTS)"); \
		exit 1; \
	fi
	nix build .#nixosConfigurations.$(HOST).config.system.build.toplevel

dry-apply-%:
	@$(call info_msg,"\[ DRYRUN \] Deploying to $* using Colmena...")
	$(COLMENA) apply dry-activate --on $* --verbose

dry-apply-all:
	@$(call info_msg,"Deploying to all hosts using Colmena...")
	$(COLMENA) apply dry-activate --verbose

# Colmena deployment commands
apply-%:
	@$(call info_msg,"Deploying to '$*' using Colmena...")
	$(COLMENA) apply --reboot --on $* --verbose

apply-all:
	@$(call info_msg,"Deploying to all hosts using Colmena...")
	$(COLMENA) apply --reboot --verbose

# Test deploy (dry run)
test-deploy-%:
	nixos-rebuild dry-run --flake .#$* --target-host $*.local

# Build SD card image for Pi5
NIX_DOCKER_VOLUME ?= nix-store-cache
NIX_DOCKER_IMAGE ?= nixos/nix:2.30.1-arm64

# Build aarch64 artifacts using Docker
aarch64-sdimage-%:
	@./scripts/linux-aarch64-docker-build.sh installerConfigurations.$* sd-image/nixos-sd-image-r$*-uboot.img.zst

aarch64-kexec:
	@./scripts/linux-aarch64-docker-build.sh installerConfigurations.aarch64-kexec nixos-kexec-installer-aarch64-linux.tar.gz

%-installer: aarch64-sdimage-% aarch64-kexec
	@$(call success_msg,"✓ $* installers complete \(SD image + kexec\)")

# Write image to SD card
write-arm64-sd-%:
	@if [ -z "$(DEVICE)" ]; then \
		$(call error_msg,"Usage: make write-sd-$* DEVICE=/dev/rdiskX"); \
		exit 1; \
	fi
	@if [ ! -f "./result/nixos-sd-image-r$*-uboot.img.zst" ] || [ ! -f "./result/nixos-kexec-installer-aarch64-linux.tar.gz" ]; then \
		$(call error_msg,"No $* installer found. Run 'make $*-installer' first"); \
		exit 1; \
	fi
	@sudo fdisk $(DEVICE)
	@$(call info_msg,"WARNING: This will erase all data on $(DEVICE)!")
	@bash -c 'read -p "Continue? (y/N) " -n 1 -r; \
	echo; \
	if [[ $$REPLY =~ ^[Yy]$$ ]]; then \
	    pi_img="./result/nixos-sd-image-r$*-uboot.img"; \
		$(call info_msg,"Uncompressing $$pi_img.zst..."); \
		if [ ! -f "$${pi_img}" ]; then \
	        zstd -d "$${pi_img}.zst" -o "$${pi_img}"; \
		fi; \
		$(call info_msg,"Begin writing $$pi_img to $(DEVICE)..."); \
	    sudo dd if="$${pi_img}" of=$(DEVICE) bs=1M status=progress; \
		$(call success_msg,"Done! The Pi will boot with SSH enabled."); \
		$(call info_msg,"Default user: nixos"); \
		$(call info_msg,"Your SSH key is already installed"); \
		$(call success_msg,"Safely eject '$(DEVICE)' and boot the $*"); \
	fi'

provision:
	$(call title_msg,"HOSTS = $(HOSTS)")
	@$(call info_msg,"Run the './scripts/linux-HOSTARCH.sh' script")

# clean-reboot
clean-reboot/%:
	@echo TODO

# SOPS targets
sops-init:
	@./scripts/sops/init.sh

sops-add-user:
	@./scripts/sops/add-user.sh

sops-add-host-keys:
	@./scripts/sops/add-host-keys.sh

sops-update-keys:
	@sops updatekeys secrets/secrets.yaml

sops-edit:
	@sops secrets/secrets.yaml

sops-status:
	@./scripts/sops/status.sh

clean:
	git clean -xfd
