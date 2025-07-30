#!/usr/bin/env bash

. ./scripts/lib/all.sh

cleanup_hook() {
	error "$0: sops failed"
}

# Sops Configuration
SOPS_CONFIG=".sops.yaml"
AGE_KEY_PATH="${HOME}/.config/sops/age/keys.txt"
SECRETS_DIR="secrets"
SECRETS_FILE="${SECRETS_DIR}/secrets.yaml"
SECRETS_HOST_KEYS_DIR="${SECRETS_DIR}/keys/hosts"
SECRETS_USER_KEYS_DIR="${SECRETS_DIR}/keys/users"
ED_PUBKEY_PATH="${SECRETS_USER_KEYS_DIR}/bobmac.pub"

title "sops/$(basename "$0")"
