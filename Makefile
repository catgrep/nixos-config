SHELL = /bin/zsh

.PHONY:
switch:
	pushd home-manager && nix run home-manager -- switch --flake . && popd
