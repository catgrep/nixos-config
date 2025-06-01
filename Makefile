SHELL = /bin/zsh

.PHONY: switch update

upgrade-nix:
	determinate-nixd upgrade

switch:
	nix run home-manager -- switch --flake ./home-manager

update:
	nix flake update --flake ./home-manager
