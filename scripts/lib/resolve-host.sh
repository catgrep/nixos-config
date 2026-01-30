#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later

# Standalone host resolver for Makefile
# Resolves hostname to local IP or Tailscale domain with caching
#
# Usage: ./scripts/lib/resolve-host.sh <hostname>
# Output: IP address or Tailscale hostname (e.g., "192.168.68.65" or "ser8.shad-bangus.ts.net")

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source dependencies
source "${SCRIPT_DIR}/yq.sh"
source "${SCRIPT_DIR}/ssh.sh"

if [ $# -lt 1 ]; then
    echo "Usage: $0 <hostname>" >&2
    exit 1
fi

resolve_ssh_host "$1"
