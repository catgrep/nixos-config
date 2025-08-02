#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later


. ./scripts/sops/common.sh

set -euo pipefail

# FIXME: commenting these out for now since its easier for me to use my gpg key
# Copy over user public key
# cp -v "${ED_PUBKEY_PATH}" "${USER_KEYS_SECRETS_DIR}/${USER}.pub"
# # Get admin public key
# ADMIN_AGE_KEY=$(ssh-to-age -i "${USER_KEYS_SECRETS_DIR}/${USER}.pub")
# yq -i "
#     .keys += [ \"${ADMIN_AGE_KEY}\" ] |
#     .keys[-1] anchor = \"${USER}\" |
#     .keys[0] line_comment = \"main workstation\"
# " "$SOPS_CONFIG"
# yq -i "
#     .creation_rules[].key_groups[].age += [ \"${USER}\"] |
#     .creation_rules[].key_groups[].age[-1] alias = \"${USER}\"
# " "$SOPS_CONFIG"

# GPG fingerprint (this will be used as the master key for updating secrets)
GPG_FINGERPRINT=05BE930549C3E945BA3D8B6E72B6A6E95F049306 # gpg -K

yq -e -i "
	.keys = [ \"${GPG_FINGERPRINT}\" ] + .keys |
	.keys[0] anchor = \"admin_${USER}\" |
	.keys[0] head_comment = \"Added 'admin_$USER' GPG master key with '$0' on $(date)\" |
	.creation_rules[].key_groups[].pgp = [ \"admin_${USER}\" ] + .creation_rules[].key_groups[].pgp |
	.creation_rules[].key_groups[].pgp[0] alias = \"admin_${USER}\"
" "$SOPS_CONFIG"

success "Generated '$SOPS_CONFIG':"
print_yaml "$SOPS_CONFIG"
