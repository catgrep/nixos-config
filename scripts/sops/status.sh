#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later

. ./scripts/sops/common.sh

# FIXME: commenting these out for now since its easier for me to use my gpg key
# Check admin key
# echo -n "Admin key: "
# if [[ -f "$AGE_KEY_PATH" ]]; then
# 	ADMIN_KEY=$(age-keygen -y "$AGE_KEY_PATH" 2>/dev/null)
# 	success "${ADMIN_KEY}"
# else
# 	error "Not found"
# fi

# Check SOPS config
echo -n "SOPS config: "
if [[ -f "$SOPS_CONFIG" ]]; then
    success "${SOPS_CONFIG}"
else
    error "Not found"
fi

echo

# Check hosts
if [[ -d "hosts" ]]; then
    echo "Host status:"
    for host_dir in hosts/*/; do
        if [ ! -d "$host_dir" ]; then
            error "Host not configured"
            continue
        fi

        host=$(basename "$host_dir")
        echo -n "  ${host}: "
        # Check if secrets exist
        if [ ! -f "${HOST_SECRETS_DIR}/${host}/secrets.yaml" ]; then
            error "Host has no secrets"
            continue
        fi

        # Check if host key is in SOPS config
        if [ ! -f "$SOPS_CONFIG" ] || ! grep -q "\*host_${host}" "$SOPS_CONFIG" 2>/dev/null; then
            error "Secrets exist but host key missing"
            continue
        fi

        # Try to decrypt
        if sops -d "${HOST_SECRETS_DIR}/${host}/secrets.yaml" >/dev/null 2>&1; then
            success "Configured (can decrypt)"
        else
            error "Configured (cannot decrypt)"
        fi
    done
fi

echo

# Check secrets files
if [[ -d "$SECRETS_DIR" ]]; then
    echo "Secrets files:"
    find "$SECRETS_DIR" -name "*.yaml" -type f | while read -r secret; do
        echo -n "  ${secret}: "
        if sops -d "$secret" >/dev/null 2>&1; then
            success "Can decrypt"
        else
            error "Cannot decrypt"
        fi
    done
fi
