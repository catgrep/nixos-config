#!/usr/bin/env bash

. ./scripts/sops/common.sh

# Check if SOPS is initialized
if [[ ! -f "$SOPS_CONFIG" ]]; then
	error "SOPS not initialized. Run './scripts/sops-init.sh' first"
	exit 1
fi

# Find all secret files
SECRET_FILES=$(find "$SECRETS_DIR" -name "*.yaml" -type f 2>/dev/null || true)

if [[ -z "$SECRET_FILES" ]]; then
	info "No secret files found to re-encrypt"
	exit 0
fi

# Re-encrypt each file
echo "$SECRET_FILES" | while read -r secret; do
	info "Re-encrypting ${secret}..."
	if sops updatekeys --yes "$secret"; then
		success "Updated ${secret}"
	else
		error "Failed to update ${secret}"
		exit 1
	fi
done

success "All secrets re-encrypted successfully!"
