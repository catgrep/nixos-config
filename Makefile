SHELL := /bin/zsh
.PHONY: help build switch deploy-% update check format clean

# Default target
help:
	@echo "Available targets:"
	@echo "  info               - Show host info"
	@echo "  build              - Build the NixOS configuration"
	@echo "  home-switch        - Switch to the new home-manager config locally"
	@echo "  switch             - Switch to the new configuration locally"
	@echo "  deploy-beelink     - Deploy to Beelink media server"
	@echo "  deploy-firebat     - Deploy to Firebat gateway"
	@echo "  deploy-pi4         - Deploy to Raspberry Pi 4 DNS server"
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

# Deploy to specific hosts
deploy-beelink:
	@echo "Deploying to Beelink (Media Server)..."
	nixos-rebuild switch --flake .#beelink --target-host beelink.local --use-remote-sudo --build-host localhost

deploy-firebat:
	@echo "Deploying to Firebat (Gateway)..."
	nixos-rebuild switch --flake .#firebat --target-host firebat.local --use-remote-sudo --build-host localhost

deploy-pi4:
	@echo "Deploying to Raspberry Pi 4 (DNS)..."
	nixos-rebuild switch --flake .#pi4 --target-host pi4.local --use-remote-sudo --build-host localhost

# Deploy to all hosts
deploy-all: deploy-beelink deploy-firebat deploy-pi4
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
	ssh bobby@beelink.local

ssh-firebat:
	ssh bobby@firebat.local

ssh-pi4:
	ssh bobby@pi4.local

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
