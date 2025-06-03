SHELL := /bin/zsh
.PHONY: help build switch deploy-% update check format clean colmena-% test-build-%
COLMENA := colmena

# Default target
help:
	@echo "Available targets:"
	@echo "  info               - Show host info"
	@echo "  devshell           - Enter devshell (aarch64-darwin)"
	@echo "  build              - Build the NixOS configuration"
	@echo "  home-switch        - Switch to the new home-manager config locally"
	@echo "  switch             - Switch to the new configuration locally"
	@echo "  test-build-HOST    - Test build configuration for HOST"
	@echo "  test-build-all     - Test build all configurations"
	@echo "  colmena-apply-HOST - Deploy to specific HOST using Colmena"
	@echo "  colmena-apply-all  - Deploy to all hosts using Colmena"
	@echo "  colmena-exec       - Execute command on hosts"
	@echo "  deploy-all         - Deploy to all hosts"
	@echo "  update             - Update flake inputs"
	@echo "  check              - Check flake and run basic tests"
	@echo "  format             - Format Nix files"
	@echo "  clean              - Clean build artifacts"
	@echo "  setup-host HOST    - Initial setup for a new host"
	@echo "  diff HOST          - Show configuration diff for host"

# Switch local configuration (for the machine you're running on)
switch:
	sudo nixos-rebuild switch --flake .

# Home manager switch
home-switch:
	nix run home-manager -- switch --flake ./home-manager

# Home-manager dev shell
devshell:
	nix develop ./home-manager

# Test builds without deploying
test-build-%:
	@echo "Test building configuration for $*..."
	$(COLMENA) build --on $*

# Colmena deployment commands
colmena-apply-%:
	@echo "Deploying to $* using Colmena..."
	$(COLMENA) apply --on $* --verbose

colmena-apply-all:
	@echo "Deploying to all hosts using Colmena..."
	$(COLMENA) apply --verbose

# Deploy by tag
colmena-apply-tag-%:
	@echo "Deploying to all hosts with tag '$*'..."
	$(COLMENA) apply --on @$* --verbose

# Execute command on hosts
colmena-exec:
	@if [ -z "$(CMD)" ]; then \
		echo "Usage: make colmena-exec CMD='command to run'"; \
		exit 1; \
	fi
	$(COLMENA) exec -- $(CMD)

# Show deployment info
colmena-info:
	$(COLMENA) eval -E 'nodes: builtins.attrNames nodes'

test-build-all:
	@echo "Test building all configurations..."
	$(COLMENA) build

# Deploy to all hosts
deploy-all: colmena-apply-all
	@echo "Deployment to all hosts completed!"

# Update flake inputs
update:
	nix flake update
	@echo "Flake inputs updated. Consider running 'make deploy-all' to apply updates."

# Check flake and run basic tests
check:
	nix flake check
	@echo "✓ Flake check passed"
	@echo "Testing host configurations..."
	nix build .#nixosConfigurations.beelink.config.system.build.toplevel --dry-run
	nix build .#nixosConfigurations.firebat.config.system.build.toplevel --dry-run
	nix build .#nixosConfigurations.pi4.config.system.build.toplevel --dry-run
	@echo "✓ All host configurations are valid"

# Format Nix files
format:
	find . -name "*.nix" -exec nixfmt {} \;
	@echo "✓ All Nix files formatted"

# Clean build artifacts
clean:
	nix-collect-garbage -d
	@echo "✓ Garbage collection completed"

# Show configuration diff for a host
diff:
	@if [ -z "$(HOST)" ]; then \
		echo "Usage: make diff HOST=<hostname>"; \
		echo "Available hosts: beelink, firebat, pi4"; \
		exit 1; \
	fi
	nixos-rebuild dry-run --flake .#$(HOST) --target-host $(HOST).local

# Initial setup for a new host
setup-host:
	@if [ -z "$(HOST)" ]; then \
		echo "Usage: make setup-host HOST=<hostname>"; \
		echo "Available hosts: beelink, firebat, pi4"; \
		exit 1; \
	fi
	@echo "Setting up $(HOST)..."
	@echo "1. Ensure the host is accessible via SSH at $(HOST).local"
	@echo "2. Installing Nix on the target if needed..."
	@# ssh root@$(HOST).local "curl -L https://nixos.org/nix/install | sh -s -- --daemon" || true
	@echo "3. Deploying NixOS configuration..."
	nixos-rebuild switch --flake .#$(HOST) --target-host $(HOST).local --use-remote-sudo --build-host localhost
	@echo "✓ $(HOST) setup completed!"

# Build specific host configuration
build-host:
	@if [ -z "$(HOST)" ]; then \
		echo "Usage: make build-host HOST=<hostname>"; \
		echo "Available hosts: beelink, firebat, pi4"; \
		exit 1; \
	fi
	nix build .#nixosConfigurations.$(HOST).config.system.build.toplevel

# Test deploy (dry run)
test-deploy:
	@if [ -z "$(HOST)" ]; then \
		echo "Usage: make test-deploy HOST=<hostname>"; \
		echo "Available hosts: beelink, firebat, pi4"; \
		exit 1; \
	fi
	nixos-rebuild dry-run --flake .#$(HOST) --target-host $(HOST).local

# Install prerequisites on a fresh NixOS system
install-prereqs:
	nix-env -iA nixpkgs.git nixpkgs.nixfmt-rfc-style

# SSH into hosts for debugging
ssh-beelink:
	ssh bdhill@beelink.local

ssh-firebat:
	ssh bdhill@firebat.local

ssh-pi4:
	ssh bdhill@pi4.local

# Show system information for all hosts
info:
	@echo "=== Homelab Host Information ==="
	@echo "Beelink (Media Server): AMD Ryzen 7 8745HS, 64GB RAM, ZFS RAID 10"
	@echo "Firebat (Gateway): AMD Ryzen 7 6800H, 32GB RAM, Load Balancer/Monitoring"
	@echo "Pi4 (DNS): Raspberry Pi 4B, 8GB RAM, AdGuard Home DNS"
	@echo ""
	@echo "Network Configuration:"
	@echo "  Beelink: beelink.local (192.168.1.20)"
	@echo "  Firebat: firebat.local (192.168.1.21)"
	@echo "  Pi4: pi4.local (192.168.1.10)"

# Quick status check
status:
	@echo "Checking host connectivity..."
	@ping -c 1 beelink.local >/dev/null 2>&1 && echo "✓ Beelink: Online" || echo "✗ Beelink: Offline"
	@ping -c 1 firebat.local >/dev/null 2>&1 && echo "✓ Firebat: Online" || echo "✗ Firebat: Offline"
	@ping -c 1 pi4.local >/dev/null 2>&1 && echo "✓ Pi4: Online" || echo "✗ Pi4: Offline"

# Development helpers
dev-shell:
	nix develop

# Show flake info
flake-info:
	nix flake show

# Backup configurations
backup-configs:
	@mkdir -p backups/$(shell date +%Y-%m-%d)
	@cp -r hosts/ backups/$(shell date +%Y-%m-%d)/
	@cp flake.nix flake.lock backups/$(shell date +%Y-%m-%d)/
	@echo "✓ Configurations backed up to backups/$(shell date +%Y-%m-%d)/"
