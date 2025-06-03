#!/usr/bin/env bash
# Helper script to migrate hostnames during Colmena deployment

set -euo pipefail

HOST=$1
OLD_HOSTNAME=$2
NEW_HOSTNAME=$3

echo "Migrating hostname from $OLD_HOSTNAME to $NEW_HOSTNAME on $HOST"

# Deploy with Colmena
nix run github:zhaofengli/colmena -- apply --on "$HOST" --verbose

# After successful deployment, update colmena.json
echo "Deployment successful. Update colmena.json to use new hostname."
echo "Change targetHost for $HOST from $OLD_HOSTNAME to $NEW_HOSTNAME"
