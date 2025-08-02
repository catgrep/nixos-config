#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later

. ./scripts/lib/all.sh

cleanup_hook() {
    error "$0: sops failed"
}

# Sops Configuration
SOPS_CONFIG=".sops.yaml"
AGE_KEY_PATH="${HOME}/.config/sops/age/keys.txt"
SECRETS_DIR="secrets"
SECRETS_FILE="${SECRETS_DIR}/secrets.yaml" # this is the host global secrets file
HOST_KEYS_SECRETS_DIR="${SECRETS_DIR}/keys/hosts"
USER_KEYS_SECRETS_DIR="${SECRETS_DIR}/keys/users"
ED_PUBKEY_PATH="/Users/bobby/.ssh/id_ed25519.pub"

title "sops/$(basename "$0")"
